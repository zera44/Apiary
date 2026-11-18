-- Лічильник перемикань помічника (для адміна).
--
-- «Перемикання» - коли система сама змінила, хто відповідає:
--   escalate - Ведмедик не впорався -> Пасічник (чи Пасічник -> Робопасічник);
--   route    - складний помічник передав просте прохання нижчому
--              (Пасічник -> Ведмедик).
-- Людей і розмов тут немає: лише доба, вид, «з кого», «на кого» й кількість.
-- Таблиця й функції закриті для anon/authenticated; посередник assistant
-- пише службовим ключем, адмін читає в SQL-редакторі Supabase:
--
--   select * from assistant_switch_stats('day');    -- за добами
--   select * from assistant_switch_stats('week');   -- за тижнями
--   select * from assistant_switch_stats('month');  -- за місяцями

create table if not exists public.assistant_switches (
  day date not null,
  kind text not null check (kind in ('escalate', 'route')),
  from_model text not null,
  to_model text not null,
  count integer not null default 0 check (count >= 0),
  primary key (day, kind, from_model, to_model)
);

alter table public.assistant_switches enable row level security;
revoke all on public.assistant_switches from public, anon, authenticated;

-- +1 до лічильника за сьогодні (UTC). Невідомі значення ігноруються.
create or replace function public.assistant_switch_hit(p_kind text, p_from text, p_to text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.assistant_switches as s (day, kind, from_model, to_model, count)
  select (now() at time zone 'utc')::date, p_kind, p_from, p_to, 1
  where p_kind in ('escalate', 'route')
    and p_from in ('haiku', 'sonnet', 'opus')
    and p_to in ('haiku', 'sonnet', 'opus')
  on conflict (day, kind, from_model, to_model) do update set count = s.count + 1;
$$;

revoke all on function public.assistant_switch_hit(text, text, text) from public, anon, authenticated;
grant execute on function public.assistant_switch_hit(text, text, text) to service_role;

-- Зведення для адміна: період ('day' | 'week' | 'month'), вид, з кого, на кого,
-- скільки перемикань, а також скільки всього запитів до помічника було за
-- період (assistant_usage) і частка перемикань у них, %.
create or replace function public.assistant_switch_stats(p_period text default 'week')
returns table (period date, kind text, from_model text, to_model text, switches bigint,
               requests bigint, percent numeric)
language sql
security definer
set search_path = public
as $$
  with unit as (select case when p_period in ('day', 'week', 'month') then p_period else 'week' end as u),
  sw as (
    select date_trunc((select u from unit), s.day)::date as period, s.kind, s.from_model, s.to_model,
           sum(s.count)::bigint as switches
    from public.assistant_switches s
    group by 1, 2, 3, 4
  ),
  rq as (
    select date_trunc((select u from unit), a.day)::date as period, sum(a.count)::bigint as requests
    from public.assistant_usage a
    group by 1
  )
  select sw.period, sw.kind, sw.from_model, sw.to_model, sw.switches,
         coalesce(rq.requests, 0), round(100.0 * sw.switches / nullif(rq.requests, 0), 1)
  from sw left join rq using (period)
  order by sw.period desc, sw.kind, sw.from_model, sw.to_model;
$$;

revoke all on function public.assistant_switch_stats(text) from public, anon, authenticated;
grant execute on function public.assistant_switch_stats(text) to service_role;
