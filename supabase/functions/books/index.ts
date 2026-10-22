// Книги для помічника: керування з адмін-сторінки (admin/feedback.html,
// вкладка «Книги»). Пошук для помічника - у функції assistant (search_books).
//
// Усі дії - POST JSON з заголовком x-feedback-admin = пароль адмінки
// (секрет FEEDBACK_ADMIN_PASSWORD, той самий, що для відгуків):
//   {action:'list'}                                   - усі книги
//   {action:'add_book', title, author?, year?, source?} - нова книга -> {id}
//   {action:'add_chunks', book_id, start, chunks:[{page?, chapter?, text}]}
//                                                     - уривки (до 100 за раз)
//   {action:'finish', book_id, pages, chunks}          - підсумок книги
//   {action:'set_enabled', book_id, enabled}           - увімкнути / вимкнути
//   {action:'delete', book_id}                         - видалити з уривками
//   {action:'search', query}                           - перевірити пошук
//
// Таблиці kb_books і kb_chunks закриті для застосунку: функція ходить у
// них зі службовим ключем (SUPABASE_SERVICE_ROLE_KEY). Тексти книг у журнал
// не потрапляють - лише лічильники.

export const ADMIN_HEADER = 'x-feedback-admin';
export const MAX_CHUNKS = 100;
export const MAX_TEXT = 4000;
export const MIN_TEXT = 20;
const MAX_BODY = 1_500_000;

export type Env = (name: string) => string | undefined;

export type Deps = {
  env: Env;
  fetch: typeof fetch;
  log: (line: string) => void;
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': `content-type, ${ADMIN_HEADER}`,
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...CORS },
  });
}
const fail = (status: number, error: string) => json({ error }, status);

/** Порівняння без витоку часу. */
function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const str = (v: unknown, max: number): string => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const int = (v: unknown): number | null => (Number.isInteger(v) && (v as number) >= 0 && (v as number) < 1e7 ? (v as number) : null);

/** Запит до PostgREST (Supabase) зі службовим ключем. */
async function rest(deps: Deps, path: string, init: { method?: string; body?: unknown; prefer?: string } = {}): Promise<Response> {
  const base = deps.env('SUPABASE_URL')?.replace(/\/+$/, '') ?? '';
  const key = deps.env('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  return deps.fetch(`${base}/rest/v1/${path}`, {
    method: init.method ?? 'GET',
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      ...(init.prefer ? { Prefer: init.prefer } : {}),
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return fail(405, 'method');

  const password = deps.env('FEEDBACK_ADMIN_PASSWORD')?.trim() ?? '';
  const got = req.headers.get(ADMIN_HEADER)?.trim() ?? '';
  if (password.length < 8 || !same(got, password)) {
    deps.log(JSON.stringify({ fn: 'books', result: 'admin_denied' }));
    return fail(401, 'unauthorized');
  }

  let b: Record<string, unknown>;
  try {
    const text = await req.text();
    if (text.length > MAX_BODY) return fail(413, 'too_large');
    b = JSON.parse(text);
  } catch {
    return fail(400, 'json');
  }
  const action = typeof b.action === 'string' ? b.action : '';

  try {
    if (action === 'list') {
      const r = await rest(deps, 'kb_books?select=id,title,author,year,source,pages,chunks,enabled,created_at&order=created_at.desc');
      if (!r.ok) return fail(502, 'db');
      return json({ books: await r.json() });
    }

    if (action === 'add_book') {
      const title = str(b.title, 300);
      if (!title) return fail(400, 'title');
      const row = { title, author: str(b.author, 200), year: int(b.year), source: str(b.source, 500) };
      const r = await rest(deps, 'kb_books', { method: 'POST', body: row, prefer: 'return=representation' });
      if (!r.ok) return fail(502, 'db');
      const [book] = (await r.json()) as { id: string }[];
      deps.log(JSON.stringify({ fn: 'books', result: 'book_added' }));
      return json({ id: book.id });
    }

    const id = typeof b.book_id === 'string' && UUID.test(b.book_id) ? b.book_id : '';

    if (action === 'add_chunks') {
      if (!id) return fail(400, 'book');
      const start = int(b.start);
      const list = Array.isArray(b.chunks) ? b.chunks : null;
      if (start === null || !list || list.length === 0 || list.length > MAX_CHUNKS) return fail(400, 'chunks');
      const rows = [];
      for (let i = 0; i < list.length; i++) {
        const c = list[i] as Record<string, unknown>;
        const text = str(c?.text, MAX_TEXT + 1);
        if (text.length < MIN_TEXT || text.length > MAX_TEXT) return fail(400, 'text');
        rows.push({ book_id: id, ord: start + i, page: int(c.page), chapter: str(c.chapter, 200), text });
      }
      const r = await rest(deps, 'kb_chunks', { method: 'POST', body: rows, prefer: 'return=minimal' });
      if (!r.ok) return fail(r.status === 409 || r.status === 400 ? 400 : 502, r.status === 409 ? 'book' : 'db');
      deps.log(JSON.stringify({ fn: 'books', result: 'chunks_added', count: rows.length }));
      return json({ added: rows.length });
    }

    if (action === 'finish') {
      if (!id) return fail(400, 'book');
      const r = await rest(deps, `kb_books?id=eq.${id}`, {
        method: 'PATCH',
        body: { pages: int(b.pages) ?? 0, chunks: int(b.chunks) ?? 0 },
        prefer: 'return=minimal',
      });
      return r.ok ? json({ ok: true }) : fail(502, 'db');
    }

    if (action === 'set_enabled') {
      if (!id || typeof b.enabled !== 'boolean') return fail(400, 'book');
      const r = await rest(deps, `kb_books?id=eq.${id}`, { method: 'PATCH', body: { enabled: b.enabled }, prefer: 'return=minimal' });
      return r.ok ? json({ ok: true }) : fail(502, 'db');
    }

    if (action === 'delete') {
      if (!id) return fail(400, 'book');
      const r = await rest(deps, `kb_books?id=eq.${id}`, { method: 'DELETE', prefer: 'return=minimal' });
      deps.log(JSON.stringify({ fn: 'books', result: 'book_deleted' }));
      return r.ok ? json({ ok: true }) : fail(502, 'db');
    }

    if (action === 'search') {
      const query = str(b.query, 300);
      if (!query) return fail(400, 'query');
      const r = await rest(deps, 'rpc/kb_search', { method: 'POST', body: { q: query, lim: 8 } });
      if (!r.ok) return fail(502, 'db');
      return json({ results: await r.json() });
    }
  } catch {
    deps.log(JSON.stringify({ fn: 'books', result: 'network' }));
    return fail(502, 'db');
  }
  return fail(400, 'action');
}

declare const Deno: { serve(h: (req: Request) => Response | Promise<Response>): unknown; env: { get(n: string): string | undefined } } | undefined;
if (typeof Deno !== 'undefined') {
  Deno.serve((req) =>
    handle(req, {
      env: (n) => Deno.env.get(n),
      fetch,
      log: (l) => console.log(l),
    }),
  );
}
