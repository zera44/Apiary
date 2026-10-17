# Відгуки з відповідями — сервер

Людина пише відгук у застосунку → він зберігається в Supabase й вам
приходить лист-сповіщення → ви відповідаєте в **адмін-сторінці** → відповідь
з'являється в застосунку як нове повідомлення. Усе безкоштовно.

| Файл | Що в ньому |
|---|---|
| `index.ts` | функція: дії застосунку (`send`, `poll`) й адмінки (`admin_*`) |
| `store.ts` | сховище: у пам'яті (тести) і PostgREST (справжнє) |
| `../../migrations/20261017000100_feedback.sql` | таблиці `feedback_threads`, `feedback_messages` |
| `../../../admin/feedback.html` | адмін-сторінка |

Перевірка без Supabase: `node --test supabase/tests/feedback.test.ts`
(у GitHub — процес «Supabase»).

## Налаштувати (один раз), проєкт `vulyk-test`

### 1. Таблиці
Supabase → **SQL Editor** → New query → вставити вміст
`supabase/migrations/20261017000100_feedback.sql` → **Run**.

### 2. Пошта: лист вам про новий відгук (Resend, безкоштовно)
1. https://resend.com → зареєструватися **з адресою myapiaryrezvin@gmail.com**
   (без домену Resend шле лише на адресу власника акаунта — нам саме це
   й треба).
2. **API Keys → Create API Key** (дозвіл «Sending access») → скопіювати
   (`re_…`).

### 3. Секрети функції
Supabase → Edge Functions → **Secrets**:

| Name | Value |
|---|---|
| `FEEDBACK_ADMIN_PASSWORD` | пароль адмінки, **не менше 8 символів**, довгий і унікальний |
| `RESEND_API_KEY` | ключ `re_…` із кроку 2 |
| `FEEDBACK_NOTIFY_TO` | `myapiaryrezvin@gmail.com` |
| `FEEDBACK_ADMIN_URL` | не обов'язково: адреса адмін-сторінки — потрапить у лист |

(`SUPABASE_URL` і `SUPABASE_SERVICE_ROLE_KEY` Supabase дає функціям сам.)

### 4. Розгорнути функцію
Edge Functions → **Deploy a new function → Via Editor** → назва `feedback`
→ два файли: `index.ts` і `store.ts` (вміст із цієї папки) → **Deploy** →
у **Details** вимкнути **Enforce JWT Verification** (доступ перевіряє сама
функція). Адреса: `https://<ref>.supabase.co/functions/v1/feedback`.

### 5. Адмін-сторінка
Файл `admin/feedback.html` — окрема сторінка, пароля в ній немає. Відкрити
можна:
* просто двічі клацнути по завантаженому файлу (працює з комп'ютера й з
  телефона), або
* через GitHub Pages: Settings → Pages → Source: *Deploy from a branch*,
  `main`, папка `/ (root)` → сторінка буде за
  `https://zera44.github.io/Apiary/admin/feedback.html`.

Вхід — пароль із кроку 3 (запам'ятовується в браузері; «Вийти» його
забуває).

## Безпека
* Застосунок не має входу: при першому відгуку створює випадкові
  `device_id` і `secret`; сервер зберігає лише **хеш** `secret`. Чужу розмову
  без `secret` прочитати не можна.
* Таблиці закриті для всіх ролей Supabase; користується ними лише ця
  функція зі службовим ключем.
* Адмін-дії — лише з правильним паролем (порівняння без витоку часу;
  пароль коротший за 8 символів сервер не приймає взагалі).
* Ліміт: 20 відгуків на добу з одного встановлення, до 5000 символів.
* У журналі функції — лише коди й довжини, без текстів.
