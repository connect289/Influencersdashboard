#!/usr/bin/env bash
# Builds "prod-replica": a local Postgres with the SCHEMA of the production Supabase project xlseqwgyjuqhktrguhyc
# (no production data), for testing the website's migrations against it.
#
#   website/scripts/db/build-replica.sh            # drop + recreate container prod-replica on localhost:54330
#   PORT=54331 NAME=my-replica website/scripts/db/build-replica.sh
#
# Connect: postgresql://postgres:postgres@localhost:54330/postgres
#
# What it does (idempotent: the container is always dropped and recreated):
#   1. docker run supabase/postgres:17.11.0.004 (same image as the website's local stack), with HTTP(S) proxy variables
#      pointing at a dead port so pg_net can never reach the internet.
#   2. Supabase's auth and storage schemas: runs GoTrue's own migrations (supabase/gotrue image) and storage-api's own
#      migrations (supabase/storage-api image) against it, exactly as a hosted project gets them.
#   3. Prelude: the extensions production has (pg_cron, pg_net, vector, pg_trgm, pgmq) and supabase_migrations.
#   4. Every migration in production's order (website/scripts/db/manifest.txt, taken from production's
#      supabase_migrations.schema_migrations), with psql -v ON_ERROR_STOP=1. Objects production has that are not in the
#      repo come from website/supabase/prod-snapshot/replica-extras.sql (one section per production migration).
#      Each recorded migration is written to supabase_migrations.schema_migrations with production's version and name.
#   5. Stubs: every pg_cron job is deactivated; vault secrets the migrations create stay placeholders.
#   6. Prints a summary (and the fidelity fingerprint, see fingerprint.sql).
set -euo pipefail

NAME="${NAME:-prod-replica}"
PORT="${PORT:-54330}"
IMAGE="${IMAGE:-supabase/postgres:17.11.0.004}"
GOTRUE_IMAGE="${GOTRUE_IMAGE:-supabase/gotrue:v2.197.0}"
STORAGE_IMAGE="${STORAGE_IMAGE:-supabase/storage-api:v1.82.1}"
PW=postgres
JWT=super-secret-jwt-token-with-at-least-32-characters-long

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MANIFEST="$HERE/manifest.txt"
EXTRAS="$ROOT/website/supabase/prod-snapshot/replica-extras.sql"
LOG="$(mktemp -t prod-replica.XXXXXX.log)"

say() { printf '== %s\n' "$*"; }
die() { printf 'FAILED: %s\n' "$*" >&2; exit 1; }
# psql inside the container (no host psql needed). Extra args are passed through; SQL comes from stdin or -c.
psql_as() { local user="$1"; shift; docker exec -i -e PGPASSWORD="$PW" -e PGOPTIONS='-c client_min_messages=warning' "$NAME" \
  psql -h 127.0.0.1 -U "$user" -d postgres -X -q -v ON_ERROR_STOP=1 "$@"; }
pg()    { psql_as postgres "$@"; }
admin() { psql_as supabase_admin "$@"; }

command -v docker >/dev/null || die "docker not found"
[ -f "$MANIFEST" ] || die "missing $MANIFEST"

say "recreating container $NAME on port $PORT ($IMAGE)"
docker rm -f "$NAME" >/dev/null 2>&1 || true
# The proxy variables send any libcurl (pg_net) request to a closed local port: nothing leaves the container.
docker run -d --name "$NAME" -p "$PORT:5432" -e POSTGRES_PASSWORD="$PW" \
  -e http_proxy=http://127.0.0.1:9 -e https_proxy=http://127.0.0.1:9 -e HTTP_PROXY=http://127.0.0.1:9 \
  -e HTTPS_PROXY=http://127.0.0.1:9 -e ALL_PROXY=http://127.0.0.1:9 -e no_proxy= -e NO_PROXY= \
  "$IMAGE" >/dev/null
# The image's entrypoint starts a temporary server for its init scripts, then restarts: wait for the real one.
for i in $(seq 1 120); do
  if docker logs "$NAME" 2>&1 | grep -q 'PostgreSQL init process complete' \
     && docker exec "$NAME" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1 \
     && pg -c 'select 1' >/dev/null 2>&1; then break; fi
  [ "$i" = 120 ] && { docker logs "$NAME" | tail -30; die "postgres did not start"; }
  sleep 1
