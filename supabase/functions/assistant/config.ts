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
  opus: 'claude-opus-5-5',
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
export const MAX_BODY_BYTES = 4 * 1024 * 1024;
export const MAX_MESSAGES = 2000;

/** Моделі - лише останні стільки повідомлень розмови (від початку
 *  якогось питання людини): довга історія в чаті не ламає помічника й не
 *  дорожчає з кожним питанням. */
export const KEEP_MESSAGES = 60;

export const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
export const ANTHROPIC_VERSION = '2023-06-01';

export type Env = (name: string) => string | undefined;

export function modelFrom(env: Env): string {
  const v = env('ASSISTANT_MODEL')?.trim() ?? '';
  return MODEL_ALIASES[v.toLowerCase()] ?? (v || DEFAULT_MODEL);
}

/** Вибір людини в застосунку (плашка під полем чату): лише ці моделі.
 *  Секрет ASSISTANT_CLIENT_CHOICE = off - сервер вибір ігнорує (напр.,
 *  поки Sonnet не для всіх). */
export const CLIENT_MODELS = ['haiku', 'sonnet', 'opus'];

/** Коротка назва для застосунку (яким персонажем показати відповідь). */
export function aliasOf(model: string): string {
  for (const [k, v] of Object.entries(MODEL_ALIASES)) if (v === model) return k;
  return model.includes('opus') ? 'opus' : model.includes('sonnet') ? 'sonnet' : 'haiku';
}

export function clientChoiceAllowed(env: Env): boolean {
  return (env('ASSISTANT_CLIENT_CHOICE')?.trim().toLowerCase() ?? '') !== 'off';
}

/** Модель і глибина для цього запиту: вибір застосунку (якщо дозволено й
 *  значення відоме), інакше - секрети, інакше - типові. */
export function choose(env: Env, wanted: { model?: unknown; effort?: unknown }) {
  const allowed = clientChoiceAllowed(env);
  const m = typeof wanted.model === 'string' ? wanted.model.trim().toLowerCase() : '';
  const e = typeof wanted.effort === 'string' ? wanted.effort.trim().toLowerCase() : '';
  return {
    model: allowed && CLIENT_MODELS.includes(m) ? MODEL_ALIASES[m] : modelFrom(env),
    effort: allowed && EFFORTS.includes(e) ? e : effortFrom(env),
  };
}

/** Невідоме значення - типове (помилка в секреті не зламає помічника). */
export function effortFrom(env: Env): string {
  const v = env('ASSISTANT_EFFORT')?.trim().toLowerCase() ?? '';
  return EFFORTS.includes(v) ? v : DEFAULT_EFFORT;
}

/** Sonnet 5.5 і Opus 5.5: якщо запобіжники моделі відмовлять, сервер
 *  Anthropic сам повторить запит іншою моделлю (server-side fallback). Для
 *  Haiku такого немає. */
export const FALLBACK_BETA = 'server-side-fallback-2026-07-01';
export function usesFallback(model: string): boolean {
  return model.startsWith('claude-sonnet-5-5') || model.startsWith('claude-opus-5-5');
}

/** Складне - лишається Пасічнику (Sonnet): поради, пояснення, книги, аналіз. */
const HEAVY =
  /порад|рекоменд|чому|навіщо|поясн|розкаж|книг|цитат|джерел|аналіз|порівн|план|прогноз|що (мені |нам )?(робити|зробити|краще)|як (краще|правильно|лікувати|боротися|підготувати|уникнути|допомогти)|хвороб|лікув|варроа|кліщ|нозем|роїн|рій|рої|зимівл|підгодів|чи варто|чи треба|чи можна|оціни|погано|слабк|загин/i;

/** Просте: відкрити, показати, знайти, записати, порахувати. */
const SIMPLE =
  /(^|[^\p{L}])(відкр|покаж|перейд|знайд|запиш|запис|внес|додай|додайте|змін|познач|видал|спиш|спис|порах|скільки|нагада|онов|відміт|скану|встанов|постав)/iu;

/** Текст останнього повідомлення людини (без службових рядків «[…]»). */
export function lastHumanText(messages: { role: string; content: unknown }[]): string {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m.role !== 'user') continue;
    const c = m.content;
    const text = typeof c === 'string'
      ? c
      : Array.isArray(c)
        ? c.filter((b) => b?.type === 'text').map((b) => String(b.text ?? '')).join('\n')
        : '';
    if (text.trim()) return text.replace(/\[[^\]\n]*\]/g, ' ').trim();
  }
  return '';
}

/** Чи просте прохання: коротке, з дією «відкрий / запиши / скільки», без
 *  ознак складного. Сумнів - не просте. */
export function isSimpleRequest(text: string): boolean {
  const t = text.trim();
  if (!t || t.length > 200) return false;
  return SIMPLE.test(t) && !HEAVY.test(t);
}

/** Драбина помічників: Ведмедик -> Пасічник -> Робопасічник. */
export const LADDER = [MODEL_ALIASES.haiku, MODEL_ALIASES.sonnet, MODEL_ALIASES.opus];

/** Модель на рівень вище; null - це вже найсильніша (чи не з драбини). */
export function nextModel(model: string): string | null {
  const i = LADDER.indexOf(model);
  return i >= 0 && i < LADDER.length - 1 ? LADDER[i + 1] : null;
}

/** Модель сама визнала, що не може / не вийшло. */
const GAVE_UP =
  /не (зміг|змогла|вдалося|вдалось|вийшло|можу (цього |це )?(зробити|допомогти|відповісти)|розумію|впевнен)|не маю (змоги|можливості)|на жаль,? (я )?не/i;

/** Чи модель не впоралась і варто спитати сильнішу: обрізана відповідь
 *  (max_tokens), порожня чи така, де модель визнає, що не вийшло. Запити
 *  інструментів і відмова запобіжників (refusal - це не про силу моделі)
 *  не рахуються. */
export function struggled(out: { content?: { type: string; text?: unknown }[]; stop_reason?: string }): string | null {
  const stop = out.stop_reason ?? 'end_turn';
  if (stop === 'max_tokens') return 'max_tokens';
  if (stop !== 'end_turn') return null;
  const blocks = out.content ?? [];
  if (blocks.some((b) => b.type === 'tool_use')) return null;
  const text = blocks.filter((b) => b.type === 'text').map((b) => String(b.text ?? '')).join('\n').trim();
  if (!text) return 'empty';
  return GAVE_UP.test(text) ? 'gave_up' : null;
}

/** Ескалація на рівень вище вимикається секретом ASSISTANT_ESCALATE = off. */
export function escalationOn(env: Env): boolean {
  return (env('ASSISTANT_ESCALATE')?.trim().toLowerCase() ?? '') !== 'off';
}

/** Пасічник (Sonnet) прості прохання помітно передає Ведмедику (Haiku) -
 *  у 20 разів дешевше; складне відповідає сам. Решта моделей - як обрано.
 *  routedFrom - кого обрала людина (застосунок покаже, хто відповів). */
export function route(model: string, messages: { role: string; content: unknown }[], env: Env) {
  const off = (env('ASSISTANT_ROUTING')?.trim().toLowerCase() ?? '') === 'off';
  if (!off && model === MODEL_ALIASES.sonnet && isSimpleRequest(lastHumanText(messages))) {
    return { model: MODEL_ALIASES.haiku, routedFrom: 'sonnet' as string | undefined };
  }
  return { model, routedFrom: undefined as string | undefined };
}

/** Відповідь, коли модель відмовилась (stop_reason «refusal»). */
export const REFUSAL_TEXT = 'Із цим я не допоможу. Спитайте, будь ласка, інакше.';
