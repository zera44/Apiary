-- Вхід через Telegram і PIN: заявки, звірка числа, контакт, одноразовість,
-- PIN зі спробами й блокуванням, запрошення для акаунтів без пошти.
begin;

-- Telegram-акаунт Марії (технічна пошта)
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000d1', 'tg-501@tg.vulyk.invalid');
insert into auth.sessions (user_id) values
  ('00000000-0000-0000-0000-0000000000d1'), ('00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-00000000000a');

set role service_role;

-- ── заявка й звірка числа ──────────────────────────────────────────────
select tests.ok(public.tg_login_create('AAAAAAAAAAAAAAAAAAAAA1', repeat('a', 64), 42::smallint, 'Samsung A52', '1.1.1.1', null), 'заявка');
select tests.ok(public.tg_login_poll('AAAAAAAAAAAAAAAAAAAAA1', repeat('b', 64)) is null, 'чужий секрет - нічого');
select tests.ok(public.tg_login_poll('AAAAAAAAAAAAAAAAAAAAA1', repeat('a', 64)) ->> 'state' = 'new', 'свій секрет - стан');
select tests.ok((public.tg_login_open('AAAAAAAAAAAAAAAAAAAAA1', 501, 9501) ->> 'match')::int = 42, 'бот бачить число');
select tests.ok(public.tg_login_open('AAAAAAAAAAAAAAAAAAAAA1', 777, 9777) is null, 'інший Telegram ту саму заявку не забере');
select tests.ok(public.tg_login_contact(501, '+380501112233', 'Марія') = 'none', 'контакт до звірки числа не приймається');
select tests.ok(public.tg_login_match('AAAAAAAAAAAAAAAAAAAAA1', 777, 42::smallint) = 'gone', 'чужий Telegram не звіряє');
select tests.ok(public.tg_login_match('AAAAAAAAAAAAAAAAAAAAA1', 501, 42::smallint) = 'ok', 'число збіглося');
select tests.ok(public.tg_login_contact(501, '+380501112233', 'Марія') = 'approved', 'контакт - підтверджено');
select tests.ok(public.tg_login_poll('AAAAAAAAAAAAAAAAAAAAA1', repeat('a', 64)) ->> 'state' = 'approved', 'опитування: підтверджено');
select tests.ok(public.tg_login_poll('AAAAAAAAAAAAAAAAAAAAA1', repeat('a', 64)) -> 'pin' ->> 'state' = 'none', 'новий акаунт - PIN ще немає');

-- новий акаунт: прив'язати; другий раз той самий Telegram не прив'яжеться
insert into public.profiles (id, email) values ('00000000-0000-0000-0000-0000000000d1', 'tg-501@tg.vulyk.invalid')
  on conflict (id) do nothing;
select tests.ok(public.tg_identity_bind(501, '00000000-0000-0000-0000-0000000000d1', 9501, '+380501112233'), 'прив''язали');
select tests.ok(not public.tg_identity_bind(501, '00000000-0000-0000-0000-00000000000b', 9501, '+380501112233'), 'вдруге - ні');
select tests.ok((select phone from public.profiles where id = '00000000-0000-0000-0000-0000000000d1') = '+380501112233', 'номер у профілі');

-- заявка спрацьовує один раз
select tests.ok(not public.tg_login_finish('AAAAAAAAAAAAAAAAAAAAA1', repeat('b', 64)), 'чужий секрет не завершить');
select tests.ok(public.tg_login_finish('AAAAAAAAAAAAAAAAAAAAA1', repeat('a', 64)), 'завершено');
select tests.ok(not public.tg_login_finish('AAAAAAAAAAAAAAAAAAAAA1', repeat('a', 64)), 'вдруге - ні');

-- не те число - заявку скасовано
select public.tg_login_create('AAAAAAAAAAAAAAAAAAAAA2', repeat('c', 64), 17::smallint, 'X', '1.1.1.1', null);
select public.tg_login_open('AAAAAAAAAAAAAAAAAAAAA2', 501, 9501);
select tests.ok(public.tg_login_match('AAAAAAAAAAAAAAAAAAAAA2', 501, 18::smallint) = 'wrong', 'не те число');
select tests.ok(public.tg_login_poll('AAAAAAAAAAAAAAAAAAAAA2', repeat('c', 64)) ->> 'state' = 'cancelled', 'скасовано');
select tests.ok(public.tg_login_match('AAAAAAAAAAAAAAAAAAAAA2', 501, 17::smallint) = 'gone', 'після скасування не вгадаєш');

-- «Це не я»
select public.tg_login_create('AAAAAAAAAAAAAAAAAAAAA3', repeat('d', 64), 20::smallint, 'X', '2.2.2.2', null);
select public.tg_login_open('AAAAAAAAAAAAAAAAAAAAA3', 501, 9501);
select tests.ok(public.tg_login_cancel('AAAAAAAAAAAAAAAAAAAAA3', 501), 'скасовано кнопкою');
select tests.ok(public.tg_login_contact(501, '+380501112233', 'Марія') = 'none', 'скасовану не підтвердиш');

