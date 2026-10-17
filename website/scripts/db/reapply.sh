#!/usr/bin/env bash
# Dev helper: re-applies one website migration file to the local DB without a full reset (drops the read model first
# so `create materialized view if not exists` rebuilds it). Usage: scripts/db/reapply.sh <migration.sql> [db-url]
set -euo pipefail
URL="${2:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
psql "$URL" -q -v ON_ERROR_STOP=1 -c "drop materialized view if exists public.web_offering_search cascade" -f "$1"
