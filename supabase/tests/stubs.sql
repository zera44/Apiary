-- Заглушки того, що Supabase дає «з коробки» (ролі, auth, storage), - щоб
-- перевіряти наші міграції й правила доступу на звичайній PostgreSQL.
-- На справжньому сервері цей файл НЕ виконується.

create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;

create schema auth;
create schema storage;
create schema extensions;

-- auth: користувачі й поточний користувач запиту (з JWT, як у Supabase)
create table auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb not null default '{}'
);

create function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;

create function auth.uid() returns uuid
language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid
$$;

-- storage: кошики й файли (лише те, на що спираються наші правила)
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz not null default now()
);

create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid,
  metadata jsonb,
  created_at timestamptz not null default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;

create function storage.foldername(name text) returns text[]
language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;

grant usage on schema auth, storage, extensions, public to anon, authenticated, service_role;
grant execute on all functions in schema auth, storage to anon, authenticated, service_role;
grant select on storage.buckets to anon, authenticated;
grant select, insert, update, delete on storage.objects to anon, authenticated, service_role;

-- як у Supabase: нові таблиці й функції public доступні ролям API, а що
-- саме можна - вирішують правила доступу (RLS)
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

-- допоміжне для тестів
create schema tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Увійти як користувач [uid] з поштою [email] (роль вмикає сам тест).
create function tests.login(uid uuid, email text) returns void
language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', uid, 'email', email, 'role', 'authenticated')::text, false);
$$;

-- Запит [q] має впасти з кодом [state] (42501 - доступ заборонено).
create function tests.fails(q text, state text default '42501') returns void
language plpgsql as $$
begin
  begin
    execute q;
  exception when others then
    if sqlstate = state then
      return;
    end if;
    raise exception 'очікували % для «%», а отримали %: %', state, q, sqlstate, sqlerrm;
  end;
  raise exception 'мало впасти (%): %', state, q;
end
$$;

-- Скільки рядків бачить поточний користувач у таблиці [t] (з умовою [w]).
create function tests.n(t text, w text default 'true') returns bigint
language plpgsql as $$
declare
  c bigint;
begin
  execute format('select count(*) from %s where %s', t, w) into c;
  return c;
end
$$;
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- Умова [c] має бути істинною.
create function tests.ok(c boolean, msg text) returns void
language plpgsql as $$
begin
  if c is not true then
    raise exception 'ПЕРЕВІРКА НЕ ПРОЙШЛА: %', msg;
  end if;
end
$$;
grant execute on function tests.ok(boolean, text) to anon, authenticated, service_role;

-- Три користувачі для всіх тестів: Олена (власниця), Петро (помічник),
-- Іван (сторонній).
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'Olena@Gmail.com', '{"full_name": "Олена"}'),
  ('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com', '{}'),
  ('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com', '{}');
