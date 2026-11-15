-- Вхід через Telegram і PIN.
--
-- Як працює вхід (функція telegram-auth):
--   1. Телефон придумує секрет S і надсилає лише його SHA-256. Сервер
--      створює заявку R (живе 5 хв) і число для звірки (10..99).
--   2. Телефон відкриває бота t.me/<бот>?start=R. Бот показує пристрій і
--      час і просить вибрати число, яке видно в застосунку. Не те число -
--      заявку скасовано.
--   3. Людина ділиться своїм контактом. Сервер приймає лише контакт самого
--      відправника (contact.user_id = from.id) - заявка «підтверджена».
--   4. Телефон опитує сервер з R і S. Сесію сервер видає лише тому, хто
--      знає S, і лише один раз. Для акаунта лише з Telegram потрібен ще PIN.
--
-- Акаунт прив'язаний до ідентифікатора Telegram, а не до номера (номер
-- оператор може перевидати). У Supabase Auth такий акаунт має технічну
-- пошту tg-<id>@tg.vulyk.invalid: вона не справжня, на неї нічого не
-- надсилається, і запрошення за поштою до неї не прив'язуються.
--
-- Усі таблиці закриті для телефона (anon, authenticated): з ними працюють
-- лише функції нижче, які викликає telegram-auth службовим ключем.

-- ── заявки на вхід ──────────────────────────────────────────────────────
create table if not exists public.tg_login_requests (
  id text primary key check (id ~ '^[A-Za-z0-9_-]{22}$'),
  secret_hash text not null check (secret_hash ~ '^[0-9a-f]{64}$'),
  match_code smallint not null check (match_code between 10 and 99),
  device_name text not null default '',
  ip text not null default '',
  -- не NULL - прив'язати Telegram до цього (уже відкритого) акаунта
  link_user uuid references auth.users (id) on delete cascade,
  telegram_id bigint,
  chat_id bigint,
  phone text,
  first_name text,
  state text not null default 'new'
    check (state in ('new', 'opened', 'matched', 'approved', 'done', 'cancelled')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '5 minutes'
);
create index if not exists tg_login_requests_ip on public.tg_login_requests (ip, created_at);
create index if not exists tg_login_requests_tg on public.tg_login_requests (telegram_id, created_at);

-- ── Telegram-акаунти: хто з Telegram яким акаунтом Vulyk є ──────────────
create table if not exists public.tg_identities (
  telegram_id bigint primary key,
  user_id uuid not null unique references auth.users (id) on delete cascade,
  chat_id bigint not null,
  phone text not null,
  created_at timestamptz not null default now(),
  last_login_at timestamptz
);

-- ── PIN: хеш (PBKDF2 у функції, з секретною добавкою), спроби, блокування
create table if not exists public.account_pins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  pin_hash text,            -- NULL - PIN вимкнено
  recovery_hash text,       -- одноразовий код відновлення
  failed integer not null default 0 check (failed >= 0),
  lockouts integer not null default 0 check (lockouts >= 0),
  locked_until timestamptz,
  disable_at timestamptz,   -- заплановане вимкнення PIN (лише Telegram-акаунти: через добу)
  updated_at timestamptz not null default now()
);

-- ── оновлення від Telegram, які вже обробили (Telegram повторює запити) ─
create table if not exists public.tg_updates (
  update_id bigint primary key,
  at timestamptz not null default now()
);

-- номер телефону в профілі (підтверджений Telegram)
alter table public.profiles add column if not exists phone text;

