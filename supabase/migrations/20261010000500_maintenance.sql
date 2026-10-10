-- Обслуговування: «пінг» (щоб безкоштовний проєкт не призупинявся) і
-- нічне прибирання.

-- ── пінг ────────────────────────────────────────────────────────────────
-- Безкоштовний проєкт Supabase призупиняється після тижня без запитів.
-- GitHub Action «Supabase keep-alive» раз на 3 дні викликає ping() - це
-- справжній запис у базу (а не лише запит до шлюзу).
create table if not exists public.keepalive (
  id integer primary key check (id = 1),
  at timestamptz not null default now(),
  count bigint not null default 0
);
insert into public.keepalive (id) values (1) on conflict (id) do nothing;
alter table public.keepalive enable row level security;
revoke all on public.keepalive from anon, authenticated;

create or replace function public.ping() returns timestamptz
language sql volatile security definer set search_path = public as $$
  update public.keepalive set at = now(), count = count + 1 where id = 1 returning at
$$;
revoke execute on function public.ping() from public;
grant execute on function public.ping() to anon, authenticated;

-- ── прибирання ──────────────────────────────────────────────────────────
-- Позначки «видалено» потрібні, доки всі телефони не дізнаються про
-- видалення. Телефон стирає свої через 30 днів; сервер тримає 180 днів
-- (телефон, що довше був без зв'язку, при синхронізації (етап 5) заново
-- завантажує все). Відповідені запрошення - 90 днів; копії, що так і не
-- були завантажені чи перевірені, - добу.
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
    'stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines', 'apiary_members']
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

-- функції правил доступу без входу не потрібні
revoke execute on function public.is_member(uuid, text), public.has_stock_access(uuid),
  public.can_see_owner(uuid), public.can_stock(uuid), public.can_apiary(uuid, text),
  public.my_email(), public.path_owner(text) from public, anon;
grant execute on function public.is_member(uuid, text), public.has_stock_access(uuid),
  public.can_see_owner(uuid), public.can_stock(uuid), public.can_apiary(uuid, text),
  public.my_email(), public.path_owner(text) to authenticated;
-- тригерні функції напряму не викликаються
revoke execute on function public.trg_owner_from_apiary(), public.trg_guard(),
  public.trg_append_only(), public.trg_stamp(), public.trg_profile_from_user(),
  public.trg_invitation_sender() from public, anon, authenticated;

-- щоночі о 03:23 UTC, якщо в проєкті ввімкнено pg_cron (Database ->
-- Extensions -> pg_cron); без нього - викликати вручну раз на кілька тижнів
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    execute $q$select cron.schedule('vulyk-purge', '23 3 * * *', 'select public.purge_tombstones()')$q$;
  end if;
end
$$;
