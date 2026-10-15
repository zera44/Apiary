// Запрошувальне посилання: https://<проєкт>.supabase.co/functions/v1/join?t=<код>
//
// Посилання з месенджера відкриває браузер; на Android функція одразу
// перенаправляє у Vulyk (intent://join?t=<код>, схема vulyk). Немає
// застосунку - браузер відкриває сторінку завантаження (JOIN_FALLBACK_URL).
// Інші пристрої отримують коротку підказку текстом.
//
// Сама функція нічого не змінює і нічого не читає з бази: посилання
// приймає застосунок (accept_invite_link) після входу. Тому попередній
// перегляд посилання в месенджері його не «використає».
//
// Публічна (без входу): розгортати з --no-verify-jwt.
// Без залежностей: той самий файл перевіряє тест на Node
// (tests/join.test.ts).

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

export const PACKAGE = 'org.apiary.apiary';
export const DEFAULT_FALLBACK = 'https://github.com/zera44/Apiary/releases/latest';

const TOKEN = /^[0-9a-f]{64}$/;

function text(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

export function handle(req: Request, fallback: string = DEFAULT_FALLBACK): Response {
  if (req.method !== 'GET' && req.method !== 'HEAD') return text('лише GET', 405);
  const token = new URL(req.url).searchParams.get('t') ?? '';
  if (!TOKEN.test(token)) return text('Посилання пошкоджене - попросіть надіслати його ще раз.', 400);
  const ua = req.headers.get('User-Agent') ?? '';
  if (!/Android/i.test(ua)) {
    return text(
      'Запрошення до пасіки у Vulyk.\n\n' +
        'Відкрийте це посилання на телефоні Android, де встановлено Vulyk.\n' +
        `Завантажити застосунок: ${fallback}\n`,
    );
  }
  const intent =
    `intent://join?t=${token}#Intent;scheme=vulyk;package=${PACKAGE};` +
    `S.browser_fallback_url=${encodeURIComponent(fallback)};end`;
  return new Response(null, { status: 302, headers: { Location: intent, 'Cache-Control': 'no-store' } });
}

if (typeof Deno !== 'undefined') {
  Deno.serve((req) => handle(req, Deno.env.get('JOIN_FALLBACK_URL') ?? DEFAULT_FALLBACK));
}
