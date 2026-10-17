// Перевірка функції feedback без Supabase й без пошти: сховище в пам'яті,
// «Resend» - підставний fetch.
//
//   node --test supabase/tests/feedback.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { ADMIN_HEADER, DAILY_LIMIT, type Deps, handle, MemoryStore } from '../functions/feedback/index.ts';

const DEVICE = '3f2c1a9e-8b4d-4c11-9a52-0d6e7b8c9f10';
const SECRET = 'device-secret-0123456789';
const PASSWORD = 'admin-password-123';

function setup(extraEnv: Record<string, string> = {}) {
  let now = Date.parse('2026-10-17T12:00:00Z');
  const store = new MemoryStore(() => new Date(now).toISOString());
  const mails: any[] = [];
  const logs: string[] = [];
  const env: Record<string, string> = {
    FEEDBACK_ADMIN_PASSWORD: PASSWORD,
    RESEND_API_KEY: 're_test',
    FEEDBACK_NOTIFY_TO: 'dev@example.com',
    ...extraEnv,
  };
  const deps: Deps = {
    store,
    env: (n) => env[n],
    fetch: (async (url: string, init: RequestInit) => {
      mails.push({ url, headers: init.headers, body: JSON.parse(init.body as string) });
      return new Response('{}', { status: 200 });
    }) as typeof fetch,
    log: (l) => logs.push(l),
    now: () => now,
  };
  return { store, mails, logs, deps, advance: (ms: number) => (now += ms) };
}

const post = (body: unknown, headers: Record<string, string> = {}) =>
  new Request('https://x/functions/v1/feedback', { method: 'POST', headers, body: JSON.stringify(body) });
const app = (extra: Record<string, unknown>) => ({ device_id: DEVICE, secret: SECRET, ...extra });
const adm = (body: unknown, pw = PASSWORD) => post(body, { [ADMIN_HEADER]: pw });

test('відгук зберігається, розробнику - лист із текстом і платформою', async () => {
  const { deps, mails } = setup();
  const r = await handle(post(app({ action: 'send', body: 'Привіт, є ідея', platform: 'android 14' })), deps);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).message.body, 'Привіт, є ідея');
  assert.equal(mails.length, 1);
  assert.equal(mails[0].url, 'https://api.resend.com/emails');
  assert.equal(mails[0].headers.Authorization, 'Bearer re_test');
  assert.deepEqual(mails[0].body.to, ['dev@example.com']);
  assert.match(mails[0].body.text, /Привіт, є ідея/);
  assert.match(mails[0].body.text, /android 14/);
});

test('пошти не налаштовано - відгук усе одно збережено', async () => {
  const { deps, store, mails } = setup({ RESEND_API_KEY: '' });
  const r = await handle(post(app({ action: 'send', body: 'Без пошти' })), deps);
  assert.equal(r.status, 200);
  assert.equal(mails.length, 0);
  assert.equal(store.msgs.length, 1);
});

test('відповідь розробника доходить до застосунку (poll), по порядку', async () => {
  const { deps } = setup();
  await handle(post(app({ action: 'send', body: 'Питання' })), deps);
  const list = await (await handle(adm({ action: 'admin_list' }), deps)).json();
  assert.equal(list.threads.length, 1);
  assert.equal(list.threads[0].unread, true);
  const id = list.threads[0].id;
  const th = await (await handle(adm({ action: 'admin_thread', thread_id: id }), deps)).json();
  assert.deepEqual(th.messages.map((m: any) => [m.from_dev, m.body]), [[false, 'Питання']]);
  const rep = await handle(adm({ action: 'admin_reply', thread_id: id, body: 'Дякую, зробимо' }), deps);
  assert.equal(rep.status, 200);

  const all = await (await handle(post(app({ action: 'poll' })), deps)).json();
  assert.deepEqual(all.messages.map((m: any) => [m.from_dev, m.body]), [[false, 'Питання'], [true, 'Дякую, зробимо']]);
  // наступне опитування - лише нове
  const seq = all.messages.at(-1).seq;
  assert.deepEqual((await (await handle(post(app({ action: 'poll', after_seq: seq })), deps)).json()).messages, []);
  // «прочитано» після відкриття, нове від людини знову робить «непрочитаним»
  assert.equal((await (await handle(adm({ action: 'admin_list' }), deps)).json()).threads[0].unread, false);
  await handle(post(app({ action: 'send', body: 'Ще одне' })), deps);
  assert.equal((await (await handle(adm({ action: 'admin_list' }), deps)).json()).threads[0].unread, true);
});

