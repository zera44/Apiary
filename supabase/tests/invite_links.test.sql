-- Запрошувальне посилання: створює власник, одноразове, діє 7 днів.
begin;
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
insert into public.apiaries (id, name, updated_at) values ('ap-1', 'Перша', 1), ('ap-2', 'Друга', 1);
insert into public.stock_items (id, name, unit, created_at) values ('s-1', 'Цукор', 'кг', 1);

-- не можна: до чужої пасіки, до порожнього списку, напряму в таблицю
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
insert into public.apiaries (id, name, updated_at) values ('ap-ivan', 'Іванова', 1);
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
select tests.fails($q$select public.create_invite_link(array['ap-ivan'], false)$q$);
select tests.fails($q$select public.create_invite_link(array[]::text[], false)$q$);
select tests.fails($q$insert into public.invite_links (token, owner_id) values ('x', auth.uid())$q$);

-- посилання до однієї пасіки, без складу: назву бере сервер
create temp table t (one text, all_ text);
grant all on t to authenticated;
insert into t (one) select public.create_invite_link(array['ap-1'], false);
update t set all_ = public.create_invite_link(null, true);
select tests.ok(length((select one from t)) = 64, 'довгий випадковий код');
select tests.ok((select apiary_names from public.invite_links where token = (select one from t)) = array['Перша'],
  'назви пасік - з бази');
select tests.ok(tests.n('public.invite_links') = 2, 'власниця бачить свої посилання');
-- своїм посиланням не скористатись
select tests.fails($q$select public.accept_invite_link((select one from t))$q$, '22023');

-- чужі посилання не видно; невідомий код - помилка
select tests.login('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com');
select tests.ok(tests.n('public.invite_links') = 0, 'чужих посилань не видно');
select tests.fails($q$select public.accept_invite_link('nope')$q$, 'P0002');

-- Петро відкриває посилання - одразу помічник до першої пасіки, без складу
select tests.ok((public.accept_invite_link((select one from t)) ->> 'owner_email') = 'olena@gmail.com',
  'видно, чиї пасіки');
select tests.ok(tests.n('public.apiaries') = 1, 'бачить лише першу пасіку');
select tests.ok(tests.n('public.stock_items') = 0, 'склад - лише за дозволом');
-- удруге тією самою людиною - без помилки
select public.accept_invite_link((select one from t));
select tests.ok(tests.n('public.apiary_members') = 1, 'один запис помічника');

-- одноразове: Іван тим самим посиланням не скористається
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select tests.fails($q$select public.accept_invite_link((select one from t))$q$, '22023');

-- власниця забирає доступ - тим самим посиланням його не повернути
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
select public.remove_member(id) from public.apiary_members where deleted = 0;
select tests.login('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com');
select public.accept_invite_link((select one from t));
select tests.ok(tests.n('public.apiaries') = 0, 'забраний доступ посилання не повертає');

-- скасоване й прострочене посилання не діє
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
select public.cancel_invite_link((select all_ from t));
select tests.fails($q$select public.cancel_invite_link((select all_ from t))$q$);
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select tests.fails($q$select public.accept_invite_link((select all_ from t))$q$, '22023');
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
update t set all_ = public.create_invite_link(null, true);
reset role;
update public.invite_links set expires_at = now() - interval '1 second' where token = (select all_ from t);
set role authenticated;
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select tests.fails($q$select public.accept_invite_link((select all_ from t))$q$, '22023');

-- діюче посилання до всіх пасік зі складом
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
update t set all_ = public.create_invite_link(null, true);
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select public.accept_invite_link((select all_ from t));
select tests.ok(tests.n('public.apiaries', $w$owner_id = '00000000-0000-0000-0000-00000000000a'$w$) = 2,
  'до всіх пасік власниці');
select tests.ok(tests.n('public.stock_items') = 1, 'склад - за дозволом у посиланні');

-- без входу - нічого
reset role;
set role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', false);
select tests.fails($q$select public.create_invite_link(null, false)$q$);
select tests.fails($q$select public.accept_invite_link('x')$q$);
reset role;

-- не більше 20 діючих посилань
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
select public.create_invite_link(null, false) from generate_series(1, 20);
select tests.fails($q$select public.create_invite_link(null, false)$q$, '54000');
rollback;
