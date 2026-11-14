// Перевірка функції telegram-auth без Supabase і Telegram: фейковий сервер
// (Auth, база з функціями, що відповідають SQL з міграції) і фейковий
// Telegram. Саму SQL перевіряє telegram_login.test.sql.
//
//   node --test supabase/tests/telegram_auth.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { handle, hashSecret, pinProblem, sha256Hex, TG_DOMAIN, verifySecret } from '../functions/telegram-auth/index.ts';

const env = {
  url: 'https://x.supabase.co',
  anonKey: 'anon',
  serviceKey: 'service',
  botToken: 'bot-token',
  botUsername: 'vulyk_test_bot',
  webhookSecret: 'webhook-secret-123',
  pepper: 'pepper-pepper-pepper-1234',
  iterations: 1000,
};

type Req = { id: string; hash: string; match: number; device: string; link: string | null; tg: number | null; chat: number | null;
  phone: string | null; first: string | null; state: string };

function fake() {
  const requests = new Map<string, Req>();
  const idents = new Map<number, { user: string; chat: number; phone: string }>();
  const pins = new Map<string, { pin: string | null; rec: string | null; failed: number; lockouts: number; locked: number; disableAt: number | null }>();
  const users = new Map<string, string>(); // id -> email
  const tokens = new Map<string, string>(); // токен доступу -> id
  const seen = new Set<number>();
  const sent: { chat: number; text: string; markup?: any }[] = [];
  const signedOut: string[] = [];
  let now = 1_000_000;
  let nextUser = 1;

  const poll = (id: string, hash: string) => {
    const r = requests.get(id);
    if (!r || r.hash !== hash) return null;
    if (r.state !== 'approved') return { state: r.state, link: r.link !== null };
    const uid = idents.get(r.tg!)?.user ?? null;
    return { state: 'approved', telegram_id: r.tg, chat_id: r.chat, phone: r.phone, first_name: r.first,
      device: r.device, user_id: uid, pin: uid ? pinState(uid) : { state: 'none' } };
  };
  const pinState = (u: string) => {
    const p = pins.get(u);
    if (p && p.disableAt !== null && p.disableAt <= now) { p.pin = null; p.disableAt = null; }
    if (!p) return { state: 'none' };
    if (p.pin === null) return { state: 'off' };
    if (p.locked > now) return { state: 'locked', retry_in: p.locked - now };
    return { state: 'on', disable_at: p.disableAt };
  };

  const rpcs: Record<string, (a: any) => any> = {
    tg_login_create: (a) => {
      requests.set(a.p_id, { id: a.p_id, hash: a.p_secret_hash, match: a.p_match, device: a.p_device, link: a.p_link_user,
        tg: null, chat: null, phone: null, first: null, state: 'new' });
      return true;
    },
    tg_update_seen: (a) => (seen.has(a.p_update_id) ? false : (seen.add(a.p_update_id), true)),
    tg_login_open: (a) => {
      const r = requests.get(a.p_id);
      if (!r || !(r.state === 'new' || (r.state === 'opened' && r.tg === a.p_telegram_id))) return null;
      r.tg = a.p_telegram_id; r.chat = a.p_chat_id; r.state = 'opened';
      return { match: r.match, device: r.device, created_at: new Date(0).toISOString(), link: r.link !== null };
    },
    tg_login_match: (a) => {
      const r = requests.get(a.p_id);
      if (!r || r.tg !== a.p_telegram_id || r.state !== 'opened') return 'gone';
      if (r.match === a.p_code) { r.state = 'matched'; return 'ok'; }
      r.state = 'cancelled';
      return 'wrong';
    },
    tg_login_cancel: (a) => {
      const r = requests.get(a.p_id);
      if (!r || r.tg !== a.p_telegram_id) return false;
      r.state = 'cancelled';
      return true;
    },
    tg_login_contact: (a) => {
      const r = [...requests.values()].find((x) => x.tg === a.p_telegram_id && x.state === 'matched');
      if (!r) return 'none';
      r.state = 'approved'; r.phone = a.p_phone; r.first = a.p_first_name;
      return 'approved';
    },
    tg_login_poll: (a) => poll(a.p_id, a.p_secret_hash),
    tg_login_finish: (a) => {
      const r = requests.get(a.p_id);
      if (!r || r.hash !== a.p_secret_hash || r.state !== 'approved') return false;
      r.state = 'done';
      return true;
    },
    tg_identity_bind: (a) => {
      if (idents.has(a.p_telegram_id)) return false;
      idents.set(a.p_telegram_id, { user: a.p_user, chat: a.p_chat_id, phone: a.p_phone });
      return true;
    },
    tg_identity_seen: () => null,
    tg_identity_of: (a) => {
      for (const [tg, i] of idents) if (i.user === a.p_user) return { telegram_id: tg, chat_id: i.chat, phone: i.phone };
      return null;
    },
    tg_user_of: (a) => idents.get(a.p_telegram_id)?.user ?? null,
    pin_state: (a) => pinState(a.p_user),
    pin_attempt: (a) => {
      const p = pins.get(a.p_user);
      if (!p || p.pin === null || p.locked > now) return null;
      p.failed++;
      return { pin_hash: p.pin, recovery_hash: p.rec, failed: p.failed };
    },
    pin_result: (a) => {
      const p = pins.get(a.p_user)!;
      if (a.p_ok) { p.failed = 0; p.lockouts = 0; p.locked = 0; return 0; }
      if (p.failed < 5) return 0;
      const secs = Math.min(900 * 2 ** p.lockouts, 86400);
      p.failed = 0; p.lockouts++; p.locked = now + secs;
      return secs;
    },
    pin_set: (a) => {
      pins.set(a.p_user, { pin: a.p_pin_hash, rec: a.p_recovery_hash, failed: 0, lockouts: 0, locked: 0, disableAt: null });
      return null;
    },
    pin_disable: (a) => {
      const p = pins.get(a.p_user)!;
      if (a.p_at === null) { p.pin = null; p.disableAt = null; } else p.disableAt = now + 86400;
      return null;
    },
    pin_keep: (a) => {
      const p = pins.get(a.p_user);
      if (!p || p.disableAt === null) return false;
      p.disableAt = null;
      return true;
    },
    sign_out_everywhere: (a) => (signedOut.push(a.p_user), 2),
  };

  const fetchFn = (async (input: string | URL | Request, init: RequestInit = {}) => {
    const url = new URL(String(input));
    const h = new Headers(init.headers);
    const body = init.body ? JSON.parse(String(init.body)) : {};
    const ok = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status });
    if (url.hostname === 'api.telegram.org') {
      const method = url.pathname.split('/').pop();
      if (method === 'sendMessage') sent.push({ chat: body.chat_id, text: body.text, markup: body.reply_markup });
      return ok({ ok: true });
    }
    if (url.pathname === '/auth/v1/user') {
      const id = tokens.get((h.get('Authorization') ?? '').replace('Bearer ', ''));
      return id ? ok({ id, email: users.get(id) }) : ok({}, 401);
    }
    if (url.pathname === '/auth/v1/admin/users' && init.method === 'POST') {
      if (h.get('Authorization') !== 'Bearer service') return ok({}, 401);
      const id = `00000000-0000-0000-0000-${String(nextUser++).padStart(12, '0')}`;
      users.set(id, body.email);
      return ok({ id, email: body.email });
    }
    const um = /^\/auth\/v1\/admin\/users\/([0-9a-f-]{36})$/.exec(url.pathname);
    if (um) {
      if (init.method === 'DELETE') { users.delete(um[1]); return ok({}); }
      return users.has(um[1]) ? ok({ id: um[1], email: users.get(um[1]) }) : ok({}, 404);
    }
    if (url.pathname === '/auth/v1/admin/generate_link') {
      const id = [...users].find(([, e]) => e === body.email)?.[0];
      return id ? ok({ hashed_token: `ht-${id}` }) : ok({}, 404);
    }
    if (url.pathname === '/auth/v1/verify') {
      const id = String(body.token_hash).replace('ht-', '');
      const t = `at-${id}-${tokens.size}`;
      tokens.set(t, id);
      return ok({ access_token: t, refresh_token: `rt-${id}`, expires_in: 3600, user: { id, email: users.get(id) } });
    }
    const rm = /^\/rest\/v1\/rpc\/(\w+)$/.exec(url.pathname);
    if (rm) {
      if (h.get('Authorization') !== 'Bearer service') return ok({}, 401);
      const fn = rpcs[rm[1]];
      if (!fn) return ok({}, 404);
      return new Response(JSON.stringify(fn(body)), { status: 200 });
    }
    return ok({}, 404);
  }) as typeof fetch;

  return { fetchFn, requests, idents, pins, users, tokens, sent, signedOut, tick: (s: number) => { now += s; } };
}

