-- Хто що бачить і змінює: власниця Олена (a), помічник Петро (b) - лише
-- пасіка «Річка», без складу; Іван (c) - сторонній.
begin;

-- профілі з'явились і для тих, хто входив до міграції
select tests.ok((select email from public.profiles where id = '00000000-0000-0000-0000-00000000000a') = 'olena@gmail.com',
  'профіль: пошта в нижньому регістрі');

-- ── Олена записує дані так, як їх шле телефон (owner_id NULL - «мій») ──
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
insert into public.apiaries (id, owner_id, name, updated_at, schema_v) values
  ('ap-river', null, 'Річка', 1, 3),
  ('ap-forest', null, 'Ліс', 1, 3);
insert into public.elements (id, apiary_id, group_id, x, y, updated_at) values
  ('el-r1', 'ap-river', 'g-r1', 0, 0, 1),
  ('el-f1', 'ap-forest', 'g-f1', 0, 0, 1);
insert into public.parameters (id, name, updated_at, seed_key) values ('p-power', 'Сила', 1, 'base:power');
insert into public.templates (id, name, size, cells, updated_at) values ('t-1', 'Вулик', 1, '{}', 1);
insert into public.param_groups (id, name, ids, updated_at) values ('pg-1', 'Обходи', '[]', 1);
insert into public.element_parameters (id, apiary_id, group_id, parameter_id, updated_at) values
  ('ep-r1', 'ap-river', 'g-r1', 'p-power', 1),
  ('ep-f1', 'ap-forest', 'g-f1', 'p-power', 1);
insert into public.parameter_records (id, apiary_id, group_id, parameter_id, value, created_at) values
  ('pr-r1', 'ap-river', 'g-r1', 'p-power', '7', 1);
insert into public.hive_notes (id, apiary_id, group_id, text, note_date, created_at, updated_at) values
  ('n-f1', 'ap-forest', 'g-f1', 'рій', 1, 1, 1);
insert into public.stock_items (id, name, unit, created_at, updated_at) values ('s-sugar', 'Цукор', 'кг', 1, 1);
insert into public.fin_ops (id, kind, amount, op_date, created_at, updated_at) values ('f-1', 'expense', 100, 1, 1, 1);

select tests.ok((select owner_id from public.apiaries where id = 'ap-river') = auth.uid(),
  'власник за замовчуванням - той, хто пише');
select tests.ok((select owner_id from public.elements where id = 'el-r1') = auth.uid(),
  'власник вулика - з пасіки');
select tests.ok((select server_seq from public.apiaries where id = 'ap-forest')
              > (select server_seq from public.apiaries where id = 'ap-river'), 'номери змін зростають');

-- давній запис, чиєї пасіки на сервері немає, - приймається як свій
insert into public.hive_notes (id, apiary_id, text, note_date, created_at) values ('n-orphan', 'ap-none', 'давня', 1, 1);
insert into public.parameter_records (id, apiary_id, element_id, parameter_id, value, created_at) values
  ('pr-orphan', null, 'el-gone', 'p-power', '1', 1);
select tests.ok((select owner_id from public.hive_notes where id = 'n-orphan') = auth.uid(), 'запис без пасіки - свій');
-- одна група (вулик) - лише в одній пасіці
select tests.fails($q$insert into public.elements (id, apiary_id, group_id, x, y) values ('el-r2', 'ap-forest', 'g-r1', 1, 0)$q$);

-- ── Петро без запрошення бачить нічого ─────────────────────────────────
select tests.login('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com');
select tests.ok(tests.n('public.apiaries') = 0, 'без запрошення: пасік не видно');
select tests.ok(tests.n('public.parameters') = 0, 'без запрошення: довідників не видно');
select tests.ok(tests.n('public.profiles') = 1, 'профіль - лише свій');
-- і не може писати в чужі дані, навіть знаючи id
select tests.fails($q$insert into public.elements (id, apiary_id, x, y) values ('el-p', 'ap-river', 1, 1)$q$);
select tests.fails($q$insert into public.parameters (id, owner_id, name) values ('p-x', '00000000-0000-0000-0000-00000000000a', 'Х')$q$);
-- «перезаписати» чужий рядок через upsert
select tests.fails($q$insert into public.apiaries (id, name) values ('ap-river', 'Моя!')
  on conflict (id) do update set name = excluded.name$q$);

-- ── Олена запрошує Петра до «Річки», без складу ─────────────────────────
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
insert into public.invitations (id, to_email, apiary_ids, apiary_names) values
  ('inv-1', ' Petro@Gmail.com ', array['ap-river'], array['Річка']);
select tests.login('00000000-0000-0000-0000-00000000000b', 'petro@gmail.com');
select public.respond_invitation('inv-1', true);

