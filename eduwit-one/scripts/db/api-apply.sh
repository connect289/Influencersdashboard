#!/usr/bin/env bash
# The production apply of apply.sh, run through Supabase's Management API instead of psql (D-090): guards → the current
# migration set has a REHEARSAL PASSED row → the owner's explicit acceptance of applying without a dump (this route has
# no pg_dump; the owner waived the dump on 24 Oct 2026, D-090) → each named file in its own transaction between the two
# catalogue fingerprints (scripts/db/wrap.ts), stopping at the first failure → smoke → the tick report and the cron jobs
# to inspect by hand. Needs SUPABASE_ACCESS_TOKEN (never printed; with-api.ts).
# Usage: ONE_APPLY_WITHOUT_DUMP=owner-accepted scripts/db/api-apply.sh 0001_schema_and_roles.sql [0002_... ...]
set -euo pipefail

here="$(cd "$(dirname "$0")/../.." && pwd)"
[ "$#" -gt 0 ] || { echo "usage: scripts/db/api-apply.sh <migration file name>..."; exit 2; }
node "$here/scripts/db/guards.ts"
hash="$(node "$here/scripts/db/guards.ts" --hash)"
grep -q "\`$hash\` | REHEARSAL PASSED" "$here/docs/REHEARSALS.md" || { echo "refused: this migration set ($hash) has no REHEARSAL PASSED row"; exit 1; }
[ -n "${SUPABASE_ACCESS_TOKEN:-}" ] || { echo "SUPABASE_ACCESS_TOKEN is not set (docs/RUNBOOK-database.md §5)"; exit 2; }
[ "${ONE_APPLY_WITHOUT_DUMP:-}" = owner-accepted ] || { echo "refused: this route takes no production dump. The owner accepted applying without one on 24 Oct 2026 (D-090); run with ONE_APPLY_WITHOUT_DUMP=owner-accepted to go ahead"; exit 1; }
echo "no dump: applying without a production dump, as the owner accepted on 24 Oct 2026 (D-090)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

api() { node "$here/scripts/db/with-api.ts" production "$@"; }
sql() { api --sql "$1"; }
scalar() { sql "$1" | jq -r '.[0].v // empty'; }
# The one-* jobs stay inactive while files run (see api-rehearse.sh): paused after every file, a running tick waited
# out, and switched back on after the smoke test.
jobs_pause() {
  sql "select cron.alter_job(jobid, active := false) from cron.job where jobname in ('one-tick', 'one-nightly') and active" > /dev/null
  for _ in $(seq 1 60); do
    [ "$(scalar "select count(*) as v from pg_stat_activity where pid <> pg_backend_pid() and state <> 'idle' and query ~ 'one\\.(tick_job|nightly)'")" = "0" ] && return
    sleep 2
  done
  echo "a one-tick run is still going after 2 min"; exit 1
}
jobs_resume() { sql "select cron.alter_job(jobid, active := true) from cron.job where jobname in ('one-tick', 'one-nightly') and not active" > /dev/null; }
for name in "$@"; do
  f="$here/supabase/migrations/$name"
  case "$name" in *.rollback.sql) echo "refused: $name is a rollback; run it by hand after reading it"; exit 2 ;; esac
  [ -f "$f" ] || { echo "no such migration: $name"; exit 2; }
  # One transaction between two catalogue fingerprints: a file that changes anything outside schema one is rolled back whole (M8).
  node "$here/scripts/db/wrap.ts" "$f" > "$work/payload.sql"
  api "$work/payload.sql" > /dev/null
  jobs_pause
  echo "  applied $name"
done
# smoke.sql's steps as separate calls (see api-rehearse.sh): the committing procedure at top level, then the assertions.
sql "call one.tick_job();" > /dev/null
grep -vE '^(set lock_timeout|set statement_timeout|reset statement_timeout|call one\.tick_job\(\))' "$here/supabase/tests/smoke.sql" > "$work/smoke-rest.sql"
api "$work/smoke-rest.sql" | jq -e '.[0].result == "SMOKE PASSED"' > /dev/null || { echo "smoke.sql failed after the apply"; exit 1; }
echo "  passed smoke.sql"
jobs_resume
echo "tick report (inspect it): $(sql "select report::text as v from one.runs where kind = 'tick' order by id desc limit 1" | jq -r '.[0].v')"
echo "cron: $(sql "select string_agg(jobname || ' ' || schedule, '; ') as v from cron.job where jobname like 'one-%'" | jq -r '.[0].v')"
echo "Record this run in docs/DECISIONS.md and docs/CHANGES.md (no dump: D-090)."
