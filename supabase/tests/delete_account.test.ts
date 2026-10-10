// Перевірка функції delete-account без Supabase: фейковий сервер (вхід,
// сховище, запрошення, акаунти).
//
//   node --test supabase/tests/delete_account.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { handle } from '../functions/delete-account/index.ts';

const OLENA = '00000000-0000-0000-0000-00000000000a';
const IVAN = '00000000-0000-0000-0000-00000000000c';
const env = { url: 'https://x.supabase.co', anonKey: 'anon', serviceKey: 'service' };

function fakeServer() {
  const users = new Map([
    ['t-olena', { id: OLENA, email: 'Olena@Gmail.com' }],
    ['t-ivan', { id: IVAN, email: 'ivan@gmail.com' }],
  ]);
  const accounts = new Set([OLENA, IVAN]);
  const files: Record<string, Set<string>> = {
    'stock-photos': new Set([`${OLENA}/a.webp`, `${OLENA}/a_t.webp`, `${IVAN}/b.webp`]),
    backups: new Set(Array.from({ length: 150 }, (_, i) => `${OLENA}/n${i}.db.gz`).concat([`${IVAN}/x.db.gz`])),
  };
  const invitations = [{ to_email: 'olena@gmail.com' }, { to_email: 'ivan@gmail.com' }];
  const prepared: string[] = [];
  const fetchFn = (async (input: string | URL | Request, init: RequestInit = {}) => {
    const url = new URL(String(input));
    const h = new Headers(init.headers);
    const method = init.method ?? 'GET';
    if (url.pathname === '/auth/v1/user') {
      const u = users.get((h.get('Authorization') ?? '').replace('Bearer ', ''));
      return u ? Response.json(u) : new Response('{}', { status: 401 });
    }
    assert.equal(h.get('Authorization'), 'Bearer service', `без ключа сервера: ${method} ${url}`);
    const list = url.pathname.match(/^\/storage\/v1\/object\/list\/(.+)$/);
    if (list && method === 'POST') {
      const { prefix, limit } = JSON.parse(String(init.body)) as { prefix: string; limit: number };
      const names = [...files[list[1]]].filter((f) => f.startsWith(prefix)).slice(0, limit);
      return Response.json(names.map((f) => ({ name: f.slice(prefix.length) })));
    }
    const del = url.pathname.match(/^\/storage\/v1\/object\/([^/]+)$/);
    if (del && method === 'DELETE') {
      for (const p of (JSON.parse(String(init.body)) as { prefixes: string[] }).prefixes) files[del[1]].delete(p);
      return Response.json([]);
    }
    if (url.pathname === '/rest/v1/rpc/delete_account_prepare' && method === 'POST') {
      const uid = (JSON.parse(String(init.body)) as { p_user: string }).p_user;
      const e = uid === OLENA ? 'olena@gmail.com' : 'ivan@gmail.com';
      for (let i = invitations.length - 1; i >= 0; i--) if (invitations[i].to_email === e) invitations.splice(i, 1);
      prepared.push(uid);
      return new Response(null, { status: 204 });
    }
    const acc = url.pathname.match(/^\/auth\/v1\/admin\/users\/(.+)$/);
    if (acc && method === 'DELETE') {
      return accounts.delete(acc[1]) ? Response.json({}) : new Response('{}', { status: 404 });
    }
    throw new Error(`неочікуваний запит ${method} ${url}`);
  }) as typeof fetch;
  return { fetchFn, accounts, files, invitations, prepared };
}

const call = (s: ReturnType<typeof fakeServer>, token: string) =>
  handle(new Request('https://f/delete-account', { method: 'POST', headers: { Authorization: `Bearer ${token}` } }), env, s.fetchFn);

test('видаляє файли, запрошення й акаунт лише того, хто викликав', async () => {
  const s = fakeServer();
  const r = await call(s, 't-olena');
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { status: 'deleted' });
  assert.ok(!s.accounts.has(OLENA));
  assert.ok(s.accounts.has(IVAN));
  assert.deepEqual([...s.files['stock-photos']], [`${IVAN}/b.webp`]);
  assert.deepEqual([...s.files.backups], [`${IVAN}/x.db.gz`]); // 150 копій - сторінками
  assert.deepEqual(s.invitations, [{ to_email: 'ivan@gmail.com' }]);
  assert.deepEqual(s.prepared, [OLENA]); // доступ - позначками, до видалення акаунта
});

test('без входу - нічого не видаляє; повторний виклик після видалення - без шкоди', async () => {
  const s = fakeServer();
  assert.equal((await call(s, 'bad')).status, 401);
  assert.equal(s.accounts.size, 2);
  assert.equal((await handle(new Request('https://f/x', { method: 'GET' }), env, s.fetchFn)).status, 405);
  await call(s, 't-olena');
  s.accounts.add(OLENA); // ще раз (скажімо, відповідь загубилась)
  s.accounts.delete(OLENA);
  assert.equal((await call(s, 't-olena')).status, 200);
});
