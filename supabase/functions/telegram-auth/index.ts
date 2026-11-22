// Вхід через Telegram-бота й PIN.
//
// Одна функція, два входи:
//   * POST …/telegram-auth/webhook - оновлення від Telegram (бот). Приймаються
//     лише із секретним заголовком, який Telegram додає до кожного запиту.
//   * POST …/telegram-auth - дії застосунку (поле action): start, poll, finish
//     (вхід), recovery_send (код відновлення в Telegram), pin_status, pin_set, pin_check, pin_disable, sign_out_everywhere.
//
// Вхід (див. міграцію 20261115000100_telegram_login.sql):
//   1. start: телефон надсилає відбиток секрету S, сервер створює заявку R
//      (5 хв) і число для звірки.
//   2. Бот за посиланням t.me/<бот>?start=R показує пристрій і час та просить
//      вибрати число, яке видно в застосунку. Потім просить поділитися
//      контактом: приймається лише власний (contact.user_id = from.id), не
//      пересланий.
//   3. poll: телефон з R і S питає, чи підтверджено, і що робити далі
//      (створити PIN, ввести PIN, або одразу війти).
//   4. finish: перевіряє PIN (або код відновлення), завершає заявку рівно
//      один раз, видає сесію Supabase. Новий акаунт створюється тут і лише з
//      PIN.
//
// PIN: PBKDF2-SHA256 із випадковою сіллю та секретною добавкою сервера
// (PIN_PEPPER); спроби лічить база ДО перевірки, п'ята помилка поспіль -
// блок на 15 хв (далі вдвічі довше, до доби).
//
// Без залежностей (лише fetch і WebCrypto): той самий файл перевіряє тест на
// Node (tests/telegram_auth.test.ts).
//
// Секрети (Supabase → Edge Functions → Secrets): TELEGRAM_BOT_TOKEN,
// TELEGRAM_BOT_USERNAME, TELEGRAM_WEBHOOK_SECRET, PIN_PEPPER. Публічна (без
// входу): розгортати з --no-verify-jwt; вхід користувача функція перевіряє сама.

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

export type Env = {
  url: string;
  anonKey: string;
  serviceKey: string;
  botToken: string;
  botUsername: string;
  webhookSecret: string;
  pepper: string;
  /** Кількість кроків PBKDF2 (у тестах - менше). */
  iterations?: number;
};

type Fetch = typeof fetch;
type Json = Record<string, any>;

export const TG_DOMAIN = 'tg.vulyk.invalid';
const ITERATIONS = 210000;
const ID = /^[A-Za-z0-9_-]{22}$/;
const enc = new TextEncoder();

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

// ── криптографія ───────────────────────────────────────────────────────

function b64(buf: ArrayBuffer | Uint8Array): string {
  return btoa(String.fromCharCode(...new Uint8Array(buf)));
}

function unb64(s: string): Uint8Array {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

function b64url(buf: Uint8Array): string {
  return b64(buf).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

export async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', enc.encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function same(a: Uint8Array | string, b: Uint8Array | string): boolean {
  const x = typeof a === 'string' ? enc.encode(a) : a;
  const y = typeof b === 'string' ? enc.encode(b) : b;
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

async function derive(env: Env, value: string, salt: Uint8Array, iterations: number): Promise<ArrayBuffer> {
  const key = await crypto.subtle.importKey('raw', enc.encode(value), 'PBKDF2', false, ['deriveBits']);
  const full = new Uint8Array([...salt, ...enc.encode(env.pepper)]);
  return crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: full, iterations }, key, 256);
}

export async function hashSecret(env: Env, value: string): Promise<string> {
  const it = env.iterations ?? ITERATIONS;
  const salt = crypto.getRandomValues(new Uint8Array(16));
  return `p1$${it}$${b64(salt)}$${b64(await derive(env, value, salt, it))}`;
}

export async function verifySecret(env: Env, value: string, stored: string | null | undefined): Promise<boolean> {
  const p = (stored ?? '').split('$');
  if (p.length !== 4 || p[0] !== 'p1') return false;
  const it = Number(p[1]);
  if (!Number.isInteger(it) || it < 1000 || it > 1_000_000) return false;
  const got = new Uint8Array(await derive(env, value, unb64(p[2]), it));
  return same(got, unb64(p[3]));
}

