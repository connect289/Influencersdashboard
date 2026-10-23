#!/usr/bin/env bash
# The phase 4 click-through (D-064), entirely local: a throwaway Postgres cluster built as scripts/db/local-test.sh
# builds it (stubs, every migration between catalogue fingerprints), e2e/fixture.sql, the Supabase shim
# (e2e/shim.ts), the production build of web/ on http://localhost:3300, then e2e/click-through.ts in Chromium.
# It never reads a Supabase key from the environment: the keys are made for the run and die with it.
# Output (screenshots, report.json) in e2e/out/. Usage: e2e/run.sh
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
out="$here/e2e/out"
work="$(mktemp -d)"
port=55441
bin="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)"
as_server() { if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi; }
[ "$(id -u)" = 0 ] && chown postgres "$work"
pids=()
cleanup() {
  # Each background piece runs in its own process group (setsid), so npx's child server stops with it.
  for p in "${pids[@]}"; do kill -- "-$p" 2>/dev/null || kill "$p" 2>/dev/null || true; done
  as_server "$bin/pg_ctl" -D "$work/data" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

as_server "$bin/initdb" -D "$work/data" -U supabase_admin --auth=trust >/dev/null
as_server "$bin/pg_ctl" -D "$work/data" -o "-k $work -p $port -c listen_addresses=''" -l "$work/log" -w start >/dev/null
q() { local role="$1"; shift; psql -X -q -h "$work" -p "$port" -U "$role" -v ON_ERROR_STOP=1 "$@"; }
q supabase_admin -d postgres -c "create database rehearsal" >/dev/null
q supabase_admin -d rehearsal -1 -f "$here/supabase/tests/local/00_platform_stubs.sql" >/dev/null
q postgres -d rehearsal -1 -f "$here/supabase/tests/local/01_app_stubs.sql" >/dev/null
for f in $(ls "$here"/supabase/migrations/[0-9][0-9][0-9][0-9]_*.sql | grep -v '\.rollback\.sql$' | sort); do
  q postgres -d rehearsal -1 -f "$here/scripts/db/fp-before.sql" -f "$f" -f "$here/scripts/db/fp-after.sql" >/dev/null
done
q supabase_admin -d rehearsal -f "$here/e2e/fixture.sql" >/dev/null 2>&1 || { q supabase_admin -d rehearsal -f "$here/e2e/fixture.sql" 2>&1 | grep -v NOTICE; exit 1; }
echo "database ready (migrations and fixture)"

export E2E_DB_URL="postgresql://supabase_admin@/rehearsal?host=$work&port=$port"
export E2E_JWT_SECRET="$(node -e 'process.stdout.write(require("crypto").randomBytes(32).toString("hex"))')"
export E2E_SHIM_PORT=54999
keys="$(node "$here/e2e/keys.ts")"
eval "$keys" # exports ONE_SUPABASE_ANON_KEY, ONE_SUPABASE_SERVICE_KEY

export E2E_RPC_LOG="$work/rpc.jsonl"
setsid node "$here/e2e/shim.ts" > "$work/shim.log" 2>&1 & pids+=($!)
for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$E2E_SHIM_PORT/" && break; sleep 0.2; done

# A copy of web/ (its node_modules linked), so a build elsewhere in the repository cannot change what is served.
mkdir -p "$work/web"
tar -C "$here/web" --exclude=./node_modules --exclude=./.next -cf - . | tar -C "$work/web" -xf -
ln -s "$here/web/node_modules" "$work/web/node_modules"
cd "$work/web"
export ONE_SUPABASE_URL="http://127.0.0.1:$E2E_SHIM_PORT"
export ONE_INTERNAL_KEY="$(node -e 'process.stdout.write(require("crypto").randomBytes(24).toString("hex"))')"
unset SUPABASE_SERVICE_ROLE_KEY SUPABASE_URL SUPABASE_ANON_KEY
npx next build >/dev/null
if curl -s -o /dev/null "http://localhost:3300/login"; then echo "refused: something already listens on port 3300"; exit 1; fi
setsid npx next start -p 3300 > "$work/next.log" 2>&1 & pids+=($!)
for _ in $(seq 100); do curl -s -o /dev/null "http://localhost:3300/login" && break; sleep 0.3; done
echo "app on http://localhost:3300"

mkdir -p "$out"
status=0
E2E_OUT="$out" E2E_BASE="http://localhost:3300" node "$here/e2e/click-through.ts" || status=$?
cp "$work/rpc.jsonl" "$out/rpc.jsonl" 2>/dev/null || true
[ "$status" = 0 ] || { echo "--- shim log"; tail -40 "$work/shim.log"; echo "--- app log"; tail -60 "$work/next.log"; }
exit "$status"
