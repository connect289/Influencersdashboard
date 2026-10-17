#!/usr/bin/env bash
# Each proposed shared change (supabase/migrations-shared/sNN_*.sql) is applied inside ONE transaction on the replica,
# its smoke test runs (migrations-shared/tests/sNN.test.sql, if any), its rollback file runs, and the database state
# (schema fingerprint + touched shared data + extensions + cron jobs, scripts/db/state.sql) must equal the state before;
# then the transaction is rolled back. Proves every proposal applies, works and rolls back cleanly on the production
# schema without keeping anything. Usage: check-shared-proposals.sh [database-url]
set -uo pipefail
cd "$(dirname "$0")/../.."
URL="${1:-postgresql://postgres:postgres@localhost:54330/postgres}"
P=(psql "$URL" -X -A -F ' ' -t -v ON_ERROR_STOP=1 -q)
before=$("${P[@]}" -f scripts/db/state.sql | sed '/^$/d')
fail=0
for f in supabase/migrations-shared/s[0-9][0-9]_*.sql; do
  case "$f" in *.rollback.sql) continue ;; esac
  name=$(basename "$f" .sql); id=${name%%_*}
  rb="supabase/migrations-shared/$name.rollback.sql"; t="supabase/migrations-shared/tests/$id.test.sql"
  [ -e "$rb" ] || { echo "FAIL  $name: no rollback file"; fail=1; continue; }
  out=$( { echo "begin;"; echo "\\i $f"; [ -e "$t" ] && echo "\\i $t"; echo "\\i $rb";
           echo "\\echo STATE"; echo "\\i scripts/db/state.sql"; echo "rollback;"; } | "${P[@]}" 2>&1)
  if [ $? -ne 0 ]; then echo "FAIL  $name"; echo "$out" | grep -E 'ERROR' | head -3; fail=1; continue; fi
  after=$(echo "$out" | sed -n '/^STATE$/,$p' | sed '1d;/^$/d;/^ROLLBACK$/d')
  if [ "$after" != "$before" ]; then
    echo "FAIL  $name: state after its rollback differs"; diff <(echo "$before") <(echo "$after") | head -6; fail=1; continue
  fi
  echo "ok    $name (applied$([ -e "$t" ] && echo ", smoke test passed"), rolled back to the identical state)"
done
exit $fail
