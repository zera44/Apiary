-- Забирання змін (sync_pull): сторінками, за курсором, за правилами доступу.
begin;
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
insert into public.apiaries (id, name, updated_at)
  select 'ap-' || g, 'Пасіка ' || g, 1 from generate_series(1, 5) g;
reset role;
-- рядки вище записано в цій же (ще не завершеній) транзакції: їх не видно,
-- поки вона триває - як і має бути для чужих довгих транзакцій
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
select tests.ok(jsonb_array_length(public.sync_pull('apiaries') -> 'rows') = 0,
  'незавершена транзакція - нічого не віддаємо');
commit;

-- після завершення - сторінками по 2, курсор рухається, повтору немає
begin;
set role authenticated;
create temp table pages (n int, body jsonb) on commit drop;
insert into pages values (1, public.sync_pull('apiaries', null, 2));
insert into pages select 2, public.sync_pull('apiaries', (select body ->> 'next' from pages where n = 1), 2);
insert into pages select 3, public.sync_pull('apiaries', (select body ->> 'next' from pages where n = 2), 2);
insert into pages select 4, public.sync_pull('apiaries', (select body ->> 'next' from pages where n = 3), 2);
select tests.ok((select (body -> 'more')::boolean from pages where n = 1), 'є ще');
select tests.ok((select count(distinct r ->> 'id') from pages, jsonb_array_elements(body -> 'rows') r) = 5,
  'усі 5 пасік рівно по разу');
select tests.ok(jsonb_array_length((select body -> 'rows' from pages where n = 4)) = 0
            and (select body ->> 'next' from pages where n = 4) = (select body ->> 'next' from pages where n = 3),
  'нічого нового - курсор той самий');
-- зміна після курсора - приходить знову
update public.apiaries set name = 'Нова назва', updated_at = 2 where id = 'ap-3';
commit;

begin;
set role authenticated;
select tests.ok((select array_agg(r ->> 'name') from jsonb_array_elements(
    public.sync_pull('apiaries', null, 100) -> 'rows') r) @> array['Нова назва'], 'зміну видно');
-- Іван чужого не отримує
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select tests.ok(jsonb_array_length(public.sync_pull('apiaries') -> 'rows') = 0, 'чужого не видно');
-- лише таблиці синхронізації й правильний курсор
select tests.fails($q$select public.sync_pull('profiles')$q$, '22023');
select tests.fails($q$select public.sync_pull('apiaries; drop table x')$q$, '22023');
select tests.fails($q$select public.sync_pull('apiaries', '1; select')$q$, '22023');
reset role;
select set_config('request.jwt.claims', '', false);
set role anon;
select tests.fails($q$select public.sync_pull('apiaries')$q$);
rollback;

-- прибрати за собою (цей файл, на відміну від інших, завершував транзакції)
reset role;
delete from public.apiaries where id like 'ap-%' and owner_id = '00000000-0000-0000-0000-00000000000a';
