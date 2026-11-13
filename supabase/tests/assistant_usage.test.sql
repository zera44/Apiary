-- Денний ліміт помічника: функція assistant_hit рахує запити людини,
-- понад ліміт відмовляє; таблиця й функція закриті для anon і authenticated.
begin;

set role service_role;

-- до ліміту - так, далі - ні, лічильник понад ліміт не росте
select tests.ok(public.assistant_hit('00000000-0000-0000-0000-00000000000a', 3), 'запит 1');
select tests.ok(public.assistant_hit('00000000-0000-0000-0000-00000000000a', 3), 'запит 2');
select tests.ok(public.assistant_hit('00000000-0000-0000-0000-00000000000a', 3), 'запит 3');
select tests.ok(not public.assistant_hit('00000000-0000-0000-0000-00000000000a', 3), 'запит 4 - ліміт вичерпано');
select tests.ok(not public.assistant_hit('00000000-0000-0000-0000-00000000000a', 3), 'запит 5 - і далі відмова');
select tests.ok((select count from public.assistant_usage
                 where user_id = '00000000-0000-0000-0000-00000000000a') = 3, 'лічильник не росте понад ліміт');

-- ліміт у кожної людини свій
select tests.ok(public.assistant_hit('00000000-0000-0000-0000-00000000000b', 3), 'інша людина: свій лічильник');

-- змінили ліміт на більший - можна далі
select tests.ok(public.assistant_hit('00000000-0000-0000-0000-00000000000a', 10), 'підняли ліміт - знову можна');

-- негодні вхідні дані: відмова, а не помилка чи безкінечний ліміт
select tests.ok(not public.assistant_hit('00000000-0000-0000-0000-00000000000a', 0), 'ліміт 0');
select tests.ok(not public.assistant_hit('00000000-0000-0000-0000-00000000000a', -5), 'ліміт від''ємний');
select tests.ok(not public.assistant_hit('00000000-0000-0000-0000-00000000000a', null), 'ліміт null');
select tests.ok(not public.assistant_hit(null, 3), 'людина null');

-- вчорашній лічильник не заважає сьогодні; доби старші за 7 днів прибираються
reset role;
insert into public.assistant_usage (user_id, day, count) values
  ('00000000-0000-0000-0000-00000000000c', (now() at time zone 'utc')::date - 1, 999),
  ('00000000-0000-0000-0000-00000000000c', (now() at time zone 'utc')::date - 30, 5);
set role service_role;
select tests.ok(public.assistant_hit('00000000-0000-0000-0000-00000000000c', 3), 'вчорашні запити не рахуються');
select tests.ok((select count(*) from public.assistant_usage
                 where user_id = '00000000-0000-0000-0000-00000000000c') = 2, 'місячної давнини прибрано, вчорашнє й сьогоднішнє - є');
reset role;

-- телефон (authenticated) і anon не бачать лічильника й не можуть його змінити
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
select tests.fails($q$select count(*) from public.assistant_usage$q$);
select tests.fails($q$insert into public.assistant_usage (user_id, day, count) values (auth.uid(), current_date, 0)$q$);
select tests.fails($q$update public.assistant_usage set count = 0$q$);
select tests.fails($q$delete from public.assistant_usage$q$);
select tests.fails($q$select public.assistant_hit(auth.uid(), 1000000)$q$);
reset role;

select set_config('request.jwt.claims', '', false);
set role anon;
select tests.fails($q$select count(*) from public.assistant_usage$q$);
select tests.fails($q$select public.assistant_hit('00000000-0000-0000-0000-00000000000a', 1000000)$q$);
reset role;

-- акаунт видалено - лічильник іде разом із ним
delete from auth.users where id = '00000000-0000-0000-0000-00000000000b';
select tests.ok((select count(*) from public.assistant_usage
                 where user_id = '00000000-0000-0000-0000-00000000000b') = 0, 'видалили акаунт - лічильника немає');

rollback;
