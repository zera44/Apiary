// Перевірка посередника помічника без Supabase і без Anthropic: замість
// API - фейкова модель із заготовленими відповідями.
//
//   node --test supabase/tests/assistant.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildRequest, type Deps, handle, stepsSinceHuman } from '../functions/assistant/index.ts';
import { testTokenAccess, TEST_TOKEN_HEADER } from '../functions/assistant/access.ts';
import { DEFAULT_MODEL, MAX_STEPS } from '../functions/assistant/config.ts';

const TOKEN = 'test-token-0123456789abcdef';
const SECRETS: Record<string, string> = {
  ANTHROPIC_API_KEY: 'sk-ant-test',
  APIARY_ASSISTANT_TEST_TOKEN: TOKEN,
};

type Call = { url: string; headers: Record<string, string>; body: any };

function deps(reply: () => Response, env: Record<string, string> = SECRETS) {
  const calls: Call[] = [];
  const logs: string[] = [];
  const d: Deps = {
    env: (n) => env[n],
    fetch: (async (url: string, init: RequestInit) => {
      calls.push({ url, headers: init.headers as Record<string, string>, body: JSON.parse(init.body as string) });
      return reply();
    }) as typeof fetch,
    log: (l) => logs.push(l),
    access: testTokenAccess,
    tools: [
      { name: 'open_screen', description: 'Відкрити екран', input_schema: { type: 'object', properties: {} } },
      { name: 'apiaries_list', description: 'Список пасік', input_schema: { type: 'object', properties: {} } },
    ],
  };
  return { d, calls, logs };
}

const modelReply = (content: unknown[], stop_reason = 'end_turn') => () =>
  new Response(
    JSON.stringify({
      content,
      stop_reason,
      usage: { input_tokens: 120, output_tokens: 30, cache_read_input_tokens: 900, cache_creation_input_tokens: 0 },
    }),
    { status: 200 },
  );

const post = (body: unknown, token: string | null = TOKEN) =>
  new Request('https://x.supabase.co/functions/v1/assistant', {
    method: 'POST',
    headers: token == null ? {} : { [TEST_TOKEN_HEADER]: token },
    body: JSON.stringify(body),
  });

const hello = { messages: [{ role: 'user', content: 'Скільки в мене пасік?' }] };

test('неправильний чи відсутній тестовий код - відмова, модель не викликається', async () => {
  for (const t of [null, 'wrong', TOKEN + 'x']) {
    const { d, calls } = deps(modelReply([]));
    const r = await handle(post(hello, t), d);
    assert.equal(r.status, 401);
    assert.equal(calls.length, 0);
  }
});

test('код не задано на сервері - не пускає нікого', async () => {
  const { d, calls } = deps(modelReply([]), { ANTHROPIC_API_KEY: 'k' });
  const r = await handle(post(hello, ''), d);
  assert.equal(r.status, 401);
  assert.equal(calls.length, 0);
});

test('немає ключа Anthropic - not_configured', async () => {
  const { d } = deps(modelReply([]), { APIARY_ASSISTANT_TEST_TOKEN: TOKEN });
  const r = await handle(post(hello), d);
  assert.equal(r.status, 500);
  assert.deepEqual(await r.json(), { error: 'not_configured' });
});

test('звичайна відповідь: ключ лише в заголовку до Anthropic, модель, кеш', async () => {
  const { d, calls } = deps(modelReply([{ type: 'text', text: 'У вас 2 пасіки.' }]));
  const r = await handle(post(hello), d);
  assert.equal(r.status, 200);
  const out = await r.json();
  assert.equal(out.stop_reason, 'end_turn');
  assert.equal(out.content[0].text, 'У вас 2 пасіки.');
  assert.equal(JSON.stringify(out).includes('sk-ant'), false);

  assert.equal(calls.length, 1);
  const c = calls[0];
  assert.equal(c.url, 'https://api.anthropic.com/v1/messages');
  assert.equal(c.headers['x-api-key'], 'sk-ant-test');
  assert.equal(c.headers['anthropic-version'], '2023-06-01');
  assert.equal(c.body.model, DEFAULT_MODEL);
  assert.equal(c.body.system[0].cache_control.type, 'ephemeral');
  assert.equal(c.body.tools.at(-1).cache_control.type, 'ephemeral');
  assert.equal(c.body.tools[0].cache_control, undefined);
  assert.deepEqual(c.body.messages, hello.messages);
});

test('модель перевизначається секретом ASSISTANT_MODEL', async () => {
  const { d, calls } = deps(modelReply([]), { ...SECRETS, ASSISTANT_MODEL: 'claude-sonnet-5-5' });
  await handle(post(hello), d);
  assert.equal(calls[0].body.model, 'claude-sonnet-5-5');
});

