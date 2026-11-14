-- Денний ліміт запитів помічника на одну людину.
--
-- Посередник assistant після перевірки входу викликає assistant_hit(людина,
-- ліміт) службовим ключем. Рядок «людина + доба (UTC)» лічить запити; понад
-- ліміт функція відмовляє (false) і лічильник не росте. Таблиця й функція
-- закриті для anon і authenticated: ні читати, ні підкрутити лічильник із
-- телефона не можна.

create table if not exists public.assistant_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day)
);

alter table public.assistant_usage enable row level security;
revoke all on public.assistant_usage from public, anon, authenticated;

-- true - запит зараховано; false - ліміт на сьогодні вичерпано (або ліміт
-- не додатний). Одна атомарна команда: паралельні запити не обійдуть ліміт.
create or replace function public.assistant_hit(p_user uuid, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  n integer;
begin
  if p_user is null or p_limit is null or p_limit < 1 then
    return false;
  end if;
  insert into public.assistant_usage as u (user_id, day, count)
  values (p_user, today, 1)
  on conflict (user_id, day) do update set count = u.count + 1
    where u.count < p_limit
  returning u.count into n;
  if n is null then
    return false;
  end if;
  -- старі доби цієї людини не потрібні
  delete from public.assistant_usage where user_id = p_user and day < today - 7;
  return true;
end
$$;

revoke all on function public.assistant_hit(uuid, integer) from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.assistant_hit(uuid, integer) to service_role;
  end if;
end
$$;
