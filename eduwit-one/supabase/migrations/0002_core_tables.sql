-- 0002 core tables of schema one (spec §5). RLS on every table with no policies: reached only through one.*
-- functions, the service role, or the reader's SELECT. Status columns are constrained (spec §16.4).

create domain one.severity as text check (value in ('P1', 'P2', 'P3'));

create table one.apps (
  key text primary key check (key in ('witty', 'b2b', 'b2c', 'web', 'influencer', 'one', 'platform', 'catalogue', 'integrity')),
  name text not null,
  host_url text,
  health_rpc text,
  health_url text,
  admin_url text,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table one.checks (
  id text primary key check (id ~ '^[A-Z0-9]+(-[A-Za-z0-9:._]+)+$'),
  app text not null references one.apps (key),
  title text not null,
  description text,
  kind text not null check (kind in ('sql', 'rpc', 'http', 'heartbeat', 'test', 'integrity')),
  -- Only migrations write sql (the service role has no UPDATE on it). It must be one read-only statement that
  -- returns one row (ok boolean, value jsonb); the constraint is defence in depth, not the boundary.
  sql text check (sql is null or (sql ~* '^\s*(select|with)\M' and position(';' in sql) = 0
                  and sql !~* '\m(insert|update|delete|truncate|alter|drop|create|grant|revoke|copy|call|perform|vacuum|reindex|refresh|lock|set|reset|notify)\M')),
  severity one.severity not null,
  cadence_s integer not null check (cadence_s between 60 and 604800),
  threshold jsonb not null default '{}',
  auto_fix_id text,
  open_after integer not null default 1 check (open_after between 1 and 60),
  resolve_after integer not null default 3 check (resolve_after between 1 and 60),
  tags text[] not null default '{}',
  enabled boolean not null default true,
  disabled_reason text check (disabled_reason is null or disabled_reason ~ '^(setup|blocked|owner|builder):[a-z0-9_.:-]+$'),
  -- Name resolution while the check runs. Empty by default; 'public, pg_temp' only for checks that call an app's
  -- invoker-rights function written with unqualified names (D-042). No other value is accepted.
  search_path text not null default '' check (search_path in ('', 'public, pg_temp')),
  muted_until timestamptz,
  created_by text not null default 'seed',
  updated_by text not null default 'seed',
  version integer not null default 1,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (kind not in ('sql', 'integrity') or sql is not null),
  check (enabled or disabled_reason is not null)
);

-- Per-check runtime state; single writer: one.evaluate().
create table one.check_state (
  check_id text primary key references one.checks (id) on delete cascade,
  last_ran_at timestamptz,
  last_status text check (last_status in ('ok', 'fail', 'error', 'source_missing', 'skipped')),
  last_started_at timestamptz,
  consecutive_fail integer not null default 0,
  consecutive_ok integer not null default 0,
  created_at timestamptz not null default now()
);

create table one.results (
  id bigint generated always as identity primary key,
  check_id text not null references one.checks (id) on delete cascade,
  ran_at timestamptz not null default now(),
  status text not null check (status in ('ok', 'fail', 'error', 'source_missing', 'skipped')),
  ok boolean generated always as (status = 'ok') stored,
  value jsonb,
  duration_ms integer,
  error text,
  created_at timestamptz not null default now()
);
create index results_check_time_idx on one.results (check_id, ran_at desc);
create index results_time_idx on one.results (ran_at);

create table one.incidents (
  id bigint generated always as identity primary key,
  check_id text not null references one.checks (id),
  app text not null references one.apps (key),
  severity one.severity not null,
  title text not null,
  opened_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  occurrences integer not null default 1,
  reopened_count integer not null default 0,
  acknowledged_at timestamptz,
  acknowledged_by text,
  resolved_at timestamptz,
  resolved_by text,
  resolution text check (resolution is null or resolution in ('recovered', 'fixed', 'false_positive', 'accepted', 'superseded', 'manual')),
  resolution_note text,
  evidence jsonb not null default '{}',
  first_evidence jsonb not null default '{}',
  summary text,
  root_cause text,
  alert_state text not null default 'pending' check (alert_state in ('pending', 'sent', 'escalated_1', 'escalated_2', 'muted', 'suppressed', 'digest', 'none')),
  -- What the incident is about, for checks that cover many things (jobs, partners): a new subject alerts again (D-043).
  subjects text[] not null default '{}',
  -- Bumped each time the incident is routed (open, reopen, escalation, new subject); part of every delivery key.
  alert_seq integer not null default 0,
  parent_id bigint references one.incidents (id),
  tags text[] not null default '{}',
  created_at timestamptz not null default now(),
  check ((resolved_at is null) = (resolution is null))
);
create unique index incidents_one_open_per_check on one.incidents (check_id) where resolved_at is null;
create index incidents_open_idx on one.incidents (severity, opened_at desc) where resolved_at is null;

create table one.actions (
  id bigint generated always as identity primary key,
  fix_id text not null,
  incident_id bigint references one.incidents (id),
  app text not null references one.apps (key),
  target jsonb not null default '{}',
  dry_run boolean not null,
  status text not null check (status in ('planned', 'done', 'failed', 'reverted', 'skipped')),
  result jsonb not null default '{}',
  idempotency_key text unique,
  ran_at timestamptz not null default now(),
  ran_by text not null,
  created_at timestamptz not null default now()
);
create index actions_time_idx on one.actions (ran_at desc);

create table one.proposals (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('fix', 'feature', 'config', 'cleanup')),
  app text not null references one.apps (key),
  title text not null,
  rationale text not null,
  evidence jsonb not null default '{}',
  change jsonb not null default '{}',
  simulation jsonb,
  risk text not null check (risk in ('low', 'medium', 'high')),
  source text not null check (source in ('ai', 'test', 'check', 'person', 'builder')),
  source_key text unique,
  model text,
  status text not null default 'open' check (status in ('open', 'approved', 'rejected', 'applied', 'expired', 'snoozed')),
  incident_id bigint references one.incidents (id),
  decided_by text,
  decided_at timestamptz,
  decision_note text,
  applied_at timestamptz,
  check_due_at timestamptz,
  check_result jsonb,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  check (status not in ('approved', 'rejected', 'applied') or decided_by is not null)
);

