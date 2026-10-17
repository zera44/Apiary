// Зворотний зв'язок з відповідями: застосунок <-> розробник.
//
// Застосунок (без входу: пара device_id + secret, яку він створює при
// першому відгуку; сервер зберігає лише хеш secret):
//   {action:'send', device_id, secret, body, platform?} - надіслати відгук;
//   {action:'poll', device_id, secret, after_seq?}      - нові повідомлення
//                                                         (відгуки й відповіді).
// Розробник (адмін-сторінка admin/feedback.html; заголовок
// x-feedback-admin = пароль FEEDBACK_ADMIN_PASSWORD):
//   {action:'admin_list'}                  - усі розмови;
//   {action:'admin_thread', thread_id}     - повідомлення розмови (і «прочитано»);
//   {action:'admin_reply', thread_id, body} - відповісти.
//
// Новий відгук - лист на FEEDBACK_NOTIFY_TO (через Resend: RESEND_API_KEY).
// Журнал: лише лічильники й коди, БЕЗ текстів.
//
// Публічна для шлюзу Supabase (--no-verify-jwt): доступ перевіряє сама.
// Без залежностей: той самий файл перевіряє тест на Node
// (tests/feedback.test.ts).

import { MemoryStore, type Message, RestStore, type Store } from './store.ts';

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

export const MAX_BODY = 5000;
/** Відгуків від одного встановлення за добу. */
export const DAILY_LIMIT = 20;
export const ADMIN_HEADER = 'x-feedback-admin';

export type Env = (name: string) => string | undefined;

export type Deps = {
  store: Store;
  env: Env;
  fetch: typeof fetch;
  log: (line: string) => void;
  now: () => number;
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': `content-type, ${ADMIN_HEADER}`,
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...CORS },
  });
}
const fail = (status: number, error: string) => json({ error }, status);

async function sha256Hex(s: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)));
  return Array.from(d, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** Порівняння без витоку часу. */
function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const view = (m: Message) => ({ seq: m.seq, from_dev: m.from_dev, body: m.body, at: m.created_at });

/** Лист розробнику про новий відгук (Resend: безкоштовно, лише на адресу
 *  власника акаунта). Не вдалося - не страшно: відгук уже збережено. */
async function notify(deps: Deps, body: string, platform: string | null): Promise<boolean> {
  const key = deps.env('RESEND_API_KEY')?.trim();
  const to = deps.env('FEEDBACK_NOTIFY_TO')?.trim();
  if (!key || !to) return false;
  const adminUrl = deps.env('FEEDBACK_ADMIN_URL')?.trim();
  try {
    const res = await deps.fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'Vulyk <onboarding@resend.dev>',
        to: [to],
        subject: "Vulyk: новий відгук",
        text: `${body}\n\n— ${platform ?? 'невідомо'}${adminUrl ? `\n\nВідповісти: ${adminUrl}` : '\n\nВідповідати - в адмін-сторінці відгуків.'}`,
      }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return fail(405, 'method');

  let b: Record<string, unknown>;
  try {
    const text = await req.text();
    if (text.length > 20000) return fail(413, 'too_large');
    b = JSON.parse(text);
  } catch {
    return fail(400, 'json');
  }
  const action = typeof b.action === 'string' ? b.action : '';

  if (action.startsWith('admin_')) return admin(req, b, action, deps);

  // ---- застосунок
  const deviceId = typeof b.device_id === 'string' ? b.device_id : '';
  const secret = typeof b.secret === 'string' ? b.secret : '';
  if (!UUID.test(deviceId) || secret.length < 16 || secret.length > 200) return fail(400, 'device');
  const hash = await sha256Hex(secret);
  let thread = await deps.store.threadByDevice(deviceId);
  if (thread && !same(thread.secret_hash, hash)) return fail(403, 'forbidden');

  if (action === 'poll') {
    if (!thread) return json({ messages: [] });
    const after = Number.isInteger(b.after_seq) ? (b.after_seq as number) : 0;
    const msgs = await deps.store.messages(thread.id, Math.max(0, after));
    return json({ messages: msgs.map(view) });
  }

  if (action === 'send') {
    const body = typeof b.body === 'string' ? b.body.trim() : '';
    if (!body) return fail(400, 'empty');
    const text = body.length > MAX_BODY ? body.slice(0, MAX_BODY) : body;
    const platform = typeof b.platform === 'string' ? b.platform.slice(0, 80) : null;
    if (!thread) thread = await deps.store.createThread(deviceId, hash, platform);
    const since = new Date(deps.now() - 24 * 3600 * 1000).toISOString();
    if ((await deps.store.userMessagesSince(thread.id, since)) >= DAILY_LIMIT) return fail(429, 'limit');
    const m = await deps.store.addMessage(thread.id, false, text);
    const mailed = await notify(deps, text, platform);
    deps.log(JSON.stringify({ fn: 'feedback', result: 'sent', mailed, length: text.length }));
    return json({ message: view(m) });
  }
  return fail(400, 'action');
}

async function admin(req: Request, b: Record<string, unknown>, action: string, deps: Deps): Promise<Response> {
  const password = deps.env('FEEDBACK_ADMIN_PASSWORD')?.trim() ?? '';
  const got = req.headers.get(ADMIN_HEADER)?.trim() ?? '';
  if (password.length < 8 || !same(got, password)) {
    deps.log(JSON.stringify({ fn: 'feedback', result: 'admin_denied' }));
    return fail(401, 'unauthorized');
  }
  if (action === 'admin_list') {
    const list = await deps.store.threads();
    return json({
      threads: list.map((t) => ({
        id: t.id,
        platform: t.platform,
        last_at: t.last_at,
        unread: t.dev_unread,
        last: t.last ? { from_dev: t.last.from_dev, body: t.last.body.slice(0, 140) } : null,
      })),
    });
  }
  const id = typeof b.thread_id === 'string' ? b.thread_id : '';
  const thread = UUID.test(id) ? await deps.store.threadById(id) : null;
  if (!thread) return fail(404, 'thread');
  if (action === 'admin_thread') {
    await deps.store.setDevUnread(thread.id, false);
    return json({ platform: thread.platform, messages: (await deps.store.messages(thread.id)).map(view) });
  }
  if (action === 'admin_reply') {
    const body = typeof b.body === 'string' ? b.body.trim() : '';
    if (!body) return fail(400, 'empty');
    const m = await deps.store.addMessage(thread.id, true, body.length > MAX_BODY ? body.slice(0, MAX_BODY) : body);
    await deps.store.setDevUnread(thread.id, false);
    deps.log(JSON.stringify({ fn: 'feedback', result: 'replied', length: body.length }));
    return json({ message: view(m) });
  }
  return fail(400, 'action');
}

if (typeof Deno !== 'undefined') {
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  Deno.serve((req) =>
    handle(req, {
      store: new RestStore(url, key),
      env: (n) => Deno.env.get(n),
      fetch,
      log: (l) => console.log(l),
      now: () => Date.now(),
    }),
  );
}

export { MemoryStore };
