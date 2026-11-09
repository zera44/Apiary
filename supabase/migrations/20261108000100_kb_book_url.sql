-- Посилання на оригінал книги (наприклад, на Google Диску): у списку книг
-- в адмінці назва відкриває його. Сам файл у базі не зберігається, лише
-- короткий рядок, тож місця майже не займає.
alter table public.kb_books add column if not exists url text not null default '';
