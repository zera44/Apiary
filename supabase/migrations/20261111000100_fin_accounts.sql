-- Рахунки фінансів: рахунки (гаманці), перекази між ними і рахунок у
-- кожній операції. Застосувати ДО встановлення збірки застосунку з
-- версією бази 5: інакше сервер відхилить нові колонки й таблиці.

create table if not exists public.fin_accounts (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  icon text,
  color text,
  start_balance double precision not null default 0,
  in_total integer not null default 1 check (in_total in (0, 1)),
  sort_order integer not null default 0,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

create table if not exists public.fin_transfers (
  id text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  from_account_id text not null,
  to_account_id text not null,
  amount double precision not null,
  op_date double precision not null,
  comment text,
  created_at double precision not null,
  deleted integer not null default 0 check (deleted in (0, 1)),
  updated_at double precision not null default 0,
  schema_v integer,
  server_at timestamptz not null default now(),
  server_seq bigint not null default nextval('public.sync_seq'),
  server_xid xid8 not null default pg_current_xact_id()
);

alter table public.fin_ops add column if not exists account_id text;

do $$
declare
  t text;
  r record;
begin
  foreach t in array array['fin_accounts', 'fin_transfers']
  loop
    execute format('create index if not exists %I on public.%I (server_xid, server_seq)', t || '_seq', t);
    execute format('create index if not exists %I on public.%I (owner_id)', t || '_owner', t);

    execute format('drop trigger if exists t20_guard on public.%I', t);
    execute format('create trigger t20_guard before insert or update on public.%I '
                   'for each row execute function public.trg_guard()', t);
    execute format('drop trigger if exists t90_stamp on public.%I', t);
    execute format('create trigger t90_stamp before insert or update on public.%I '
                   'for each row execute function public.trg_stamp()', t);

    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke delete, truncate on public.%I from authenticated', t);
    for r in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', r.policyname, t);
    end loop;
    -- як склад і решта фінансів: власник і помічник із дозволом
    execute format('create policy read on public.%I for select to authenticated '
                   'using (public.can_stock(owner_id))', t);
    execute format('create policy add on public.%I for insert to authenticated '
                   'with check (public.can_stock(owner_id))', t);
    execute format('create policy change on public.%I for update to authenticated '
                   'using (public.can_stock(owner_id)) with check (public.can_stock(owner_id))', t);
  end loop;
end
$$;

-- забирання змін: дозволити нові таблиці
create or replace function public.sync_pull(p_table text, p_after text default null, p_limit integer default 500)
returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare
  horizon xid8 := pg_snapshot_xmin(pg_current_snapshot());
  ax xid8 := '0'::xid8;
  aseq bigint := -1;
  lim integer := least(greatest(coalesce(p_limit, 500), 1), 1000);
  rows jsonb;
  n integer;
begin
  if p_table <> all (array[
    'apiaries', 'elements', 'templates', 'parameters', 'element_parameters',
    'parameter_records', 'qr_codes', 'note_labels', 'hive_notes', 'param_groups',
    'stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines',
    'fin_accounts', 'fin_transfers',
    'apiary_members', 'invitations']) then
    raise exception 'невідома таблиця %', p_table using errcode = '22023';
  end if;
  if coalesce(p_after, '') <> '' then
    if p_after !~ '^[0-9]+:-?[0-9]+$' then
      raise exception 'курсор % не такий', p_after using errcode = '22023';
    end if;
    ax := split_part(p_after, ':', 1)::xid8;
    aseq := split_part(p_after, ':', 2)::bigint;
  end if;
  execute format(
    'select coalesce(jsonb_agg(to_jsonb(t) order by t.server_xid, t.server_seq), ''[]''::jsonb) '
    'from (select * from public.%I where (server_xid, server_seq) > ($1, $2) and server_xid < $3 '
    'order by server_xid, server_seq limit $4) t', p_table)
    into rows using ax, aseq, horizon, lim;
  n := jsonb_array_length(rows);
  return jsonb_build_object(
    'rows', rows,
    'next', case when n = 0 then nullif(p_after, '')
                 else (rows -> (n - 1) ->> 'server_xid') || ':' || (rows -> (n - 1) ->> 'server_seq') end,
    'more', n = lim);
end
$$;
revoke execute on function public.sync_pull(text, text, integer) from public, anon;
grant execute on function public.sync_pull(text, text, integer) to authenticated;

-- нічне прибирання видалених рядків: нові таблиці теж
create or replace function public.purge_tombstones(keep interval default interval '180 days')
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  t text;
  n bigint;
  total bigint := 0;
begin
  -- спершу пасіки: лише ті, в яких не лишилось живих записів (інакше
  -- записи, що ще живуть на телефонах, втратили б пасіку)
  delete from public.apiaries p
  where p.deleted = 1 and p.server_at < now() - keep
    and not exists (select 1 from public.elements x where x.apiary_id = p.id and x.deleted = 0)
    and not exists (select 1 from public.element_parameters x where x.apiary_id = p.id and x.deleted = 0)
    and not exists (select 1 from public.parameter_records x where x.apiary_id = p.id and x.deleted = 0)
    and not exists (select 1 from public.qr_codes x where x.apiary_id = p.id and x.deleted = 0)
    and not exists (select 1 from public.hive_notes x where x.apiary_id = p.id and x.deleted = 0);
  get diagnostics n = row_count;
  total := total + n;
  foreach t in array array[
    'elements', 'templates', 'parameters', 'element_parameters',
    'parameter_records', 'qr_codes', 'note_labels', 'hive_notes', 'param_groups',
    'stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines',
    'fin_accounts', 'fin_transfers', 'apiary_members']
  loop
    execute format('delete from public.%I where deleted = 1 and server_at < now() - $1', t) using keep;
    get diagnostics n = row_count;
    total := total + n;
  end loop;
  delete from public.invitations where status <> 'pending' and server_at < now() - interval '90 days';
  get diagnostics n = row_count;
  return total + n;
end
$$;
revoke execute on function public.purge_tombstones(interval) from public, anon, authenticated;