type Fake = ReturnType<typeof fake>;

const app = (f: Fake, body: unknown, bearer?: string) =>
  handle(new Request('https://x.supabase.co/functions/v1/telegram-auth', {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}) },
    body: JSON.stringify(body) }), env, f.fetchFn);

let updateId = 1000;
const hook = (f: Fake, update: object, secret: string | null = env.webhookSecret) =>
  handle(new Request('https://x.supabase.co/functions/v1/telegram-auth/webhook', {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(secret ? { 'X-Telegram-Bot-Api-Secret-Token': secret } : {}) },
    body: JSON.stringify({ update_id: ++updateId, ...update }) }), env, f.fetchFn);

const say = (from: number, extra: object) => ({ message: { from: { id: from, first_name: 'Марія' }, chat: { id: from, type: 'private' }, ...extra } });
const press = (from: number, data: string) => ({ callback_query: { id: 'cb', data, from: { id: from }, message: { chat: { id: from } } } });
const contact = (from: number, who = from, extra: object = {}) => say(from, { contact: { phone_number: '380501112233', user_id: who }, ...extra });

const SECRET = 'S'.repeat(43);

/** Заявка від телефона: повертає id і число. */
async function start(f: Fake, secret = SECRET, bearer?: string) {
  const r = await app(f, { action: 'start', secret_hash: await sha256Hex(secret), device: 'Samsung A52' }, bearer);
  assert.equal(r.status, 200);
  return (await r.json()) as { id: string; match: number; url: string };
}

