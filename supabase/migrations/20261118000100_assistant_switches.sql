-- Лічильник перемикань помічника (для адміна).
--
-- «Перемикання» - коли система сама змінила, хто відповідає:
--   escalate - Ведмедик не впорався -> Пасічник (чи Пасічник -> Робопасічник);
--   route    - складний помічник передав просте прохання нижчому
--              (Пасічник -> Ведмедик).
-- Людей показуємо без імен і пошти: «Юзер 1», «Юзер 2»... Номер дається
-- при першому перемиканні людини й далі не змінюється. Розмов тут немає.
-- Таблиці й функції закриті для anon/authenticated; посередник assistant
-- пише службовим ключем, адмін читає в SQL-редакторі Supabase:
--
--   select * from assistant_switch_stats('day');    -- за добами
--   select * from assistant_switch_stats('week');   -- за тижнями
--   select * from assistant_switch_stats('month');  -- за місяцями

-- постійний номер людини («Юзер N»)
create table if not exists public.assistant_switch_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  n integer generated always as identity unique
);

create table if not exists public.assistant_switches (
  day date not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('escalate', 'route')),
  from_model text not null,
  to_model text not null,
  count integer not null default 0 check (count >= 0),
  primary key (day, user_id, kind, from_model, to_model)
);

alter table public.assistant_switch_users enable row level security;
alter table public.assistant_switches enable row level security;
revoke all on public.assistant_switch_users from public, anon, authenticated;
revoke all on public.assistant_switches from public, anon, authenticated;

-- +1 до лічильника людини за сьогодні (UTC). Невідомі значення ігноруються.
create or replace function public.assistant_switch_hit(p_user uuid, p_kind text, p_from text, p_to text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user is null or p_kind not in ('escalate', 'route')
     or p_from not in ('haiku', 'sonnet', 'opus') or p_to not in ('haiku', 'sonnet', 'opus') then
    return;
  end if;
  insert into public.assistant_switch_users (user_id) values (p_user) on conflict do nothing;
  insert into public.assistant_switches as s (day, user_id, kind, from_model, to_model, count)
  values ((now() at time zone 'utc')::date, p_user, p_kind, p_from, p_to, 1)
  on conflict (day, user_id, kind, from_model, to_model) do update set count = s.count + 1;
end;
$$;

revoke all on function public.assistant_switch_hit(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.assistant_switch_hit(uuid, text, text, text) to service_role;

-- Зведення для адміна: період ('day' | 'week' | 'month'), «Юзер N», вид,
-- з кого, на кого, скільки перемикань; а також усього запитів цієї людини
-- за період (assistant_usage) і частка перемикань, %.
create or replace function public.assistant_switch_stats(p_period text default 'week')
returns table (period date, who text, kind text, from_model text, to_model text,
               switches bigint, requests bigint, percent numeric)
language sql
security definer
set search_path = public
as $$
  with unit as (select case when p_period in ('day', 'week', 'month') then p_period else 'week' end as u),
  sw as (
    select date_trunc((select u from unit), s.day)::date as period, s.user_id, s.kind,
           s.from_model, s.to_model, sum(s.count)::bigint as switches
    from public.assistant_switches s
    group by 1, 2, 3, 4, 5
  ),
  rq as (
    select date_trunc((select u from unit), a.day)::date as period, a.user_id, sum(a.count)::bigint as requests
    from public.assistant_usage a
    group by 1, 2
  )
  select sw.period, 'Юзер ' || u.n, sw.kind, sw.from_model, sw.to_model, sw.switches,
         coalesce(rq.requests, 0), round(100.0 * sw.switches / nullif(rq.requests, 0), 1)
  from sw
  join public.assistant_switch_users u on u.user_id = sw.user_id
  left join rq on rq.period = sw.period and rq.user_id = sw.user_id
  order by sw.period desc, u.n, sw.kind, sw.from_model, sw.to_model;
$$;

revoke all on function public.assistant_switch_stats(text) from public, anon, authenticated;
grant execute on function public.assistant_switch_stats(text) to service_role;
