# Фото чеків для довчання розпізнавання — сервер

Людина один раз дає згоду в застосунку (екран чека) → кожне фото чека йде
функції `receipt-photo` → лягає в закрите сховище `receipt-training`.
Звідти розробник переносить їх у гілку `ocr-training` й розмічає.

| Файл | Що в ньому |
|---|---|
| `index.ts` | функція: перевірка JPEG, розміру (до 4 МБ), дубля (хеш у імені), добового ліміту (30 з одного телефона) |
| `../../migrations/20261105000100_receipt_training.sql` | закритий бакет `receipt-training` (політик немає: пише й читає лише службовий ключ) |

Перевірка без Supabase: `node --test supabase/tests/receipt_photo.test.ts`.

## Налаштувати (один раз)
1. SQL Editor → вставити `20261105000100_receipt_training.sql` → Run.
2. Створити функцію `receipt-photo` (вміст `index.ts`) і розгорнути:
   `npx supabase functions deploy receipt-photo --no-verify-jwt --project-ref <ref>`.
   Секрети `SUPABASE_URL` і `SUPABASE_SERVICE_ROLE_KEY` Supabase дає функціям сам.

## Забрати фото
Storage → `receipt-training` → папка кожного телефона → завантажити. Фото чека
може містити частину номера картки: зберігати лише в закритому сховищі й у
гілці, яку бачите лише ви.
