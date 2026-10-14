-- Запрошувальне посилання: власник створює посилання (для однієї людини,
-- діє 7 днів) і надсилає будь-яким месенджером; помічник відкриває його -
-- і одразу додається до пасік (без пошуку за поштою й без відповіді на
-- запрошення). Посилання одноразове: удруге (зокрема після «Забрати
-- доступ») ним не скористатися.

create table if not exists public.invite_links (
  token text primary key,
  owner_id uuid not null references auth.users (id) on delete cascade,
  apiary_ids text[],
  apiary_names text[] not null default '{}',
  stock_access integer not null default 0 check (stock_access in (0, 1)),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by uuid,
  used_at timestamptz,
  revoked boolean not null default false
);
create index if not exists invite_links_owner on public.invite_links (owner_id);

-- власник бачить свої посилання; створюються й використовуються - лише
-- функціями нижче
alter table public.invite_links enable row level security;
revoke all on public.invite_links from public, anon, authenticated;
grant select on public.invite_links to authenticated;
drop policy if exists invite_links_own on public.invite_links;
create policy invite_links_own on public.invite_links
  for select to authenticated using (owner_id = auth.uid());

-- Створити посилання до пасік [p_apiary_ids] (NULL - до всіх, зокрема
-- майбутніх); [p_stock] - зі складом і фінансами. Повертає код посилання.
create or replace function public.create_invite_link(p_apiary_ids text[], p_stock boolean)
returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  names text[] := '{}';
  t text;
begin
  if me is null then
    raise exception 'потрібен вхід' using errcode = '42501';
  end if;
  if p_apiary_ids is not null then
    if cardinality(p_apiary_ids) = 0 or exists (
        select 1 from unnest(p_apiary_ids) a
        where not exists (select 1 from public.apiaries p
                          where p.id = a and p.owner_id = me and p.deleted = 0)) then
      raise exception 'чужа пасіка' using errcode = '42501';
    end if;
    -- назви - з бази (не від телефона)
    select coalesce(array_agg(p.name order by p.name), '{}') into names
      from public.apiaries p where p.id = any (p_apiary_ids) and p.owner_id = me;
  end if;
  -- від розсилки без кінця: не більше 20 діючих посилань
  if (select count(*) from public.invite_links
      where owner_id = me and not revoked and used_by is null and expires_at > now()) >= 20 then
    raise exception 'забагато посилань - скасуйте старі' using errcode = '54000';
  end if;
  t := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.invite_links (token, owner_id, apiary_ids, apiary_names, stock_access)
  values (t, me, p_apiary_ids, names, case when p_stock then 1 else 0 end);
  return t;
end
$$;

-- Скасувати своє посилання, поки ним не скористались.
create or replace function public.cancel_invite_link(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.invite_links set revoked = true
    where token = p_token and owner_id = auth.uid() and used_by is null and not revoked;
  if not found then
    raise exception 'посилання не знайдено або ним уже скористались' using errcode = '42501';
  end if;
end
$$;

-- Прийняти посилання: людина, яка увійшла, стає помічником. Повертає, чиї
-- й які пасіки ({owner_email, apiary_names}). Повторне відкриття тією самою
-- людиною - без помилки.
create or replace function public.accept_invite_link(p_token text) returns json
language plpgsql security definer set search_path = public as $$
declare
  l public.invite_links;
  me uuid := auth.uid();
  a text;
  stamp double precision := extract(epoch from now());
  owner_email text;
begin
  if me is null then
    raise exception 'потрібен вхід' using errcode = '42501';
  end if;
  select * into l from public.invite_links where token = p_token for update;
  if l.token is null then
    raise exception 'посилання не знайдено' using errcode = 'P0002';
  end if;
  select coalesce(p.email, '') into owner_email from public.profiles p where p.id = l.owner_id;
  if l.used_by = me then
    return json_build_object('owner_email', owner_email, 'apiary_names', l.apiary_names);
  end if;
  if l.owner_id = me then
    raise exception 'це ваше власне посилання' using errcode = '22023';
  end if;
  if l.revoked or l.used_by is not null or l.expires_at <= now() then
    raise exception 'посилання вже не діє' using errcode = '22023';
  end if;
  foreach a in array coalesce(l.apiary_ids, array[null::text]) loop
    -- пасіку, яку тим часом видалили чи віддали, - пропускаємо
    if a is not null and not exists (
        select 1 from public.apiaries p
        where p.id = a and p.owner_id = l.owner_id and p.deleted = 0) then
      continue;
    end if;
    insert into public.apiary_members (owner_id, apiary_id, user_id, email, stock_access, updated_at)
    values (l.owner_id, a, me, public.my_email(), l.stock_access, stamp)
    on conflict (owner_id, (coalesce(apiary_id, '')), user_id) do update
      set deleted = 0,
          email = excluded.email,
          stock_access = greatest(
            case when public.apiary_members.deleted = 1 then 0 else public.apiary_members.stock_access end,
            excluded.stock_access),
          updated_at = stamp;
  end loop;
  update public.invite_links set used_by = me, used_at = now() where token = p_token;
  return json_build_object('owner_email', owner_email, 'apiary_names', l.apiary_names);
end
$$;

revoke execute on function public.create_invite_link(text[], boolean), public.cancel_invite_link(text),
  public.accept_invite_link(text) from public, anon;
grant execute on function public.create_invite_link(text[], boolean), public.cancel_invite_link(text),
  public.accept_invite_link(text) to authenticated;
