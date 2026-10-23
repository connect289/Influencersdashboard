#!/usr/bin/env bash
# Local migration test on a throwaway Postgres cluster (D-011). Never touches a Supabase project: it starts its own
# server on a private socket, loads stubs of cron / net / vault and of the app objects schema one reads, then runs
#   apply 0001..N → tests → rollback N..0001 (asserting schema one and both roles are gone) → apply again → tests.
# Prints the schema fingerprint after the first apply and LOCAL TEST PASSED on success. Usage: scripts/db/local-test.sh
set -euo pipefail

here="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
port=55433
bin="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)"
# The server refuses to run as root; in a root container it runs as the OS user postgres.
as_server() { if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi; }
[ "$(id -u)" = 0 ] && chown postgres "$work"
trap 'as_server "$bin/pg_ctl" -D "$work/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

as_server "$bin/initdb" -D "$work/data" -U supabase_admin --auth=trust >/dev/null
as_server "$bin/pg_ctl" -D "$work/data" -o "-k $work -p $port -c listen_addresses=''" -l "$work/log" -w start >/dev/null

psql_as() { # role, then psql args
  local role="$1"; shift
  psql -X -q -h "$work" -p "$port" -U "$role" -v ON_ERROR_STOP=1 "$@"
}
apply() { # role, file: one transaction, as on production (spec §4)
  psql_as "$1" -d rehearsal -1 -c "set local lock_timeout = '5s'; set local statement_timeout = '5min';" -f "$2" >/dev/null
}

psql_as supabase_admin -d postgres -c "create database rehearsal" >/dev/null
apply supabase_admin "$here/supabase/tests/local/00_platform_stubs.sql"
apply postgres "$here/supabase/tests/local/01_app_stubs.sql"

mapfile -t forward < <(ls "$here"/supabase/migrations/[0-9][0-9][0-9][0-9]_*.sql | grep -v '\.rollback\.sql$' | sort)

apply_all() { for f in "${forward[@]}"; do apply postgres "$f"; echo "  applied $(basename "$f")"; done; }
rollback_all() {
  for (( i=${#forward[@]}-1; i>=0; i-- )); do
    apply postgres "${forward[$i]%.sql}.rollback.sql"
    echo "  rolled back $(basename "${forward[$i]}")"
  done
}
run_tests() {
  for t in "$here"/supabase/tests/local/[1-9][0-9]_*.sql; do psql_as supabase_admin -d rehearsal -f "$t" >/dev/null; echo "  passed $(basename "$t")"; done
  psql_as postgres -d rehearsal -At -f "$here/supabase/tests/smoke.sql" | grep -q "^SMOKE PASSED" || { echo "smoke.sql failed"; exit 1; }
  echo "  passed smoke.sql"
}

echo "apply"; apply_all
# What a rehearsal target must match after its first apply (scripts/db/fingerprint.sql).
echo "  fingerprint $(psql_as postgres -d rehearsal -At -F ' ' -f "$here/scripts/db/fingerprint.sql")"
echo "test"; run_tests
echo "rollback"; rollback_all
left="$(psql_as postgres -d rehearsal -At -f "$here/scripts/db/leftovers.sql")"
[ "$left" = "0" ] || { echo "rollback left $left objects behind"; exit 1; }
echo "  rollback left nothing behind"
echo "re-apply"; apply_all
echo "re-test"; run_tests
echo "LOCAL TEST PASSED"
