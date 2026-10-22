// Перевірка книг для помічника без Supabase: замість PostgREST - підставний
// fetch, що записує запити.
//
//   node --test supabase/tests/books.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { ADMIN_HEADER, type Deps, handle } from '../functions/books/index.ts';
import { handle as assistantHandle, type Deps as AssistantDeps } from '../functions/assistant/index.ts';
import { testTokenAccess, TEST_TOKEN_HEADER } from '../functions/assistant/access.ts';
import { searchBooks } from '../functions/assistant/kb.ts';

const PW = 'admin-password-123';
const BOOK = '11111111-1111-4111-8111-111111111111';
const ENV: Record<string, string> = {
  FEEDBACK_ADMIN_PASSWORD: PW,
  SUPABASE_URL: 'https://x.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'service-key',
};

type Call = { url: string; method: string; headers: Record<string, string>; body: any };

function setup(reply: (c: Call) => Response = () => new Response('[]', { status: 200 }), env = ENV) {
  const calls: Call[] = [];
  const logs: string[] = [];
  const d: Deps = {
    env: (n) => env[n],
    fetch: (async (url: string, init: RequestInit) => {
      const c = { url, method: init.method ?? 'GET', headers: init.headers as Record<string, string>, body: init.body ? JSON.parse(init.body as string) : undefined };
      calls.push(c);
      return reply(c);
    }) as typeof fetch,
    log: (l) => logs.push(l),
  };
  return { d, calls, logs };
}

const post = (body: unknown, pw: string | null = PW) =>
  new Request('https://x.supabase.co/functions/v1/books', {
    method: 'POST',
    headers: pw == null ? {} : { [ADMIN_HEADER]: pw },
    body: JSON.stringify(body),
  });

const text = (n = 60) => 'Бджоли восени потребують підгодівлі цукровим сиропом. '.repeat(3).slice(0, n);

test('без пароля адмінки чи з чужим - 401, у базу не ходить; пароль замалий - ніхто не пускається', async () => {
  const s = setup();
  for (const pw of [null, 'wrong', PW + 'x']) {
    assert.equal((await handle(post({ action: 'list' }, pw), s.d)).status, 401);
  }
  const weak = setup(undefined, { ...ENV, FEEDBACK_ADMIN_PASSWORD: 'short' });
  assert.equal((await handle(post({ action: 'list' }, 'short'), weak.d)).status, 401);
  assert.equal(s.calls.length + weak.calls.length, 0);
});

test('OPTIONS - 204 (CORS), GET - 405, не JSON - 400, невідома дія - 400', async () => {
  const s = setup();
  const o = await handle(new Request('https://x', { method: 'OPTIONS' }), s.d);
  assert.equal(o.status, 204);
  assert.match(o.headers.get('Access-Control-Allow-Headers') ?? '', /x-feedback-admin/);
  assert.equal((await handle(new Request('https://x', { method: 'GET' }), s.d)).status, 405);
  const bad = new Request('https://x', { method: 'POST', headers: { [ADMIN_HEADER]: PW }, body: 'не json' });
  assert.equal((await handle(bad, s.d)).status, 400);
  assert.equal((await handle(post({ action: 'щось' }), s.d)).status, 400);
});

test('add_book: запис у kb_books зі службовим ключем; без назви - 400; рік лише числом', async () => {
  const s = setup(() => new Response(JSON.stringify([{ id: BOOK }]), { status: 201 }));
  const r = await handle(post({ action: 'add_book', title: '  Посібник  ', author: 'Іваненко', year: 2019, source: 'власний примірник' }), s.d);
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { id: BOOK });
  const c = s.calls[0];
  assert.equal(c.url, 'https://x.supabase.co/rest/v1/kb_books');
  assert.equal(c.method, 'POST');
  assert.equal(c.headers.apikey, 'service-key');
  assert.equal(c.headers.Authorization, 'Bearer service-key');
  assert.deepEqual(c.body, { title: 'Посібник', author: 'Іваненко', year: 2019, source: 'власний примірник' });

  const s2 = setup(() => new Response(JSON.stringify([{ id: BOOK }]), { status: 201 }));
  await handle(post({ action: 'add_book', title: 'Книга', year: '2019' }), s2.d);
  assert.equal(s2.calls[0].body.year, null);
  assert.equal((await handle(post({ action: 'add_book', title: '   ' }), s2.d)).status, 400);
  assert.equal(s2.calls.length, 1);
});

