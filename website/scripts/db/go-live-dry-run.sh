#!/usr/bin/env bash
# Production migration dry run (Phase 12; report: docs/GO_LIVE_DRY_RUN.md). On a FRESH replica of the production schema:
#   1. baseline state (= production fingerprint)
#   2. every website migration in order, each in its own transaction with production-safe timeouts
#      (lock_timeout 5 s, statement_timeout 5 min); time taken and any lock stronger than ACCESS SHARE on a shared table
#   3. SQL test suites + shared objects unchanged
#   4. every shared proposal (APPROVALS_NEEDED) in go-live order, with its smoke test; test suites again
#   5. full rollback in reverse (proposal rollbacks, then scripts/db/rollback-web.sql) → state must equal the baseline
# Never touches production. Usage: go-live-dry-run.sh   (rebuilds prod-replica on port 54330)
set -euo pipefail
cd "$(dirname "$0")/../.."
URL="postgresql://postgres:postgres@localhost:54330/postgres"
P=(psql "$URL" -X -A -F ' ' -t -v ON_ERROR_STOP=1 -q)
ms() { date +%s%3N; }
section() { echo; echo "== $*"; }

section "1. fresh production-schema replica"
scripts/db/build-replica.sh 2>&1 | grep -E "fingerprint|rows match|rows differ|DIFF" | sed 's/^/   /'
base=$("${P[@]}" -f scripts/db/state.sql | sed '/^$/d')
echo "   baseline state captured ($(echo "$base" | wc -l) rows)"

section "2. website migrations (production-safe timeouts)"
SHARED_LOCKS="select coalesce(string_agg(distinct n.nspname || '.' || c.relname || ':' || l.mode, ', '), 'none')
  from pg_locks l join pg_class c on c.oid = l.relation join pg_namespace n on n.oid = c.relnamespace
  where l.pid = pg_backend_pid() and n.nspname in ('public', 'b2b', 'b2c', 'catalog', 'cron') and c.relname not like 'web\\_%'
    and c.relkind in ('r', 'p', 'm') and l.mode <> 'AccessShareLock'"
total=0
for f in $(ls supabase/migrations/*.sql | grep -v '/00000000000000_'); do
  t0=$(ms)
  locks=$("${P[@]}" -1 -c "set local lock_timeout = '5s'; set local statement_timeout = '5min';" -f "$f" -c "$SHARED_LOCKS" | tail -1)
  t=$(( $(ms) - t0 )); total=$(( total + t ))
  printf "   %-45s %6d ms   stronger locks on shared tables: %s\n" "$(basename "$f")" "$t" "$locks"
done
echo "   total: $total ms"

section "3. tests on the replica"
scripts/db/test.sh "$URL" 2>&1 | sed 's/^/   /'
scripts/db/check-shared-unchanged.sh "$URL" 2>&1 | sed 's/^/   /'

section "4. shared proposals in go-live order"
ORDER="s07_b2b_routing_web_leads s05_b2b_consent_texts_web s01_lead_intake_email_verified s04_w2_prompts_channel_web s06_unaccent s02_w2_messages_channel s03_shared_taxonomy"
for name in $ORDER; do
  id=${name%%_*}; smoke_sql="supabase/migrations-shared/tests/$id.test.sql"
  t0=$(ms)
  "${P[@]}" -1 -c "set local lock_timeout = '5s'; set local client_min_messages = warning;" -f "supabase/migrations-shared/$name.sql" >/dev/null
  took=$(( $(ms) - t0 ))
  smoke="no smoke test (data/extension change)"
  if [ -e "$smoke_sql" ]; then
    { echo "begin;"; echo "\\i $smoke_sql"; echo "rollback;"; } | "${P[@]}" >/dev/null 2>&1 && smoke="smoke test passed" || { echo "   FAIL smoke $name"; exit 1; }
  fi
  printf "   %-35s %5d ms   %s\n" "$name" "$took" "$smoke"
done
echo "   test suites with every proposal applied:"
scripts/db/test.sh "$URL" 2>&1 | sed 's/^/     /'

section "5. full rollback (reverse order) → baseline"
for name in $(echo "$ORDER" | tr ' ' '\n' | tac); do
  "${P[@]}" -1 -f "supabase/migrations-shared/$name.rollback.sql" >/dev/null
  echo "   rolled back $name"
done
t0=$(ms)
"${P[@]}" -f scripts/db/rollback-web.sql >/dev/null
echo "   rolled back website objects ($(( $(ms) - t0 )) ms)"
after=$("${P[@]}" -f scripts/db/state.sql | sed '/^$/d')
if [ "$after" == "$base" ]; then
  echo "   state after full rollback == baseline (production fingerprint, shared data, extensions, cron jobs)"
else
  echo "   STATE DIFFERS FROM BASELINE:"; diff <(echo "$base") <(echo "$after") | head -20; exit 1
fi
echo; echo "DRY RUN PASSED"
