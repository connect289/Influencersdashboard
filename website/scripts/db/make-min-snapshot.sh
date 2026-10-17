#!/usr/bin/env bash
# Builds supabase/migrations/00000000000000_prod_snapshot.sql: the shared production objects the website depends on,
# extracted from the prod-replica container (exact production schema, no data). This file is the baseline of the
# local "fresh" database and is NEVER applied to production (the objects already exist there).
# Usage: scripts/db/make-min-snapshot.sh   (requires the prod-replica container: scripts/db/build-replica.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=supabase/migrations/00000000000000_prod_snapshot.sql
R="docker exec -i prod-replica"

TABLES=(
  public.catalog_universities public.catalog_programs public.catalog_synonyms
  public.student_leads public.touchpoints public.w2_trusted
  public.w2_meta public.w2_search_cache public.w2_prompts public.w2_learnings public.w2_kb_docs public.w2_kb_chunks
  public.w2_messages public.w2_conversations
  b2b.allocations
)
FUNCS=(
  public.crm_norm_phone public.crm_find_lead public.w2_is_test public.w2_crm_owned public.lead_intake
  public.student_leads_touch public.student_leads_bulk_delete_guard
  public.w2_fee_sanity public.catalog_programs_fee_check public.w2_bump
  public.w2_build_prompt public.w2_catalog_index public.w2_search_programs public.w2_search_programs_cached public.w2_kb_search
)

{
  echo "-- ====================================================================================================================="
  echo "-- Read-only snapshot of the SHARED production objects the website depends on, extracted from prod-replica"
  echo "-- (fingerprint-identical to production $(date -u +%Y-%m-%d)). Baseline for the local fresh database only."
  echo "-- NEVER apply to production: these objects already exist there and belong to Witty / the CRMs."
  echo "-- Regenerate: scripts/db/make-min-snapshot.sh"
  echo "-- ====================================================================================================================="
  echo "create schema if not exists b2b;"
  echo "create extension if not exists pg_trgm with schema public;"
  echo "create extension if not exists vector with schema public;"
  echo "create extension if not exists pgcrypto with schema extensions;"
  echo
  # Functions first that tables reference in defaults/triggers are created after tables; plpgsql bodies are not checked
  # at creation time, so order is: tables (without triggers) -> functions -> triggers/policies (pg_dump post-data).
  args=(); for t in "${TABLES[@]}"; do args+=(-t "$t"); done
  $R pg_dump -U postgres -d postgres --schema-only --no-owner --no-privileges --section=pre-data "${args[@]}" \
    | grep -vE '^(SET |SELECT pg_catalog.set_config|--|$)' | grep -v '^[\\]' | sed -E 's/^CREATE SCHEMA/-- CREATE SCHEMA/'
  echo
  for f in "${FUNCS[@]}"; do
    $R psql -U postgres -d postgres -At -c "select string_agg(pg_get_functiondef(p.oid) || ';', E'\n\n') from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname || '.' || p.proname = '$f'"
    echo
  done
  $R pg_dump -U postgres -d postgres --schema-only --no-owner --no-privileges --section=post-data "${args[@]}" \
    | grep -vE '^(SET |SELECT pg_catalog.set_config|--|$)' | grep -v '^[\\]' \
    | python3 scripts/db/filter-post-data.py "$(IFS=,; echo "${TABLES[*]}")" "$(IFS=,; echo "${FUNCS[*]}")"
  echo
  echo "-- Production grants on lead_intake (service_role only)."
  echo "revoke all on function public.lead_intake(jsonb) from public, anon, authenticated;"
  echo "grant execute on function public.lead_intake(jsonb) to service_role;"
} > "$OUT"
echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