done

say "auth schema: GoTrue migrations ($GOTRUE_IMAGE)"
docker run --rm --network "container:$NAME" -e GOTRUE_DB_DRIVER=postgres \
  -e "GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin:$PW@127.0.0.1:5432/postgres" \
  -e GOTRUE_JWT_SECRET="$JWT" -e API_EXTERNAL_URL=http://localhost:9999 -e GOTRUE_SITE_URL=http://localhost:3000 \
  -e GOTRUE_API_HOST=127.0.0.1 -e PORT=9999 "$GOTRUE_IMAGE" gotrue migrate >>"$LOG" 2>&1 || { tail -20 "$LOG"; die "gotrue migrate"; }

say "storage schema: storage-api migrations ($STORAGE_IMAGE)"
docker rm -f "$NAME-storage-migrate" >/dev/null 2>&1 || true
docker run -d --name "$NAME-storage-migrate" --network "container:$NAME" \
  -e DATABASE_URL="postgres://supabase_storage_admin:$PW@127.0.0.1:5432/postgres" -e ANON_KEY=stub -e SERVICE_KEY=stub \
  -e AUTH_JWT_SECRET="$JWT" -e PGRST_JWT_SECRET="$JWT" -e STORAGE_BACKEND=file -e FILE_STORAGE_BACKEND_PATH=/tmp/storage \
  -e TENANT_ID=stub -e REGION=local -e GLOBAL_S3_BUCKET=stub -e POSTGREST_URL=http://127.0.0.1:3000 \
  -e SERVER_PORT=5999 -e PORT=5999 "$STORAGE_IMAGE" >/dev/null
for i in $(seq 1 90); do
  docker logs "$NAME-storage-migrate" 2>&1 | grep -q 'Server listening' && break
  if [ "$i" = 90 ] || [ "$(docker inspect -f '{{.State.Running}}' "$NAME-storage-migrate" 2>/dev/null)" != true ]; then
    docker logs "$NAME-storage-migrate" 2>&1 | tail -20; docker rm -f "$NAME-storage-migrate" >/dev/null; die "storage migrations"; fi
  sleep 1
done
docker rm -f "$NAME-storage-migrate" >/dev/null
pg -c "select 1 from storage.buckets limit 1" >/dev/null || die "storage.buckets missing"

say "prelude: extensions and supabase_migrations (as production has them)"
admin <<'SQL'
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres with grant option;
grant all on all tables in schema cron to postgres with grant option;
grant all on all sequences in schema cron to postgres with grant option;
grant all on all functions in schema cron to postgres with grant option;
create extension if not exists pg_net with schema extensions;
create extension if not exists pgmq;
SQL
pg <<'SQL'
create extension if not exists pg_trgm with schema public;
create extension if not exists vector with schema public;
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (
  version text primary key, statements text[], name text, created_by text, idempotency_key text unique, rollback text[]);
SQL

# Prints one section of replica-extras.sql (between "-- @section <name>" and the next "-- @section").
extras_section() { awk -v s="$1" '/^-- @section /{on=($3==s); next} on' "$EXTRAS"; }

