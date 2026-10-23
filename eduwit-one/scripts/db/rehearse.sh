#!/usr/bin/env bash
# Rehearsal on staging (spec §5 and standard 8): guards → apply 0001..N → smoke → rollback N..0001, asserting nothing
# is left → apply again → smoke → REHEARSAL PASSED, recorded in docs/REHEARSALS.md with the migration-set hash that
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
apply() { q -1 -c "set local lock_timeout = '5s'; set local statement_timeout = '5min';" -f "$1" >/dev/null; }
mapfile -t forward < <(ls "$here"/supabase/migrations/[0-9][0-9][0-9][0-9]_*.sql | grep -v '\.rollback\.sql$' | sort)
apply_all() { for f in "${forward[@]}"; do apply "$f"; echo "  applied $(basename "$f")"; done; }
rollback_all() { for (( i=${#forward[@]}-1; i>=0; i-- )); do apply "${forward[$i]%.sql}.rollback.sql"; echo "  rolled back $(basename "${forward[$i]}")"; done; }
smoke() { q -At -f "$here/supabase/tests/smoke.sql" | grep -q '^SMOKE PASSED' || { echo "smoke.sql failed"; exit 1; }; echo "  passed smoke.sql"; }
left() { q -At -f "$here/scripts/db/leftovers.sql"; }

[ "$(left)" = "0" ] || { echo "refused: schema one, its roles or its cron jobs already exist on staging; roll back first"; exit 1; }
echo "apply"; apply_all
echo "  fingerprint $(q -At -F ' ' -f "$here/scripts/db/fingerprint.sql")"
echo "smoke"; smoke
echo "rollback"; rollback_all
n="$(left)"; [ "$n" = "0" ] || { echo "rollback left $n objects behind"; exit 1; }
echo "  rollback left nothing behind"
echo "re-apply"; apply_all
echo "re-smoke"; smoke

hash="$(node "$here/scripts/db/guards.ts" --hash)"
printf '| %s | staging | `%s` | REHEARSAL PASSED | scripts/db/rehearse.sh |\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$hash" >> "$here/docs/REHEARSALS.md"
echo "REHEARSAL PASSED ($hash)"
