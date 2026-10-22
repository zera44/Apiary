# books - книги для помічника

Керування книгами з адмін-сторінки (`admin/feedback.html`, вкладка «Книги»).
Пошук для помічника - не тут, а в функції `assistant` (дія `search_books`).
Повний опис - `docs/KNOWLEDGE_BASE.md`.

## Розгортання

1. SQL Editor → виконати `supabase/migrations/20261022000100_kb_books.sql`.
2. Edge Functions → Deploy a new function → Via Editor, назва **books**,
   файл `index.ts` з цієї папки. Details → вимкнути «Verify JWT» (доступ
   перевіряє сама функція).
3. Секрети: нових немає - той самий `FEEDBACK_ADMIN_PASSWORD`, що й для відгуків
   (не менше 8 символів). `SUPABASE_URL` і `SUPABASE_SERVICE_ROLE_KEY`
   Supabase дає сам.

## Дії

POST JSON із заголовком `x-feedback-admin: <пароль адмінки>`:

| action | поля | що робить |
|---|---|---|
| `list` | - | усі книги |
| `add_book` | `title`, `author?`, `year?`, `source?` | нова книга, повертає `id` |
| `add_chunks` | `book_id`, `start`, `chunks: [{page?, chapter?, text}]` | до 100 уривків (20-4000 знаків) |
| `finish` | `book_id`, `pages`, `chunks` | підсумок книги |
| `set_enabled` | `book_id`, `enabled` | вмикає / вимикає |
| `delete` | `book_id` | видаляє книгу й уривки |
| `search` | `query` | перевірка пошуку (як у помічника) |

Журнал - лише лічильники: ні назв, ні текстів книг, ні паролів.
