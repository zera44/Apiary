-- Спільний доступ: функції, які викликає застосунок (SharingApi).

-- Користувач із поштою [p_email] (NULL - ще не входив у Vulyk).
create or replace function public.find_user(p_email text) returns uuid
language sql stable security definer set search_path = public as $$
  select p.id from public.profiles p
  where auth.uid() is not null and p.email = lower(trim(p_email))
  limit 1
$$;

-- Відповісти на запрошення. Прийняли - людина стає помічником (до кожної
-- з пасік запрошення або до всіх). Повторне запрошення оновлює наявний
-- запис помічника, а не створює другий.
create or replace function public.respond_invitation(p_id text, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  inv public.invitations;
  me uuid := auth.uid();
  a text;
  stamp double precision := extract(epoch from now());
begin
  select * into inv from public.invitations where id = p_id for update;
  if inv.id is null or me is null or inv.to_email <> public.my_email() then
    raise exception 'чуже запрошення' using errcode = '42501';
  end if;
  if inv.status <> 'pending' then
    raise exception 'на запрошення вже відповіли' using errcode = '22023';
  end if;
  update public.invitations
    set status = case when p_accept then 'accepted' else 'declined' end, updated_at = stamp
    where id = p_id;
  if not p_accept then
    return;
  end if;
  foreach a in array coalesce(inv.apiary_ids, array[null::text]) loop
    -- пасіку, яку тим часом видалили чи віддали, - пропускаємо
    if a is not null and not exists (
        select 1 from public.apiaries p
        where p.id = a and p.owner_id = inv.from_user_id and p.deleted = 0) then
      continue;
    end if;
    insert into public.apiary_members (owner_id, apiary_id, user_id, email, stock_access, updated_at)
    values (inv.from_user_id, a, me, public.my_email(), inv.stock_access, stamp)
    on conflict (owner_id, (coalesce(apiary_id, '')), user_id) do update
      set deleted = 0,
          email = excluded.email,
          stock_access = greatest(
            case when public.apiary_members.deleted = 1 then 0 else public.apiary_members.stock_access end,
            excluded.stock_access),
          updated_at = stamp;
  end loop;
end
$$;

-- Скасувати своє запрошення, поки на нього не відповіли.
create or replace function public.cancel_invitation(p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.invitations
    set status = 'revoked', updated_at = extract(epoch from now())
    where id = p_id and from_user_id = auth.uid() and status = 'pending';
  if not found then
    raise exception 'запрошення не знайдено або на нього вже відповіли' using errcode = '42501';
  end if;
end
$$;

-- Власник: дозволити чи заборонити помічнику склад і фінанси.
create or replace function public.set_member_stock_access(p_id text, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.apiary_members
    set stock_access = case when p_on then 1 else 0 end, updated_at = extract(epoch from now())
    where id = p_id and owner_id = auth.uid() and deleted = 0;
  if not found then
    raise exception 'чужий помічник' using errcode = '42501';
  end if;
end
$$;

-- Забрати доступ (власник) або відмовитись від нього (сам помічник).
-- Позначкою «видалено»: телефон помічника дізнається й прибере чужі дані.
create or replace function public.remove_member(p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.apiary_members
    set deleted = 1, stock_access = 0, updated_at = extract(epoch from now())
    where id = p_id and (owner_id = auth.uid() or user_id = auth.uid()) and deleted = 0;
  if not found then
    raise exception 'чужий помічник' using errcode = '42501';
  end if;
end
$$;

-- Перед видаленням акаунта [p_user] (функція delete-account, ключ
-- сервера): його записи про доступ - позначками «видалено» (без пошти), щоб
-- телефони помічників і власників прибрали чужі дані; його запрошення -
-- геть.
create or replace function public.delete_account_prepare(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.apiary_members
    set deleted = 1, stock_access = 0, email = '', updated_at = extract(epoch from now())
    where (owner_id = p_user or user_id = p_user) and (deleted = 0 or email <> '');
  delete from public.invitations
    where from_user_id = p_user
       or to_email = (select lower(trim(email)) from auth.users where id = p_user);
end
$$;
revoke execute on function public.delete_account_prepare(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_prepare(uuid) to service_role;

revoke execute on function public.find_user(text), public.respond_invitation(text, boolean),
  public.cancel_invitation(text), public.set_member_stock_access(text, boolean),
  public.remove_member(text) from public, anon;
grant execute on function public.find_user(text), public.respond_invitation(text, boolean),
  public.cancel_invitation(text), public.set_member_stock_access(text, boolean),
  public.remove_member(text) to authenticated;
