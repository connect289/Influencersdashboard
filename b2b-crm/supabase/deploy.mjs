// Windows-friendly deploy for migrations M24 to M31p. Same steps as deploy.sh, written in Node.
// Usage (PowerShell), in this folder:
//   npm install pg --no-save
//   $env:DATABASE_URL = 'postgresql://postgres:PASSWORD@db.PROJECTREF.supabase.co:5432/postgres'
//   node deploy.mjs
import pg from 'pg';
import { readFileSync } from 'node:fs';
import { dirname, basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const url = process.env.DATABASE_URL;
if (!url) { console.error('Set DATABASE_URL first.'); process.exit(1); }
const here = dirname(fileURLToPath(import.meta.url));
const files = [
  'migrations/m24a_performance_stats.sql', 'migrations/m24b_route_score.sql', 'migrations/m24c_routing_segments_admin.sql',
  'migrations/m25a_ml_registry_features.sql', 'migrations/m25b_ml_training.sql', 'migrations/m25c_ml_admin.sql', 'pending/m25d_ml_training_rows_prune.sql',
  'migrations/m26a_ai_tools_simulation.sql', 'migrations/m26b_ai_worker_inbox.sql',
  'migrations/m27a_analytics_facts.sql', 'migrations/m27b_metric_layer.sql', 'migrations/m28a_dashboards.sql', 'migrations/m28b_alerts_schedules.sql',
  'migrations/m29a_reports.sql', 'migrations/m30a_autopilot_ask.sql', 'migrations/m30b_review_fixes.sql', 'pending/m30b_fact_views.sql',
  'migrations/m31a0_a3_allocation_columns.sql', 'migrations/m31a_a3_schema.sql', 'pending/m31a_guards.sql', 'migrations/m31b_a3_helpers.sql',
  'migrations/m31c_a3_stats.sql', 'migrations/m31d_a3_readiness.sql', 'migrations/m31e_a3_consent.sql', 'migrations/m31f_a3_route_engine.sql',
  'migrations/m31g_a3_attribution.sql', 'migrations/m31h_a3_intake.sql', 'migrations/m31i_a3_after_push.sql', 'pending/m31i_dispute_index.sql',
  'migrations/m31j_a3_b2c_contract.sql', 'migrations/m31k_a3_redecide.sql', 'migrations/m31l_a3_admin_reads.sql', 'migrations/m31m_a3_ai_ml.sql',
  'pending/m31n_facts.sql', 'migrations/m31o_a3_metrics.sql', 'migrations/m31p_partner_agreement.sql',
];
const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
await client.connect();
console.log('connected to', new URL(url).hostname);
let paused = false;
try {
  await client.query("select cron.alter_job(jobid, active := false) from cron.job where jobname like 'b2b-%'");
  paused = true; console.log('background jobs paused');
  for (const f of files) {
    const name = basename(f, '.sql');
    const done = await client.query("select 1 from supabase_migrations.schema_migrations where name = $1", [name]);
    if (done.rowCount) { console.log('skip (already applied)', name); continue; }
    process.stdout.write('applying ' + name + ' ... ');
    const sql = readFileSync(join(here, f), 'utf8');
    try {
      await client.query('begin');
      await client.query(sql);
      await client.query("insert into supabase_migrations.schema_migrations(version, name) values (to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'), $1)", [name]);
      await client.query('commit');
      console.log('ok');
    } catch (e) {
      await client.query('rollback').catch(() => {});
      console.log('FAILED'); console.error(e.message); throw e;
    }
  }
  console.log('all migrations applied. Routing stays OFF.');
} finally {
  if (paused) { await client.query("select cron.alter_job(jobid, active := true) from cron.job where jobname like 'b2b-%'").catch(e => console.error('could not resume jobs:', e.message)); console.log('background jobs resumed'); }
  await client.end();
}