-- минула заявка
select public.tg_login_create('AAAAAAAAAAAAAAAAAAAAA4', repeat('e', 64), 30::smallint, 'X', '2.2.2.2', null);
reset role;
update public.tg_login_requests set expires_at = now() - interval '1 second' where id = 'AAAAAAAAAAAAAAAAAAAAA4';
set role service_role;
select tests.ok(public.tg_login_open('AAAAAAAAAAAAAAAAAAAAA4', 501, 9501) is null, 'минула - бот не відкриє');
select tests.ok(public.tg_login_poll('AAAAAAAAAAAAAAAAAAAAA4', repeat('e', 64)) ->> 'state' = 'expired', 'минула');

-- ліміт заявок з однієї адреси
select public.tg_login_create('BBBBBBBBBBBBBBBBBBBBB' || n, repeat('f', 64), 11::smallint, 'X', '3.3.3.3', null)
  from generate_series(0, 9) n;
select tests.ok(not public.tg_login_create('CCCCCCCCCCCCCCCCCCCCC0', repeat('f', 64), 11::smallint, 'X', '3.3.3.3', null), '11-та за 10 хв - ні');
select tests.ok(public.tg_login_create('CCCCCCCCCCCCCCCCCCCCC1', repeat('f', 64), 11::smallint, 'X', '4.4.4.4', null), 'з іншої адреси - так');

-- повтори оновлень Telegram
select tests.ok(public.tg_update_seen(100), 'нове оновлення');
select tests.ok(not public.tg_update_seen(100), 'повтор');

-- ── прив'язати Telegram до Google-акаунта Олени ────────────────────────
select public.tg_login_create('DDDDDDDDDDDDDDDDDDDDD1', repeat('1', 64), 55::smallint, 'Pixel', '5.5.5.5', '00000000-0000-0000-0000-00000000000a');
select public.tg_login_open('DDDDDDDDDDDDDDDDDDDDD1', 501, 9501);
select public.tg_login_match('DDDDDDDDDDDDDDDDDDDDD1', 501, 55::smallint);
select tests.ok(public.tg_login_contact(501, '+380501112233', 'Марія') = 'taken', 'Telegram Марії не прив''язати до Олени');
select public.tg_login_create('DDDDDDDDDDDDDDDDDDDDD2', repeat('2', 64), 56::smallint, 'Pixel', '5.5.5.5', '00000000-0000-0000-0000-00000000000a');
select public.tg_login_open('DDDDDDDDDDDDDDDDDDDDD2', 600, 9600);
select public.tg_login_match('DDDDDDDDDDDDDDDDDDDDD2', 600, 56::smallint);
select tests.ok(public.tg_login_contact(600, '+380671234567', 'Олена') = 'linked', 'свій Telegram - прив''язано');
select tests.ok(public.tg_user_of(600) = '00000000-0000-0000-0000-00000000000a', 'Telegram 600 - Олена');
select tests.ok(public.tg_login_poll('DDDDDDDDDDDDDDDDDDDDD2', repeat('2', 64)) ->> 'state' = 'done', 'застосунок бачить, що прив''язано');

-- ── PIN ────────────────────────────────────────────────────────────────
select tests.ok(public.pin_state('00000000-0000-0000-0000-0000000000d1') ->> 'state' = 'none', 'PIN ще немає');
select tests.ok(public.pin_attempt('00000000-0000-0000-0000-0000000000d1') is null, 'без PIN спроби немає');
select public.pin_set('00000000-0000-0000-0000-0000000000d1', 'hash-pin', 'hash-rec');
select tests.ok(public.pin_state('00000000-0000-0000-0000-0000000000d1') ->> 'state' = 'on', 'PIN увімкнено');
-- 4 помилки - ще не блок; правильний - лічильник з нуля
select public.pin_attempt('00000000-0000-0000-0000-0000000000d1'), public.pin_result('00000000-0000-0000-0000-0000000000d1', false)
  from generate_series(1, 4);
select tests.ok(public.pin_attempt('00000000-0000-0000-0000-0000000000d1') ->> 'pin_hash' = 'hash-pin', 'п''ята спроба дозволена');
select tests.ok(public.pin_result('00000000-0000-0000-0000-0000000000d1', true) = 0, 'правильний PIN');
select tests.ok((select failed from public.account_pins where user_id = '00000000-0000-0000-0000-0000000000d1') = 0, 'лічильник з нуля');
-- 5 помилок поспіль - блок на 15 хв
select public.pin_attempt('00000000-0000-0000-0000-0000000000d1'), public.pin_result('00000000-0000-0000-0000-0000000000d1', false)
  from generate_series(1, 4);
