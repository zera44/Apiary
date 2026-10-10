#!/usr/bin/env bash
# Перевірка сервера без Supabase: тимчасова PostgreSQL, заглушки Supabase
# (stubs.sql), наші міграції (двічі - вони мають бути повторюваними) і
# тести *.test.sql. Потрібна лише PostgreSQL (є на раннерах GitHub).
#
#   supabase/tests/run.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
PGBIN=${PGBIN:-$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)}
tmp=$(mktemp -d)
chmod 755 "$tmp"

as_pg() {
  # initdb не працює від root - тоді від користувача postgres
  if [ "$(id -u)" = 0 ]; then
    chown -R postgres "$tmp"
    runuser -u postgres -- "$@"
  else
    "$@"
  fi
}
as_pg "$PGBIN/initdb" -D "$tmp/data" -A trust -U postgres -E UTF8 --locale=C.UTF-8 >/dev/null
as_pg "$PGBIN/pg_ctl" -D "$tmp/data" -l "$tmp/log" -w \
  -o "-k $tmp -c listen_addresses='' -c client_min_messages=warning" start >/dev/null
cleanup() {
  as_pg "$PGBIN/pg_ctl" -D "$tmp/data" -m fast stop >/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

sql() { "$PGBIN/psql" -h "$tmp" -U postgres -d postgres -X -q -v ON_ERROR_STOP=1 "$@"; }

sql -f "$here/stubs.sql"
for pass in 1 2; do
  for f in "$root"/migrations/*.sql; do
    sql -f "$f"
  done
done
echo "Міграції застосовано (двічі)"

failed=0
for t in "$here"/*.test.sql; do
  if sql -f "$t" >"$tmp/out" 2>&1; then
    echo "  ok  $(basename "$t")"
  else
    echo "  FAIL $(basename "$t")"
    sed 's/^/       /' "$tmp/out"
    failed=1
  fi
done
if command -v node >/dev/null && node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)'; then
  if node --test "$here/backup_commit.test.ts" >"$tmp/out" 2>&1; then
    echo "  ok  backup_commit.test.ts"
  else
    echo "  FAIL backup_commit.test.ts"
    sed 's/^/       /' "$tmp/out"
    failed=1
  fi
else
  echo "  (backup_commit.test.ts пропущено: потрібен Node 22+)"
fi
[ "$failed" = 0 ] && echo "Усі перевірки сервера пройшли"
exit "$failed"
