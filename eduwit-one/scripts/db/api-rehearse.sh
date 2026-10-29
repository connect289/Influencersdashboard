#!/usr/bin/env bash
# The staging rehearsal of rehearse.sh, run through Supabase's Management API instead of psql (D-090): for a machine with
# HTTPS to api.supabase.com and no Postgres connection. Same sequence and same checks: guards → nothing of Eduwit One on
# staging → apply 0001..N, each file one transaction between the two catalogue fingerprints (scripts/db/wrap.ts) →
# fingerprint equals supabase/tests/fingerprint.expected → smoke → one real pg_cron run of one-tick → rollback N..0001
# leaving nothing → apply again → smoke → REHEARSAL PASSED, recorded in docs/REHEARSALS.md with the migration-set hash.
# Needs SUPABASE_ACCESS_TOKEN (never printed; with-api.ts). Usage: scripts/db/api-rehearse.sh
set -euo pipefail

here="$(cd "$(dirname "$0")/../.." && pwd)"
node "$here/scripts/db/guards.ts"
[ -n "${SUPABASE_ACCESS_TOKEN:-}" ] || { echo "SUPABASE_ACCESS_TOKEN is not set (docs/RUNBOOK-database.md §5)"; exit 2; }
work="$(mktemp -d)"
# Whatever way this script ends, the one-* jobs go back on: a smoke failure after the apply left production's
# jobs paused on 29 Oct 2026 until they were switched on by hand (D-098).
trap 'jobs_resume 2>/dev/null || true; rm -rf "$work"' EXIT

api() { node "$here/scripts/db/with-api.ts" staging "$@"; }
sql() { api --sql "$1"; }
scalar() { sql "$1" | jq -r '.[0].v // empty'; }   # the first row's column v
# While files run, the one-* jobs stay inactive: 0005 schedules them active, and a tick that ran during a later file
# deadlocked with apply_grants()'s "enable row level security" (staging, 24 Oct). Paused after every file (a no-op
# until 0005), a running tick is waited out, and the jobs go back on after the smoke test
# (a tick writes settings, which the fingerprint reads, and would race the smoke test's own tick). Inactive jobs keep their
# schedule and command; the fingerprint leaves one-* jobs out, so pausing changes nothing it measures.
jobs_pause() {
  sql "select cron.alter_job(jobid, active := false) from cron.job where jobname in ('one-tick', 'one-nightly') and active" > /dev/null
  for _ in $(seq 1 60); do
    [ "$(scalar "select count(*) as v from pg_stat_activity where pid <> pg_backend_pid() and state <> 'idle' and query ~ 'one\\.(tick_job|nightly)'")" = "0" ] && return
    sleep 2
  done
  echo "a one-tick run is still going after 2 min"; exit 1
}
jobs_resume() { sql "select cron.alter_job(jobid, active := true) from cron.job where jobname in ('one-tick', 'one-nightly') and not active" > /dev/null; }
apply() { node "$here/scripts/db/wrap.ts" "$@" > "$work/payload.sql"; api "$work/payload.sql" > /dev/null; jobs_pause; }
# The set this rehearsal vouches for is fixed before the first apply; a file edited while it runs fails the run (m16).
hash_before="$(node "$here/scripts/db/guards.ts" --hash)"
mapfile -t forward < <(ls "$here"/supabase/migrations/[0-9][0-9][0-9][0-9]_*.sql | grep -v '\.rollback\.sql$' | sort)
apply_all() { for f in "${forward[@]}"; do apply "$f"; echo "  applied $(basename "$f")"; done; }
# Staging's history may be discarded (0006's rollback refuses otherwise; m8): the flag is set inside each transaction.
rollback_all() { jobs_pause; for (( i=${#forward[@]}-1; i>=0; i-- )); do apply "${forward[$i]%.sql}.rollback.sql" --discard-history; echo "  rolled back $(basename "${forward[$i]}")"; done; }
leftovers_sql="$(grep -v '^--' "$here/scripts/db/leftovers.sql" | tr '\n' ' ')"
left() { scalar "${leftovers_sql%;*} as v"; }
smoke() {
  # smoke.sql's steps, as separate calls: the committing procedure must run at top level, outside any transaction block
  # (pg_cron's form, D-044); session settings do not carry between calls, so its set/reset lines are left out.
  # A run pg_cron started in this minute, before the file applied, would be judged instead of a fresh one (0025's
  # apply, D-098): wait for a minute that has no run yet.
  while [ "$(scalar "select exists (select 1 from one.runs where kind = 'tick' and bucket = date_trunc('minute', now())) as v")" = "t" ]; do sleep 5; done
  sql "call one.tick_job();" > /dev/null
  grep -vE '^(set lock_timeout|set statement_timeout|reset statement_timeout|call one\.tick_job\(\))' "$here/supabase/tests/smoke.sql" > "$work/smoke-rest.sql"
  api "$work/smoke-rest.sql" | jq -e '.[0].result == "SMOKE PASSED"' > /dev/null || { echo "smoke.sql failed"; exit 1; }
  echo "  passed smoke.sql"
}

[ "$(left)" = "0" ] || { echo "refused: schema one, its roles or its cron jobs already exist on staging; roll back first"; exit 1; }
# Staging lacks several sources by design (D-009): there, a missing source must not count as a failure.
staging_mode() { sql "select one.settings_put('checks', one.setting('checks') || '{\"source_missing_opens_incident\": false}', 'api-rehearse.sh', 'staging lacks sources (D-009)')" > /dev/null; }
echo "apply"; apply_all
fp="$(api "$here/scripts/db/fingerprint.sql" | jq -r '.[0] | [.functions, .columns, .constraints, .checks, .settings, (.function_count | tostring), (.table_count | tostring)] | join(" ")')"
echo "  fingerprint $fp"
# Staging must hold exactly what the local test built from the same files (m16).
[ "$fp" = "$(cat "$here/supabase/tests/fingerprint.expected")" ] || { echo "the fingerprint differs from supabase/tests/fingerprint.expected (the local test's): staging did not receive these files unaltered"; exit 1; }
staging_mode
echo "smoke"; smoke
jobs_resume
# pg_cron must accept the committing procedure (D-044): wait for one real one-tick run and require success.
since="$(scalar 'select now() as v')"
echo "cron"; st=""; for _ in $(seq 1 24); do
  st="$(scalar "select d.status as v from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'one-tick' and d.start_time > '$since' and d.status in ('succeeded', 'failed') order by d.start_time desc limit 1")"
  [ -n "$st" ] && break; sleep 5
done
[ "$st" = "succeeded" ] || { echo "one-tick under pg_cron: ${st:-no run in 2 min}"; exit 1; }
echo "  one-tick ran under pg_cron: succeeded"
echo "rollback"; rollback_all
n="$(left)"; [ "$n" = "0" ] || { echo "rollback left $n objects behind"; exit 1; }
echo "  rollback left nothing behind"
echo "re-apply"; apply_all
staging_mode
echo "re-smoke"; smoke
jobs_resume

hash="$(node "$here/scripts/db/guards.ts" --hash)"
[ "$hash" = "$hash_before" ] || { echo "a migration changed while the rehearsal ran; run it again"; exit 1; }
printf '| %s | staging | `%s` | REHEARSAL PASSED | scripts/db/api-rehearse.sh |\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$hash" >> "$here/docs/REHEARSALS.md"
echo "REHEARSAL PASSED ($hash)"