function randomInt(max: number): number {
  const limit = Math.floor(0x100000000 / max) * max;
  const a = new Uint32Array(1);
  do crypto.getRandomValues(a); while (a[0] >= limit);
  return a[0] % max;
}

const RECOVERY_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 32 знаки, без схожих

function newRecovery(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const chars = [...bytes].map((b) => RECOVERY_ALPHABET[b % 32]);
  return `${chars.slice(0, 4).join('')}-${chars.slice(4).join('')}`;
}

/** Скільки живе код відновлення, і як часто його можна просити. */
const RECOVERY_TTL_SECS = 300;
const RECOVERY_GAP_SECS = 30;
const RECOVERY_PER_HOUR = 5;
/** Новий PIN після відновлення, коли в акаунті є інші пристрої, діє через добу. */
const RECOVERY_DELAY_SECS = 24 * 3600;

function normalizeRecovery(s: string): string {
  return s.toUpperCase().replace(/[^A-Z0-9]/g, '');
}

const WEAK = new Set(['123456', '1234567', '12345678', '123456789', '654321', '121212', '123123', '112233', '159753']);

/** null - добрий PIN; інакше причина відмови. */
export function pinProblem(pin: unknown): string | null {
  if (typeof pin !== 'string' || pin.length < 6 || pin.length > 64) return 'PIN має містити від 6 до 64 знаків';
  if (/^(.)\1*$/.test(pin) || WEAK.has(pin)) return 'Надто простий PIN';
  if (/^\d+$/.test(pin)) {
    const up = '0123456789012345678901234567890123456789'.includes(pin);
    const down = '9876543210987654321098765432109876543210'.includes(pin);
    if (up || down) return 'Надто простий PIN';
  }
  return null;
}

// ── Supabase ───────────────────────────────────────────────────────────

class Server {
  env: Env;
  f: Fetch;
  constructor(env: Env, f: Fetch) {
    this.env = env;
    this.f = f;
  }

  get admin(): Record<string, string> {
    return { apikey: this.env.serviceKey, Authorization: `Bearer ${this.env.serviceKey}` };
  }

  async rpc(name: string, args: Json): Promise<any> {
    const r = await this.f(`${this.env.url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { ...this.admin, 'Content-Type': 'application/json' },
      body: JSON.stringify(args),
    });
    if (!r.ok) throw new Error(`${name}: ${r.status}`);
    const t = await r.text();
    return t ? JSON.parse(t) : null;
  }

  /** Хто увійшов за заголовком Authorization. null - ніхто. */
  async whoami(req: Request): Promise<{ id: string; email: string } | null> {
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return null;
    const r = await this.f(`${this.env.url}/auth/v1/user`, {
      headers: { apikey: this.env.anonKey, Authorization: auth },
    });
    if (!r.ok) return null;
    const u = (await r.json()) as { id?: string; email?: string };
    if (!u.id || !/^[0-9a-f-]{36}$/i.test(u.id)) return null;
    return { id: u.id, email: (u.email ?? '').toLowerCase() };
  }

  async createUser(telegramId: number, name: string): Promise<string | null> {
    const r = await this.f(`${this.env.url}/auth/v1/admin/users`, {
      method: 'POST',
      headers: { ...this.admin, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: `tg-${telegramId}@${TG_DOMAIN}`,
        email_confirm: true,
        user_metadata: { full_name: name, provider: 'telegram' },
      }),
    });
    if (!r.ok) return null;
    return ((await r.json()) as { id?: string }).id ?? null;
  }

  async deleteUser(id: string): Promise<void> {
    await this.f(`${this.env.url}/auth/v1/admin/users/${id}`, { method: 'DELETE', headers: this.admin });
  }

  /** Сесія Supabase для користувача: одноразове посилання входу, одразу погашене. */
  async mintSession(userId: string): Promise<Json | null> {
    const u = await this.f(`${this.env.url}/auth/v1/admin/users/${userId}`, { headers: this.admin });
    if (!u.ok) return null;
    const email = ((await u.json()) as { email?: string }).email;
    if (!email) return null;
    const g = await this.f(`${this.env.url}/auth/v1/admin/generate_link`, {
      method: 'POST',
      headers: { ...this.admin, 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'magiclink', email }),
    });
    if (!g.ok) return null;
    const hashed = ((await g.json()) as { hashed_token?: string }).hashed_token;
    if (!hashed) return null;
    const v = await this.f(`${this.env.url}/auth/v1/verify`, {
      method: 'POST',
      headers: { apikey: this.env.anonKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'magiclink', token_hash: hashed }),
    });
    if (!v.ok) return null;
    const s = (await v.json()) as Json;
    return s.access_token && s.refresh_token ? s : null;
  }
}

// ── Telegram ───────────────────────────────────────────────────────────

type Button = { text: string; callback_data: string };

class Bot {
  env: Env;
  f: Fetch;
  constructor(env: Env, f: Fetch) {
    this.env = env;
    this.f = f;
  }

  async call(method: string, body: Json): Promise<void> {
    try {
      await this.f(`https://api.telegram.org/bot${this.env.botToken}/${method}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
    } catch {
      // Telegram недоступний - вхід не ламаємо
    }
  }

