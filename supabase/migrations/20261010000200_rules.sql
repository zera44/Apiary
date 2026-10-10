-- Правила запису (тригери) і доступу (Row Level Security).
--
-- Хто що бачить:
--   * власник - усе своє;
--   * помічник - пасіки, до яких його запросили (або всі пасіки власника),
--     їхні вулики, огляди, нотатки, QR-коди; довідники власника
--     (характеристики, мітки, шаблони, групи «Конструктора»);
--   * склад і фінанси власника - лише помічник із дозволом «Також склад і
--     фінанси» (він може їх і змінювати).
-- Видаляти рядки назовсім клієнт не може - лише позначкою deleted = 1
-- (інакше видалення не дійшло б до інших телефонів).

-- ── допоміжні функції доступу ───────────────────────────────────────────
-- security definer: читають apiary_members/apiaries в обхід правил (інакше
-- правило посилалося б саме на себе); search_path - фіксований.

create or replace function public.my_email() returns text
language sql stable as $$
  select lower(trim(coalesce(auth.jwt() ->> 'email', '')))
$$;

-- Я - помічник власника [owner] з доступом до пасіки [apiary]
-- (apiary NULL - до будь-якої його пасіки).
create or replace function public.is_member(owner uuid, apiary text default null)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.apiary_members m
    where m.user_id = auth.uid() and m.owner_id = owner and m.deleted = 0
      and (apiary is null or m.apiary_id is null or m.apiary_id = apiary))
$$;

-- Я - помічник власника [owner] зі складом і фінансами.
create or replace function public.has_stock_access(owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.apiary_members m
    where m.user_id = auth.uid() and m.owner_id = owner and m.deleted = 0
      and m.stock_access = 1)
$$;

-- Можу бачити й змінювати дані власника [owner] (свої або як помічник).
create or replace function public.can_see_owner(owner uuid) returns boolean
language sql stable as $$
  select owner = auth.uid() or public.is_member(owner)
$$;

create or replace function public.can_stock(owner uuid) returns boolean
language sql stable as $$
  select owner = auth.uid() or public.has_stock_access(owner)
$$;

create or replace function public.can_apiary(owner uuid, apiary text) returns boolean
language sql stable as $$
  select owner = auth.uid() or public.is_member(owner, apiary)
$$;

-- ── тригери запису ──────────────────────────────────────────────────────

-- Вулики й записи вуликів: власник - власник пасіки. Перенести запис до
-- пасіки іншого власника не можна.
create or replace function public.trg_owner_from_apiary() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o uuid;
begin
  select a.owner_id into o from public.apiaries a where a.id = new.apiary_id;
  if o is null then
    raise exception 'пасіки % на сервері немає', new.apiary_id using errcode = '23503';
  end if;
  if tg_op = 'UPDATE' and o <> old.owner_id then
    raise exception 'запис не можна перенести до чужої пасіки' using errcode = '42501';
  end if;
  new.owner_id := o;
  return new;
end
$$;

-- Спільне для всіх таблиць даних: власник за замовчуванням - той, хто
-- пише; id і власника не змінити; позначка «видалено» не знімається
-- старішою зміною (телефон, що довго був без зв'язку, не «воскресить»
-- видалене - лише зміна, зроблена пізніше за видалення).
create or replace function public.trg_guard() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if new.owner_id is null then
      new.owner_id := auth.uid();
    end if;
    return new;
  end if;
  new.id := old.id;
  new.owner_id := old.owner_id;
  if old.deleted = 1 and new.deleted = 0 and new.updated_at <= old.updated_at then
    return null; -- видалення новіше - лишаємо як є
  end if;
  return new;
end
$$;

-- Лише дописуються: змінити можна тільки колонки з аргументів тригера
-- (позначки й службові поля).
create or replace function public.trg_append_only() returns trigger
language plpgsql as $$
declare
  free text[] := array['updated_at', 'schema_v', 'server_at', 'server_seq'] || tg_argv;
