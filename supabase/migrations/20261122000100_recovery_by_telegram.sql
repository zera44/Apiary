-- Відновлення доступу кодом із Telegram замість довгого коду на папері.
--
--   * код (лише хеш) діє 2 хвилини, один раз і лише в тій заявці на вхід, для якої
--     його попросили (recovery_request): секрет заявки знає тільки телефон, що просив;
--   * просити код можна не частіше ніж раз на 30 с і не більше 5 разів за годину;
--   * кнопка «Це я» в повідомленні бота (tg_recovery_confirm) дозволяє застосунку,
--     що опитує заявку, перейти до нового PIN без введення коду;
--   * новий PIN після відновлення (pin_recover): якщо в акаунті є інші активні
--     пристрої, він почне діяти через добу (власник устигне натиснути «Це не я»),
--     а в момент, коли почне, усі пристрої вийдуть; якщо інших пристроїв немає - одразу;
--   * «Це не я» (pin_keep, sign_out_everywhere) скасовує і код, і заплановану зміну PIN.

alter table public.account_pins
  add column if not exists recovery_expires timestamptz,
  add column if not exists recovery_sent_at timestamptz,
  add column if not exists recovery_request text,
  add column if not exists recovery_msg_id bigint,
  add column if not exists recovery_count integer not null default 0,
  add column if not exists recovery_window timestamptz,
  add column if not exists pending_pin_hash text,
  add column if not exists pending_pin_at timestamptz;

comment on column public.account_pins.recovery_hash is
  'Хеш одноразового коду відновлення, надісланого в Telegram; діє до recovery_expires і лише в заявці recovery_request.';

-- коли власник натиснув «Це я» під повідомленням про відновлення (до цього часу діє)
alter table public.tg_login_requests
  add column if not exists recovery_ok_until timestamptz;

-- старі довгі коди, що не спливали, більше не діють
update public.account_pins set recovery_hash = null, recovery_expires = null where recovery_hash is not null;