test('add_chunks: перевірка уривків; порядок від start; до бази - лише правильне', async () => {
  const s = setup(() => new Response(null, { status: 201 }));
  const ok = await handle(
    post({ action: 'add_chunks', book_id: BOOK, start: 100, chunks: [{ page: 5, chapter: 'Підгодівля', text: text() }, { text: text(), page: -3 }] }),
    s.d,
  );
  assert.equal(ok.status, 200);
  assert.deepEqual(await ok.json(), { added: 2 });
  const rows = s.calls[0].body;
  assert.equal(s.calls[0].url, 'https://x.supabase.co/rest/v1/kb_chunks');
  assert.deepEqual(rows.map((r: any) => [r.ord, r.page, r.chapter]), [[100, 5, 'Підгодівля'], [101, null, '']]);
  assert.equal(rows[0].book_id, BOOK);

  const before = s.calls.length;
  const bad = [
    { action: 'add_chunks', book_id: 'не-uuid', start: 0, chunks: [{ text: text() }] },
    { action: 'add_chunks', book_id: BOOK, chunks: [{ text: text() }] }, // немає start
    { action: 'add_chunks', book_id: BOOK, start: 0, chunks: [] },
    { action: 'add_chunks', book_id: BOOK, start: 0, chunks: [{ text: 'зависоке коротке' }] },
    { action: 'add_chunks', book_id: BOOK, start: 0, chunks: [{ text: 'я'.repeat(4001) }] },
    { action: 'add_chunks', book_id: BOOK, start: 0, chunks: Array.from({ length: 101 }, () => ({ text: text() })) },
  ];
  for (const b of bad) assert.equal((await handle(post(b), s.d)).status, 400, JSON.stringify(b).slice(0, 80));
  assert.equal(s.calls.length, before); // у базу нічого не пішло
});

test('finish, set_enabled, delete: правильні запити; id лише UUID (без вставки в запит)', async () => {
  const s = setup(() => new Response(null, { status: 204 }));
  await handle(post({ action: 'finish', book_id: BOOK, pages: 120, chunks: 340 }), s.d);
  await handle(post({ action: 'set_enabled', book_id: BOOK, enabled: false }), s.d);
  await handle(post({ action: 'delete', book_id: BOOK }), s.d);
  assert.deepEqual(s.calls.map((c) => [c.method, c.url.split('/rest/v1/')[1]]), [
    ['PATCH', `kb_books?id=eq.${BOOK}`],
    ['PATCH', `kb_books?id=eq.${BOOK}`],
    ['DELETE', `kb_books?id=eq.${BOOK}`],
  ]);
  assert.deepEqual(s.calls[0].body, { pages: 120, chunks: 340 });
  assert.deepEqual(s.calls[1].body, { enabled: false });

  const before = s.calls.length;
  for (const id of [`${BOOK}&enabled=eq.true`, '*', '', 'all']) {
    assert.equal((await handle(post({ action: 'delete', book_id: id }), s.d)).status, 400, id);
  }
  assert.equal((await handle(post({ action: 'set_enabled', book_id: BOOK, enabled: 'так' }), s.d)).status, 400);
  assert.equal(s.calls.length, before);
});

test('list і search: передають відповідь бази; збій бази - 502', async () => {
  const rows = [{ id: BOOK, title: 'Книга', chunks: 3 }];
  const s = setup((c) => new Response(JSON.stringify(c.url.includes('rpc/kb_search') ? [{ title: 'Книга', body: 'Текст' }] : rows), { status: 200 }));
  assert.deepEqual(await (await handle(post({ action: 'list' }), s.d)).json(), { books: rows });
  assert.match(s.calls[0].url, /kb_books\?select=.*order=created_at\.desc/);
  const found = await (await handle(post({ action: 'search', query: 'вощина' }), s.d)).json();
  assert.equal(found.results[0].title, 'Книга');
  assert.equal(s.calls[1].url, 'https://x.supabase.co/rest/v1/rpc/kb_search');
  assert.deepEqual(s.calls[1].body, { q: 'вощина', lim: 8 });
  assert.equal((await handle(post({ action: 'search', query: ' ' }), s.d)).status, 400);

  const down = setup(() => new Response('помилка', { status: 500 }));
  assert.equal((await handle(post({ action: 'list' }), down.d)).status, 502);
  const net = setup(() => { throw new Error('мережа'); });
  assert.equal((await handle(post({ action: 'list' }), net.d)).status, 502);
});

test('журнал: лише лічильники - без назв і текстів книг, без паролів', async () => {
  const s = setup(() => new Response(JSON.stringify([{ id: BOOK }]), { status: 201 }));
  await handle(post({ action: 'add_book', title: 'Таємна назва' }), s.d);
  await handle(post({ action: 'add_chunks', book_id: BOOK, start: 0, chunks: [{ text: text() }] }), s.d);
  await handle(post({ action: 'list' }, 'wrong'), s.d);
  const log = s.logs.join('\n');
  assert.ok(log.includes('chunks_added') && log.includes('admin_denied'));
  for (const secret of ['Таємна', 'Бджоли', PW, 'service-key']) assert.equal(log.includes(secret), false, secret);
});

// ---- пошук помічника (функція assistant, дія search_books)

const TOKEN = 'test-token-0123456789abcdef';
const A_ENV: Record<string, string> = { ...ENV, ANTHROPIC_API_KEY: 'sk-ant-test', APIARY_ASSISTANT_TEST_TOKEN: TOKEN };

