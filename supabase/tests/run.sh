#!/usr/bin/env bash
# Runs the database tests on a throwaway local Postgres (16+).
# Each tests/*.test.sql file gets a fresh database with all migrations applied.
#
#   supabase/tests/run.sh            # all tests
#   supabase/tests/run.sh points     # files whose name contains "points"
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PGBIN="${PGBIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
WORK="$(mktemp -d)"
PORT="${PGPORT_TEST:-55432}"

# initdb refuses to run as root; use the postgres user when we are root.
as_pg() { if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi; }

chmod 777 "$WORK"
as_pg "$PGBIN/initdb" -D "$WORK/data" -A trust -U postgres >/dev/null
as_pg "$PGBIN/pg_ctl" -D "$WORK/data" -o "-p $PORT -k $WORK -c listen_addresses=''" -l "$WORK/log" -w start >/dev/null
trap 'as_pg "$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1; rm -rf "$WORK"' EXIT

PSQL=(psql -h "$WORK" -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q -X)

"${PSQL[@]}" -d postgres -c "create database kora_template" >/dev/null
"${PSQL[@]}" -d kora_template -f "$HERE/support/supabase_stub.sql" >/dev/null
for f in "$ROOT"/migrations/*.sql; do
  "${PSQL[@]}" -d kora_template -f "$f" >/dev/null 2>"$WORK/migrate.err" || { cat "$WORK/migrate.err"; echo "migration failed: $f"; exit 1; }
done
"${PSQL[@]}" -d kora_template -f "$HERE/support/helpers.sql" >/dev/null

pass=0; fail=0
for t in "$HERE"/*.test.sql; do
  name="$(basename "$t" .test.sql)"
  if [ $# -gt 0 ] && [[ "$name" != *"$1"* ]]; then continue; fi
  db="t_$(echo "$name" | tr -c 'a-z0-9\n' '_')"
  "${PSQL[@]}" -d postgres -c "create database $db template kora_template" >/dev/null
  if out="$("${PSQL[@]}" -d "$db" -f "$t" 2>&1)"; then
    n=$(grep -c 'ok - ' <<<"$out" || true)
    echo "PASS $name ($n checks)"; pass=$((pass + 1))
  else
    echo "FAIL $name"; grep -E 'ok - |FAIL|ERROR|CONTEXT' <<<"$out" | sed 's/^/    /' | tail -15; fail=$((fail + 1))
  fi
done
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