select public.pin_attempt('00000000-0000-0000-0000-0000000000d1');
select tests.ok(public.pin_result('00000000-0000-0000-0000-0000000000d1', false) = 900, 'п''ята помилка - блок 15 хв');
select tests.ok(public.pin_attempt('00000000-0000-0000-0000-0000000000d1') is null, 'під час блоку перевірки немає');
select tests.ok(public.pin_state('00000000-0000-0000-0000-0000000000d1') ->> 'state' = 'locked', 'стан - заблоковано');
-- наступний блок - удвічі довший
reset role;
update public.account_pins set locked_until = now() - interval '1 second' where user_id = '00000000-0000-0000-0000-0000000000d1';
set role service_role;
select public.pin_attempt('00000000-0000-0000-0000-0000000000d1'), public.pin_result('00000000-0000-0000-0000-0000000000d1', false)
  from generate_series(1, 4);
select public.pin_attempt('00000000-0000-0000-0000-0000000000d1');
select tests.ok(public.pin_result('00000000-0000-0000-0000-0000000000d1', false) = 1800, 'другий блок - 30 хв');

-- вимкнення через добу, скасування, настання
select public.pin_set('00000000-0000-0000-0000-0000000000d1', 'hash-pin2', 'hash-rec2');
select public.pin_disable('00000000-0000-0000-0000-0000000000d1', now() + interval '1 day');
select tests.ok(public.pin_state('00000000-0000-0000-0000-0000000000d1') ->> 'state' = 'on', 'до настання PIN діє');
select tests.ok(public.pin_keep('00000000-0000-0000-0000-0000000000d1'), '«Це не я» - скасовано');
select tests.ok(not public.pin_keep('00000000-0000-0000-0000-0000000000d1'), 'вдруге нічого скасовувати');
select public.pin_disable('00000000-0000-0000-0000-0000000000d1', now() - interval '1 second');
select tests.ok(public.pin_state('00000000-0000-0000-0000-0000000000d1') ->> 'state' = 'off', 'час настав - PIN вимкнено');

-- вийти всюди
select tests.ok(public.sign_out_everywhere('00000000-0000-0000-0000-0000000000d1') = 2, 'дві сесії стерто');
reset role;
select tests.ok((select count(*) from auth.sessions) = 1, 'сесія Олени лишилась');

-- ── телефон не бачить і не змінює нічого з цього ──────────────────────
select tests.login('00000000-0000-0000-0000-0000000000d1', 'tg-501@tg.vulyk.invalid');
set role authenticated;
select tests.fails($q$select count(*) from public.tg_login_requests$q$);
select tests.fails($q$select count(*) from public.tg_identities$q$);
select tests.fails($q$select count(*) from public.account_pins$q$);
select tests.fails($q$select public.pin_set('00000000-0000-0000-0000-0000000000d1', 'x', 'y')$q$);
select tests.fails($q$select public.tg_login_poll('AAAAAAAAAAAAAAAAAAAAA1', repeat('a', 64))$q$);
select tests.fails($q$select public.sign_out_everywhere('00000000-0000-0000-0000-00000000000a')$q$);
reset role;
set role anon;
select tests.fails($q$select public.tg_login_create('EEEEEEEEEEEEEEEEEEEEE1', repeat('a', 64), 42::smallint, 'X', '', null)$q$);
reset role;

-- ── запрошення: Telegram-акаунт не бачить і не приймає чужих ───────────
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
insert into public.invitations (id, from_user_id, from_email, to_email) values
  ('inv-empty', '00000000-0000-0000-0000-00000000000a', 'olena@gmail.com', ''),
  ('inv-tg', '00000000-0000-0000-0000-00000000000a', 'olena@gmail.com', 'tg-501@tg.vulyk.invalid');
select tests.login('00000000-0000-0000-0000-0000000000d1', 'tg-501@tg.vulyk.invalid');
set role authenticated;
select tests.ok(public.my_email() = '', 'технічна пошта - не пошта');
select tests.ok(tests.n('public.invitations') = 0, 'запрошень на порожню чи технічну пошту не видно');
select tests.fails($q$select public.respond_invitation('inv-empty', true)$q$);
select tests.fails($q$select public.respond_invitation('inv-tg', true)$q$);
select tests.ok(public.find_user('tg-501@tg.vulyk.invalid') is null, 'за технічною поштою не знайти');
select tests.ok(public.find_user('') is null, 'за порожньою - теж');
-- Telegram-акаунт може запросити людину з поштою
insert into public.apiaries (id, name, updated_at) values ('ap-m', 'Марії', 1);
insert into public.invitations (id, to_email) values ('inv-m', 'petro@gmail.com');
select tests.ok(tests.n('public.invitations', $w$id = 'inv-m'$w$) = 1, 'запросила Петра');
select tests.fails($q$insert into public.invitations (id, to_email) values ('inv-m2', '')$q$);
select tests.fails($q$insert into public.invitations (id, to_email) values ('inv-m3', 'tg-9@tg.vulyk.invalid')$q$);
reset role;

rollback;
