#!/usr/bin/env bash
# Full dump of production, taken before any change to it (spec §2). Target: ONE_PROD_DB_URL, never printed.
# Writes a custom-format archive outside the repository (ONE_DUMP_DIR, default ~/eduwit-one-dumps): it holds
# personal data and is never committed. Checks that pg_dump's major version is at least the server's (D-022), verifies
# the archive with pg_restore --list, writes <archive>.sha256, and prints the path to record in DECISIONS.md.
# Read-only on the database. Usage: scripts/db/dump.sh
set -euo pipefail

here="$(cd "$(dirname "$0")/../.." && pwd)"
if [ "${ONE_DB_TARGET:-}" != production ]; then
  exec node "$here/scripts/db/with-db.ts" ONE_PROD_DB_URL "$0" "$@"
fi

server_major="$(psql -X -At -c 'show server_version_num' 2>/dev/null | cut -c1-2)" || { echo "could not connect (details withheld)"; exit 1; }
tool_major="$(pg_dump --version | grep -oE '[0-9]+' | head -1)"
[ "$tool_major" -ge "$server_major" ] || { echo "refused: pg_dump $tool_major cannot dump server $server_major; install pg_dump $server_major"; exit 1; }

dir="${ONE_DUMP_DIR:-$HOME/eduwit-one-dumps}"
mkdir -p "$dir" && chmod 700 "$dir"
case "$(cd "$dir" && pwd)/" in "$(cd "$here/.." && pwd)"/*) echo "refused: the dump directory is inside the repository"; exit 2 ;; esac
file="$dir/production-$(date -u +%Y%m%dT%H%MZ).dump"

# pg_dump's messages go to a file beside the archive, never to the terminal: they can quote connection details.
if ! pg_dump -Fc --no-password --file "$file" 2>"$file.err"; then
  echo "pg_dump failed ($(wc -l < "$file.err") lines in $file.err, which stays local)"; exit 1
fi
rm -f "$file.err"
entries="$(pg_restore --list "$file" | grep -cv '^;')"
[ "$entries" -gt 0 ] || { echo "the archive lists no entries"; exit 1; }
(cd "$dir" && sha256sum "$(basename "$file")" > "$(basename "$file").sha256")
echo "DUMP OK $file ($entries entries, $(du -h "$file" | cut -f1), sha256 $(cut -c1-16 < "$file.sha256")…)"