/** Людина відкриває бота, вибирає правильне число й ділиться контактом. */
async function approve(f: Fake, tg: number, req: { id: string; match: number }) {
  await hook(f, say(tg, { text: `/start ${req.id}` }));
  const prompt = f.sent.at(-1)!;
  const nums = prompt.markup.inline_keyboard[0].map((b: any) => b.callback_data as string);
  assert.ok(nums.includes(`m:${req.id}:${req.match}`), 'правильне число серед кнопок');
  await hook(f, press(tg, `m:${req.id}:${req.match}`));
  await hook(f, contact(tg));
}

test('вебхук без секретного заголовка чи з чужим відхиляється', async () => {
  const f = fake();
  assert.equal((await hook(f, say(1, { text: '/start x' }), null)).status, 401);
  assert.equal((await hook(f, say(1, { text: '/start x' }), 'wrong')).status, 401);
  assert.equal(f.sent.length, 0);
});

test('без секретної добавки функція не працює', async () => {
  const f = fake();
  const r = await handle(new Request('https://x/f', { method: 'POST', body: '{}' }), { ...env, pepper: 'short' }, f.fetchFn);
  assert.equal(r.status, 503);
});

test('новий акаунт: заявка, число, контакт, PIN, сесія, код відновлення; вдруге заявка не спрацює', async () => {
  const f = fake();
  const req = await start(f);
  assert.match(req.url, /^https:\/\/t\.me\/vulyk_test_bot\?start=/);
  assert.equal((await (await app(f, { action: 'poll', id: req.id, secret: SECRET })).json()).state, 'new');

  await approve(f, 501, req);
  assert.match(f.sent.at(-1)!.text, /підтверджено/);

  // чужий секрет нічого не дізнається
  assert.equal((await app(f, { action: 'poll', id: req.id, secret: 'X'.repeat(43) })).status, 404);
  const p = await (await app(f, { action: 'poll', id: req.id, secret: SECRET })).json();
  assert.equal(p.state, 'approved');
  assert.equal(p.next, 'pin_setup');

  // простий PIN і відсутній PIN не проходять
  assert.equal((await app(f, { action: 'finish', id: req.id, secret: SECRET, pin: '111111' })).status, 400);
  assert.equal((await app(f, { action: 'finish', id: req.id, secret: SECRET })).status, 400);
  assert.equal(f.users.size, 0, 'акаунт не створено без хорошого PIN');

  const ok = await app(f, { action: 'finish', id: req.id, secret: SECRET, pin: 'k7-Quartz-91' });
  assert.equal(ok.status, 200);
  const j = await ok.json();
  assert.ok(j.session.access_token && j.session.refresh_token);
  assert.match(j.recovery_code, /^[A-Z2-9]{5}(-[A-Z2-9]{5}){3}$/);
  assert.equal([...f.users.values()][0], `tg-501@${TG_DOMAIN}`);
  assert.ok(f.sent.at(-1)!.text.includes('Новий вхід'), 'повідомлення про вхід');
  const stored = [...f.pins.values()][0];
  assert.ok(!stored.pin!.includes('k7-Quartz'), 'PIN не зберігається відкрито');

  // вдруге ту саму заявку використати не можна
  assert.equal((await app(f, { action: 'finish', id: req.id, secret: SECRET, pin: 'k7-Quartz-91' })).status, 409);
});

