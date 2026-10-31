#!/usr/bin/env bash
# Applies the B2B CRM migrations M24–M34g to a Supabase database, in order (files already applied are skipped).
# Usage: DATABASE_URL='postgresql://postgres:...@db.<project>.supabase.co:5432/postgres' ./deploy.sh
# Run on STAGING first (mplbspysxmtohnlwpbti), then PRODUCTION (xlseqwgyjuqhktrguhyc). Routing stays off; nothing is sent.
set -euo pipefail
: "${DATABASE_URL:?set DATABASE_URL}"
cd "$(dirname "$0")"
P="psql $DATABASE_URL -v ON_ERROR_STOP=1 -q"
echo "== pausing b2b background jobs"
$P -c "select cron.alter_job(jobid, active := false) from cron.job where jobname like 'b2b-%';" >/dev/null
FILES=(
 migrations/m24a_performance_stats.sql migrations/m24b_route_score.sql migrations/m24c_routing_segments_admin.sql
 migrations/m25a_ml_registry_features.sql migrations/m25b_ml_training.sql migrations/m25c_ml_admin.sql pending/m25d_ml_training_rows_prune.sql
 migrations/m26a_ai_tools_simulation.sql migrations/m26b_ai_worker_inbox.sql
 migrations/m27a_analytics_facts.sql migrations/m27b_metric_layer.sql migrations/m28a_dashboards.sql migrations/m28b_alerts_schedules.sql
 migrations/m29a_reports.sql migrations/m30a_autopilot_ask.sql migrations/m30b_review_fixes.sql pending/m30b_fact_views.sql
 migrations/m31a0_a3_allocation_columns.sql migrations/m31a_a3_schema.sql pending/m31a_guards.sql migrations/m31b_a3_helpers.sql
 migrations/m31c_a3_stats.sql migrations/m31d_a3_readiness.sql migrations/m31e_a3_consent.sql migrations/m31f_a3_route_engine.sql
 migrations/m31g_a3_attribution.sql migrations/m31h_a3_intake.sql migrations/m31i_a3_after_push.sql pending/m31i_dispute_index.sql
 migrations/m31j_a3_b2c_contract.sql migrations/m31k_a3_redecide.sql migrations/m31l_a3_admin_reads.sql migrations/m31m_a3_ai_ml.sql
 pending/m31n_facts.sql migrations/m31o_a3_metrics.sql migrations/m31p_partner_agreement.sql
 migrations/m32a_a4_b2c_realtime_batch.sql migrations/m32b_a4_b2c_events_reads.sql migrations/m32c_a4_catalog.sql
  migrations/m33a_access_api_hardening.sql migrations/m33b_lead_workspace.sql migrations/m33c_data_protection_audit.sql
  migrations/m33d_referral_outcomes.sql migrations/m33e_email_partner_adapter.sql migrations/m33f_cron_history_performance.sql
  migrations/m33g_revoke_legacy_stage_function.sql migrations/m34a_definer_helper_access.sql migrations/m34b_ml_training_skipped.sql
  migrations/m34c_auth_failure_log_throttle.sql migrations/m34d_referral_outcomes_scoped.sql migrations/m34e_outbound_url_guard.sql
  migrations/m34f_ai_worker_auth.sql migrations/m34g_anonymise_internal_path.sql
)
for f in "${FILES[@]}"; do
  name=$(basename "$f" .sql)
  if [ -n "$($P -tAc "select 1 from supabase_migrations.schema_migrations where name = '$name'")" ]; then echo "== skip (already applied) $f"; continue; fi
  echo "== $f"
  $P --single-transaction -f "$f"
  name=$(basename "$f" .sql)
  $P -c "insert into supabase_migrations.schema_migrations(version, name) values (to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'), '$name') on conflict do nothing;" >/dev/null 2>&1 || true
done
echo "== resuming b2b background jobs"
$P -c "select cron.alter_job(jobid, active := true) from cron.job where jobname like 'b2b-%';" >/dev/null
echo "== done. Routing stays OFF until the go-live checklist on Routing → Overview passes."
