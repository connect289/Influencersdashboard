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
raw() { # role, file: one transaction (the stubs, which stand in for the apps)
  psql_as "$1" -d rehearsal -1 -c "set local lock_timeout = '60s'; set local statement_timeout = '5min';" -f "$2" >/dev/null
}
apply() { # role, file: one transaction, as on production (spec §4), refused if it changes anything outside schema one
  psql_as "$1" -d rehearsal -1 -c "set local lock_timeout = '60s'; set local statement_timeout = '5min';" \
    -f "$here/scripts/db/fp-before.sql" -f "$2" -f "$here/scripts/db/fp-after.sql" >/dev/null
}

psql_as supabase_admin -d postgres -c "create database rehearsal" >/dev/null
raw supabase_admin "$here/supabase/tests/local/00_platform_stubs.sql"
raw postgres "$here/supabase/tests/local/01_app_stubs.sql"

mapfile -t forward < <(ls "$here"/supabase/migrations/[0-9][0-9][0-9][0-9]_*.sql | grep -v '\.rollback\.sql$' | sort)

apply_all() { for f in "${forward[@]}"; do apply postgres "$f"; echo "  applied $(basename "$f")"; done; }
rollback_all() { # the throwaway cluster's history may be discarded (0006's rollback refuses otherwise; m8)
  for (( i=${#forward[@]}-1; i>=0; i-- )); do
    PGOPTIONS="-c one.rollback_discards_history=on" apply postgres "${forward[$i]%.sql}.rollback.sql"
    echo "  rolled back $(basename "${forward[$i]}")"
  done
}
run_tests() {
  for t in "$here"/supabase/tests/local/[1-9][0-9]_*.sql; do psql_as supabase_admin -d rehearsal -f "$t" >/dev/null; echo "  passed $(basename "$t")"; done
  psql_as postgres -d rehearsal -At -f "$here/supabase/tests/smoke.sql" | grep -q "^SMOKE PASSED" || { echo "smoke.sql failed"; exit 1; }
  echo "  passed smoke.sql"
}

echo "apply"; apply_all
# What a rehearsal target must match after its first apply (scripts/db/fingerprint.sql), kept in
# supabase/tests/fingerprint.expected so rehearse.sh can compare (m16). ONE_UPDATE_FINGERPRINT=1 rewrites it.
fp="$(psql_as postgres -d rehearsal -At -F ' ' -f "$here/scripts/db/fingerprint.sql")"
echo "  fingerprint $fp"
if [ "${ONE_UPDATE_FINGERPRINT:-}" = 1 ]; then
  echo "$fp" > "$here/supabase/tests/fingerprint.expected"
elif [ "$fp" != "$(cat "$here/supabase/tests/fingerprint.expected" 2>/dev/null)" ]; then
  echo "the fingerprint differs from supabase/tests/fingerprint.expected; run ONE_UPDATE_FINGERPRINT=1 scripts/db/local-test.sh and commit it"; exit 1
fi
echo "test"; run_tests
# m8: with history in schema one, 0006's rollback refuses unless told to discard it.
psql_as postgres -d rehearsal -c "select one.open_or_touch_incident('PLAT-05', 'P1', '{}')" >/dev/null
if out="$(apply postgres "$here/supabase/migrations/0006_seed_checks.rollback.sql" 2>&1)"; then
  echo "0006's rollback discarded history without being told to"; exit 1
fi
echo "$out" | grep -q "0006 rollback refused" || { echo "$out"; exit 1; }
echo "  0006's rollback refuses to discard history"
# M8: a file that changes anything outside schema one is rolled back whole by the fingerprint wrapper.
printf 'create table one.fp_probe (id int);\nalter table public.student_leads add column fp_probe text;\n' > "$work/bad.sql"
if out="$(apply postgres "$work/bad.sql" 2>&1)"; then echo "the fingerprint wrapper let an app change through"; exit 1; fi
echo "$out" | grep -q "changed an object outside schema one" || { echo "$out"; exit 1; }
[ "$(psql_as postgres -d rehearsal -At -c "select to_regclass('one.fp_probe') is null")" = t ] || { echo "the refused file was partly applied"; exit 1; }
echo "  the fingerprint wrapper refuses a change outside schema one"
# Phase 7 review B1: grants to anyone, Eduwit One's roles included, that the migrations do not make are refused too.
for bad in \
  "grant select (student_name) on public.student_leads to anon;" \
  "grant select (id), update (id) on public.student_leads to eduwit_one_fixer;" \
  "grant update on public.w2_outbox to eduwit_one_fixer;" \
  "grant execute on function public.lead_intake(jsonb) to eduwit_one_fixer;" \
  "grant create on schema public to eduwit_one_fixer;" \
  "alter default privileges for role postgres in schema public grant select on tables to eduwit_one_fixer;" \
  "grant eduwit_one_fixer to authenticated;" \
  "grant eduwit_one_reader to eduwit_one_fixer;" \
  "alter role eduwit_one_fixer bypassrls;" \
  "do \$\$ begin execute('grant select (email_id) on public.student_leads to eduwit_one_reader'); end \$\$;"; do
  printf 'create table one.fp_probe (id int);\n%s\n' "$bad" > "$work/bad.sql"
  if out="$(apply postgres "$work/bad.sql" 2>&1)"; then echo "the fingerprint wrapper let this through: $bad"; exit 1; fi
  echo "$out" | grep -q "changed an object outside schema one" || { echo "$bad: $out"; exit 1; }
done
echo "  the fingerprint wrapper refuses grants the migrations do not make, Eduwit One's roles included"
echo "rollback"; rollback_all
left="$(psql_as postgres -d rehearsal -At -f "$here/scripts/db/leftovers.sql")"
[ "$left" = "0" ] || { echo "rollback left $left objects behind"; exit 1; }
echo "  rollback left nothing behind"
echo "re-apply"; apply_all
echo "re-test"; run_tests
echo "LOCAL TEST PASSED"
