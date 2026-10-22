// Пошук у книгах для помічника: інструмент search_books. Виконує його
// застосунок через цю функцію ({action:'search_books', query}) - сервер
// шукає в таблицях kb_books / kb_chunks (supabase/migrations/…kb_books.sql)
// зі службовим ключем. Тексти запитів і книг у журнал не потрапляють.

import type { Env } from './config.ts';

/** Скільки уривків і яка довжина кожного йдуть моделі. */
export const KB_LIMIT = 5;
export const KB_MAX_LIMIT = 8;
export const KB_SNIPPET = 1400;

export type KbHit = { book: string; author: string; year: number | null; page: number | null; chapter: string; text: string };
export type KbResult = { books: boolean; results: KbHit[] };

type Row = { title: string; author: string; year: number | null; page: number | null; chapter: string; body: string };

/** Уривки за запитом; books=false - книг (увімкнених) у базі ще немає. */
export async function searchBooks(env: Env, fetchFn: typeof fetch, query: string, limit: number = KB_LIMIT): Promise<KbResult | null> {
  const base = env('SUPABASE_URL')?.replace(/\/+$/, '') ?? '';
  const key = env('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!base || !key) return null;
  const headers = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  const lim = Math.min(Math.max(Number.isInteger(limit) ? limit : KB_LIMIT, 1), KB_MAX_LIMIT);
  try {
    const has = await fetchFn(`${base}/rest/v1/kb_books?select=id&enabled=eq.true&limit=1`, { headers });
    if (!has.ok) return null;
    if (((await has.json()) as unknown[]).length === 0) return { books: false, results: [] };
    const r = await fetchFn(`${base}/rest/v1/rpc/kb_search`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ q: query.slice(0, 300), lim }),
    });
    if (!r.ok) return null;
    const rows = (await r.json()) as Row[];
    return {
      books: true,
      results: rows.map((x) => ({
        book: x.title,
        author: x.author,
        year: x.year,
        page: x.page,
        chapter: x.chapter,
        text: x.body.length > KB_SNIPPET ? `${x.body.slice(0, KB_SNIPPET)}…` : x.body,
      })),
    };
  } catch {
    return null;
  }
}
