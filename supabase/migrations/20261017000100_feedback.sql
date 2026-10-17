-- Зворотний зв'язок з відповідями: людина пише розробнику з застосунку, а
-- розробник відповідає зі своєї адмін-сторінки - відповідь повертається в
-- застосунок як нове повідомлення.
--
-- Один тред на встановлення застосунку (device_id); його «ключ»
-- (secret) зберігається лише хешем - читати чужий тред не можна. Усе
-- (читання й запис) робить лише функція feedback зі службовим ключем:
-- таблиці закриті для ролей anon і authenticated.

create table if not exists public.feedback_threads (
  id uuid primary key default gen_random_uuid(),
  device_id uuid not null unique,
  secret_hash text not null,
  platform text,
  created_at timestamptz not null default now(),
  last_at timestamptz not null default now(),
  -- є нові повідомлення людини, яких розробник ще не відкривав
  dev_unread boolean not null default true
);

create table if not exists public.feedback_messages (
  seq bigint generated always as identity primary key,
  id uuid not null unique default gen_random_uuid(),
  thread_id uuid not null references public.feedback_threads (id) on delete cascade,
  from_dev boolean not null default false,
  body text not null check (length(body) between 1 and 5000),
  created_at timestamptz not null default now()
);
create index if not exists feedback_messages_thread on public.feedback_messages (thread_id, seq);

alter table public.feedback_threads enable row level security;
alter table public.feedback_messages enable row level security;
revoke all on public.feedback_threads from public, anon, authenticated;
revoke all on public.feedback_messages from public, anon, authenticated;
