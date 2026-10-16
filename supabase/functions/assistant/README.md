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
| `ASSISTANT_MODEL` | не обов'язково: `haiku` (типово) або `sonnet` |
| `ASSISTANT_EFFORT` | не обов'язково: `low`, `medium` (типово), `high`, `xhigh`, `max` |

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
`main` — теж, але **тимчасово** (`ASSISTANT_IN_RELEASE: 'true'` у
`.github/workflows/build.yml`, поки в Anthropic ліміт $5): перед
публікацією в Google Play поставити `'false'` (docs/REMINDERS.md, розділ 4,
п. 6).

Без адреси застосунок працює з demo-моделлю (заготовлені відповіді, без
сервера).

### Перевірка

```bash
curl -s https://<ref>.supabase.co/functions/v1/assistant -H "x-apiary-assistant-token: <код>" -H "content-type: application/json" -d "{\"messages\":[{\"role\":\"user\",\"content\":\"Привіт\"}]}"
```

Має повернути `{"content":[…],"stop_reason":"end_turn",…}`. Без коду чи з
неправильним — `{"error":"unauthorized"}`.

## Модель і глибина міркувань — перемикач без коду

Supabase → Edge Functions → **Secrets**: змінити (або додати) секрет — і
наступне ж повідомлення піде вже з новим налаштуванням. Нічого
перезбирати й розгортати не треба.

| Секрет | Значення | Що дає |
|---|---|---|
| `ASSISTANT_MODEL` | `haiku` (типово) | швидко й найдешевше (~$0.001 за повідомлення) |
| | `sonnet` | кмітливіший, приблизно у 20 разів дорожчий (~$0.02 за повідомлення); якщо його запобіжники відмовлять, Anthropic сам повторить запит іншою моделлю |
| `ASSISTANT_EFFORT` | `low` / `medium` (типово) / `high` / `xhigh` / `max` | глибина міркувань: вище — точніше на складних проханнях, але довше чекати й більше вихідних токенів |

Невідоме значення (описка) — береться типове, помічник не ламається.
Що реально витрачається — у журналі функції: `model`, `effort`,
`input_tokens`, `output_tokens`, `cache_read_input_tokens`.

Після зміни моделі краще почати в чаті «Нову розмову».

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

## Автоматичні перевірки

Фейкова модель із заготовленими викликами інструментів — ані Anthropic, ані
Supabase не потрібні (і нічого не коштують). Запускаються в GitHub:

* процес **«Помічник»** (`.github/workflows/assistant.yml`) — при кожному
  push у `assistant` / `main` і в PR, якщо змінено щось помічника;
* повна збірка **«Build»** — усі тести застосунку й посередника перед APK;
* **«Supabase»** — посередник разом з іншими функціями сервера.

| Сценарій | Де перевіряється |
|---|---|
| навігація («відкрий склад») | `test/assistant_scenarios_test.dart`, `test/assistant_tools_test.dart`, `test/assistant_chat_test.dart` (диспетчер усіх 19 екранів) |
| пошук (вулики, історія, склад, фінанси) | `test/assistant_scenarios_test.dart`, `test/assistant_tools_test.dart` |
| запис із «Так» / з «Ні», виправлення в картці | `test/assistant_scenarios_test.dart`, `test/assistant_tools_test.dart`, `test/assistant_chat_test.dart` |
| «Скасувати» | ті самі |
| черга: офлайн → онлайн, по порядку | `test/assistant_scenarios_test.dart`, `test/assistant_queue_test.dart` |
| перезапуск із непорожньою чергою | ті самі |
| повтор після збою, «не надіслано» після 5 | ті самі |
| видалення з черги | ті самі + `test/assistant_chat_test.dart` |
| відповідь із черги не відкриває екран сама | ті самі |
| записи з черги — картка чекає в чаті | `test/assistant_queue_test.dart` |
| зупинка після 6 кроків | `test/assistant_scenarios_test.dart`, `test/assistant_model_test.dart`, `supabase/tests/assistant.test.ts` |
| неправильний тестовий код — відмова сервера | `test/assistant_scenarios_test.dart`, `supabase/tests/assistant.test.ts` |
| голос, читання вголос | `test/assistant_voice_test.dart` |
| промпт і опис інструментів (назви збігаються з застосунком) | `supabase/tests/assistant_prompt.test.ts`, `supabase/tests/assistant_tools.test.ts`, `test/assistant_tools_test.dart` |

Локально: `flutter test test/assistant_*_test.dart` і
`node --test supabase/tests/assistant*.test.ts`.