test('не те число скасовує заявку; після цього контакт не приймається', async () => {
  const f = fake();
  const req = await start(f);
  await hook(f, say(501, { text: `/start ${req.id}` }));
  const wrong = req.match === 10 ? 11 : req.match - 1;
  await hook(f, press(501, `m:${req.id}:${wrong}`));
  assert.match(f.sent.at(-1)!.text, /скасовано/);
  assert.equal((await (await app(f, { action: 'poll', id: req.id, secret: SECRET })).json()).state, 'cancelled');
  await hook(f, contact(501));
  assert.match(f.sent.at(-1)!.text, /Немає активної заявки/);
});

test('чужий чи пересланий контакт не приймається', async () => {
  const f = fake();
  const req = await start(f);
  await hook(f, say(501, { text: `/start ${req.id}` }));
  await hook(f, press(501, `m:${req.id}:${req.match}`));
  await hook(f, contact(501, 777)); // номер іншої людини
  assert.match(f.sent.at(-1)!.text, /ваш номер/);
  await hook(f, contact(501, 501, { forward_origin: { type: 'user' } })); // пересланий
  assert.match(f.sent.at(-1)!.text, /ваш номер/);
  assert.equal((await (await app(f, { action: 'poll', id: req.id, secret: SECRET })).json()).state, 'matched');
  await hook(f, contact(501)); // власний - проходить
  assert.equal((await (await app(f, { action: 'poll', id: req.id, secret: SECRET })).json()).state, 'approved');
});

test('заявку не забере інший Telegram, а чужа людина не вгадає число', async () => {
  const f = fake();
  const req = await start(f);
  await hook(f, say(501, { text: `/start ${req.id}` }));
  await hook(f, say(777, { text: `/start ${req.id}` }));
  assert.match(f.sent.at(-1)!.text, /не знайдена/);
  await hook(f, press(777, `m:${req.id}:${req.match}`));
  assert.match(f.sent.at(-1)!.text, /застаріла/);
});

test('повтор того самого оновлення Telegram ігнорується', async () => {
  const f = fake();
  const req = await start(f);
  const u = { update_id: 777777, ...say(501, { text: `/start ${req.id}` }) };
  const send = () => handle(new Request('https://x/functions/v1/telegram-auth/webhook', {
    method: 'POST', headers: { 'X-Telegram-Bot-Api-Secret-Token': env.webhookSecret }, body: JSON.stringify(u) }), env, f.fetchFn);
  await send();
  const n = f.sent.length;
  await send();
  assert.equal(f.sent.length, n);
});

async function register(f: Fake, tg: number, pin: string) {
  const secret = String(tg).repeat(8).padEnd(43, 'a');
  const req = await start(f, secret);
  await approve(f, tg, req);
  const r = await (await app(f, { action: 'finish', id: req.id, secret, pin })).json();
  return { session: r.session, recovery: r.recovery_code as string };
}

test('повторний вхід: PIN, помилки, блокування, код відновлення', async () => {
  const f = fake();
  const first = await register(f, 501, 'k7-Quartz-91');

  const secret = 'T'.repeat(43);
  const req = await start(f, secret);
  await approve(f, 501, req);
  const p = await (await app(f, { action: 'poll', id: req.id, secret })).json();
  assert.equal(p.next, 'pin');
  const fin = (b: object) => app(f, { action: 'finish', id: req.id, secret, ...b });

  // без PIN і з чужим PIN - ні, і сесії немає
  assert.equal((await fin({})).status, 401);
  for (let i = 0; i < 3; i++) assert.equal((await fin({ pin: 'wrong-pin-1' })).status, 401);
  // п'ята помилка поспіль - блок і сповіщення власнику
  const blocked = await fin({ pin: 'wrong-pin-2' });
  assert.equal(blocked.status, 429);
  assert.ok((await blocked.json()).retry_in >= 900);
  assert.ok(f.sent.some((m) => m.text.includes('заблоковано')));
  // і правильний PIN під час блоку не допомагає
  assert.equal((await fin({ pin: 'k7-Quartz-91' })).status, 429);
  assert.equal((await (await app(f, { action: 'poll', id: req.id, secret })).json()).next, 'locked');

  // після блоку правильний PIN впускає
  f.tick(901);
  const ok = await fin({ pin: 'k7-Quartz-91' });
  assert.equal(ok.status, 200);
  assert.ok((await ok.json()).session.access_token);

  // код відновлення замість PIN: потрібен новий PIN і видається новий код
  const secret2 = 'U'.repeat(43);
  const req2 = await start(f, secret2);
  await approve(f, 501, req2);
  const rec = first.recovery.toLowerCase().replaceAll('-', ' ');
  const noNew = await app(f, { action: 'finish', id: req2.id, secret: secret2, recovery: rec });
  assert.equal(noNew.status, 400);
  const viaRec = await app(f, { action: 'finish', id: req2.id, secret: secret2, recovery: rec, new_pin: 'zz-New-Pin-55' });
  assert.equal(viaRec.status, 200);
  const j = await viaRec.json();
  assert.ok(j.recovery_code && j.recovery_code !== first.recovery);
});