-- Застосувати заплановані зміни, час яких настав: вимкнення PIN і новий PIN після
-- відновлення (тоді всі пристрої виходять).
create or replace function public.pin_apply_due(p_user uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  update public.account_pins set pin_hash = null, disable_at = null, updated_at = now()
    where user_id = p_user and disable_at is not null and disable_at <= now();
  update public.account_pins
    set pin_hash = pending_pin_hash, pending_pin_hash = null, pending_pin_at = null,
        failed = 0, lockouts = 0, locked_until = null, disable_at = null, updated_at = now()
    where user_id = p_user and pending_pin_at is not null and pending_pin_at <= now();
  if found then
    delete from auth.sessions where user_id = p_user;
  end if;
end
$$;

-- Стан PIN: 'none', 'on', 'off', 'locked'; pending_at - коли почне діяти новий PIN.
create or replace function public.pin_state(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.account_pins;
begin
  perform public.pin_apply_due(p_user);
  select * into p from public.account_pins where user_id = p_user;
  if p.user_id is null then
    return jsonb_build_object('state', 'none');
  end if;
  if p.pin_hash is null then
    return jsonb_build_object('state', 'off');
  end if;
  if p.locked_until is not null and p.locked_until > now() then
    return jsonb_build_object('state', 'locked',
      'retry_in', ceil(extract(epoch from p.locked_until - now()))::int);
  end if;
  return jsonb_build_object('state', 'on', 'disable_at', p.disable_at, 'pending_at', p.pending_pin_at);
end
$$;

-- Видати код для заявки p_request. Повертає 0 - видано; -1 - PIN немає чи вимкнено;
-- інакше секунди, через які можна попросити знову.
drop function if exists public.pin_recovery_issue(uuid, text, integer, integer);
create or replace function public.pin_recovery_issue(
  p_user uuid, p_request text, p_hash text, p_ttl_secs integer, p_gap_secs integer, p_per_hour integer
) returns integer
language plpgsql security definer set search_path = public as $$
declare p public.account_pins;
begin
  perform public.pin_apply_due(p_user);
  select * into p from public.account_pins where user_id = p_user for update;
  if p.user_id is null or p.pin_hash is null then
    return -1;
  end if;
  if p.recovery_sent_at is not null and p.recovery_sent_at > now() - make_interval(secs => p_gap_secs) then
    return greatest(1, ceil(extract(epoch from p.recovery_sent_at + make_interval(secs => p_gap_secs) - now()))::int);
  end if;
  if p.recovery_window is null or p.recovery_window <= now() - interval '1 hour' then
    p.recovery_window := now();
    p.recovery_count := 0;
  end if;
  if p.recovery_count >= p_per_hour then
    return greatest(1, ceil(extract(epoch from p.recovery_window + interval '1 hour' - now()))::int);
  end if;
  update public.account_pins
    set recovery_hash = p_hash,
        recovery_expires = now() + make_interval(secs => p_ttl_secs),
        recovery_request = p_request,
        recovery_msg_id = null,
        recovery_sent_at = now(),
        recovery_window = p.recovery_window,
        recovery_count = p.recovery_count + 1,
        updated_at = now()
    where user_id = p_user;
  return 0;
end
$$;

-- Номер повідомлення бота з кодом (щоб потім позначити його «використано»).
create or replace function public.pin_recovery_msg(p_user uuid, p_msg bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.account_pins set recovery_msg_id = p_msg where user_id = p_user;
end
$$;

-- Почати перевірку PIN (спроба зараховується до перевірки). Хеш коду - лише поки діє.
create or replace function public.pin_attempt(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.account_pins;
begin
  perform public.pin_apply_due(p_user);
  update public.account_pins set failed = failed + 1, updated_at = now()
    where user_id = p_user and pin_hash is not null
      and (locked_until is null or locked_until <= now())
    returning * into p;
  if p.user_id is null then
    return null;
  end if;
  return jsonb_build_object(
    'pin_hash', p.pin_hash,
    'recovery_hash',
      case when p.recovery_expires is not null and p.recovery_expires > now() then p.recovery_hash end,
    'recovery_request', p.recovery_request,
    'failed', p.failed);
end
$$;

-- Вдала перевірка й блокування стирають код (одноразовий).
create or replace function public.pin_result(p_user uuid, p_ok boolean) returns integer
language plpgsql security definer set search_path = public as $$
declare
  p public.account_pins;
  secs integer;
begin
  if p_ok then
    update public.account_pins
      set failed = 0, lockouts = 0, locked_until = null,
          recovery_hash = null, recovery_expires = null, updated_at = now()
      where user_id = p_user;
    return 0;
  end if;
  select * into p from public.account_pins where user_id = p_user for update;
  if p.user_id is null or p.failed < 5 then
    return 0;
  end if;
  secs := least(15 * 60 * power(2, p.lockouts)::int, 24 * 3600);
  update public.account_pins
    set failed = 0, lockouts = lockouts + 1, locked_until = now() + make_interval(secs => secs),
        recovery_hash = null, recovery_expires = null, updated_at = now()
    where user_id = p_user;
  return secs;
end
$$;

-- Встановити (змінити) PIN, коли власник знає чинний; стирає код і заплановане.
drop function if exists public.pin_set(uuid, text, text);
create or replace function public.pin_set(p_user uuid, p_pin_hash text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.account_pins (user_id, pin_hash)
  values (p_user, p_pin_hash)
  on conflict (user_id) do update
    set pin_hash = excluded.pin_hash, recovery_hash = null, recovery_expires = null,
        recovery_request = null, recovery_msg_id = null, pending_pin_hash = null, pending_pin_at = null,
        failed = 0, lockouts = 0, locked_until = null, disable_at = null, updated_at = now();
end
$$;

-- Новий PIN після відновлення. Є інші активні пристрої - почне діяти через p_delay_secs
-- (pending_at у відповіді), інакше одразу. msg - повідомлення бота з кодом, якщо було.
create or replace function public.pin_recover(p_user uuid, p_pin_hash text, p_delay_secs integer) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  msg bigint;
  at timestamptz;
begin
  select recovery_msg_id into msg from public.account_pins where user_id = p_user for update;
  if p_delay_secs > 0 and exists (select 1 from auth.sessions where user_id = p_user) then
    at := now() + make_interval(secs => p_delay_secs);
    update public.account_pins
      set pending_pin_hash = p_pin_hash, pending_pin_at = at,
          recovery_hash = null, recovery_expires = null, recovery_request = null, recovery_msg_id = null,
          updated_at = now()
      where user_id = p_user;
  else
    update public.account_pins
      set pin_hash = p_pin_hash, pending_pin_hash = null, pending_pin_at = null,
          recovery_hash = null, recovery_expires = null, recovery_request = null, recovery_msg_id = null,
          failed = 0, lockouts = 0, locked_until = null, disable_at = null, updated_at = now()
      where user_id = p_user;
  end if;
  return jsonb_build_object('pending_at', at, 'msg', msg);
end
$$;

-- «Це не я»: скасувати заплановане вимкнення PIN, заплановану зміну PIN і код.
-- true - було що скасовувати.
create or replace function public.pin_keep(p_user uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.account_pins
    set disable_at = null, pending_pin_hash = null, pending_pin_at = null,
        recovery_hash = null, recovery_expires = null, updated_at = now()
    where user_id = p_user and (disable_at is not null or pending_pin_at is not null);
  return found;
end
$$;

-- «Вийти всюди» скасовує й код відновлення та заплановану зміну PIN.
create or replace function public.sign_out_everywhere(p_user uuid) returns integer
language plpgsql security definer set search_path = public, auth as $$
declare n integer;
begin
  update public.account_pins
    set recovery_hash = null, recovery_expires = null, pending_pin_hash = null, pending_pin_at = null
    where user_id = p_user;
  delete from auth.sessions where user_id = p_user;
  get diagnostics n = row_count;
  return n;
end
$$;

-- Власник натиснув «Це я»: заявка від його Telegram, уже схвалена, і саме для неї
-- видано код, що ще діє. true - підтверджено.
create or replace function public.tg_recovery_confirm(p_id text, p_telegram_id bigint) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.tg_login_requests r
    set recovery_ok_until = now() + interval '2 minutes'
    from public.tg_identities i, public.account_pins p
    where r.id = p_id and r.state = 'approved' and r.expires_at > now()
      and r.telegram_id = p_telegram_id
      and i.telegram_id = r.telegram_id and p.user_id = i.user_id
      and p.pin_hash is not null and p.recovery_request = p_id
      and p.recovery_expires is not null and p.recovery_expires > now();
  return found;
end
$$;

-- Опитування заявки тепер повідомляє й про підтвердження відновлення.
create or replace function public.tg_login_poll(p_id text, p_secret_hash text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.tg_login_requests;
  uid uuid;
begin
  select * into r from public.tg_login_requests where id = p_id;
  if r.id is null or r.secret_hash <> p_secret_hash then
    return null;
  end if;
  if r.expires_at <= now() and r.state not in ('done', 'cancelled') then
    return jsonb_build_object('state', 'expired');
  end if;
  if r.state <> 'approved' then
    return jsonb_build_object('state', r.state, 'link', r.link_user is not null);
  end if;
  select user_id into uid from public.tg_identities where telegram_id = r.telegram_id;
  return jsonb_build_object('state', 'approved', 'telegram_id', r.telegram_id, 'chat_id', r.chat_id,
    'phone', r.phone, 'first_name', r.first_name, 'device', r.device_name, 'user_id', uid,
    'recovery_ok', r.recovery_ok_until is not null and r.recovery_ok_until > now(),
    'pin', case when uid is null then jsonb_build_object('state', 'none') else public.pin_state(uid) end);
end
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'pin_apply_due(uuid)', 'pin_state(uuid)',
    'pin_recovery_issue(uuid, text, text, integer, integer, integer)', 'pin_recovery_msg(uuid, bigint)',
    'pin_attempt(uuid)', 'pin_result(uuid, boolean)', 'pin_set(uuid, text)',
    'pin_recover(uuid, text, integer)', 'pin_keep(uuid)', 'sign_out_everywhere(uuid)',
    'tg_recovery_confirm(text, bigint)', 'tg_login_poll(text, text)'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end
$$;