do $$
declare t text;
begin
  foreach t in array array['tg_login_requests', 'tg_identities', 'account_pins', 'tg_updates'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end
$$;

-- ── функції для telegram-auth ───────────────────────────────────────────

-- Нова заявка. false - забагато заявок (з цієї адреси або загалом).
create or replace function public.tg_login_create(
  p_id text, p_secret_hash text, p_match smallint, p_device text, p_ip text, p_link_user uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  -- старе прибираємо тут же: заявки живуть хвилини
  delete from public.tg_login_requests where expires_at < now() - interval '1 day';
  delete from public.tg_updates where at < now() - interval '1 day';
  if (select count(*) from public.tg_login_requests
      where ip = coalesce(p_ip, '') and created_at > now() - interval '10 minutes') >= 10 then
    return false;
  end if;
  if p_link_user is not null and (select count(*) from public.tg_login_requests
      where link_user = p_link_user and created_at > now() - interval '10 minutes') >= 5 then
    return false;
  end if;
  if (select count(*) from public.tg_login_requests
      where created_at > now() - interval '5 minutes') >= 1000 then
    return false;
  end if;
  insert into public.tg_login_requests (id, secret_hash, match_code, device_name, ip, link_user)
  values (p_id, p_secret_hash, p_match, left(coalesce(p_device, ''), 60), coalesce(p_ip, ''), p_link_user);
  return true;
end
$$;

-- Чи це оновлення Telegram нове (true) чи повтор (false).
create or replace function public.tg_update_seen(p_update_id bigint) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  insert into public.tg_updates (update_id) values (p_update_id) on conflict do nothing;
  return found;
end
$$;

-- Людина відкрила бота за посиланням заявки. Заявку «забирає» перший, хто
-- її відкрив; інший Telegram цю заявку вже не отримає.
create or replace function public.tg_login_open(p_id text, p_telegram_id bigint, p_chat_id bigint)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.tg_login_requests;
begin
  update public.tg_login_requests
    set telegram_id = p_telegram_id, chat_id = p_chat_id, state = 'opened'
    where id = p_id and expires_at > now()
      and (state = 'new' or (state = 'opened' and telegram_id = p_telegram_id))
    returning * into r;
  if r.id is null then
    return null;
  end if;
  return jsonb_build_object('match', r.match_code, 'device', r.device_name, 'created_at', r.created_at,
                            'link', r.link_user is not null);
end
$$;

-- Людина вибрала число. 'ok' - збіглося; 'wrong' - ні (заявку скасовано);
-- 'gone' - заявки немає або минула.
create or replace function public.tg_login_match(p_id text, p_telegram_id bigint, p_code smallint)
returns text
language plpgsql security definer set search_path = public as $$
declare r public.tg_login_requests;
begin
  select * into r from public.tg_login_requests
    where id = p_id and telegram_id = p_telegram_id and state = 'opened' and expires_at > now()
    for update;
  if r.id is null then
    return 'gone';
  end if;
  if r.match_code = p_code then
    update public.tg_login_requests set state = 'matched' where id = p_id;
    return 'ok';
  end if;
  update public.tg_login_requests set state = 'cancelled' where id = p_id;
  return 'wrong';
end
$$;

-- «Це не я»: скасувати заявку.
create or replace function public.tg_login_cancel(p_id text, p_telegram_id bigint) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.tg_login_requests set state = 'cancelled'
    where id = p_id and telegram_id = p_telegram_id and state in ('new', 'opened', 'matched');
  return found;
end
$$;

-- Людина поділилася своїм контактом (функція вже перевірила, що контакт
-- її власний). Підтверджує останню заявку цього Telegram, де збіглося
-- число. Відповідь: 'approved' (вхід), 'linked' (прив'язано до акаунта),
-- 'taken' (цей Telegram уже має інший акаунт або акаунт - інший Telegram),
-- 'none' (немає такої заявки).
create or replace function public.tg_login_contact(p_telegram_id bigint, p_phone text, p_first_name text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  r public.tg_login_requests;
  owner uuid;
begin
  select * into r from public.tg_login_requests
    where telegram_id = p_telegram_id and state = 'matched' and expires_at > now()
    order by created_at desc limit 1
    for update;
  if r.id is null then
    return 'none';
  end if;
  if r.link_user is not null then
    select user_id into owner from public.tg_identities where telegram_id = p_telegram_id;
    if (owner is not null and owner <> r.link_user)
       or exists (select 1 from public.tg_identities where user_id = r.link_user and telegram_id <> p_telegram_id) then
      update public.tg_login_requests set state = 'cancelled' where id = r.id;
      return 'taken';
    end if;
    insert into public.tg_identities (telegram_id, user_id, chat_id, phone)
    values (p_telegram_id, r.link_user, r.chat_id, p_phone)
    on conflict (telegram_id) do update set chat_id = excluded.chat_id, phone = excluded.phone;
    update public.profiles set phone = p_phone where id = r.link_user;
    update public.tg_login_requests set state = 'done', phone = p_phone where id = r.id;
    return 'linked';
  end if;
  -- на PIN після підтвердження - ще 5 хвилин
  update public.tg_login_requests
    set state = 'approved', phone = p_phone, first_name = left(coalesce(p_first_name, ''), 60),
        expires_at = now() + interval '5 minutes'
    where id = r.id;
  return 'approved';
end
$$;

-- Стан PIN акаунта: 'none' (не встановлено), 'on', 'off', 'locked'.
-- Заплановане вимкнення, час якого настав, застосовується тут.
create or replace function public.pin_state(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.account_pins;
begin
  update public.account_pins set pin_hash = null, disable_at = null, updated_at = now()
    where user_id = p_user and disable_at is not null and disable_at <= now();
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
  return jsonb_build_object('state', 'on', 'disable_at', p.disable_at);
end
$$;

-- Заявка за R і відбитком секрету S. Лише той, хто знає S, дізнається
-- стан. NULL - немає такої заявки або секрет не той.
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
    'pin', case when uid is null then jsonb_build_object('state', 'none') else public.pin_state(uid) end);
end
$$;

-- Завершити вхід: заявка спрацьовує рівно один раз (паралельні запити
-- отримають false).
create or replace function public.tg_login_finish(p_id text, p_secret_hash text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.tg_login_requests set state = 'done'
    where id = p_id and secret_hash = p_secret_hash and state = 'approved' and expires_at > now();
  return found;
end
$$;

-- Новий акаунт із Telegram (акаунт Auth функція вже створила).
create or replace function public.tg_identity_bind(p_telegram_id bigint, p_user uuid, p_chat_id bigint, p_phone text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  insert into public.tg_identities (telegram_id, user_id, chat_id, phone, last_login_at)
  values (p_telegram_id, p_user, p_chat_id, p_phone, now())
  on conflict do nothing;
  if not found then
    return false;
  end if;
  update public.profiles set phone = p_phone where id = p_user;
  return true;
end
$$;

-- Успішний вхід: оновити чат, номер і час входу.
create or replace function public.tg_identity_seen(p_telegram_id bigint, p_chat_id bigint, p_phone text)
returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  update public.tg_identities set chat_id = p_chat_id, phone = p_phone, last_login_at = now()
    where telegram_id = p_telegram_id returning user_id into uid;
  if uid is not null then
    update public.profiles set phone = p_phone where id = uid;
  end if;
end
$$;

-- Telegram акаунта (для сповіщень і перевірок): NULL - не прив'язано.
create or replace function public.tg_identity_of(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('telegram_id', telegram_id, 'chat_id', chat_id, 'phone', phone)
  from public.tg_identities where user_id = p_user
$$;

-- Акаунт за Telegram (кнопки бота «Це не я»): NULL - не прив'язано.
create or replace function public.tg_user_of(p_telegram_id bigint) returns uuid
language sql stable security definer set search_path = public as $$
  select user_id from public.tg_identities where telegram_id = p_telegram_id
$$;

-- Почати перевірку PIN: спроба зараховується ДО перевірки, тож паралельні
-- запити не обійдуть ліміт. Повертає хеші або NULL (заблоковано, PIN
-- немає чи вимкнено - тоді див. pin_state).
create or replace function public.pin_attempt(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.account_pins;
begin
  update public.account_pins set failed = failed + 1, updated_at = now()
    where user_id = p_user and pin_hash is not null
      and (locked_until is null or locked_until <= now())
    returning * into p;
  if p.user_id is null then
    return null;
  end if;
  return jsonb_build_object('pin_hash', p.pin_hash, 'recovery_hash', p.recovery_hash, 'failed', p.failed);
end
$$;

-- Результат перевірки PIN. Вдалося - лічильник з нуля. П'ята помилка
-- поспіль - блокування: 15 хв, далі вдвічі довше щоразу, до доби.
-- Повертає секунди блокування (0 - без блокування).
create or replace function public.pin_result(p_user uuid, p_ok boolean) returns integer
language plpgsql security definer set search_path = public as $$
declare
  p public.account_pins;
  secs integer;
begin
  if p_ok then
    update public.account_pins set failed = 0, lockouts = 0, locked_until = null, updated_at = now()
      where user_id = p_user;
    return 0;
  end if;
  select * into p from public.account_pins where user_id = p_user for update;
  if p.user_id is null or p.failed < 5 then
    return 0;
  end if;
  secs := least(15 * 60 * power(2, p.lockouts)::int, 24 * 3600);
  update public.account_pins
    set failed = 0, lockouts = lockouts + 1, locked_until = now() + make_interval(secs => secs), updated_at = now()
    where user_id = p_user;
  return secs;
end
$$;

-- Встановити (змінити) PIN і код відновлення; скасовує заплановане вимкнення.
create or replace function public.pin_set(p_user uuid, p_pin_hash text, p_recovery_hash text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.account_pins (user_id, pin_hash, recovery_hash)
  values (p_user, p_pin_hash, p_recovery_hash)
  on conflict (user_id) do update
    set pin_hash = excluded.pin_hash, recovery_hash = excluded.recovery_hash,
        failed = 0, lockouts = 0, locked_until = null, disable_at = null, updated_at = now();
end
$$;

-- Вимкнути PIN: одразу (p_at NULL) або в зазначений час.
create or replace function public.pin_disable(p_user uuid, p_at timestamptz) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_at is null then
    update public.account_pins set pin_hash = null, disable_at = null, updated_at = now() where user_id = p_user;
  else
    update public.account_pins set disable_at = p_at, updated_at = now() where user_id = p_user and pin_hash is not null;
  end if;
end
$$;

-- Скасувати заплановане вимкнення PIN. true - було що скасовувати.
create or replace function public.pin_keep(p_user uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  update public.account_pins set disable_at = null, updated_at = now()
    where user_id = p_user and disable_at is not null;
  return found;
end
$$;

-- «Вийти всюди»: стерти всі сесії акаунта. Токени доступу, видані раніше,
-- доживають свою годину, але оновитися вже не зможуть.
create or replace function public.sign_out_everywhere(p_user uuid) returns integer
language plpgsql security definer set search_path = public, auth as $$
declare n integer;
begin
  delete from auth.sessions where user_id = p_user;
  get diagnostics n = row_count;
  return n;
end
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'tg_login_create(text, text, smallint, text, text, uuid)', 'tg_update_seen(bigint)',
    'tg_login_open(text, bigint, bigint)', 'tg_login_match(text, bigint, smallint)',
    'tg_login_cancel(text, bigint)', 'tg_login_contact(bigint, text, text)', 'pin_state(uuid)',
    'tg_login_poll(text, text)', 'tg_login_finish(text, text)',
    'tg_identity_bind(bigint, uuid, bigint, text)', 'tg_identity_seen(bigint, bigint, text)',
    'tg_identity_of(uuid)', 'tg_user_of(bigint)', 'pin_attempt(uuid)', 'pin_result(uuid, boolean)',
    'pin_set(uuid, text, text)', 'pin_disable(uuid, timestamptz)', 'pin_keep(uuid)',
    'sign_out_everywhere(uuid)'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end
$$;
