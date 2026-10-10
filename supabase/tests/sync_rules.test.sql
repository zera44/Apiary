-- Правила запису, на які спирається синхронізація (етап 5).
begin;
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
insert into public.apiaries (id, name, updated_at) values ('ap-1', 'Перша', 10);
insert into public.elements (id, apiary_id, x, y, updated_at) values ('el-1', 'ap-1', 0, 0, 10);

-- id і власника не змінити (тихо лишаються як були)
update public.apiaries set owner_id = '00000000-0000-0000-0000-00000000000c' where id = 'ap-1';
select tests.ok((select owner_id from public.apiaries where id = 'ap-1') = auth.uid(), 'власник незмінний');

-- кожна зміна - новий номер і час сервера
select tests.ok((select server_seq is not null and server_at is not null from public.elements where id = 'el-1'),
  'номер і час сервера є');
create temp table s as select server_seq from public.elements where id = 'el-1';
update public.elements set x = 1, updated_at = 11 where id = 'el-1';
select tests.ok((select server_seq from public.elements where id = 'el-1') > (select server_seq from s),
  'зміна - новий номер (телефони заберуть «після N»)');

-- видалення, зроблене пізніше за зміну, перемагає: старіша зміна з іншого
-- телефона (updated_at раніше за видалення) не «воскрешає» вулик
update public.elements set deleted = 1, updated_at = 20 where id = 'el-1';
insert into public.elements (id, apiary_id, x, y, deleted, updated_at) values ('el-1', 'ap-1', 7, 7, 0, 15)
  on conflict (id) do update set x = excluded.x, y = excluded.y, deleted = excluded.deleted, updated_at = excluded.updated_at;
select tests.ok((select deleted from public.elements where id = 'el-1') = 1, 'давніша зміна не скасувала видалення');
-- ...і отримала новий номер зміни: телефон, що надіслав давню версію,
-- забере позначку «видалено»
create temp table s2 as select server_seq from public.elements where id = 'el-1';
insert into public.elements (id, apiary_id, x, y, deleted, updated_at) values ('el-1', 'ap-1', 7, 7, 0, 16)
  on conflict (id) do update set x = excluded.x, deleted = excluded.deleted, updated_at = excluded.updated_at;
select tests.ok((select server_seq from public.elements where id = 'el-1') > (select server_seq from s2)
            and (select deleted from public.elements where id = 'el-1') = 1
            and (select x from public.elements where id = 'el-1') = 1, 'позначку розіслано заново, дані не змінено');
-- а зміна, зроблена після видалення (свідоме відновлення), - так
update public.elements set deleted = 0, x = 9, updated_at = 30 where id = 'el-1';
select tests.ok((select deleted from public.elements where id = 'el-1') = 0
             and (select x from public.elements where id = 'el-1') = 9, 'пізніша зміна відновила');

-- до пасіки іншого власника запис не перенести
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
insert into public.apiaries (id, name, updated_at) values ('ap-ivan', 'Іванова', 1);
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
select tests.fails($q$update public.elements set apiary_id = 'ap-ivan' where id = 'el-1'$q$);

-- рухи складу лише дописуються: змінити кількість не можна, скасувати - можна
insert into public.stock_items (id, name, unit, created_at) values ('s-1', 'Цукор', 'кг', 1);
insert into public.stock_moves (id, item_id, kind, amount, quantity_after, created_at, updated_at)
  values ('m-1', 's-1', 'receive', 10, 10, 1, 1);
select tests.fails($q$update public.stock_moves set amount = 99 where id = 'm-1'$q$);
select tests.fails($q$update public.stock_moves set item_id = 's-2' where id = 'm-1'$q$);
-- дату операції фінансів змінюють - і дату руху теж
update public.stock_moves set op_date = 200, updated_at = 2 where id = 'm-1';
select tests.ok((select op_date from public.stock_moves where id = 'm-1') = 200, 'дату руху змінено');
update public.stock_moves set cancelled = 1, updated_at = 2 where id = 'm-1';
select tests.ok((select cancelled from public.stock_moves where id = 'm-1') = 1, 'рух скасовано');
-- повторна відправка того самого руху (телефон не отримав відповіді) - без помилки
insert into public.stock_moves (id, item_id, kind, amount, quantity_after, created_at, cancelled, updated_at)
  values ('m-1', 's-1', 'receive', 10, 10, 1, 1, 2)
  on conflict (id) do update set amount = excluded.amount, cancelled = excluded.cancelled, updated_at = excluded.updated_at;
select tests.ok((select amount from public.stock_moves where id = 'm-1') = 10, 'повторна відправка');

-- історія значень: лише дописується, прибрати - позначкою
insert into public.parameter_records (id, apiary_id, parameter_id, value, created_at) values ('r-1', 'ap-1', 'p', '5', 1);
select tests.fails($q$update public.parameter_records set value = '6' where id = 'r-1'$q$);
-- злиття однакових характеристик з двох телефонів переводить історію на одну
update public.parameter_records set parameter_id = 'p-kept' where id = 'r-1';
select tests.ok((select parameter_id from public.parameter_records where id = 'r-1') = 'p-kept', 'історію переведено');
update public.parameter_records set deleted = 1, updated_at = 3 where id = 'r-1';
select tests.ok((select deleted from public.parameter_records where id = 'r-1') = 1, 'запис позначено видаленим');

-- рядок від новішої версії застосунку - з її номером схеми
insert into public.note_labels (id, name, schema_v, updated_at) values ('l-1', 'Огляд', 4, 1);
select tests.ok((select schema_v from public.note_labels where id = 'l-1') = 4, 'версія схеми збережена');
rollback;