begin
  if (to_jsonb(new) - free) is distinct from (to_jsonb(old) - free) then
    raise exception '% лише дописуються: змінити можна тільки %', tg_table_name,
      array_to_string(tg_argv, ', ') using errcode = '42501';
  end if;
  return new;
end
$$;

-- Час сервера й номер зміни - при кожному записі.
create or replace function public.trg_stamp() returns trigger
language plpgsql as $$
begin
  new.server_at := now();
  new.server_seq := nextval('public.sync_seq');
  return new;
end
$$;

do $$
declare
  t text;
begin
  -- тригери спрацьовують за абеткою назв: t10 -> t20 -> t30 -> t90
  foreach t in array array['elements', 'element_parameters', 'parameter_records', 'qr_codes', 'hive_notes']
  loop
    execute format('drop trigger if exists t10_owner on public.%I', t);
    execute format('create trigger t10_owner before insert or update on public.%I '
                   'for each row execute function public.trg_owner_from_apiary()', t);
  end loop;
  foreach t in array array[
    'apiaries', 'elements', 'templates', 'parameters', 'element_parameters',
    'parameter_records', 'qr_codes', 'note_labels', 'hive_notes', 'param_groups',
    'stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines']
  loop
    execute format('drop trigger if exists t20_guard on public.%I', t);
    execute format('create trigger t20_guard before insert or update on public.%I '
                   'for each row execute function public.trg_guard()', t);
  end loop;
  foreach t in array array[
    'apiaries', 'elements', 'templates', 'parameters', 'element_parameters',
    'parameter_records', 'qr_codes', 'note_labels', 'hive_notes', 'param_groups',
    'stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines',
    'apiary_members', 'invitations']
  loop
    execute format('drop trigger if exists t90_stamp on public.%I', t);
    execute format('create trigger t90_stamp before insert or update on public.%I '
                   'for each row execute function public.trg_stamp()', t);
  end loop;
end
$$;

drop trigger if exists t30_append_only on public.stock_moves;
create trigger t30_append_only before update on public.stock_moves
  for each row execute function public.trg_append_only('cancelled', 'deleted');
drop trigger if exists t30_append_only on public.parameter_records;
create trigger t30_append_only before update on public.parameter_records
  for each row execute function public.trg_append_only('deleted');

