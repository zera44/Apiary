# Помічник «Пасічник» — посередник

Застосунок → ця функція → Anthropic API (модель `claude-haiku-5-5`).
Ключ Anthropic лежить **лише** в секретах Supabase; у застосунку його немає.

| Файл | Що в ньому |
|---|---|
| `index.ts` | прийом запиту, перевірки, виклик моделі, журнал (лише числа) |
| `access.ts` | хто може звертатися (зараз — тестовий код; потім — вхід і ліміти) |
| `config.ts` | модель, ліміт 6 кроків, розміри |
| `prompt.ts` | характер, межі порад, опис застосунку й екранів (системний промпт) |
| `tools.ts` | опис інструментів для моделі (виконує їх телефон) |

Перевірка без Supabase: `node --test supabase/tests/assistant.test.ts`
(у GitHub — процес «Supabase»).

## Як підключити (один раз)

Робимо в **тестовому** проєкті `vulyk-test` (тестові збірки гілок ходять туди).

### 1. Ключ Anthropic

1. https://platform.claude.com → зареєструватися, поповнити баланс.
2. **Settings → Limits**: поставити ліміт витрат (на тест — $5 на місяць).
3. **API Keys → Create Key** → скопіювати ключ (`sk-ant-…`, показується один раз).

### 2. Тестовий код доступу

Будь-який довгий випадковий рядок (не менше 16 символів), наприклад у
PowerShell:

```powershell
-join ((48..57)+(97..102) | Get-Random -Count 40 | % {[char]$_})
```

Його треба покласти у **два** місця (кроки 3 і 5) — однаковий.

### 3. Секрети Supabase

https://supabase.com/dashboard → проєкт `vulyk-test` → **Edge Functions →
Secrets** → **Add new secret**:

| Name | Value |
|---|---|
| `ANTHROPIC_API_KEY` | ключ із кроку 1 |
| `APIARY_ASSISTANT_TEST_TOKEN` | код із кроку 2 |
| `ASSISTANT_MODEL` | не обов'язково; без нього — `claude-haiku-5-5` |

### 4. Розгорнути функцію

**Через сайт:** Edge Functions → **Deploy a new function → Via Editor** →
назва `assistant` → додати п'ять файлів із цієї папки (`index.ts`,
`access.ts`, `config.ts`, `prompt.ts`, `tools.ts`) з тим самим вмістом →
**Deploy**. Потім у налаштуваннях функції (**Details**) вимкнути
**Enforce JWT Verification** — доступ перевіряє сама функція (тестовий код).

**Або командою** (якщо встановлено Supabase CLI):

```bash
supabase functions deploy assistant --no-verify-jwt --project-ref <ref проєкту>
```

Адреса функції: `https://<ref проєкту>.supabase.co/functions/v1/assistant`.

Після кожної зміни файлів цієї папки функцію треба розгорнути знову.

### 5. Секрети GitHub (для тестових APK)

https://github.com/zera44/Apiary → **Settings → Secrets and variables →
Actions → New repository secret**:

| Name | Value |
|---|---|
| `APIARY_ASSISTANT_URL` | адреса функції з кроку 4 |
| `APIARY_ASSISTANT_TEST_TOKEN` | код із кроку 2 |

Тестова збірка гілки (Actions → Run workflow) вкладе їх у APK. Реліз із
`main` їх **не** бере: там помічник у demo-режимі, доки не буде входу й
лімітів (docs/REMINDERS.md).

Без адреси застосунок працює з demo-моделлю (заготовлені відповіді, без
сервера).

### Перевірка

```bash
curl -s https://<ref>.supabase.co/functions/v1/assistant -H "x-apiary-assistant-token: <код>" -H "content-type: application/json" -d "{\"messages\":[{\"role\":\"user\",\"content\":\"Привіт\"}]}"
```

Має повернути `{"content":[…],"stop_reason":"end_turn",…}`. Без коду чи з
неправильним — `{"error":"unauthorized"}`.

## Журнал

Supabase → Edge Functions → `assistant` → **Logs**: рядки на кшталт
`{"fn":"assistant","result":"ok","steps":1,"input_tokens":…,"output_tokens":…,"cache_read_input_tokens":…}`.
Тексту розмов там немає.

## Відповіді функції

| Код | Тіло | Що робить застосунок |
|---|---|---|
| 200 | `content`, `stop_reason`, `steps_left` | показує відповідь або виконує інструменти |
| 401 | `unauthorized` | «помічник недоступний» |
| 400 / 413 | причина | помилка застосунку (не повторювати) |
| 422 | `step_limit` | «спитайте простіше» |
| 503 | `busy`, `retry: true` | черга, повтор пізніше |
| 500 | `not_configured` | на сервері немає ключа |
