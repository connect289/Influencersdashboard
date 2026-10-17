#!/usr/bin/env bash
# Proves the website's migrations changed no shared object: fingerprints the database with every web_* object excluded
# and compares it with production's stored fingerprint (scripts/db/fingerprint.prod.txt).
# Usage: check-shared-unchanged.sh [database-url]   (default: prod-replica after apply-web-migrations.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
URL="${1:-postgresql://postgres:postgres@localhost:54330/postgres}"
SQL=$(sed -e 's/^from items group by nspname, kind order by/from items where key not like '"'"'web\\_%'"'"' and key not like '"'"'% web\\_%'"'"' group by nspname, kind order by/' scripts/db/fingerprint.sql)
diff <(psql "$URL" -X -A -F ' ' -t -c "$SQL" | sed '/^$/d') <(sed '/^$/d' scripts/db/fingerprint.prod.txt) \
  && echo "shared objects unchanged: all rows match production" \
  || { echo "SHARED OBJECTS CHANGED (rows above differ from production)"; exit 1; }