-- ── профілі: з'являються при першому вході ──────────────────────────────
create or replace function public.trg_profile_from_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name)
  values (new.id, lower(trim(coalesce(new.email, ''))),
          coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'))
  on conflict (id) do update set email = excluded.email, name = excluded.name;
  return new;
end
$$;
drop trigger if exists vulyk_profile on auth.users;
create trigger vulyk_profile after insert or update of email, raw_user_meta_data on auth.users
  for each row execute function public.trg_profile_from_user();
-- ті, хто вже входив до цієї міграції
insert into public.profiles (id, email, name)
select u.id, lower(trim(coalesce(u.email, ''))),
       coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name')
from auth.users u
on conflict (id) do nothing;

-- ── правила доступу ─────────────────────────────────────────────────────
do $$
declare
  t text;
  r record;
begin
  foreach t in array array[
    'profiles', 'apiaries', 'elements', 'templates', 'parameters', 'element_parameters',
    'parameter_records', 'qr_codes', 'note_labels', 'hive_notes', 'param_groups',
    'stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines',
    'apiary_members', 'invitations']
  loop
    execute format('alter table public.%I enable row level security', t);
    -- без входу - нічого; видаляти назовсім - лише сервер
    execute format('revoke all on public.%I from anon', t);
    execute format('revoke delete, truncate on public.%I from authenticated', t);
    for r in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', r.policyname, t);
    end loop;
  end loop;

  -- вулики й усе, що належить вулику: власник або помічник цієї пасіки
  foreach t in array array['elements', 'element_parameters', 'parameter_records', 'qr_codes', 'hive_notes']
  loop
    execute format('create policy read on public.%I for select to authenticated '
                   'using (public.can_apiary(owner_id, apiary_id))', t);
    execute format('create policy add on public.%I for insert to authenticated '
                   'with check (public.can_apiary(owner_id, apiary_id))', t);
    execute format('create policy change on public.%I for update to authenticated '
                   'using (public.can_apiary(owner_id, apiary_id)) '
                   'with check (public.can_apiary(owner_id, apiary_id))', t);
  end loop;

  -- характеристики й мітки: бачать і доповнюють власник і помічники
  foreach t in array array['parameters', 'note_labels']
  loop
    execute format('create policy read on public.%I for select to authenticated '
                   'using (public.can_see_owner(owner_id))', t);
    execute format('create policy add on public.%I for insert to authenticated '
                   'with check (public.can_see_owner(owner_id))', t);
    execute format('create policy change on public.%I for update to authenticated '
                   'using (public.can_see_owner(owner_id)) with check (public.can_see_owner(owner_id))', t);
  end loop;

  -- шаблони й групи «Конструктора»: помічники бачать, змінює власник
  foreach t in array array['templates', 'param_groups']
  loop
    execute format('create policy read on public.%I for select to authenticated '
                   'using (public.can_see_owner(owner_id))', t);
    execute format('create policy add on public.%I for insert to authenticated '
                   'with check (owner_id = auth.uid())', t);
    execute format('create policy change on public.%I for update to authenticated '
                   'using (owner_id = auth.uid()) with check (owner_id = auth.uid())', t);
  end loop;

  -- склад і фінанси: власник і помічник із дозволом
  foreach t in array array['stock_items', 'stock_moves', 'fin_categories', 'fin_ops', 'fin_lines']
  loop
    execute format('create policy read on public.%I for select to authenticated '
                   'using (public.can_stock(owner_id))', t);
    execute format('create policy add on public.%I for insert to authenticated '
                   'with check (public.can_stock(owner_id))', t);
    execute format('create policy change on public.%I for update to authenticated '
                   'using (public.can_stock(owner_id)) with check (public.can_stock(owner_id))', t);
  end loop;
end
$$;

-- пасіки: помічник бачить, створює й змінює лише власник
create policy read on public.apiaries for select to authenticated
  using (public.can_apiary(owner_id, id));
create policy add on public.apiaries for insert to authenticated
  with check (owner_id = auth.uid());
create policy change on public.apiaries for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- профіль: лише свій (знайти людину за поштою - функція find_user)
create policy read on public.profiles for select to authenticated using (id = auth.uid());
revoke insert, update on public.profiles from authenticated;

-- помічники: бачать власник і сам помічник; змінюються лише функціями
-- (respond_invitation, set_member_stock_access, remove_member)
create policy read on public.apiary_members for select to authenticated
  using (owner_id = auth.uid() or user_id = auth.uid());
revoke insert, update on public.apiary_members from authenticated;

-- запрошення: бачать той, хто запросив, і той, кого запросили
create policy read on public.invitations for select to authenticated
  using (from_user_id = auth.uid() or to_email = public.my_email());
-- надіслати можна лише від свого імені і лише до своїх пасік
create policy add on public.invitations for insert to authenticated
  with check (
    from_user_id = auth.uid() and status = 'pending' and deleted = 0
    and to_email <> public.my_email()
    and (apiary_ids is null or not exists (
      select 1 from unnest(apiary_ids) a(id)
      where not exists (
        select 1 from public.apiaries p where p.id = a.id and p.owner_id = auth.uid()))));
revoke update on public.invitations from authenticated;

-- запрошення: відправник і пошта - з входу, а не з того, що надіслав телефон
create or replace function public.trg_invitation_sender() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null then
    new.from_user_id := auth.uid();
    new.from_email := public.my_email();
  end if;
  new.to_email := lower(trim(new.to_email));
  return new;
end
$$;
drop trigger if exists t10_sender on public.invitations;
create trigger t10_sender before insert on public.invitations
  for each row execute function public.trg_invitation_sender();
