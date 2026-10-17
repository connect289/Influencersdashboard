#!/usr/bin/env bash
# Applies each proposed shared change (supabase/migrations-shared/*.sql) inside a transaction on the replica, runs a
# smoke query, and rolls back — proving the proposals apply cleanly to the production schema without keeping them.
set -uo pipefail
cd "$(dirname "$0")/../.."
URL="${1:-postgresql://postgres:postgres@127.0.0.1:54330/postgres}"
fail=0
for f in supabase/migrations-shared/*.sql; do
  [ -e "$f" ] || continue
  out=$( { echo "begin;"; cat "$f"; echo "select public.web_search('{\"q\":\"mba\"}') is not null as search_ok;"; echo "rollback;"; } | psql "$URL" -v ON_ERROR_STOP=1 -q -At 2>&1)
  if [ $? -eq 0 ]; then echo "ok    $(basename "$f") (applied in a transaction, rolled back)"; else echo "FAIL  $(basename "$f")"; echo "$out" | grep -E 'ERROR' | head -3; fail=1; fi
done
exit $fail
