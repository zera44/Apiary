-- Книги для помічника: порадник відповідає лише за уривками цих книг і
-- називає джерело (docs/KNOWLEDGE_BASE.md).
--
-- Книги додає власник в адмін-сторінці (admin/feedback.html, вкладка
-- «Книги»): текст ділиться на уривки з номерами сторінок. Пошук - повно-
-- текстовий Postgres (слова за початком: «вощини» знаходить «вощина»);
-- вектори (pgvector) - пізніше, коли книг стане багато.
--
-- Таблиці закриті для anon і authenticated: читає й пише лише функція
-- books (адмінка) і посередник assistant (пошук) зі службовим ключем.

create table if not exists public.kb_books (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(title) between 1 and 300),
  author text not null default '',
  year int,
  -- звідки книга й на яких правах (власний примірник, дозвіл автора…)
  source text not null default '',
  pages int not null default 0,
  chunks int not null default 0,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.kb_chunks (
  id bigint generated always as identity primary key,
  book_id uuid not null references public.kb_books (id) on delete cascade,
  ord int not null,
  page int,
  chapter text not null default '',
  text text not null check (length(text) between 20 and 4000),
  tsv tsvector generated always as (to_tsvector('simple', text)) stored
);

create index if not exists kb_chunks_tsv on public.kb_chunks using gin (tsv);
create index if not exists kb_chunks_book on public.kb_chunks (book_id, ord);

alter table public.kb_books enable row level security;
alter table public.kb_chunks enable row level security;
revoke all on public.kb_books from public, anon, authenticated;
revoke all on public.kb_chunks from public, anon, authenticated;

-- Пошук уривків за словами запиту. Слова скорочуються на 2 літери з кінця
-- (відмінки: вощина / вощини / вощиною) і шукаються за початком; більше
-- збігів - вище. Лише увімкнені книги.
create or replace function public.kb_search(q text, lim int default 6)
returns table (book_id uuid, title text, author text, year int, page int, chapter text, body text, rank real)
language sql
stable
security definer
set search_path = public
as $$
  with words as (
    select distinct case when length(w) > 5 then left(w, length(w) - 2) else w end as stem
    from regexp_split_to_table(
      regexp_replace(lower(coalesce(q, '')), '[^а-яіїєґё0-9a-z]+', ' ', 'g'), ' '
    ) as w
    where length(w) >= 3
  ),
  tsq as (
    select to_tsquery('simple', string_agg(quote_literal(stem) || ':*', ' | ')) as tq from words
  )
  select b.id, b.title, b.author, b.year, c.page, c.chapter, c.text, ts_rank(c.tsv, tsq.tq)
  from tsq
  join public.kb_chunks c on tsq.tq is not null and c.tsv @@ tsq.tq
  join public.kb_books b on b.id = c.book_id and b.enabled
  order by ts_rank(c.tsv, tsq.tq) desc, b.id, c.ord
  limit least(greatest(coalesce(lim, 6), 1), 10)
$$;

revoke all on function public.kb_search(text, int) from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.kb_search(text, int) to service_role;
  end if;
end
$$;
