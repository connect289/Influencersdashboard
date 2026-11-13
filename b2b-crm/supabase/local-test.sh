#!/usr/bin/env bash
# Local migration and SQL test run on a throwaway Postgres cluster. Never touches a Supabase project: it starts its own
# server on a private socket (no TCP), loads stubs of auth / storage / cron / net / vault / pgmq
# (tests/local/00_platform_stubs.sql), applies the baseline and every migration in deploy order (timestamped files, then
# the list in deploy.sh), applies the m24+ list a second time (every file must re-apply cleanly), then runs the SQL test
# files and fails on any row with ok = false.
#   ./local-test.sh                     every file in tests/local-suite.txt
#   ./local-test.sh tests/test_x.sql    just these files
# Needs the PostgreSQL 15+ server binaries (initdb, pg_ctl, postgres) and psql. Locally only pgcrypto, uuid-ossp and
# pg_trgm are real extensions: pgvector columns become the real[] domain public.vector and their indexes are skipped (the B2B CRM does not use them).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
bin="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
[ -x "$bin/initdb" ] || { echo "PostgreSQL server binaries not found (set PG_BIN)"; exit 1; }
work="$(mktemp -d)"
port=55439
# The server refuses to run as root; in a root container it runs as the OS user postgres.
as_server() { if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi; }
[ "$(id -u)" = 0 ] && chown postgres "$work"
trap 'as_server "$bin/pg_ctl" -D "$work/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

as_server "$bin/initdb" -D "$work/data" -U supabase_admin --auth=trust -E UTF8 --no-locale >/dev/null
as_server "$bin/pg_ctl" -D "$work/data" -o "-k $work -p $port -c listen_addresses='' -c timezone=UTC" -l "$work/log" -w start >/dev/null

db() { psql -X -q -h "$work" -p "$port" -U "$1" -d b2b -v ON_ERROR_STOP=1 "${@:2}"; }
psql -X -q -h "$work" -p "$port" -U supabase_admin -d postgres -c "create database b2b" >/dev/null
db supabase_admin -1 -f tests/local/00_platform_stubs.sql >/dev/null
# Production runs PostgreSQL 17; on an older local server the baseline's MAINTAIN grants are dropped.
pgmajor="$(db supabase_admin -At -c "show server_version_num" | cut -c1-2)"

# Extensions the cluster has stand in as stubs (above); pgvector columns and indexes are rewritten.
prep() {
  sed -E -e '/^create extension if not exists (vector|pg_net|supabase_vault|pg_cron|pgmq)\b/d' \
         -e 's/\bvector\(([0-9]+)\)/vector/g' \
         -e '/USING (hnsw|ivfflat)/d' \
         -e "$( [ "$pgmajor" -lt 17 ] && echo 's/(grant |, )MAINTAIN, /\1/' || echo 's/^$//' )" "$1"
}
apply() { # one transaction per file, as deploy.sh does
  prep "$1" > "$work/f.sql"
  if ! db postgres -1 -c "set client_min_messages = warning" -f "$work/f.sql" > "$work/out" 2>&1; then
    cat "$work/out"; echo "FAILED applying $1"; exit 1
  fi
}

mapfile -t early < <(ls migrations/[0-9]*.sql | sort)
mapfile -t later < <(sed -n '/^FILES=(/,/^)/p' deploy.sh | tr ' ' '\n' | grep -E '\.sql$')

echo "apply"
for f in "${early[@]}" "${later[@]}"; do apply "$f"; done
echo "  applied ${#early[@]} + ${#later[@]} files"
echo "re-apply m24+"
for f in "${later[@]}"; do apply "$f"; done
echo "  re-applied ${#later[@]} files"

if [ "$#" -gt 0 ]; then tests=("$@"); else mapfile -t tests < <(grep -vE '^\s*(#|$)' tests/local-suite.txt); fi
fail=0
for t in "${tests[@]}"; do
  # Each test file prints its result rows (name | ok | detail) and ends with rollback; a row with ok = f fails the run.
  if ! out="$(db postgres -At -F ' | ' -c "set client_min_messages = warning" -f "$t" 2>&1)"; then
    echo "  ERROR $t"; echo "$out" | tail -20; fail=1; continue
  fi
  rows="$(echo "$out" | grep -cE '^[^|]+ \| (t|f) \| ' || true)"
  bad="$(echo "$out" | grep -E '^[^|]+ \| f \| ' || true)"
  if [ "$rows" = 0 ]; then echo "  NO ROWS $t"; echo "$out" | tail -5; fail=1
  elif [ -n "$bad" ]; then echo "  FAILED $t"; echo "$bad"; fail=1
  else echo "  passed $t ($rows rows)"; fi
done
[ "$fail" = 0 ] && echo "LOCAL TEST PASSED" || { echo "LOCAL TEST FAILED"; exit 1; }
