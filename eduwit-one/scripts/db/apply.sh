#!/usr/bin/env bash
# Applies migrations to production one file at a time, in the order of spec §5:
#   guards → the current migration set has a REHEARSAL PASSED row in docs/REHEARSALS.md → a dump from the last 24 h
#   exists and matches its .sha256 (scripts/db/dump.sh), unless ONE_APPLY_WITHOUT_DUMP=owner-accepted (D-090) → each named file in its own transaction (lock_timeout 5s,
#   statement_timeout 5min), stopping at the first failure → smoke test → prints the tick report to inspect by hand.
# Target: ONE_PROD_DB_URL, never printed. Usage: scripts/db/apply.sh 0001_schema_and_roles.sql [0002_... ...]
set -euo pipefail

here="$(cd "$(dirname "$0")/../.." && pwd)"
[ "$#" -gt 0 ] || { echo "usage: scripts/db/apply.sh <migration file name>..."; exit 2; }
if [ "${ONE_DB_TARGET:-}" != production ]; then
  node "$here/scripts/db/guards.ts"
  hash="$(node "$here/scripts/db/guards.ts" --hash)"
  grep -q "\`$hash\` | REHEARSAL PASSED" "$here/docs/REHEARSALS.md" || { echo "refused: this migration set ($hash) has no REHEARSAL PASSED row"; exit 1; }
  exec node "$here/scripts/db/with-db.ts" ONE_PROD_DB_URL "$0" "$@"
fi
prod_ref="$(node -p "require('$here/config/defaults.json').supabase.production_ref")"
case "${PGHOST:-} ${PGUSER:-}" in *"$prod_ref"*) ;; *) echo "refused: the connection is not the production project"; exit 2 ;; esac

if [ "${ONE_APPLY_WITHOUT_DUMP:-}" = owner-accepted ]; then
  # The owner waived the dump for this apply on 24 Oct 2026 (D-090); the variable must be set on purpose, every run.
  echo "no dump: applying without a production dump, as the owner accepted on 24 Oct 2026 (D-090)"
else
  dir="${ONE_DUMP_DIR:-$HOME/eduwit-one-dumps}"
  dump="$(find "$dir" -maxdepth 1 -name 'production-*.dump' -mmin -1440 2>/dev/null | sort | tail -1)"
  [ -n "$dump" ] || { echo "refused: no production dump from the last 24 h in $dir; run scripts/db/dump.sh, or ONE_APPLY_WITHOUT_DUMP=owner-accepted if the owner waived it (D-090)"; exit 1; }
  (cd "$dir" && sha256sum -c --quiet "$(basename "$dump").sha256") || { echo "refused: $dump does not match its sha256"; exit 1; }
  echo "dump $dump"
fi

q() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }
for name in "$@"; do
  f="$here/supabase/migrations/$name"
  case "$name" in *.rollback.sql) echo "refused: $name is a rollback; run it by hand after reading it"; exit 2 ;; esac
  [ -f "$f" ] || { echo "no such migration: $name"; exit 2; }
  # Between two catalogue fingerprints: a file that changes anything outside schema one is rolled back whole (M8).
  q -1 -c "set local lock_timeout = '5s'; set local statement_timeout = '5min';" \
    -f "$here/scripts/db/fp-before.sql" -f "$f" -f "$here/scripts/db/fp-after.sql" >/dev/null
  echo "  applied $name"
done
q -At -f "$here/supabase/tests/smoke.sql" | grep -q '^SMOKE PASSED' || { echo "smoke.sql failed after the apply"; exit 1; }
echo "  passed smoke.sql"
echo "tick report (inspect it): $(q -At -c 'select report from one.runs where kind = '\''tick'\'' order by id desc limit 1')"
echo "cron: $(q -At -c "select string_agg(jobname || ' ' || schedule, '; ') from cron.job where jobname like 'one-%'")"
echo "Record the dump path and this run in docs/DECISIONS.md and docs/CHANGES.md."
