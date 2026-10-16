// Налаштування посередника помічника «Пасічник». Усе, що може змінитися без
// оновлення застосунку, - тут. Модель і глибину міркувань перемикають
// секрети Supabase (без правки коду й без нового Deploy):
//   ASSISTANT_MODEL  - haiku (типово) або sonnet, чи повна назва моделі;
//   ASSISTANT_EFFORT - low | medium (типово) | high | xhigh | max.

/** Модель за замовчуванням. */
export const DEFAULT_MODEL = 'claude-haiku-5-5';

/** Короткі назви для секрету ASSISTANT_MODEL. */
export const MODEL_ALIASES: Record<string, string> = {
  haiku: 'claude-haiku-5-5',
  sonnet: 'claude-sonnet-5-5',
};

/** Не більше стільки звернень моделі до інструментів на одне повідомлення людини. */
export const MAX_STEPS = 6;

/** Стеля відповіді моделі (токенів); відповіді короткі, 1-4 речення. */
export const MAX_TOKENS = 4096;

/** Глибина міркувань: «medium» - щоб краще зіставляти прохання з даними й
 *  інструментами (коштує трохи більше, ніж «low»). Вище - довше думає
 *  (повільніші відповіді) і більше вихідних токенів. */
export const DEFAULT_EFFORT = 'medium';
export const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];

/** Обмеження запиту від застосунку. */
export const MAX_BODY_BYTES = 256 * 1024;
export const MAX_MESSAGES = 80;

export const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
export const ANTHROPIC_VERSION = '2023-06-01';

export type Env = (name: string) => string | undefined;

export function modelFrom(env: Env): string {
  const v = env('ASSISTANT_MODEL')?.trim() ?? '';
  return MODEL_ALIASES[v.toLowerCase()] ?? (v || DEFAULT_MODEL);
}

/** Невідоме значення - типове (помилка в секреті не зламає помічника). */
export function effortFrom(env: Env): string {
  const v = env('ASSISTANT_EFFORT')?.trim().toLowerCase() ?? '';
  return EFFORTS.includes(v) ? v : DEFAULT_EFFORT;
}

/** Sonnet 5.5: якщо запобіжники моделі відмовлять, сервер Anthropic сам
 *  повторить запит іншою моделлю (server-side fallback). Для Haiku такого
 *  немає. */
export const FALLBACK_BETA = 'server-side-fallback-2026-07-01';
export function usesFallback(model: string): boolean {
  return model.startsWith('claude-sonnet-5-5');
}

/** Відповідь, коли модель відмовилась (stop_reason «refusal»). */
export const REFUSAL_TEXT = 'Із цим я не допоможу. Спитайте, будь ласка, інакше.';
