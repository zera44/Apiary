-- Книги для помічника: пошук за початком слів, лише увімкнені книги,
-- таблиці й пошук закриті для anon і authenticated.
begin;

insert into public.kb_books (id, title, author, year, enabled) values
  ('11111111-1111-4111-8111-111111111111', 'Посібник пасічника', 'Іваненко', 2019, true),
  ('22222222-2222-4222-8222-222222222222', 'Вимкнена книга', '', null, false);

insert into public.kb_chunks (book_id, ord, page, chapter, text) values
  ('11111111-1111-4111-8111-111111111111', 1, 12, 'Підгодівля',
   'Восени бджолам дають цукровий сироп у співвідношенні два до одного, щоб вони встигли запасти корм.'),
  ('11111111-1111-4111-8111-111111111111', 2, 40, 'Вощина',
   'Вощину встановлюють у рамки навесні, коли бджоли активно будують стільники.'),
  ('11111111-1111-4111-8111-111111111111', 3, null, '',
   'Рій з''являється, коли сім''я переповнена бджолами, а матка не має місця для відкладання яєць.'),
  ('22222222-2222-4222-8222-222222222222', 1, 1, '',
   'Вощина і сироп із вимкненої книги не повинні потрапляти у відповіді помічника.');

set role service_role;

-- слова відмінюються: «вощини» знаходить «вощина», «сиропом» - «сироп»
select tests.ok((select count(*) from public.kb_search('вощини')) = 1, 'вощини -> один уривок (без вимкненої книги)');
select tests.ok((select page from public.kb_search('Вощину в рамки')) = 40, 'сторінка й порядок: уривок про вощину');
select tests.ok((select title from public.kb_search('сиропом')) = 'Посібник пасічника', 'сироп -> книга');
select tests.ok((select chapter from public.kb_search('підгодівля восени')) = 'Підгодівля', 'розділ повертається');
select tests.ok((select count(*) from public.kb_search('рій матка яйця')) = 1, 'уривок без сторінки теж знаходиться');
select tests.ok((select page from public.kb_search('рій')) is null, 'сторінка null, якщо невідома');
-- порожнє, короткі слова, лапки й розділові знаки - без помилок і без результатів
select tests.ok((select count(*) from public.kb_search('')) = 0, 'порожній запит');
select tests.ok((select count(*) from public.kb_search('а в ' || chr(39) || ' ;:!')) = 0, 'самі короткі слова й знаки');
select tests.ok((select count(*) from public.kb_search(null)) = 0, 'null');
select tests.ok((select count(*) from public.kb_search('зовсім інше слово')) = 0, 'нічого не знайдено');
-- обмеження кількості
select tests.ok((select count(*) from public.kb_search('бджоли', 1)) = 1, 'ліміт 1');
reset role;

-- вимкнена книга з'являється після вмикання
update public.kb_books set enabled = true where id = '22222222-2222-4222-8222-222222222222';
select tests.ok((select count(*) from public.kb_search('вощини')) = 2, 'увімкнули - знаходиться');

-- закрито для людей і застосунку
set role anon;
select tests.fails($q$select * from public.kb_books$q$);
select tests.fails($q$select * from public.kb_chunks$q$);
select tests.fails($q$select * from public.kb_search('вощина')$q$);
reset role;
select tests.login('00000000-0000-0000-0000-00000000000a', 'olena@gmail.com');
set role authenticated;
select tests.fails($q$select * from public.kb_chunks$q$);
select tests.fails($q$insert into public.kb_books (title) values ('x')$q$);
select tests.fails($q$select * from public.kb_search('вощина')$q$);
reset role;

-- видалення книги прибирає її уривки
delete from public.kb_books where id = '11111111-1111-4111-8111-111111111111';
select tests.ok((select count(*) from public.kb_chunks where book_id = '11111111-1111-4111-8111-111111111111') = 0,
  'уривки видалено разом із книгою');

rollback;
