// Посередник помічника «Пасічник»: застосунок -> ця функція -> Anthropic API.
//
// Ключ Anthropic (ANTHROPIC_API_KEY) - лише в секретах Supabase; у
// застосунку його немає. Хто може звертатися - вирішує access.ts.
//
// Один запит = один крок моделі. Цикл інструментів веде застосунок (дані
// на телефоні): модель просить інструмент (stop_reason 'tool_use') ->
// застосунок виконує й надсилає всю розмову з tool_result -> модель
// продовжує. Функція рахує кроки після останнього повідомлення людини й
// після MAX_STEPS модель не викликає.
//
// Розмову застосунок надсилає повністю й лише дописує в кінець (відповіді
// моделі - без змін, разом із блоками thinking): так працює кеш і модель
// приймає свої попередні міркування.
//
// Журнал: лише кількість кроків і токенів - без тексту розмов.
//
// Публічна для шлюзу Supabase (розгортати з --no-verify-jwt): перевірку
// робить access.ts. Без залежностей: той самий файл перевіряє тест на Node
// (tests/assistant.test.ts).

import {
  ANTHROPIC_URL,
  ANTHROPIC_VERSION,
  EFFORT,
  type Env,
  MAX_BODY_BYTES,
  MAX_MESSAGES,
  MAX_STEPS,
  MAX_TOKENS,
  modelFrom,
} from './config.ts';
import { type AccessCheck, checkAccess } from './access.ts';
import { SYSTEM_PROMPT } from './prompt.ts';
import { TOOLS, type ToolDef } from './tools.ts';

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

type Block = { type: string; [k: string]: unknown };
type Message = { role: 'user' | 'assistant'; content: string | Block[] };

export type Deps = {
  env: Env;
  fetch: typeof fetch;
  log: (line: string) => void;
  access: AccessCheck;
  system?: string;
  tools?: ToolDef[];
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

const fail = (status: number, error: string) => json({ error }, status);

/** Чи повідомлення - від людини (а не лише результати інструментів). */
function isHumanTurn(m: Message): boolean {
  if (m.role !== 'user') return false;
  if (typeof m.content === 'string') return true;
  return m.content.some((b) => b.type !== 'tool_result');
}

/** Скільки разів модель уже зверталася до інструментів після останнього
 *  повідомлення людини. */
export function stepsSinceHuman(messages: Message[]): number {
  let steps = 0;
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (isHumanTurn(m)) break;
    if (m.role === 'assistant' && Array.isArray(m.content) && m.content.some((b) => b.type === 'tool_use')) {
      steps++;
    }
  }
  return steps;
}

/** Перевірка форми розмови; повертає причину відмови або null. */
export function validateMessages(raw: unknown): string | null {
  if (!Array.isArray(raw) || raw.length === 0) return 'messages';
  if (raw.length > MAX_MESSAGES) return 'too_long';
  for (let i = 0; i < raw.length; i++) {
    const m = raw[i] as Message;
    if (!m || (m.role !== 'user' && m.role !== 'assistant')) return 'role';
    if (i > 0 && (raw[i - 1] as Message).role === m.role) return 'order';
    const ok =
      typeof m.content === 'string'
        ? m.content.length > 0
        : Array.isArray(m.content) &&
          m.content.length > 0 &&
          m.content.every((b) => b && typeof b === 'object' && typeof b.type === 'string');
    if (!ok) return 'content';
  }
  if ((raw[0] as Message).role !== 'user' || (raw[raw.length - 1] as Message).role !== 'user') return 'order';
  return null;
}

/** Тіло запиту до Anthropic: кеш - на останньому інструменті й на
 *  системному промпті (порядок рендеру tools -> system -> messages). */
export function buildRequest(model: string, messages: Message[], system: string, tools: ToolDef[]) {
  const t = tools.map((d, i) =>
    i === tools.length - 1 ? { ...d, cache_control: { type: 'ephemeral' } } : { ...d },
  );
  return {
    model,
    max_tokens: MAX_TOKENS,
    output_config: { effort: EFFORT },
    system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
    ...(t.length > 0 ? { tools: t, tool_choice: { type: 'auto' } } : {}),
    messages,
  };
}

type Usage = {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
};

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method !== 'POST') return fail(405, 'method');

  const access = await deps.access(req, deps.env);
  if (!access.ok) return fail(access.status, access.error);

  const key = deps.env('ANTHROPIC_API_KEY')?.trim();
  if (!key) return fail(500, 'not_configured');

  const text = await req.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) return fail(413, 'too_large');
  let body: { messages?: unknown };
  try {
    body = JSON.parse(text);
  } catch {
    return fail(400, 'json');
  }
  const bad = validateMessages(body?.messages);
  if (bad) return fail(400, bad);
  const messages = body.messages as Message[];

  const steps = stepsSinceHuman(messages);
  if (steps >= MAX_STEPS) {
    deps.log(JSON.stringify({ fn: 'assistant', result: 'step_limit', steps }));
    return fail(422, 'step_limit');
  }

  const model = modelFrom(deps.env);
  const payload = buildRequest(model, messages, deps.system ?? SYSTEM_PROMPT, deps.tools ?? TOOLS);
  let res: Response;
  try {
    res = await deps.fetch(ANTHROPIC_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': key,
        'anthropic-version': ANTHROPIC_VERSION,
      },
      body: JSON.stringify(payload),
    });
  } catch {
    deps.log(JSON.stringify({ fn: 'assistant', result: 'network', steps }));
    return json({ error: 'busy', retry: true }, 503);
  }

  if (!res.ok) {
    // 429 (ліміт), 529 (перевантажено), 5xx - можна повторити згодом
    const retry = res.status === 429 || res.status >= 500;
    deps.log(JSON.stringify({ fn: 'assistant', result: 'upstream', status: res.status, steps }));
    return retry ? json({ error: 'busy', retry: true }, 503) : fail(502, 'upstream');
  }

  const out = (await res.json()) as { content?: Block[]; stop_reason?: string; usage?: Usage };
  const u = out.usage ?? {};
  deps.log(
    JSON.stringify({
      fn: 'assistant',
      result: 'ok',
      model,
      steps: steps + (out.stop_reason === 'tool_use' ? 1 : 0),
      input_tokens: u.input_tokens ?? 0,
      output_tokens: u.output_tokens ?? 0,
      cache_read_input_tokens: u.cache_read_input_tokens ?? 0,
      cache_creation_input_tokens: u.cache_creation_input_tokens ?? 0,
    }),
  );
  return json({
    content: out.content ?? [],
    stop_reason: out.stop_reason ?? 'end_turn',
    steps_left: MAX_STEPS - steps - (out.stop_reason === 'tool_use' ? 1 : 0),
  });
}

if (typeof Deno !== 'undefined') {
  Deno.serve((req) =>
    handle(req, {
      env: (n) => Deno.env.get(n),
      fetch,
      log: (l) => console.log(l),
      access: checkAccess,
    }),
  );
}