create table one.briefs (
  id bigint generated always as identity primary key,
  for_date date not null,
  tier text,
  body_md text not null,
  stats jsonb not null default '{}',
  model text,
  cost_usd numeric(10, 4),
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index briefs_date_idx on one.briefs (for_date desc);

create table one.events (
  id bigint generated always as identity primary key,
  app text not null,
  source_table text not null,
  source_id text not null,
  occurred_at timestamptz not null,
  type text not null,
  lead_id bigint,
  actor_type text,
  actor_id text,
  payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (app, source_table, source_id)
);
create index events_time_idx on one.events (occurred_at desc);
create index events_lead_idx on one.events (lead_id, occurred_at) where lead_id is not null;

-- Watermarks are rows, not settings: they move every minute and must not version the settings table (spec §16.5).
create table one.event_watermarks (
  source text primary key,
  last_id bigint,
  last_at timestamptz,
  last_status text check (last_status in ('ok', 'source_missing', 'error')),
  last_error text,
  rows_copied bigint not null default 0,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table one.heartbeats (
  component text primary key,
  last_ok_at timestamptz,
  last_error_at timestamptz,
  last_error text,
  detail jsonb not null default '{}',
  expected_interval_s integer not null check (expected_interval_s between 30 and 604800),
  created_at timestamptz not null default now()
);

create table one.deliveries (
  id bigint generated always as identity primary key,
  incident_id bigint references one.incidents (id),
  channel text not null check (channel in ('email', 'whatsapp', 'github')),
  recipient text not null,
  kind text not null default 'alert' check (kind in ('alert', 'escalation', 'storm', 'digest', 'brief', 'test')),
  escalation_level integer not null default 0 check (escalation_level between 0 and 10),
  status text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed', 'suppressed', 'muted')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  sent_at timestamptz,
  error text,
  idempotency_key text not null unique,
  created_at timestamptz not null default now()
);
create index deliveries_pending_idx on one.deliveries (next_attempt_at) where status in ('pending', 'failed');

create table one.tests (
  id text primary key check (id ~ '^T-[A-Z0-9-]+$'),
  app text not null references one.apps (key),
  title text not null,
  steps jsonb not null default '[]',
  schedule text not null,
  timeout_s integer not null default 300,
  severity one.severity not null,
  enabled boolean not null default false,
  disabled_reason text,
  updated_by text not null default 'seed',
  created_at timestamptz not null default now(),
  check (enabled or disabled_reason is not null)
);

create table one.test_runs (
  id bigint generated always as identity primary key,
  test_id text not null references one.tests (id),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  ok boolean,
  step_results jsonb not null default '[]',
  artefacts jsonb not null default '{}',
  purged_at timestamptz,
  idempotency_key text unique,
  created_at timestamptz not null default now()
);
create index test_runs_test_idx on one.test_runs (test_id, started_at desc);

create table one.ai_tasks (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('classify', 'triage', 'explain', 'brief', 'propose_fix', 'propose_feature', 'ask', 'test_author')),
  input jsonb not null default '{}',
  model_hint text check (model_hint is null or model_hint in ('quick', 'regular', 'deep')),
  status text not null default 'pending' check (status in ('pending', 'claimed', 'done', 'failed', 'deferred', 'cancelled')),
  claimed_by text,
  claimed_at timestamptz,
  result jsonb,
  error text,
  attempts integer not null default 0,
  idempotency_key text unique,
  incident_id bigint references one.incidents (id),
  created_at timestamptz not null default now()
);
create index ai_tasks_pending_idx on one.ai_tasks (created_at) where status = 'pending';

create table one.ai_calls (
  id bigint generated always as identity primary key,
  task_id bigint references one.ai_tasks (id),
  provider text not null,
  model text not null,
  purpose text not null,
  prompt_version text,
  input_tokens integer,
  output_tokens integer,
  cache_read integer,
  cost_usd numeric(10, 5),
  cost_inr numeric(10, 2),
  latency_ms integer,
  ok boolean not null,
  error text,
  created_at timestamptz not null default now()
);
create index ai_calls_time_idx on one.ai_calls (created_at);

-- Same shape as b2b.settings. actor 'seed' marks a row a seed may still overwrite (spec §16.8).
create table one.settings (
  key text primary key,
  value jsonb not null,
  version integer not null default 1,
  updated_at timestamptz not null default now(),
  actor text not null default 'seed',
  created_at timestamptz not null default now()
);

create table one.settings_versions (
  id bigint generated always as identity primary key,
  key text not null,
  version integer not null,
  value jsonb not null,
  reason text,
  actor text not null,
  at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (key, version)
);

create table one.users (
  user_id uuid primary key,
  email text not null unique check (email ~* '^[^@\s]+@eduwit\.in$'),
  role text not null check (role in ('owner', 'engineer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table one.audit (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  actor text not null,
  action text not null,
  target text,
  before jsonb,
  after jsonb,
  request_id text,
  created_at timestamptz not null default now()
);
create index audit_time_idx on one.audit (at desc);

create table one.privilege_baseline (
  fn text primary key,
  schema text not null,
  roles text[] not null,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  acknowledged boolean not null default false,
  acknowledged_by text,
  created_at timestamptz not null default now()
);

-- Snapshots that integrity checks compare against (lead_intake hash, student_leads columns, money row counts).
create table one.baselines (
  key text primary key,
  value jsonb not null,
  captured_at timestamptz not null default now(),
  acknowledged_by text,
  created_at timestamptz not null default now()
);

-- Mutes and maintenance windows: incidents still record, deliveries are held (spec §9).
create table one.mutes (
  id bigint generated always as identity primary key,
  target_type text not null check (target_type in ('check', 'app')),
  target text not null,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  reason text not null,
  created_by text not null,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

-- One row per tick or nightly run. The unique bucket makes one.tick() idempotent within a minute (spec §16.5).
create table one.runs (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('tick', 'nightly')),
  bucket timestamptz not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  report jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (kind, bucket)
);

-- Grants for every object in schema one: closed to anon and authenticated, full to the service role (the app's
-- one.* writer), SELECT to the reader. Re-run at the end of every migration that adds objects.
create or replace procedure one.apply_grants()
language plpgsql
set search_path = ''
as $$
declare
  t record;
begin
  for t in select c.oid::regclass as rel, c.relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'one' and c.relkind in ('r', 'p', 'v', 'm')
  loop
    if t.relkind in ('r', 'p') then
      execute format('alter table %s enable row level security', t.rel);
    end if;
    execute format('revoke all on %s from public, anon, authenticated', t.rel);
    execute format('grant all on %s to service_role', t.rel);
    execute format('grant select on %s to eduwit_one_reader', t.rel);
  end loop;
  execute 'grant usage on all sequences in schema one to service_role';
  execute 'revoke execute on all functions in schema one from public, anon, authenticated';
  execute 'revoke execute on all procedures in schema one from public, anon, authenticated';
  -- Only migrations write a check's rule: the service role may change operational columns, never insert a check,
  -- change its sql or kind, or delete it (a check's sql runs as the database owner inside one.tick()).
  execute 'revoke insert, update, delete, truncate on one.checks from service_role';
  execute 'grant update (enabled, disabled_reason, muted_until, severity, cadence_s, threshold, open_after, resolve_after, updated_by, updated_at, version) on one.checks to service_role';
end $$;

call one.apply_grants();
