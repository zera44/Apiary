// Вхід і денний ліміт помічника (functions/assistant/access.ts) без Supabase:
// замість Supabase Auth і бази - фейковий fetch.
//
//   node --test supabase/tests/assistant_access.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { dailyLimit, DEFAULT_DAILY_LIMIT, jwtAccess, rpcUsage } from '../functions/assistant/access.ts';
import { type Deps, handle } from '../functions/assistant/index.ts';

const USER = '22222222-2222-4222-8222-222222222222';
const ENV: Record<string, string> = {
  SUPABASE_URL: 'https://p.supabase.co/',
  SUPABASE_ANON_KEY: 'anon-key',
  SUPABASE_SERVICE_ROLE_KEY: 'service-key',
  ANTHROPIC_API_KEY: 'sk-ant-test',
};
const env = (e: Record<string, string> = ENV) => (n: string) => e[n];

type Seen = { url: string; headers: Record<string, string>; body?: any };
function fakeFetch(reply: (s: Seen) => Response | Promise<Response>) {
  const seen: Seen[] = [];
  const f = (async (url: string, init: RequestInit = {}) => {
    const s = { url, headers: (init.headers ?? {}) as Record<string, string>, body: init.body ? JSON.parse(init.body as string) : undefined };
    seen.push(s);
    return reply(s);
  }) as typeof fetch;
  return { f, seen };
}
const userReply = (u: unknown, status = 200) => () => new Response(JSON.stringify(u), { status });
const req = (auth?: string) =>
  new Request('https://x/functions/v1/assistant', { method: 'POST', headers: auth == null ? {} : { Authorization: auth } });

// ── вхід ────────────────────────────────────────────────────────────────

test('дійсний токен: пускає, людина - з відповіді Supabase Auth, токен іде лише туди', async () => {
  const { f, seen } = fakeFetch(userReply({ id: USER.toUpperCase(), email: 'a@b.c' }));
  const a = await jwtAccess(req('Bearer abc.def.ghi'), env(), f);
  assert.deepEqual(a, { ok: true, subject: USER });
  assert.equal(seen.length, 1);
  assert.equal(seen[0].url, 'https://p.supabase.co/auth/v1/user');
  assert.equal(seen[0].headers.Authorization, 'Bearer abc.def.ghi');
  assert.equal(seen[0].headers.apikey, 'anon-key');
});

test('немає чи кривий заголовок - 401 і до Supabase не звертаємось', async () => {
  for (const h of [undefined, '', 'abc', 'Basic abc', 'Bearer', 'Bearer a b', 'Bearer ' + 'x'.repeat(5000)]) {
    const { f, seen } = fakeFetch(userReply({ id: USER }));
    const a = await jwtAccess(req(h), env(), f);
    assert.deepEqual(a, { ok: false, status: 401, error: 'unauthorized' }, String(h).slice(0, 20));
    assert.equal(seen.length, 0);
  }
});

test('Supabase відхилив токен (401/403) - 401', async () => {
  for (const st of [401, 403]) {
    const { f } = fakeFetch(userReply({ msg: 'bad' }, st));
    const a = await jwtAccess(req('Bearer t'), env(), f);
    assert.equal(a.ok, false);
    assert.equal((a as any).status, 401);
  }
});

test('Supabase недоступний (мережа, 5xx, 429, не JSON) - 503, а не 401: застосунок повторить пізніше', async () => {
  const bad: (() => Response | Promise<Response>)[] = [
    () => { throw new Error('network'); },
    userReply({}, 500),
    userReply({}, 429),
    () => new Response('<html>', { status: 200 }),
  ];
  for (const r of bad) {
    const { f } = fakeFetch(r);
    const a = await jwtAccess(req('Bearer t'), env(), f);
    assert.deepEqual(a, { ok: false, status: 503, error: 'busy' });
  }
});

test('відповідь без нормального id або анонімний вхід - 401', async () => {
  for (const u of [{}, { id: 'not-a-uuid' }, { id: 5 }, null, { id: USER, is_anonymous: true }]) {
    const { f } = fakeFetch(userReply(u));
    const a = await jwtAccess(req('Bearer t'), env(), f);
    assert.equal(a.ok, false);
    assert.equal((a as any).status, 401);
  }
  const { f } = fakeFetch(userReply({ id: USER, is_anonymous: false }));
  assert.equal((await jwtAccess(req('Bearer t'), env(), f)).ok, true);
});

test('сервер без SUPABASE_URL чи ключа - not_configured, а не мовчазне «пускаю»', async () => {
  for (const drop of ['SUPABASE_URL', 'SUPABASE_ANON_KEY']) {
    const e = { ...ENV };
    delete e[drop];
    const { f, seen } = fakeFetch(userReply({ id: USER }));
    const a = await jwtAccess(req('Bearer t'), env(e), f);
    assert.deepEqual(a, { ok: false, status: 500, error: 'not_configured' });
    assert.equal(seen.length, 0);
  }
});