applied=0; recorded=0; skipped=0; n=0
say "applying migrations in production order"
# Line endings: production received some files with Windows (CRLF) line endings: the 8 Oct deploy.mjs batch (m24a to
# m31p, run from Windows) and the 16 Oct SQL-editor files. Their function bodies (prosrc) carry the \r, so the
# manifest flags them "crlf" and they are fed with CRLF here: the replica's prosrc then hashes exactly as production's.
as_crlf() { if [ "$1" = crlf ]; then sed 's/\r$//; s/$/\r/'; else cat; fi; }
while IFS="|" read -r -u 3 version name src eol; do
  case "$version" in ''|'#'*) continue;; esac
  n=$((n+1))
  if [ "$src" = "-" ]; then
    :   # recorded only: the previous file already holds this part
  elif [[ "$src" == extras:* ]]; then
    sec="${src#extras:}"
    body="$( [ -f "$EXTRAS" ] && extras_section "$sec" || true )"
    if printf '%s' "$body" | grep -q '^-- @skip'; then
      printf '   %-62s (recorded, not run: %s)\n' "$name" "$(printf '%s' "$body" | sed -n 's/^-- @skip \([^:]*\).*/\1/p' | head -1)"; skipped=$((skipped+1))
    elif [ -z "$(printf '%s' "$body" | grep -v '^\s*--' | tr -d '[:space:]')" ]; then
      printf '   %-62s (no extras section, skipped)\n' "$name"; skipped=$((skipped+1))
    else
      printf '   %-62s <- replica-extras.sql [%s]\n' "$name" "$sec"
      printf '%s\n' "$body" | as_crlf "$eol" | pg --single-transaction -f - >>"$LOG" 2>&1 || { tail -20 "$LOG"; die "$name (extras:$sec)"; }
      applied=$((applied+1))
    fi
  else
    f="$ROOT/$src"; [ -f "$f" ] || die "missing file $src"
    printf '   %-62s <- %s%s\n' "$name" "$src" "${eol:+ ($eol)}"
    # Files that manage their own transaction (begin; ... commit;) are run as they are.
    if grep -qiE '^\s*begin\s*;' "$f"; then tx=(); else tx=(--single-transaction); fi
    as_crlf "$eol" <"$f" | pg "${tx[@]}" -f - >>"$LOG" 2>&1 || { tail -20 "$LOG"; die "$name ($src)"; }
    applied=$((applied+1))
  fi
  if [ "$version" != "-" ]; then
    pg -c "insert into supabase_migrations.schema_migrations(version, name) values ('$version', '$name') on conflict (version) do nothing" >/dev/null
    recorded=$((recorded+1))
  fi
done 3<"$MANIFEST"

say "stubs: deactivating every pg_cron job (jobs exist, none runs)"
pg -At -c "select count(*) from (select cron.alter_job(jobid, active := false) from cron.job) x" | sed 's/^/   jobs deactivated: /'

say "summary"
pg -At <<'SQL'
select format('   recorded migrations: %s (latest %s %s)', count(*), max(version),
              (select name from supabase_migrations.schema_migrations order by version desc limit 1))
  from supabase_migrations.schema_migrations;
select format('   %-8s tables %s, views %s, functions %s, policies %s, triggers %s', n.nspname,
  (select count(*) from pg_class c where c.relnamespace = n.oid and c.relkind in ('r','p')),
  (select count(*) from pg_class c where c.relnamespace = n.oid and c.relkind in ('v','m')),
  (select count(*) from pg_proc p where p.pronamespace = n.oid),
  (select count(*) from pg_policy po join pg_class c on c.oid = po.polrelid where c.relnamespace = n.oid),
  (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = n.oid and not t.tgisinternal))
from pg_namespace n where n.nspname in ('public','b2b','b2c','catalog') order by 1;
select format('   cron jobs %s (active %s), vault secrets %s, buckets %s', (select count(*) from cron.job),
  (select count(*) from cron.job where active), (select count(*) from vault.secrets), (select count(*) from storage.buckets));
SQL
printf '   files/sections applied: %s, extras skipped: %s, log: %s\n' "$applied" "$skipped" "$LOG"
# Fidelity: fingerprint.sql on the replica against production's output saved in fingerprint.prod.txt (17 Oct 2026; refresh it
# by running fingerprint.sql on production, read-only, whenever production gains migrations).
say "fingerprint: replica vs production (fingerprint.prod.txt)"
FP="$(pg -At -F ' ' <"$HERE/fingerprint.sql")"
if [ -f "$HERE/fingerprint.prod.txt" ]; then
  diffs=0
  while read -r sch kind n md5; do
    prod="$(awk -v s="$sch" -v k="$kind" '$1==s && $2==k {print $3" "$4}' "$HERE/fingerprint.prod.txt")"
    if [ "$prod" != "$n $md5" ]; then diffs=$((diffs+1)); printf '   DIFF  %-8s %-12s replica %s | production %s\n' "$sch" "$kind" "$n $md5" "${prod:-missing}"; fi
  done <<<"$FP"
  rows="$(printf '%s\n' "$FP" | grep -c .)"
  if [ "$diffs" = 0 ]; then printf '   all %s rows match production (public, b2b, b2c, catalog)\n' "$rows"; else printf '   %s of %s rows differ\n' "$diffs" "$rows"; fi
else
  printf '%s\n' "$FP"
fi
say "ready: postgresql://postgres:$PW@localhost:$PORT/postgres"
