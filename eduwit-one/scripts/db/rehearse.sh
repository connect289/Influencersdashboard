#!/usr/bin/env bash
# Rehearsal on staging (spec §5 and standard 8): guards → apply 0001..N → smoke → one real pg_cron run of one-tick →
# rollback N..0001, asserting nothing is left → apply again → smoke → REHEARSAL PASSED, recorded in docs/REHEARSALS.md with the migration-set hash that
# scripts/db/apply.sh requires before production. Target: ONE_STAGING_DB_URL, never printed; with-db.ts refuses a URL
# that reaches any other project. The fixture tests in supabase/tests/local/ never run here (they refuse any database
# but the local test cluster). Usage: scripts/db/rehearse.sh
set -euo pipefail

here="$(cd "$(dirname "$0")/../.." && pwd)"
if [ "${ONE_DB_TARGET:-}" != staging ]; then
  node "$here/scripts/db/guards.ts"
  exec node "$here/scripts/db/with-db.ts" ONE_STAGING_DB_URL "$0" "$@"
fi
staging_ref="$(node -p "require('$here/config/defaults.json').supabase.staging_ref")"
case "${PGHOST:-} ${PGUSER:-}" in *"$staging_ref"*) ;; *) echo "refused: the connection is not the staging project"; exit 2 ;; esac

q() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }
# Each file in one transaction, between two catalogue fingerprints: a file that changes anything outside schema one is
# rolled back whole (scripts/db/app-fingerprint.sql; M8 of the second review).
apply() { q -1 -c "set local lock_timeout = '5s'; set local statement_timeout = '5min';" \
  -f "$here/scripts/db/fp-before.sql" -f "$1" -f "$here/scripts/db/fp-after.sql" >/dev/null; }
# The set this rehearsal vouches for is fixed before the first apply; a file edited while it runs fails the run (m16).
hash_before="$(node "$here/scripts/db/guards.ts" --hash)"
mapfile -t forward < <(ls "$here"/supabase/migrations/[0-9][0-9][0-9][0-9]_*.sql | grep -v '\.rollback\.sql$' | sort)
apply_all() { for f in "${forward[@]}"; do apply "$f"; echo "  applied $(basename "$f")"; done; }
# Staging's history may be discarded (0006's rollback refuses otherwise; m8).
rollback_all() { for (( i=${#forward[@]}-1; i>=0; i-- )); do PGOPTIONS="-c one.rollback_discards_history=on" apply "${forward[$i]%.sql}.rollback.sql"; echo "  rolled back $(basename "${forward[$i]}")"; done; }
smoke() { q -At -f "$here/supabase/tests/smoke.sql" | grep -q '^SMOKE PASSED' || { echo "smoke.sql failed"; exit 1; }; echo "  passed smoke.sql"; }
left() { q -At -f "$here/scripts/db/leftovers.sql"; }

[ "$(left)" = "0" ] || { echo "refused: schema one, its roles or its cron jobs already exist on staging; roll back first"; exit 1; }
# Staging lacks several sources by design (D-009): there, a missing source must not count as a failure.
staging_mode() { q -c "select one.settings_put('checks', one.setting('checks') || '{\"source_missing_opens_incident\": false}', 'rehearse.sh', 'staging lacks sources (D-009)')" >/dev/null; }
echo "apply"; apply_all
fp="$(q -At -F ' ' -f "$here/scripts/db/fingerprint.sql")"
echo "  fingerprint $fp"
# Staging must hold exactly what the local test built from the same files (m16).
[ "$fp" = "$(cat "$here/supabase/tests/fingerprint.expected")" ] || { echo "the fingerprint differs from supabase/tests/fingerprint.expected (the local test's): staging did not receive these files unaltered"; exit 1; }
staging_mode
echo "smoke"; smoke
# pg_cron must accept the committing procedure (D-044): wait for one real one-tick run and require success.
since="$(q -At -c 'select now()')"
echo "cron"; for _ in $(seq 1 24); do
  st="$(q -At -c "select d.status from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'one-tick' and d.start_time > '$since' and d.status in ('succeeded', 'failed') order by d.start_time desc limit 1")"
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

hash="$(node "$here/scripts/db/guards.ts" --hash)"
[ "$hash" = "$hash_before" ] || { echo "a migration changed while the rehearsal ran; run it again"; exit 1; }
printf '| %s | staging | `%s` | REHEARSAL PASSED | scripts/db/rehearse.sh |\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$hash" >> "$here/docs/REHEARSALS.md"
echo "REHEARSAL PASSED ($hash)"
