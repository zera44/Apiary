#!/usr/bin/env bash
# Перевірка адреси сервера синхронізації перед збіркою APK.
#
#   bash tool/check_supabase_url.sh "$SUPABASE_URL" "$SUPABASE_ANON_KEY"
#
# Порожня адреса - не помилка (синхронізація в APK буде вимкнена).
# Помилка (exit 1) - коли адреса явно не на сервер Supabase: не https або
# замість відповіді сервера входу приходить веб-сторінка (HTML). Так було з
# тестовою збіркою 0.3.15: адреса вела на github.com, і кожен вхід на сервер
# закінчувався «422» з HTML-сторінкою GitHub.
# Сервер недоступний (призупинений проєкт, немає мережі) - лише попередження.
set -u
URL="${1:-}"
KEY="${2:-}"
[ -z "$URL" ] && exit 0

fail() { echo "::error title=SUPABASE_URL::$1"; echo "ПОМИЛКА: $1" >&2; exit 1; }

case "$URL" in
  https://*) ;;
  *) fail "адреса сервера має починатися з https:// (зараз: ${URL%%/*}//…)" ;;
esac
host="${URL#https://}"; host="${host%%/*}"
case "$host" in
  github.com|*.github.com|*.github.io|githubusercontent.com|*.githubusercontent.com)
    fail "адреса сервера вказує на GitHub ($host), а має бути адреса проєкту Supabase (https://<ref>.supabase.co)" ;;
esac

# сервер входу Supabase на /auth/v1/settings відповідає JSON-ом
body="$(mktemp)"; trap 'rm -f "$body"' EXIT
code="$(curl -sS --max-time 20 -o "$body" -w '%{http_code}' \
  -H "apikey: $KEY" "${URL%/}/auth/v1/settings" 2>/dev/null)" || code=000
first="$(tr -d ' \t\r\n' < "$body" | head -c 1)"
if [ "$first" = "<" ]; then
  fail "за адресою $host відповідає веб-сторінка (HTML, код $code), а не сервер Supabase - перевірте секрет SUPABASE_URL"
fi
if [ "$code" != "200" ] || [ "$first" != "{" ]; then
  echo "::warning title=SUPABASE_URL::сервер $host не відповів як Supabase (код $code) - можливо, проєкт призупинено або немає мережі"
  exit 0
fi
echo "Сервер синхронізації $host відповідає"
