// Налаштування посередника помічника «Пасічник». Усе, що може змінитися без
// оновлення застосунку, - тут (модель можна перевизначити секретом).

/** Модель за замовчуванням (секрет ASSISTANT_MODEL її перевизначає). */
export const DEFAULT_MODEL = 'claude-haiku-5-5';

/** Не більше стільки звернень моделі до інструментів на одне повідомлення людини. */
export const MAX_STEPS = 6;

/** Стеля відповіді моделі (токенів); відповіді короткі, 1-4 речення. */
export const MAX_TOKENS = 4096;

/** Глибина міркувань: коротка порада й навігація - "low" вистачає. */
export const EFFORT = 'low';

/** Обмеження запиту від застосунку. */
export const MAX_BODY_BYTES = 256 * 1024;
export const MAX_MESSAGES = 80;

export const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
export const ANTHROPIC_VERSION = '2023-06-01';

export type Env = (name: string) => string | undefined;

export function modelFrom(env: Env): string {
  return env('ASSISTANT_MODEL')?.trim() || DEFAULT_MODEL;
}