-- бачить «Річку» і її вулики/записи, але не «Ліс»
select tests.ok(tests.n('public.apiaries') = 1, 'помічник бачить лише свою пасіку');
select tests.ok(tests.n('public.elements') = 1 and tests.n('public.elements', $w$id = 'el-r1'$w$) = 1,
  'вулики лише цієї пасіки');
select tests.ok(tests.n('public.element_parameters') = 1, 'прив''язки лише цієї пасіки');
select tests.ok(tests.n('public.parameter_records') = 1, 'історія лише цієї пасіки');
select tests.ok(tests.n('public.hive_notes') = 0, 'нотатки іншої пасіки не видно');
-- довідники власника - видно
select tests.ok(tests.n('public.parameters') = 1, 'характеристики власника видно');
select tests.ok(tests.n('public.templates') = 1, 'шаблони власника видно');
select tests.ok(tests.n('public.param_groups') = 1, 'групи «Конструктора» власника видно');
-- склад і фінанси - ні (немає дозволу)
select tests.ok(tests.n('public.stock_items') = 0, 'склад без дозволу не видно');
select tests.ok(tests.n('public.fin_ops') = 0, 'фінанси без дозволу не видно');
select tests.fails($q$insert into public.stock_items (id, owner_id, name, unit, created_at) values
  ('s-p', '00000000-0000-0000-0000-00000000000a', 'Х', 'кг', 1)$q$);

-- помічник робить огляд і нотатку у «Річці» - власник рядків - Олена
insert into public.parameter_records (id, apiary_id, group_id, parameter_id, value, created_at) values
  ('pr-p1', 'ap-river', 'g-r1', 'p-power', '8', 2);
insert into public.hive_notes (id, apiary_id, group_id, text, note_date, created_at, updated_at) values
  ('n-p1', 'ap-river', 'g-r1', 'матка є', 2, 2, 2);
select tests.ok((select owner_id from public.hive_notes where id = 'n-p1') = '00000000-0000-0000-0000-00000000000a',
  'запис помічника належить власниці пасіки');
-- нова характеристика - у довідник власниці
insert into public.parameters (id, owner_id, name, updated_at) values
  ('p-p', '00000000-0000-0000-0000-00000000000a', 'Від Петра', 2);
-- вулик можна переставити в межах пасіки
update public.elements set x = 3, updated_at = 2 where id = 'el-r1';
select tests.ok((select x from public.elements where id = 'el-r1') = 3, 'помічник змінює вулик');
-- у вулик «Лісу» не дописати, навіть вказавши свою пасіку: пасіку сервер
-- бере з вулика
select tests.fails($q$insert into public.parameter_records (id, apiary_id, element_id, parameter_id, value, created_at)
  values ('pr-inj', 'ap-river', 'el-f1', 'p-power', '1', 3)$q$);
select tests.fails($q$insert into public.qr_codes (id, apiary_id, group_id, code, updated_at)
  values ('q-inj', 'ap-river', 'g-f1', 'QR-1', 3)$q$);
-- записів без пасіки власниці не видно (вони лише її)
select tests.ok(tests.n('public.hive_notes', $w$id = 'n-orphan'$w$) = 0, 'записи без пасіки помічнику не видно');
-- але не в «Ліс» (чужа для нього пасіка) і не змінює саму пасіку чи шаблони
select tests.fails($q$insert into public.hive_notes (id, apiary_id, text, note_date, created_at) values
  ('n-p2', 'ap-forest', 'х', 2, 2)$q$);
update public.apiaries set name = 'Перейменовано' where id = 'ap-river';
update public.templates set name = 'Інший' where id = 't-1';
select tests.ok((select name from public.apiaries where id = 'ap-river') = 'Річка', 'пасіку змінює лише власник');
select tests.ok((select name from public.templates where id = 't-1') = 'Вулик', 'шаблони змінює лише власник');
-- видалити назовсім не можна нікому з клієнтів
select tests.fails($q$delete from public.hive_notes where id = 'n-p1'$q$);

-- ── Іван не бачить нічого з цього ───────────────────────────────────────
select tests.login('00000000-0000-0000-0000-00000000000c', 'ivan@gmail.com');
select tests.ok(tests.n('public.apiaries') + tests.n('public.elements') + tests.n('public.parameters')
              + tests.n('public.hive_notes') + tests.n('public.apiary_members') + tests.n('public.invitations') = 0,
  'сторонній не бачить нічого');

-- ── без входу (anon) - нічого ───────────────────────────────────────────
reset role;
select set_config('request.jwt.claims', '', false);
set role anon;
select tests.fails($q$select count(*) from public.apiaries$q$);
select tests.fails($q$insert into public.apiaries (id, name) values ('ap-anon', 'х')$q$);

rollback;
