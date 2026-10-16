// Хто може звертатися до помічника. Окремий шар: зараз - тестовий код
// (поки немає входу), пізніше - перевірка входу (JWT Supabase) і ліміти,
// без переробки index.ts: достатньо підмінити [checkAccess].

import type { Env } from './config.ts';

export const TEST_TOKEN_HEADER = 'x-apiary-assistant-token';

export type Access =
  | { ok: true; subject: string }
  | { ok: false; status: number; error: string };

export type AccessCheck = (req: Request, env: Env) => Promise<Access>;

/** Порівняння без витоку часу (довжина не секрет). */
function sameText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Пускає лише запити з тестовим кодом APIARY_ASSISTANT_TEST_TOKEN.
 *  Код не задано на сервері - не пускає нікого. */
export const testTokenAccess: AccessCheck = async (req, env) => {
  const expected = env('APIARY_ASSISTANT_TEST_TOKEN')?.trim() ?? '';
  const got = req.headers.get(TEST_TOKEN_HEADER)?.trim() ?? '';
  if (expected.length < 16 || !sameText(got, expected)) {
    return { ok: false, status: 401, error: 'unauthorized' };
  }
  return { ok: true, subject: 'test' };
};

/** Поточна перевірка доступу. */
export const checkAccess: AccessCheck = testTokenAccess;
