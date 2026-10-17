#!/usr/bin/env bash
# Applies the website's own migrations (not the 00000000000000 snapshot) to a database, in order, stopping on the first
# error — used for the "copy of the production schema" gate on prod-replica. Usage: apply-web-migrations.sh <url>
set -euo pipefail
cd "$(dirname "$0")/../.."
URL="${1:-postgresql://postgres:postgres@localhost:54330/postgres}"
for f in $(ls supabase/migrations/*.sql | grep -v '/00000000000000_'); do
  psql "$URL" -v ON_ERROR_STOP=1 -q -f "$f" >/dev/null
  echo "applied $(basename "$f")"
done
