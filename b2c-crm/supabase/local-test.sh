#!/usr/bin/env bash
# Spark (b2c-crm) on a throwaway local PostgreSQL: the stubs for the shared objects, every migration in order, applied
# twice (they are idempotent), then every tests/test_*.sql suite. A suite fails when psql fails, when it returns no
# check row, or when a row's ok column is false. Offline: nothing leaves the machine, and it never connects to staging
# or production. Usage: ./local-test.sh [test_file.sql ...]
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"; port="${B2C_TEST_PORT:-55446}"
bin="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)"
as_server() { if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi; }
[ "$(id -u)" = 0 ] && chown postgres "$work"
trap 'as_server "$bin/pg_ctl" -D "$work/data" -m immediate stop >/dev/null 2>&1; rm -rf "$work"' EXIT
as_server "$bin/initdb" -D "$work/data" -U postgres --auth=trust -E UTF8 --no-locale >/dev/null
as_server "$bin/pg_ctl" -D "$work/data" -o "-k $work -p $port -c listen_addresses=''" -l "$work/log" -w start >/dev/null
q() { psql -X -q -h "$work" -p "$port" -U postgres -v ON_ERROR_STOP=1 "$@"; }
q -d postgres -c "create database b2c_fresh" >/dev/null
q -d b2c_fresh -f "$here/tests/local_stubs.sql" >/dev/null || { echo "stubs failed"; exit 1; }
mapfile -t migs < <(ls "$here"/migrations/b*.sql | sed 's|.*/b\([0-9]*\)_|\1 &|' | sort -n | cut -d' ' -f2)
for pass in 1 2; do
  for f in "${migs[@]}"; do
    out=$(q -d b2c_fresh -f "$f" 2>&1) || { echo "pass $pass: $(basename "$f") failed:"; echo "$out" | tail -5; exit 1; }
  done
  echo "pass $pass: ${#migs[@]} migrations applied"
done
suites=("$@"); [ ${#suites[@]} -eq 0 ] && mapfile -t suites < <(ls "$here"/tests/test_*.sql | xargs -n1 basename)
fail=0
for t in "${suites[@]}"; do
  out=$(q -d b2c_fresh -A -t -F '|' -f "$here/tests/$t" 2>&1); rc=$?
  bad=$(echo "$out" | grep -E '\|f\||\|f$' | head -5)
  total=$(echo "$out" | grep -cE '\|(t|f)(\||$)')
  if [ $rc -ne 0 ] || [ -n "$bad" ] || [ "$total" -eq 0 ]; then
    fail=1; echo "FAIL $t (rc $rc, $total rows)"; echo "$bad"; echo "$out" | grep -i "error" | head -3
  else
    echo "ok   $t ($total checks)"
  fi
done
if [ $fail -eq 0 ]; then echo "B2C LOCAL TEST PASSED"; else echo "B2C LOCAL TEST FAILED"; exit 1; fi
