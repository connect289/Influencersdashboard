#!/usr/bin/env bash
# Runs every supabase/tests/*.test.sql against a database (each file is wrapped in begin … rollback and raises on any
# failed check). Usage: scripts/db/test.sh [database-url]   (default: local Supabase stack)
set -uo pipefail
cd "$(dirname "$0")/../.."
URL="${1:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
fail=0
for f in supabase/tests/*.test.sql; do
  out=$(psql "$URL" -v ON_ERROR_STOP=1 -q -f "$f" 2>&1)
  if [ $? -eq 0 ]; then echo "ok    $(basename "$f")  $(echo "$out" | grep -o 'PASS [0-9]* checks' | tail -1)"; else echo "FAIL  $(basename "$f")"; echo "$out" | grep -E 'ERROR|FAILED' | head -5; fail=1; fi
done
exit $fail
