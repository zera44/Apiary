-- Фото складу й нічні копії: хто може читати й класти файли.
begin;
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
-- свої фото - так; у чужу теку чи поза теками - ні
insert into storage.objects (bucket_id, name) values
  ('stock-photos', '00000000-0000-0000-0000-00000000000a/ph1.webp');
select tests.fails($q$insert into storage.objects (bucket_id, name) values
  ('stock-photos', '00000000-0000-0000-0000-00000000000c/ph.webp')$q$);
select tests.fails($q$insert into storage.objects (bucket_id, name) values ('stock-photos', 'ph.webp')$q$);
select tests.fails($q$insert into storage.objects (bucket_id, name) values ('stock-photos', '../x/ph.webp')$q$);

-- запросила Петра без складу, Івана - зі складом
insert into public.apiaries (id, name) values ('ap-1', 'Перша');
insert into public.invitations (id, to_email) values ('i-p', 'petro@gmail.com');
insert into public.invitations (id, to_email, stock_access) values ('i-i', 'ivan@gmail.com', 1);
select tests.login('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com');
select public.respond_invitation('i-p', true);
select tests.ok(tests.n('storage.objects') = 0, 'без складу фото не видно');
select tests.fails($q$insert into storage.objects (bucket_id, name) values
  ('stock-photos', '00000000-0000-0000-0000-00000000000a/ph2.webp')$q$);
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select public.respond_invitation('i-i', true);
select tests.ok(tests.n('storage.objects') = 1, 'зі складом фото видно');
insert into storage.objects (bucket_id, name) values
  ('stock-photos', '00000000-0000-0000-0000-00000000000a/ph3.webp');

-- копії: лише свої; телефон лише заявляє копію, «перевірено» ставить сервер
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
insert into public.device_backups (id, path, size, sha256, schema_v) values
  ('bk-00000001', '00000000-0000-0000-0000-00000000000a/bk-00000001.db.gz', 10, repeat('a', 64), 3);
insert into storage.objects (bucket_id, name) values
  ('backups', '00000000-0000-0000-0000-00000000000a/bk-00000001.db.gz');
select tests.fails($q$insert into public.device_backups (id, path, size, sha256, schema_v, status) values
  ('bk-00000002', '00000000-0000-0000-0000-00000000000a/bk-00000002.db.gz', 10, repeat('a', 64), 3, 'ok')$q$);
select tests.fails($q$insert into public.device_backups (id, path, size, sha256, schema_v) values
  ('bk-00000003', '00000000-0000-0000-0000-00000000000c/bk-00000003.db.gz', 10, repeat('a', 64), 3)$q$);
select tests.fails($q$update public.device_backups set status = 'ok'$q$);
-- перезаписати чи видалити копію з телефона не можна
with d as (delete from storage.objects where bucket_id = 'backups' returning 1)
select tests.ok((select count(*) from d) = 0, 'копію з телефона не видалити');
with d as (update storage.objects set name = name where bucket_id = 'backups' returning 1)
select tests.ok((select count(*) from d) = 0, 'копію з телефона не перезаписати');
select tests.ok(tests.n('storage.objects', $w$bucket_id = 'backups'$w$) = 1, 'свою копію видно');
-- чужі копії не видно навіть помічнику зі складом
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select tests.ok(tests.n('storage.objects', $w$bucket_id = 'backups'$w$) = 0, 'чужих копій не видно');
select tests.ok(tests.n('public.device_backups') = 0, 'чужого обліку копій не видно');
select tests.fails($q$insert into storage.objects (bucket_id, name) values
  ('backups', '00000000-0000-0000-0000-00000000000a/x.db.gz')$q$);
rollback;
