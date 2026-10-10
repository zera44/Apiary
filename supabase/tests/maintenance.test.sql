-- Пінг (keep-alive) і прибирання давніх позначок «видалено».
begin;
-- пінг можна без входу, він пише в базу
set role anon;
select set_config('request.jwt.claims', '', false);
select tests.ok(public.ping() is not null, 'пінг відповідає');
select tests.fails($q$select * from public.keepalive$q$);
select tests.fails($q$select public.purge_tombstones()$q$);
reset role;
select tests.ok((select count from public.keepalive) = 1, 'пінг записав у базу');

-- прибирання: стирає лише давні позначки
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
insert into public.apiaries (id, name, deleted, updated_at) values
  ('ap-old', 'Давня', 1, 1), ('ap-new', 'Свіжа', 1, 1), ('ap-live', 'Жива', 0, 1);
reset role;
alter table public.apiaries disable trigger t90_stamp;
update public.apiaries set server_at = now() - interval '200 days' where id in ('ap-old', 'ap-live');
alter table public.apiaries enable trigger t90_stamp;
-- давно видалена пасіка, де ще живе нотатка (на телефоні вона є), - лишається
set role authenticated;
insert into public.apiaries (id, name, deleted, updated_at) values ('ap-old-notes', 'З нотаткою', 0, 1);
insert into public.hive_notes (id, apiary_id, text, note_date, created_at) values ('n-1', 'ap-old-notes', 'жива', 1, 1);
update public.apiaries set deleted = 1, updated_at = 2 where id = 'ap-old-notes';
reset role;
alter table public.apiaries disable trigger t90_stamp;
update public.apiaries set server_at = now() - interval '200 days' where id = 'ap-old-notes';
alter table public.apiaries enable trigger t90_stamp;
select tests.ok(public.purge_tombstones() = 1, 'стерто одну давню позначку');
select tests.ok((select array_agg(id order by id) from public.apiaries) = array['ap-live', 'ap-new', 'ap-old-notes'],
  'свіжа позначка, живий запис і пасіка з живою нотаткою лишились');

-- видалення акаунта (етап 7) стирає все користувача
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select tests.ok((select count(*) from public.apiaries) = 0 and (select count(*) from public.profiles
  where id = '00000000-0000-0000-0000-00000000000a') = 0, 'дані користувача стерто разом з акаунтом');
rollback;