// ── ліміт ───────────────────────────────────────────────────────────────

test('dailyLimit: типово 200; секрет лише ціле 1..10000', () => {
  assert.equal(DEFAULT_DAILY_LIMIT, 200);
  assert.equal(dailyLimit(env({})), 200);
  assert.equal(dailyLimit(env({ ASSISTANT_DAILY_LIMIT: '50' })), 50);
  assert.equal(dailyLimit(env({ ASSISTANT_DAILY_LIMIT: ' 10000 ' })), 10000);
  for (const bad of ['0', '-5', '10001', 'abc', '1e3', '12.5', '']) {
    assert.equal(dailyLimit(env({ ASSISTANT_DAILY_LIMIT: bad })), 200, bad);
  }
});

test('rpcUsage: службовий ключ, людина й ліміт - у тілі; true -> ok, false -> limit', async () => {
  const ok = fakeFetch(userReply(true));
  assert.equal(await rpcUsage(USER, env({ ...ENV, ASSISTANT_DAILY_LIMIT: '7' }), ok.f), 'ok');
  assert.equal(ok.seen[0].url, 'https://p.supabase.co/rest/v1/rpc/assistant_hit');
  assert.equal(ok.seen[0].headers.Authorization, 'Bearer service-key');
  assert.deepEqual(ok.seen[0].body, { p_user: USER, p_limit: 7 });

  const over = fakeFetch(userReply(false));
  assert.equal(await rpcUsage(USER, env(), over.f), 'limit');
});

test('rpcUsage: будь-який збій перевірки - error (не пускаємо), навіть дивна відповідь', async () => {
  const cases: (() => Response | Promise<Response>)[] = [
    userReply({}, 500),
    userReply({ message: 'no function' }, 404),
    userReply('true'),
    userReply(null),
    () => { throw new Error('network'); },
  ];
  for (const r of cases) {
    const { f } = fakeFetch(r);
    assert.equal(await rpcUsage(USER, env(), f), 'error');
  }
  const { f, seen } = fakeFetch(userReply(true));
  assert.equal(await rpcUsage(USER, env({ SUPABASE_URL: 'https://p.supabase.co' }), f), 'error');
  assert.equal(seen.length, 0);
});

// ── разом із посередником ───────────────────────────────────────────────

function wired(usage: 'ok' | 'limit' | 'error') {
  const anthropic: string[] = [];
  const logs: string[] = [];
  const d: Deps = {
    env: env(),
    fetch: (async (url: string) => {
      anthropic.push(url);
      return new Response(JSON.stringify({ content: [{ type: 'text', text: 'Привіт' }], stop_reason: 'end_turn', usage: {} }), { status: 200 });
    }) as typeof fetch,
    log: (l) => logs.push(l),
    access: async () => ({ ok: true, subject: USER }),
    usage: async (u) => {
      assert.equal(u, USER);
      return usage;
    },
    tools: [],
  };
  return { d, anthropic, logs };
}
const post = (body: unknown) =>
  new Request('https://x/functions/v1/assistant', { method: 'POST', body: JSON.stringify(body) });
const hello = { messages: [{ role: 'user', content: 'Скільки в мене пасік?' }] };

test('ліміт вичерпано - 429 daily_limit, Anthropic і книги не викликаються', async () => {
  for (const body of [hello, { action: 'search_books', query: 'мед' }]) {
    const { d, anthropic, logs } = wired('limit');
    const r = await handle(post(body), d);
    assert.equal(r.status, 429);
    assert.deepEqual(await r.json(), { error: 'daily_limit' });
    assert.equal(anthropic.length, 0);
    assert.ok(logs.some((l) => l.includes('daily_limit')));
    assert.equal(logs.join('').includes(USER), false, 'людину в журнал не пишемо');
  }
});

test('ліміт не перевірити - 503 busy з повтором, Anthropic не викликається', async () => {
  const { d, anthropic } = wired('error');
  const r = await handle(post(hello), d);
  assert.equal(r.status, 503);
  assert.deepEqual(await r.json(), { error: 'busy', retry: true });
  assert.equal(anthropic.length, 0);
});

test('ліміт є - запит іде до моделі', async () => {
  const { d, anthropic } = wired('ok');
  const r = await handle(post(hello), d);
  assert.equal(r.status, 200);
  assert.equal(anthropic.length, 1);
});

test('відмова входу раніше за ліміт: чужий не з\'їдає чужий ліміт', async () => {
  let counted = 0;
  const { d } = wired('ok');
  d.access = async () => ({ ok: false, status: 401, error: 'unauthorized' });
  d.usage = async () => {
    counted++;
    return 'ok';
  };
  const r = await handle(post(hello), d);
  assert.equal(r.status, 401);
  assert.equal(counted, 0);
});