function assistant(reply: (c: Call) => Response, env = A_ENV) {
  const calls: Call[] = [];
  const logs: string[] = [];
  const d: AssistantDeps = {
    env: (n) => env[n],
    fetch: (async (url: string, init: RequestInit) => {
      const c = { url, method: init.method ?? 'GET', headers: init.headers as Record<string, string>, body: init.body ? JSON.parse(init.body as string) : undefined };
      calls.push(c);
      return reply(c);
    }) as typeof fetch,
    log: (l) => logs.push(l),
    access: testTokenAccess,
    tools: [],
  };
  return { d, calls, logs };
}
const ask = (body: unknown, token: string | null = TOKEN) =>
  new Request('https://x/functions/v1/assistant', {
    method: 'POST',
    headers: token == null ? {} : { [TEST_TOKEN_HEADER]: token },
    body: JSON.stringify(body),
  });

const hit = (over: Record<string, unknown> = {}) => ({ title: 'Посібник', author: 'Іваненко', year: 2019, page: 12, chapter: 'Підгодівля', body: 'Сироп два до одного.', ...over });

test('search_books: уривки з книги, джерело; ключ лише службовий; без пошуку в Anthropic', async () => {
  const s = assistant((c) => new Response(JSON.stringify(c.url.includes('rpc/') ? [hit(), hit({ page: null, body: 'я'.repeat(3000) })] : [{ id: BOOK }]), { status: 200 }));
  const r = await assistantHandle(ask({ action: 'search_books', query: ' підгодівля восени ', limit: 3 }), s.d);
  assert.equal(r.status, 200);
  const out = await r.json();
  assert.equal(out.books, true);
  assert.deepEqual(out.results[0], { book: 'Посібник', author: 'Іваненко', year: 2019, page: 12, chapter: 'Підгодівля', text: 'Сироп два до одного.' });
  assert.equal(out.results[1].page, null);
  assert.ok(out.results[1].text.length <= 1401 && out.results[1].text.endsWith('…'));
  assert.equal(s.calls.every((c) => !c.url.includes('anthropic')), true);
  assert.equal(s.calls[1].url, 'https://x.supabase.co/rest/v1/rpc/kb_search');
  assert.deepEqual(s.calls[1].body, { q: 'підгодівля восени', lim: 3 });
  assert.equal(s.calls[1].headers.apikey, 'service-key');
  const log = s.logs.join('\n');
  assert.equal(log.includes('підгодівля'), false); // текст запиту - не в журнал
  assert.ok(log.includes('"result":"books"'));
});

test('search_books: книг немає - books:false без пошуку; пошук без доступу чи без запиту - відмова', async () => {
  const none = assistant(() => new Response('[]', { status: 200 }));
  const out = await (await assistantHandle(ask({ action: 'search_books', query: 'рій' }), none.d)).json();
  assert.deepEqual(out, { books: false, results: [] });
  assert.equal(none.calls.length, 1); // лише перевірка «чи є книги»

  const s = assistant(() => new Response('[]', { status: 200 }));
  assert.equal((await assistantHandle(ask({ action: 'search_books', query: 'рій' }, null), s.d)).status, 401);
  assert.equal((await assistantHandle(ask({ action: 'search_books', query: 'рій' }, 'wrong'), s.d)).status, 401);
  assert.equal((await assistantHandle(ask({ action: 'search_books', query: '   ' }), s.d)).status, 400);
  assert.equal(s.calls.length, 0);
});

test('search_books: збій бази чи немає службового ключа - «зайнято» (503), не поради', async () => {
  const down = assistant(() => new Response('x', { status: 500 }));
  assert.equal((await assistantHandle(ask({ action: 'search_books', query: 'рій' }), down.d)).status, 503);
  const net = assistant(() => { throw new Error('мережа'); });
  assert.equal((await assistantHandle(ask({ action: 'search_books', query: 'рій' }), net.d)).status, 503);
  const nokey = assistant(() => new Response('[]'), { ...A_ENV, SUPABASE_SERVICE_ROLE_KEY: '' });
  assert.equal((await assistantHandle(ask({ action: 'search_books', query: 'рій' }), nokey.d)).status, 503);
  assert.equal(nokey.calls.length, 0);
  assert.equal(await searchBooks((n) => A_ENV[n], (() => new Response('[]')) as unknown as typeof fetch, 'x', 99).then((r) => r?.books), false);
});

test('адмін-сторінка: вкладка «Книги» - наша функція, без innerHTML, pdf.js з пінінгом версії', () => {
  const html = readFileSync(new URL('../../admin/feedback.html', import.meta.url), 'utf8');
  assert.match(html, /functions\/v1\/books/);
  assert.match(html, /cdnjs\.cloudflare\.com\/ajax\/libs\/pdf\.js\/\d+\.\d+\.\d+\//);
  assert.doesNotMatch(html, /innerHTML/);
  assert.match(html, /add_chunks/);
  assert.match(html, /set_enabled/);
});
