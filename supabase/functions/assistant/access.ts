// Хто може звертатися до помічника і скільки разів на добу.
//
//  * checkAccess - вхід: застосунок надсилає токен входу Supabase
//    (Authorization: Bearer ...), посередник питає в Supabase Auth, чий це
//    токен. Анонімні входи (is_anonymous) не пускаємо: інакше «нові люди»
//    створювалися б безкінечно й ліміт нічого б не давав.
//  * checkUsage - денний ліміт на людину: функція бази assistant_hit
//    (міграція 20261113000200), службовий ключ лише в секретах Supabase.
//
// Обидва кроки без залежностей від Deno: той самий файл перевіряє тест на
// Node (tests/assistant_access.test.ts).

import type { Env } from './config.ts';

export type Access =
  | { ok: true; subject: string }
  | { ok: false; status: number; error: string };

export type AccessCheck = (req: Request, env: Env, fetchFn: typeof fetch) => Promise<Access>;

/** 'ok' - можна; 'limit' - ліміт на сьогодні вичерпано; 'error' - не вдалося
 *  перевірити (база недоступна): не пускаємо, застосунок повторить пізніше. */
export type UsageResult = 'ok' | 'limit' | 'error';
export type UsageCheck = (userId: string, env: Env, fetchFn: typeof fetch) => Promise<UsageResult>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UNAUTHORIZED: Access = { ok: false, status: 401, error: 'unauthorized' };
const BUSY: Access = { ok: false, status: 503, error: 'busy' };

/** Скільки секунд чекаємо на Supabase, поки перевіряємо вхід чи ліміт. */
const CHECK_TIMEOUT_MS = 8000;

function baseUrl(env: Env): string {
  return env('SUPABASE_URL')?.trim().replace(/\/+$/, '') ?? '';
}

/** Пускає лише людину з дійсним токеном входу Supabase. */
export const jwtAccess: AccessCheck = async (req, env, fetchFn) => {
  const m = /^Bearer\s+(\S+)$/i.exec((req.headers.get('Authorization') ?? '').trim());
  if (!m || m[1].length > 4096) return UNAUTHORIZED;
  const url = baseUrl(env);
  const anon = env('SUPABASE_ANON_KEY')?.trim() ?? '';
  if (!url || !anon) return { ok: false, status: 500, error: 'not_configured' };

  let res: Response;
  try {
    res = await fetchFn(`${url}/auth/v1/user`, {
      headers: { apikey: anon, Authorization: `Bearer ${m[1]}` },
      signal: AbortSignal.timeout(CHECK_TIMEOUT_MS),
    });
  } catch {
    return BUSY; // Supabase не відповів - це не «недійсний токен»
  }
  if (res.status === 401 || res.status === 403) return UNAUTHORIZED;
  if (!res.ok) return BUSY;
  let user: { id?: unknown; is_anonymous?: unknown };
  try {
    user = await res.json();
  } catch {
    return BUSY;
  }
  if (typeof user?.id !== 'string' || !UUID.test(user.id)) return UNAUTHORIZED;
  if (user.is_anonymous === true) return UNAUTHORIZED;
  return { ok: true, subject: user.id.toLowerCase() };
};

/** Типовий ліміт запитів (кроків моделі й пошуків у книгах) на людину за добу. */
export const DEFAULT_DAILY_LIMIT = 200;

/** Секрет ASSISTANT_DAILY_LIMIT (ціле 1..10000); інше - типовий ліміт. */
export function dailyLimit(env: Env): number {
  const v = env('ASSISTANT_DAILY_LIMIT')?.trim() ?? '';
  const n = /^\d{1,5}$/.test(v) ? Number(v) : NaN;
  return n >= 1 && n <= 10000 ? n : DEFAULT_DAILY_LIMIT;
}

/** Зараховує запит людини в базі й каже, чи не вичерпано ліміт. */
export const rpcUsage: UsageCheck = async (userId, env, fetchFn) => {
  const url = baseUrl(env);
  const key = env('SUPABASE_SERVICE_ROLE_KEY')?.trim() ?? '';
  if (!url || !key) return 'error';
  try {
    const res = await fetchFn(`${url}/rest/v1/rpc/assistant_hit`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_user: userId, p_limit: dailyLimit(env) }),
      signal: AbortSignal.timeout(CHECK_TIMEOUT_MS),
    });
    if (!res.ok) return 'error';
    const answer = await res.json();
    if (answer === true) return 'ok';
    if (answer === false) return 'limit';
    return 'error';
  } catch {
    return 'error';
  }
};

/** Поточна перевірка доступу й ліміту. */
export const checkAccess: AccessCheck = jwtAccess;
export const checkUsage: UsageCheck = rpcUsage;

/** Рахує перемикання помічника (escalate / route) для адміна; помилка не заважає відповіді. */
export type SwitchCount = (kind: 'escalate' | 'route', from: string, to: string, env: Env, fetchFn: typeof fetch) => Promise<void>;

export const rpcSwitch: SwitchCount = async (kind, from, to, env, fetchFn) => {
  const url = baseUrl(env);
  const key = env('SUPABASE_SERVICE_ROLE_KEY')?.trim() ?? '';
  if (!url || !key) return;
  try {
    await fetchFn(`${url}/rest/v1/rpc/assistant_switch_hit`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_kind: kind, p_from: from, p_to: to }),
      signal: AbortSignal.timeout(CHECK_TIMEOUT_MS),
    });
  } catch {
    // лічильник не критичний
  }
};