test('запит інструмента передається застосунку як є', async () => {
  const use = { type: 'tool_use', id: 'tu_1', name: 'apiaries_list', input: {} };
  const { d } = deps(modelReply([{ type: 'thinking', thinking: '', signature: 's' }, use], 'tool_use'));
  const out = await (await handle(post(hello), d)).json();
  assert.equal(out.stop_reason, 'tool_use');
  assert.deepEqual(out.content[1], use);
  assert.equal(out.content[0].type, 'thinking'); // застосунок поверне його без змін
  assert.equal(out.steps_left, MAX_STEPS - 1);
});

// розмова, де модель уже n разів зверталася до інструментів
function conversation(n: number) {
  const m: any[] = [{ role: 'user', content: 'Знайди слабкі вулики' }];
  for (let i = 0; i < n; i++) {
    m.push({ role: 'assistant', content: [{ type: 'tool_use', id: `t${i}`, name: 'find_hives', input: {} }] });
    m.push({ role: 'user', content: [{ type: 'tool_result', tool_use_id: `t${i}`, content: '[]' }] });
  }
  return m;
}

test('кроки рахуються лише після останнього повідомлення людини', () => {
  assert.equal(stepsSinceHuman(conversation(0)), 0);
  assert.equal(stepsSinceHuman(conversation(4)), 4);
  const again = [...conversation(5), { role: 'assistant', content: 'Готово.' }, { role: 'user', content: 'А ще?' }];
  assert.equal(stepsSinceHuman(again), 0);
});

test('після 6 кроків модель не викликається', async () => {
  const { d, calls, logs } = deps(modelReply([]));
  const below = await handle(post({ messages: conversation(MAX_STEPS - 1) }), d);
  assert.equal(below.status, 200);
  assert.equal(calls.length, 1);
  const r = await handle(post({ messages: conversation(MAX_STEPS) }), d);
  assert.equal(r.status, 422);
  assert.deepEqual(await r.json(), { error: 'step_limit' });
  assert.equal(calls.length, 1);
  assert.match(logs.at(-1)!, /step_limit/);
});

test('неправильна розмова - 400 без виклику моделі', async () => {
  const bad = [
    {},
    { messages: [] },
    { messages: [{ role: 'assistant', content: 'привіт' }] },
    { messages: [{ role: 'user', content: 'a' }, { role: 'user', content: 'b' }] },
    { messages: [{ role: 'system', content: 'a' }] },
    { messages: [{ role: 'user', content: '' }] },
    { messages: [{ role: 'user', content: [{ text: 'без типу' }] }] },
  ];
  for (const b of bad) {
    const { d, calls } = deps(modelReply([]));
    const r = await handle(post(b), d);
    assert.equal(r.status, 400, JSON.stringify(b));
    assert.equal(calls.length, 0);
  }
});

test('перевантаження чи ліміт Anthropic - 503 «спробувати пізніше»; інша помилка - 502', async () => {
  for (const s of [429, 500, 529]) {
    const { d } = deps(() => new Response('{}', { status: s }));
    const r = await handle(post(hello), d);
    assert.equal(r.status, 503);
    assert.deepEqual(await r.json(), { error: 'busy', retry: true });
  }
  const { d } = deps(() => new Response('{}', { status: 400 }));
  assert.equal((await handle(post(hello), d)).status, 502);
});

test('немає зв\'язку з Anthropic - 503', async () => {
  const { d } = deps(() => {
    throw new TypeError('fetch failed');
  });
  assert.equal((await handle(post(hello), d)).status, 503);
});

test('журнал: лише числа - без тексту розмови і без ключа', async () => {
  const { d, logs } = deps(modelReply([{ type: 'text', text: 'Таємна відповідь' }]));
  await handle(post({ messages: [{ role: 'user', content: 'Таємне питання' }] }), d);
  assert.equal(logs.length, 1);
  const line = JSON.parse(logs[0]);
  assert.deepEqual(Object.keys(line).sort(), [
    'cache_creation_input_tokens', 'cache_read_input_tokens', 'fn', 'input_tokens', 'model', 'output_tokens', 'result', 'steps',
  ]);
  assert.equal(line.input_tokens, 120);
  assert.equal(line.cache_read_input_tokens, 900);
  assert.doesNotMatch(logs[0], /Таємн|sk-ant/);
});

test('без інструментів запит не містить tools', () => {
  const b = buildRequest('m', [{ role: 'user', content: 'x' }], 'sys', []) as Record<string, unknown>;
  assert.equal('tools' in b, false);
  assert.equal((b.system as any[])[0].cache_control.type, 'ephemeral');
});

test('лише POST', async () => {
  const { d } = deps(modelReply([]));
  const r = await handle(new Request('https://x/assistant', { headers: { [TEST_TOKEN_HEADER]: TOKEN } }), d);
  assert.equal(r.status, 405);
});