test('чужий тред не прочитати: інший секрет - відмова; невідомий пристрій - порожньо', async () => {
  const { deps } = setup();
  await handle(post(app({ action: 'send', body: 'Таємне' })), deps);
  const bad = await handle(post({ device_id: DEVICE, secret: 'another-secret-0123456789', action: 'poll' }), deps);
  assert.equal(bad.status, 403);
  const bad2 = await handle(post({ device_id: DEVICE, secret: 'another-secret-0123456789', action: 'send', body: 'x' }), deps);
  assert.equal(bad2.status, 403);
  const other = await handle(post({ device_id: '11111111-2222-4333-8444-555555555555', secret: SECRET, action: 'poll' }), deps);
  assert.deepEqual(await other.json(), { messages: [] });
});

test('адмінка: без пароля чи з чужим - 401; слабкий пароль на сервері - теж', async () => {
  const { deps } = setup();
  assert.equal((await handle(post({ action: 'admin_list' }), deps)).status, 401);
  assert.equal((await handle(adm({ action: 'admin_list' }, 'wrong-password-123'), deps)).status, 401);
  const weak = setup({ FEEDBACK_ADMIN_PASSWORD: '123' });
  assert.equal((await handle(adm({ action: 'admin_list' }, '123'), weak.deps)).status, 401);
  const none = setup({ FEEDBACK_ADMIN_PASSWORD: '' });
  assert.equal((await handle(adm({ action: 'admin_list' }, ''), none.deps)).status, 401);
});

test('додаток не може користуватися адмін-діями (немає секретів - немає доступу)', async () => {
  const { deps } = setup();
  const r = await handle(post(app({ action: 'admin_reply', thread_id: DEVICE, body: 'x' })), deps);
  assert.equal(r.status, 401);
});

test('ліміт: не більше ' + DAILY_LIMIT + ' відгуків за добу, наступної доби - знову можна', async () => {
  const { deps, advance } = setup();
  for (let i = 0; i < DAILY_LIMIT; i++) {
    assert.equal((await handle(post(app({ action: 'send', body: `m${i}` })), deps)).status, 200);
  }
  assert.equal((await handle(post(app({ action: 'send', body: 'забагато' })), deps)).status, 429);
  advance(25 * 3600 * 1000);
  assert.equal((await handle(post(app({ action: 'send', body: 'вже можна' })), deps)).status, 200);
});

test('порожнє, довге, зіпсоване - відмова або обрізання', async () => {
  const { deps } = setup();
  assert.equal((await handle(post(app({ action: 'send', body: '   ' })), deps)).status, 400);
  assert.equal((await handle(post({ action: 'send', body: 'x', device_id: 'не-uuid', secret: SECRET }), deps)).status, 400);
  assert.equal((await handle(post({ action: 'send', body: 'x', device_id: DEVICE, secret: 'коротко' }), deps)).status, 400);
  const long = await (await handle(post(app({ action: 'send', body: 'я'.repeat(9000) })), deps)).json();
  assert.equal(long.message.body.length, 5000);
  assert.equal((await handle(new Request('https://x', { method: 'POST', body: '{не json' }), deps)).status, 400);
  assert.equal((await handle(new Request('https://x'), deps)).status, 405);
});

test('журнал: лише лічильники - без тексту й секретів', async () => {
  const { deps, logs } = setup();
  await handle(post(app({ action: 'send', body: 'Дуже особисте' })), deps);
  await handle(adm({ action: 'admin_list' }, 'wrong-password-123'), deps);
  assert.ok(logs.length >= 2);
  for (const l of logs) assert.doesNotMatch(l, /особисте|device-secret|admin-password|wrong-password/);
});

test('CORS: адмін-сторінка з іншої адреси може викликати функцію', async () => {
  const { deps } = setup();
  const pre = await handle(new Request('https://x', { method: 'OPTIONS' }), deps);
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get('Access-Control-Allow-Origin'), '*');
  assert.match(pre.headers.get('Access-Control-Allow-Headers') ?? '', /x-feedback-admin/);
});

test('адмін-сторінка: HTML на місці, пароль у ній не зашито, адреса - наша функція', () => {
  const html = readFileSync(new URL('../../admin/feedback.html', import.meta.url), 'utf8');
  assert.match(html, /functions\/v1\/feedback/);
  assert.match(html, /x-feedback-admin/);
  assert.doesNotMatch(html, /FEEDBACK_ADMIN_PASSWORD\s*=\s*['"]/);
  // тексти розмов - лише через textContent (без innerHTML - немає вставки розмітки)
  assert.doesNotMatch(html, /innerHTML/);
});