test('налаштування PIN: потрібен вхід; вимкнення через добу для акаунта лише з Telegram', async () => {
  const f = fake();
  const { session } = await register(f, 501, 'k7-Quartz-91');
  const at = session.access_token as string;

  assert.equal((await app(f, { action: 'pin_status' })).status, 401);
  assert.equal((await app(f, { action: 'pin_status' }, 'bad-token')).status, 401);
  const st = await (await app(f, { action: 'pin_status' }, at)).json();
  assert.equal(st.state, 'on');
  assert.equal(st.telegram_only, true);

  // вимкнути без PIN не можна
  assert.equal((await app(f, { action: 'pin_disable', pin: 'nope-nope-1' }, at)).status, 401);
  const off = await (await app(f, { action: 'pin_disable', pin: 'k7-Quartz-91' }, at)).json();
  assert.equal(off.state, 'scheduled');
  assert.equal((await (await app(f, { action: 'pin_status' }, at)).json()).state, 'on', 'ще діє');
  const note = f.sent.at(-1)!;
  assert.match(note.text, /24 години/);

  // «Це не я» скасовує вимкнення й виводить усі пристрої
  await hook(f, press(501, 'keep'));
  assert.equal(f.signedOut.length, 1);
  assert.equal([...f.pins.values()][0].disableAt, null);

  // змінити PIN: потрібен чинний; новий код відновлення
  assert.equal((await app(f, { action: 'pin_set', pin: 'wrong-pin-1', new_pin: 'ab-Fresh-Pin-3' }, at)).status, 401);
  assert.equal((await app(f, { action: 'pin_set', pin: 'k7-Quartz-91', new_pin: '123456' }, at)).status, 400);
  const set = await (await app(f, { action: 'pin_set', pin: 'k7-Quartz-91', new_pin: 'ab-Fresh-Pin-3' }, at)).json();
  assert.ok(set.recovery_code);
  assert.equal((await (await app(f, { action: 'pin_check', pin: 'ab-Fresh-Pin-3' }, at)).json()).ok, true);
  assert.equal((await app(f, { action: 'pin_check', pin: 'k7-Quartz-91' }, at)).status, 401);
});

test('кнопка «Це не я» у сповіщенні виводить усі пристрої', async () => {
  const f = fake();
  await register(f, 501, 'k7-Quartz-91');
  await hook(f, press(501, 'out'));
  assert.equal(f.signedOut.length, 1);
  // чужий Telegram без акаунта нічого не виведе
  await hook(f, press(999, 'out'));
  assert.equal(f.signedOut.length, 1);
});

test('прив\'язка Telegram потребує входу', async () => {
  const f = fake();
  const r = await app(f, { action: 'start', secret_hash: await sha256Hex(SECRET) }, 'bad-token');
  assert.equal(r.status, 401);
});

test('PIN: надто прості відхиляються, хеш перевіряється', async () => {
  for (const p of ['', '12345', '123456', '111111', '987654', '000000', 'aaaaaaa', 'x'.repeat(65)]) {
    assert.ok(pinProblem(p), `відхилено: ${p}`);
  }
  assert.equal(pinProblem('k7-Quartz-91'), null);
  assert.equal(pinProblem('493817'), null);
  const h = await hashSecret(env, 'k7-Quartz-91');
  assert.ok(await verifySecret(env, 'k7-Quartz-91', h));
  assert.ok(!(await verifySecret(env, 'k7-Quartz-92', h)));
  assert.ok(!(await verifySecret({ ...env, pepper: 'another-pepper-1234567' }, 'k7-Quartz-91', h)));
  assert.ok(!(await verifySecret(env, 'x', null)));
  assert.ok(!(await verifySecret(env, 'x', 'p1$5$AAAA$AAAA')));
});
