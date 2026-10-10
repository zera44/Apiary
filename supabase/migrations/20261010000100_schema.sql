-- Vulyk / «Моя пасіка»: таблиці сервера.
--
-- Кожна таблиця повторює таблицю на телефоні (lib/data/database.dart) без
-- службової колонки synced і має:
--   owner_id   - власник даних (користувач Supabase). Для пасік, довідників,
--                складу й фінансів телефон шле свій id (або NULL - сервер
--                підставить того, хто пише); для вуликів і їхніх записів
--                сервер бере власника з пасіки сам;
--   schema_v   - версією схеми якого застосунку записано рядок;
--   server_at  - час сервера останнього запису («перемагає пізніший»);
--   server_seq - наскрізний номер зміни;
--   server_xid - транзакція, що записала рядок. Телефон забирає зміни
--                функцією sync_pull за курсором (server_xid, server_seq) -
--                лише із завершених транзакцій, тож рядок довгої транзакції
--                не «проскочить» повз курсор.
-- Позначки 0/1 - integer, як на телефоні (рядок іде на сервер без перетворень).

create sequence if not exists public.sync_seq;

-- ── профілі: пошта Google -> користувач (для запрошень) ─────────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  name text,
  created_at timestamptz not null default now()
);
create index if not exists profiles_email on public.profiles (email);

-- ── пасіки, вулики, записи ──────────────────────────────────────────────
create table if not exists public.apiaries (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  lat double precision,
  lon double precision,
  visit_period integer,
  visit_period_at double precision,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

create table if not exists public.elements (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  apiary_id text,
  group_id text,
  x integer not null,
  y integer not null,
  type text not null default 'hive',
  label text,
  rotation integer not null default 0,
  archived integer not null default 0 check (archived in (0, 1)),
  variant text,
  icon text,
  color text,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

create table if not exists public.templates (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  size integer not null,
  cells text not null,
  width integer,
  height integer,
  seed_key text,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

create table if not exists public.parameters (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  unit text,
  data_type text not null default 'text',
  is_base integer not null default 0 check (is_base in (0, 1)),
  base_type text,
  base_key text,
  options text,
  seed_key text,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

create table if not exists public.element_parameters (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  apiary_id text,
  group_id text,
  element_id text,
  parameter_id text not null,
  sort_order integer not null default 0,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

-- історія значень: лише дописується (змінити можна тільки позначку «видалено»)
create table if not exists public.parameter_records (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  apiary_id text,
  group_id text,
  element_id text,
  parameter_id text not null,
  value text,
  created_at double precision not null,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

create table if not exists public.qr_codes (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  apiary_id text,
  code text not null,
  number integer,
  group_id text,
  element_id text,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

create table if not exists public.note_labels (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  seed_key text,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

create table if not exists public.hive_notes (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  apiary_id text,
  group_id text,
  element_id text,
  text text not null,
  note_date double precision not null,
  label_id text,
  created_at double precision not null,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

-- групи «Конструктора»
create table if not exists public.param_groups (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  ids text not null,
  sort_order integer not null default 0,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

-- ── склад ───────────────────────────────────────────────────────────────
create table if not exists public.stock_items (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  unit text not null,
  quantity double precision,
  min_quantity double precision,
  photo text,
  created_at double precision not null,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

-- рухи складу: лише дописуються (змінити можна тільки «скасовано»/«видалено»)
create table if not exists public.stock_moves (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  item_id text not null,
  kind text not null,
  amount double precision not null,
  quantity_after double precision not null,
  op_date double precision,
  price double precision,
  total double precision,
  reason text,
  comment text,
  ref_id text,
  cancelled integer not null default 0 check (cancelled in (0, 1)),
  created_at double precision not null,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

-- ── фінанси ─────────────────────────────────────────────────────────────
create table if not exists public.fin_categories (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  kind text not null,
  to_stock integer not null default 0 check (to_stock in (0, 1)),
  icon text,
  color text,
  sort_order integer not null default 0,
  seed_key text,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

create table if not exists public.fin_ops (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  kind text not null,
  category_id text,
  amount double precision not null,
  op_date double precision not null,
  comment text,
  cancelled integer not null default 0 check (cancelled in (0, 1)),
  created_at double precision not null,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

create table if not exists public.fin_lines (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  op_id text not null,
  name text not null,
  qty double precision not null,
  unit text not null,
  price double precision not null,
  to_stock integer not null default 0 check (to_stock in (0, 1)),
  stock_item_id text,
  stock_move_id text,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

-- ── спільний доступ ─────────────────────────────────────────────────────
-- помічник [user_id] бачить пасіку [apiary_id] власника [owner_id]
-- (apiary_id NULL - усі пасіки власника, зокрема майбутні)
-- Без зв'язку з auth.users: коли акаунт видаляють, записи про доступ стають
-- позначками «видалено» (див. delete_account_prepare) - так телефони
-- помічника й власника дізнаються, що доступу більше немає. Позначки
-- стирає нічне прибирання.
create table if not exists public.apiary_members (
  id text primary key default gen_random_uuid()::text,
  owner_id uuid not null,
  apiary_id text,
  user_id uuid not null,
  email text not null,
  role text not null default 'helper',
  stock_access integer not null default 0 check (stock_access in (0, 1)),
  created_at double precision not null default extract(epoch from now()),
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default extract(epoch from now()),
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);
-- одна людина - один запис на пасіку (повторне запрошення оновлює його)
create unique index if not exists apiary_members_one
  on public.apiary_members (owner_id, (coalesce(apiary_id, '')), user_id);
create index if not exists apiary_members_user on public.apiary_members (user_id);

create table if not exists public.invitations (
  id text primary key,
  from_user_id uuid not null references auth.users (id) on delete cascade,
  from_email text not null default '',
  from_name text,
  to_email text not null,
  apiary_ids text[],
  apiary_names text[] not null default '{}',
  stock_access integer not null default 0 check (stock_access in (0, 1)),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'revoked')),
  created_at double precision not null default extract(epoch from now()),
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default extract(epoch from now()),
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);
create index if not exists invitations_to on public.invitations (to_email);
create index if not exists invitations_from on public.invitations (from_user_id);

-- ── індекси для «змін після N» і правил доступу ─────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array[
    'apiaries', 'elements', 'templates', 'parameters', 'element_parameters',
    'parameter_records', 'qr_codes', 'note_labels', 'hive_notes', 'param_groups',
    'stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines',
    'apiary_members', 'invitations']
  loop
    execute format('create index if not exists %I on public.%I (server_xid, server_seq)', t || '_seq', t);
  end loop;
  foreach t in array array[
    'apiaries', 'templates', 'parameters', 'note_labels', 'param_groups',
    'stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines']
  loop
    execute format('create index if not exists %I on public.%I (owner_id)', t || '_owner', t);
  end loop;
  foreach t in array array[
    'elements', 'element_parameters', 'parameter_records', 'qr_codes', 'hive_notes']
  loop
    execute format('create index if not exists %I on public.%I (apiary_id)', t || '_apiary', t);
  end loop;
end
$$;
