#!/usr/bin/env bash
# Applies the B2B CRM migrations M24–M31p to a Supabase database, in order.
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
)
for f in "${FILES[@]}"; do
  echo "== $f"
  $P --single-transaction -f "$f"
  name=$(basename "$f" .sql)
  $P -c "insert into supabase_migrations.schema_migrations(version, name) values (to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'), '$name') on conflict do nothing;" >/dev/null 2>&1 || true
done
echo "== resuming b2b background jobs"
$P -c "select cron.alter_job(jobid, active := true) from cron.job where jobname like 'b2b-%';" >/dev/null
echo "== done. Routing stays OFF until the go-live checklist on Routing → Overview passes."