  /** Надіслати й повернути номер повідомлення (null - Telegram недоступний). */
  async send(chat: number, text: string, rows: Button[][]): Promise<number | null> {
    try {
      const r = await this.f(`https://api.telegram.org/bot${this.env.botToken}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_id: chat, text, reply_markup: { inline_keyboard: rows } }),
      });
      const j = (await r.json()) as Json;
      const id = j?.result?.message_id;
      return typeof id === 'number' ? id : null;
    } catch {
      return null;
    }
  }

  /** Замінити текст повідомлення (і прибрати кнопки під ним). */
  edit(chat: number, messageId: number, text: string): Promise<void> {
    return this.call('editMessageText', { chat_id: chat, message_id: messageId, text });
  }

  say(chat: number, text: string, markup?: Json): Promise<void> {
    return this.call('sendMessage', { chat_id: chat, text, ...(markup ? { reply_markup: markup } : {}) });
  }

  sayButtons(chat: number, text: string, rows: Button[][]): Promise<void> {
    return this.say(chat, text, { inline_keyboard: rows });
  }
}

function kyivTime(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleTimeString('uk-UA', { timeZone: 'Europe/Kyiv', hour: '2-digit', minute: '2-digit' });
}

/** Повідомити власника акаунта в його Telegram (якщо прив'язано). */
async function notify(srv: Server, bot: Bot, userId: string, text: string, buttons?: Button[][]): Promise<void> {
  const ident = (await srv.rpc('tg_identity_of', { p_user: userId })) as Json | null;
  if (!ident?.chat_id) return;
  if (buttons) await bot.sayButtons(Number(ident.chat_id), text, buttons);
  else await bot.say(Number(ident.chat_id), text);
}

const NOT_ME: Button[][] = [[{ text: 'Це не я: вийти всюди', callback_data: 'out' }]];

// ── перевірка PIN ──────────────────────────────────────────────────────

type PinCheck = { ok: true; byRecovery: boolean } | { ok: false; retryIn: number; missing?: boolean };

/** Перевірити PIN (або код відновлення). Спроба зараховується до перевірки.
 *  Код відновлення діє лише в заявці [requestId], для якої його попросили. */
async function checkPin(
  srv: Server, bot: Bot, userId: string, pin: unknown, recovery: unknown, requestId?: string,
): Promise<PinCheck> {
  const a = (await srv.rpc('pin_attempt', { p_user: userId })) as Json | null;
  if (!a) {
    const st = (await srv.rpc('pin_state', { p_user: userId })) as Json;
    return { ok: false, retryIn: Number(st.retry_in ?? 0), missing: st.state !== 'locked' };
  }
  const byPin = typeof pin === 'string' && pin.length > 0 && pin.length <= 64 && (await verifySecret(srv.env, pin, a.pin_hash));
  const byRec =
    !byPin && typeof recovery === 'string' && recovery.length <= 64 &&
    requestId !== undefined && a.recovery_request === requestId &&
    (await verifySecret(srv.env, normalizeRecovery(recovery), a.recovery_hash));
  if (byPin || byRec) {
    await srv.rpc('pin_result', { p_user: userId, p_ok: true });
    return { ok: true, byRecovery: byRec };
  }
  const secs = Number(await srv.rpc('pin_result', { p_user: userId, p_ok: false }));
  if (secs > 0) {
    await notify(
      srv, bot, userId,
      `Кілька разів введено неправильний PIN. Вхід заблоковано на ${Math.round(secs / 60)} хв. Якщо це були не ви, натисніть кнопку.`,
      NOT_ME,
    );
  }
  return { ok: false, retryIn: secs };
}

function pinFailure(c: Extract<PinCheck, { ok: false }>): Response {
  if (c.missing) return json({ error: 'pin_state_changed' }, 409);
  if (c.retryIn > 0) return json({ error: 'locked', retry_in: c.retryIn }, 429);
  return json({ error: 'wrong_pin' }, 401);
}

// ── дії застосунку ─────────────────────────────────────────────────────

function clientIp(req: Request): string {
  const f = req.headers.get('x-forwarded-for') ?? req.headers.get('cf-connecting-ip') ?? '';
  return f.split(',')[0].trim().slice(0, 64);
}

async function readBody(req: Request): Promise<Json | null> {
  const len = Number(req.headers.get('content-length') ?? '0');
  if (len > 4096) return null;
  try {
    const t = await req.text();
    if (t.length > 4096) return null;
    const j = JSON.parse(t);
    return j && typeof j === 'object' && !Array.isArray(j) ? j : null;
  } catch {
    return null;
  }
}

async function loadRequest(srv: Server, body: Json): Promise<{ id: string; hash: string; r: Json } | Response> {
  const id = body.id, secret = body.secret;
  if (typeof id !== 'string' || !ID.test(id) || typeof secret !== 'string' || secret.length < 20 || secret.length > 128) {
    return json({ error: 'bad_request' }, 400);
  }
  const hash = await sha256Hex(secret);
  const r = (await srv.rpc('tg_login_poll', { p_id: id, p_secret_hash: hash })) as Json | null;
  if (!r) return json({ state: 'unknown' }, 404);
  return { id, hash, r };
}

function nextStep(r: Json): { next: string; retry_in?: number } {
  if (!r.user_id) return { next: 'pin_setup' };
  const st = (r.pin ?? {}) as Json;
  if (st.state === 'locked') return { next: 'locked', retry_in: Number(st.retry_in ?? 0) };
  if (st.state === 'on') return { next: 'pin' };
  return { next: 'ready' };
}

async function app(req: Request, srv: Server, bot: Bot): Promise<Response> {
  const body = await readBody(req);
  if (!body) return json({ error: 'bad_request' }, 400);
  const action = body.action;

  if (action === 'start') {
    const hash = body.secret_hash;
    if (typeof hash !== 'string' || !/^[0-9a-f]{64}$/.test(hash)) return json({ error: 'bad_request' }, 400);
    let link: string | null = null;
    if (req.headers.get('Authorization')) {
      const who = await srv.whoami(req);
      if (!who) return json({ error: 'потрібен вхід' }, 401);
      link = who.id;
    }
    const id = b64url(crypto.getRandomValues(new Uint8Array(16)));
    const match = 10 + randomInt(90);
    const ok = await srv.rpc('tg_login_create', {
      p_id: id, p_secret_hash: hash, p_match: match,
      p_device: String(body.device ?? '').slice(0, 60), p_ip: clientIp(req), p_link_user: link,
    });
    if (!ok) return json({ error: 'too_many' }, 429);
    return json({ id, match, url: `https://t.me/${srv.env.botUsername}?start=${id}`, expires_in: 300 });
  }

  if (action === 'poll') {
    const l = await loadRequest(srv, body);
    if (l instanceof Response) return l;
    const { r } = l;
    if (r.state !== 'approved') return json({ state: r.state, link: r.link === true });
    return json({ state: 'approved', device: r.device, recovery_ok: r.recovery_ok === true, ...nextStep(r) });
  }

  // Код відновлення: надіслати в Telegram власника (5 хв, один раз) із кнопкою «Це я».
  if (action === 'recovery_send') {
    const l = await loadRequest(srv, body);
    if (l instanceof Response) return l;
    const { id, r } = l;
    if (r.state !== 'approved' || !r.user_id) return json({ error: 'not_approved', state: r.state }, 409);
    const st = (r.pin ?? {}) as Json;
    if (st.state === 'locked') return json({ error: 'locked', retry_in: Number(st.retry_in ?? 0) }, 429);
    if (st.state !== 'on') return json({ error: 'pin_state_changed' }, 409);
    const code = newRecovery();
    const wait = Number(await srv.rpc('pin_recovery_issue', {
      p_user: r.user_id,
      p_request: id,
      p_hash: await hashSecret(srv.env, normalizeRecovery(code)),
      p_ttl_secs: RECOVERY_TTL_SECS,
      p_gap_secs: RECOVERY_GAP_SECS,
      p_per_hour: RECOVERY_PER_HOUR,
    }));
    if (wait < 0) return json({ error: 'pin_state_changed' }, 409);
    if (wait > 0) return json({ error: 'too_soon', retry_in: wait }, 429);
    const msg = await bot.send(
      Number(r.chat_id),
      `Відновлення доступу до Vulyk${r.device ? ` з пристрою ${r.device}` : ''}.\n\n` +
        `Код: ${code}\nДіє ${RECOVERY_TTL_SECS / 60} хв, використати можна один раз.\n\n` +
        'Натисніть «Це я»: застосунок сам перейде до нового PIN. Якщо ви нічого не просили, натисніть «Це не я» і нікому не повідомляйте код.',
      [[{ text: 'Це я: відновити доступ', callback_data: `r:${id}` }], ...NOT_ME],
    );
    if (msg !== null) await srv.rpc('pin_recovery_msg', { p_user: r.user_id, p_msg: msg });
    return json({ ok: true, expires_in: RECOVERY_TTL_SECS });
  }

  if (action === 'finish') {
    const l = await loadRequest(srv, body);
    if (l instanceof Response) return l;
    const { id, hash, r } = l;
    if (r.state !== 'approved') return json({ error: 'not_approved', state: r.state }, 409);
    const tid = Number(r.telegram_id), chat = Number(r.chat_id);
    let userId: string | null = r.user_id ?? null;
    let created = false;

    if (!userId) {
      const problem = pinProblem(body.pin);
      if (problem) return json({ error: 'bad_pin', message: problem }, 400);
      userId = await srv.createUser(tid, String(r.first_name ?? ''));
      if (!userId) return json({ error: 'server' }, 502);
      if (!(await srv.rpc('tg_identity_bind', { p_telegram_id: tid, p_user: userId, p_chat_id: chat, p_phone: r.phone }))) {
        await srv.deleteUser(userId);
        return json({ error: 'conflict' }, 409);
      }
      await srv.rpc('pin_set', { p_user: userId, p_pin_hash: await hashSecret(srv.env, body.pin) });
      created = true;
    } else {
      const st = (r.pin ?? {}) as Json;
      if (st.state === 'locked') return json({ error: 'locked', retry_in: Number(st.retry_in ?? 0) }, 429);
      if (st.state === 'on') {
        // «Це я» в Telegram дозволяє обійтися без PIN і без коду, але лише з новим PIN
        const confirmed = body.recovery_confirmed === true && r.recovery_ok === true;
        let byRecovery = confirmed;
        // код відновлення одноразовий: без хорошого нового PIN його не витрачаємо
        const tryingCode = !confirmed && typeof body.recovery === 'string' && body.recovery !== '' &&
          !(typeof body.pin === 'string' && body.pin !== '');
        if (tryingCode) {
          const problem = pinProblem(body.new_pin);
          if (problem) return json({ error: 'new_pin_required', message: problem }, 400);
        }
        if (!confirmed) {
          const c = await checkPin(srv, bot, userId, body.pin, body.recovery, id);
          if (!c.ok) return pinFailure(c);
          byRecovery = c.byRecovery;
        }
        if (byRecovery) {
          const problem = pinProblem(body.new_pin);
          if (problem) return json({ error: 'new_pin_required', message: problem }, 400);
          const rec = (await srv.rpc('pin_recover', {
            p_user: userId,
            p_pin_hash: await hashSecret(srv.env, body.new_pin),
            p_delay_secs: RECOVERY_DELAY_SECS,
          })) as Json;
          if (typeof rec?.msg === 'number') await bot.edit(chat, rec.msg, 'Код відновлення використано.');
          if (rec?.pending_at) {
            // в акаунті є інші пристрої: новий PIN - через добу, щоб власник устиг заперечити
            if (!(await srv.rpc('tg_login_finish', { p_id: id, p_secret_hash: hash }))) return json({ error: 'used' }, 409);
            await bot.sayButtons(
              chat,
              `Запит на новий PIN у Vulyk${r.device ? ` з пристрою ${r.device}` : ''}. ` +
                `Новий PIN почне діяти завтра о ${kyivTime(String(rec.pending_at))}, тоді всі пристрої вийдуть з акаунта. ` +
                'Якщо це були не ви, натисніть кнопку: зміна скасується, а всі пристрої вийдуть одразу.',
              [[{ text: 'Це не я: скасувати', callback_data: 'keep' }]],
            );
            const secs = Math.max(0, Math.round((Date.parse(String(rec.pending_at)) - Date.now()) / 1000));
            return json({ error: 'recovery_scheduled', pending_at: rec.pending_at, retry_in: secs }, 409);
          }
          await bot.sayButtons(
            chat,
            'PIN змінено через відновлення доступу. Якщо це були не ви, натисніть кнопку.',
            NOT_ME,
          );
        }
      }
    }

    // заявка спрацьовує рівно один раз
    if (!(await srv.rpc('tg_login_finish', { p_id: id, p_secret_hash: hash }))) return json({ error: 'used' }, 409);
    if (!created) await srv.rpc('tg_identity_seen', { p_telegram_id: tid, p_chat_id: chat, p_phone: r.phone });
    const session = await srv.mintSession(userId);
    if (!session) return json({ error: 'server' }, 502);
    await bot.sayButtons(
      chat,
      `Новий вхід у Vulyk${r.device ? ` з пристрою ${r.device}` : ''}. Якщо це були не ви, натисніть кнопку.`,
      NOT_ME,
    );
    return json({ session });
  }

  // далі - лише для користувача, що вже увійшов
  const who = await srv.whoami(req);
  if (!who) return json({ error: 'потрібен вхід' }, 401);

  if (action === 'pin_status') {
    const st = (await srv.rpc('pin_state', { p_user: who.id })) as Json;
    const ident = (await srv.rpc('tg_identity_of', { p_user: who.id })) as Json | null;
    return json({ ...st, telegram: ident ? { phone: ident.phone } : null, telegram_only: who.email.endsWith(`@${TG_DOMAIN}`) });
  }

  if (action === 'pin_check') {
    const st = (await srv.rpc('pin_state', { p_user: who.id })) as Json;
    if (st.state !== 'on') return json({ ok: st.state !== 'locked' });
    const c = await checkPin(srv, bot, who.id, body.pin, body.recovery);
    return c.ok ? json({ ok: true }) : pinFailure(c);
  }

  if (action === 'pin_set') {
    const problem = pinProblem(body.new_pin);
    if (problem) return json({ error: 'bad_pin', message: problem }, 400);
    const st = (await srv.rpc('pin_state', { p_user: who.id })) as Json;
    if (st.state === 'locked') return json({ error: 'locked', retry_in: Number(st.retry_in ?? 0) }, 429);
    if (st.state === 'on') {
      const c = await checkPin(srv, bot, who.id, body.pin, body.recovery);
      if (!c.ok) return pinFailure(c);
    }
    await srv.rpc('pin_set', { p_user: who.id, p_pin_hash: await hashSecret(srv.env, body.new_pin) });
    await notify(srv, bot, who.id, st.state === 'on' ? 'PIN змінено.' : 'PIN увімкнено.', NOT_ME);
    return json({ ok: true });
  }

  if (action === 'pin_disable') {
    const st = (await srv.rpc('pin_state', { p_user: who.id })) as Json;
    if (st.state === 'none' || st.state === 'off') return json({ ok: true, state: 'off' });
    const c = await checkPin(srv, bot, who.id, body.pin, body.recovery);
    if (!c.ok) return pinFailure(c);
    // акаунт лише з Telegram: через добу, щоб власник встиг помітити
    if (who.email.endsWith(`@${TG_DOMAIN}`)) {
      const at = new Date(Date.now() + 24 * 3600 * 1000);
      await srv.rpc('pin_disable', { p_user: who.id, p_at: at.toISOString() });
      await notify(
        srv, bot, who.id,
        'PIN буде вимкнено через 24 години. Якщо це були не ви, натисніть кнопку: вимкнення скасується, а всі пристрої вийдуть.',
        [[{ text: 'Це не я: скасувати', callback_data: 'keep' }]],
      );
      return json({ ok: true, state: 'scheduled', disable_at: at.toISOString() });
    }
    await srv.rpc('pin_disable', { p_user: who.id, p_at: null });
    await notify(srv, bot, who.id, 'PIN вимкнено. Якщо це були не ви, натисніть кнопку.', NOT_ME);
    return json({ ok: true, state: 'off' });
  }

  if (action === 'sign_out_everywhere') {
    const n = Number(await srv.rpc('sign_out_everywhere', { p_user: who.id }));
    return json({ ok: true, sessions: n });
  }

  return json({ error: 'unknown_action' }, 400);
}

// ── бот ────────────────────────────────────────────────────────────────

function normalizePhone(p: unknown): string | null {
  if (typeof p !== 'string') return null;
  const digits = p.replace(/\D/g, '');
  if (digits.length < 8 || digits.length > 15) return null;
  return `+${digits}`;
}

async function webhook(req: Request, srv: Server, bot: Bot): Promise<Response> {
  const got = req.headers.get('X-Telegram-Bot-Api-Secret-Token') ?? '';
  if (!srv.env.webhookSecret || !same(got, srv.env.webhookSecret)) return json({ error: 'forbidden' }, 401);
  const u = await readBody(req);
  if (!u || !Number.isSafeInteger(u.update_id)) return json({ ok: true });
  // Telegram повторює запити: те саме оновлення вдруге ігноруємо
  if (!(await srv.rpc('tg_update_seen', { p_update_id: u.update_id }))) return json({ ok: true });

  // кнопки
  const cb = u.callback_query as Json | undefined;
  if (cb && typeof cb.data === 'string' && cb.from?.id && cb.message?.chat?.id === cb.from.id) {
    const from = Number(cb.from.id);
    await bot.call('answerCallbackQuery', { callback_query_id: cb.id });
    const data = cb.data as string;
    const m = /^m:([A-Za-z0-9_-]{22}):(\d{2})$/.exec(data);
    const n = /^n:([A-Za-z0-9_-]{22})$/.exec(data);
    const rc = /^r:([A-Za-z0-9_-]{22})$/.exec(data);
    if (rc) {
      const ok = await srv.rpc('tg_recovery_confirm', { p_id: rc[1], p_telegram_id: from });
      if (ok && typeof cb.message?.message_id === 'number') {
        await bot.edit(from, cb.message.message_id, 'Підтверджено. Поверніться в застосунок і придумайте новий PIN.');
      } else {
        await bot.say(
          from,
          ok
            ? 'Підтверджено. Поверніться в застосунок і придумайте новий PIN.'
            : 'Запит застарів або вже використаний. Почніть відновлення в застосунку заново.',
        );
      }
    } else if (m) {
      const res = await srv.rpc('tg_login_match', { p_id: m[1], p_telegram_id: from, p_code: Number(m[2]) });
      if (res === 'ok') {
        await bot.say(from, 'Тепер поділіться своїм номером кнопкою внизу.', {
          keyboard: [[{ text: 'Поділитися номером', request_contact: true }]],
          resize_keyboard: true,
          one_time_keyboard: true,
        });
      } else if (res === 'wrong') {
        await bot.say(from, 'Число не збіглося, вхід скасовано. Якщо це були не ви, нічого не робіть.');
      } else {
        await bot.say(from, 'Заявка застаріла. Почніть вхід у застосунку заново.');
      }
    } else if (n) {
      await srv.rpc('tg_login_cancel', { p_id: n[1], p_telegram_id: from });
      await bot.say(from, 'Вхід скасовано.');
    } else if (data === 'out' || data === 'keep') {
      const uid = (await srv.rpc('tg_user_of', { p_telegram_id: from })) as string | null;
      if (uid) {
        if (data === 'keep') await srv.rpc('pin_keep', { p_user: uid });
        await srv.rpc('sign_out_everywhere', { p_user: uid });
        await bot.say(
          from,
          data === 'keep'
            ? 'Готово: заплановану зміну PIN скасовано, усі пристрої вийшли з акаунта. Увійдіть заново в застосунку.'
            : 'Готово: усі пристрої вийшли з акаунта. Увійдіть заново в застосунку.',
        );
      }
    }
    return json({ ok: true });
  }

  const msg = u.message as Json | undefined;
  if (!msg?.from?.id || msg.chat?.type !== 'private' || msg.chat.id !== msg.from.id || msg.from.is_bot) {
    return json({ ok: true });
  }
  const from = Number(msg.from.id);

  // контакт
  if (msg.contact) {
    const c = msg.contact as Json;
    // лише власний контакт, не пересланий і не чужий
    if (c.user_id !== msg.from.id || msg.forward_origin || msg.forward_date || msg.forward_from) {
      await bot.say(from, 'Потрібен саме ваш номер: натисніть кнопку «Поділитися номером».');
      return json({ ok: true });
    }
    const phone = normalizePhone(c.phone_number);
    if (!phone) {
      await bot.say(from, 'Не вдалося прочитати номер.');
      return json({ ok: true });
    }
    const res = await srv.rpc('tg_login_contact', {
      p_telegram_id: from, p_phone: phone, p_first_name: String(msg.from.first_name ?? '').slice(0, 60),
    });
    const remove = { remove_keyboard: true };
    if (res === 'approved') await bot.say(from, 'Номер підтверджено. Поверніться в застосунок.', remove);
    else if (res === 'linked') await bot.say(from, 'Telegram прив\'язано до вашого акаунта. Поверніться в застосунок.', remove);
    else if (res === 'taken') await bot.say(from, 'Цей Telegram або акаунт уже пов\'язаний з іншим. Прив\'язку скасовано.', remove);
    else await bot.say(from, 'Немає активної заявки. Почніть вхід у застосунку.', remove);
    return json({ ok: true });
  }

  // /start <заявка>
  const text = typeof msg.text === 'string' ? msg.text : '';
  const start = /^\/start(?:@\w+)?\s+([A-Za-z0-9_-]{22})$/.exec(text.trim());
  if (!start) {
    await bot.say(from, 'Це бот входу в Vulyk. Натисніть «Увійти через Telegram» у застосунку.');
    return json({ ok: true });
  }
  const id = start[1];
  const o = (await srv.rpc('tg_login_open', { p_id: id, p_telegram_id: from, p_chat_id: Number(msg.chat.id) })) as Json | null;
  if (!o) {
    await bot.say(from, 'Заявка не знайдена або застаріла. Почніть вхід у застосунку заново.');
    return json({ ok: true });
  }
  const match = Number(o.match);
  const opts = new Set<number>([match]);
  while (opts.size < 3) opts.add(10 + randomInt(90));
  const shuffled = [...opts].sort(() => randomInt(2) - 0.5);
  const what = o.link ? 'Прив\'язка Telegram до акаунта' : 'Вхід у Vulyk';
  await bot.sayButtons(
    from,
    `${what}${o.device ? ` з пристрою ${o.device}` : ''}, ${kyivTime(String(o.created_at))}.\n\n` +
      'Виберіть число, яке зараз видно в застосунку. Якщо ви нічого не відкривали, натисніть «Це не я».',
    [
      shuffled.map((x) => ({ text: String(x), callback_data: `m:${id}:${x}` })),
      [{ text: 'Це не я', callback_data: `n:${id}` }],
    ],
  );
  return json({ ok: true });
}

// ── вхідна точка ───────────────────────────────────────────────────────

export async function handle(req: Request, env: Env, fetchFn: Fetch = fetch): Promise<Response> {
  if (req.method !== 'POST') return json({ error: 'лише POST' }, 405);
  // без довгої секретної добавки PIN захищений гірше, ніж задумано
  if (env.pepper.length < 16) return json({ error: 'не налаштовано' }, 503);
  const srv = new Server(env, fetchFn);
  const bot = new Bot(env, fetchFn);
  try {
    if (new URL(req.url).pathname.endsWith('/webhook')) return await webhook(req, srv, bot);
    return await app(req, srv, bot);
  } catch (e) {
    console.error('telegram-auth', e instanceof Error ? e.message : e);
    return json({ error: 'server' }, 500);
  }
}

if (typeof Deno !== 'undefined') {
  Deno.serve((req) =>
    handle(req, {
      url: Deno.env.get('SUPABASE_URL') ?? '',
      anonKey: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      botToken: Deno.env.get('TELEGRAM_BOT_TOKEN') ?? '',
      botUsername: Deno.env.get('TELEGRAM_BOT_USERNAME') ?? '',
      webhookSecret: Deno.env.get('TELEGRAM_WEBHOOK_SECRET') ?? '',
      pepper: Deno.env.get('PIN_PEPPER') ?? '',
    }),
  );
}
