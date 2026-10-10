-- Запрошення й помічники - лише через правила й функції сервера.
begin;
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
insert into public.apiaries (id, name, updated_at) values ('ap-1', 'Перша', 1), ('ap-2', 'Друга', 1);
insert into public.stock_items (id, name, unit, created_at) values ('s-1', 'Цукор', 'кг', 1);

-- знайти людину можна лише за точною поштою
select tests.ok(public.find_user(' PETRO@gmail.com') = '00000000-0000-0000-0000-00000000000b', 'знайшли за поштою');
select tests.ok(public.find_user('nobody@gmail.com') is null, 'немає такого - NULL');

-- не можна: від чужого імені (сервер підставить себе), до чужої пасіки, собі
insert into public.invitations (id, from_user_id, from_email, to_email) values
  ('inv-fake', '00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com', 'petro@gmail.com');
select tests.ok((select from_user_id from public.invitations where id = 'inv-fake') = auth.uid()
            and (select from_email from public.invitations where id = 'inv-fake') = 'olena@gmail.com',
  'відправник - завжди той, хто увійшов');
select tests.fails($q$insert into public.invitations (id, to_email, apiary_ids) values ('inv-x', 'petro@gmail.com', array['ap-ivan'])$q$);
select tests.fails($q$insert into public.invitations (id, to_email) values ('inv-self', 'Olena@gmail.com')$q$);
select tests.fails($q$insert into public.invitations (id, to_email, status) values ('inv-acc', 'ivan@gmail.com', 'accepted')$q$);
-- змінити запрошення напряму не можна (лише функціями)
select tests.fails($q$update public.invitations set status = 'accepted' where id = 'inv-fake'$q$);
select public.cancel_invitation('inv-fake');
select tests.ok((select status from public.invitations where id = 'inv-fake') = 'revoked', 'скасовано');
select tests.fails($q$select public.cancel_invitation('inv-fake')$q$);

-- запрошення до всіх пасік зі складом
insert into public.invitations (id, to_email, stock_access) values ('inv-all', 'petro@gmail.com', 1);

-- Іван не бачить і не може прийняти чуже
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select tests.ok(tests.n('public.invitations') = 0, 'чужих запрошень не видно');
select tests.fails($q$select public.respond_invitation('inv-all', true)$q$);

-- Петро бачить своє й приймає
select tests.login('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com');
select tests.ok(tests.n('public.invitations', $w$status = 'pending'$w$) = 1, 'запрошення в скриньці');
select tests.fails($q$insert into public.apiary_members (owner_id, user_id, email) values
  ('00000000-0000-0000-0000-00000000000a', auth.uid(), 'petro@gmail.com')$q$);
select public.respond_invitation('inv-all', true);
select tests.fails($q$select public.respond_invitation('inv-all', true)$q$, '22023');
select tests.ok(tests.n('public.apiary_members') = 1, 'помічник - один запис');
select tests.ok(tests.n('public.apiaries') = 2, 'усі пасіки власниці');
select tests.ok(tests.n('public.stock_items') = 1, 'склад - за дозволом');
-- помічник із дозволом змінює склад
update public.stock_items set quantity = 5, updated_at = 2 where id = 's-1';
select tests.ok((select quantity from public.stock_items where id = 's-1') = 5, 'склад змінено помічником');
-- сам собі дозвіл не змінить
select tests.fails($q$select public.set_member_stock_access((select id from public.apiary_members), false)$q$);

-- друге запрошення (до однієї пасіки, без складу) не створює другого запису
-- і не забирає склад
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
insert into public.invitations (id, to_email, apiary_ids) values ('inv-one', 'petro@gmail.com', array['ap-1']);
select tests.login('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com');
select public.respond_invitation('inv-one', true);
select tests.ok(tests.n('public.apiary_members', 'apiary_id is null') = 1, 'доступ до всіх лишився');
select tests.ok(tests.n('public.apiary_members', 'stock_access = 1') >= 1, 'склад не забрали');

-- власниця вимикає склад і забирає доступ
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
select public.set_member_stock_access(id, false) from public.apiary_members where apiary_id is null;
select tests.login('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com');
select tests.ok(tests.n('public.stock_items') = 0, 'склад вимкнено - не видно');
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
select public.remove_member(id) from public.apiary_members;
select tests.ok(tests.n('public.apiary_members', 'deleted = 1') = 2, 'видалення - позначкою (телефон помічника дізнається)');
select tests.login('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com');
select tests.ok(tests.n('public.apiaries') = 0, 'доступ забрано - пасік не видно');
select tests.ok(tests.n('public.apiary_members') = 2, 'помічник бачить, що доступ забрано');

-- нове запрошення після видалення: доступ повертається, склад - лише як у запрошенні
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
insert into public.invitations (id, to_email) values ('inv-again', 'petro@gmail.com');
select tests.login('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com');
select public.respond_invitation('inv-again', true);
select tests.ok(tests.n('public.apiaries') = 2, 'знову помічник');
select tests.ok(tests.n('public.stock_items') = 0, 'старий дозвіл на склад не повернувся');

-- помічник може сам відмовитись
select public.remove_member(id) from public.apiary_members where deleted = 0;
select tests.ok(tests.n('public.apiaries') = 0, 'відмовився - пасік не видно');

-- відхилене запрошення доступу не дає
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
insert into public.invitations (id, to_email, apiary_ids) values ('inv-no', 'ivan@gmail.com', array['ap-2']);
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select public.respond_invitation('inv-no', false);
select tests.ok(tests.n('public.apiaries') = 0, 'відхилив - доступу немає');

-- запрошення до пасіки, яку тим часом видалили, - її пропускаємо
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
insert into public.invitations (id, to_email, apiary_ids) values ('inv-del', 'ivan@gmail.com', array['ap-2']);
update public.apiaries set deleted = 1, updated_at = 5 where id = 'ap-2';
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select public.respond_invitation('inv-del', true);
select tests.ok(tests.n('public.apiary_members') = 0, 'до видаленої пасіки доступу не дали');
rollback;
