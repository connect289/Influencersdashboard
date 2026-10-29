-- The Catalogue Engine (migrations 0022 and 0023, D-096): its app key; its five checks seeded off for Setup; each
-- check's verdict on stub ce tables, passing and failing; the Setup facts and the validation that switches the checks on;
-- Ask's app_status for it; and the event copy with and without ce.events (production has no schema ce before
-- 1 Nov 2026, as this cluster has none until section 3). Everything it creates it removes. Local test cluster only.
\set ON_ERROR_STOP 1
do $$ begin
  if current_database() <> 'rehearsal' or to_regclass('public.stub_health') is null then
    raise exception 'refused: this test creates and drops schema ce and runs only on the local test cluster';
  end if;
end $$;
create or replace function pg_temp.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'ASSERT FAILED: %', p_msg; end if;
end $$;
create or replace function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate;
end $$;
-- A check's statement exactly as one.run_check executes it (the check's empty search_path, one row expected), without
-- recording a result or touching an incident.
create or replace function pg_temp.ce(p_id text) returns jsonb language plpgsql set search_path = '' as $$
declare
  v_sql text;
  v_rows integer;
  v_ok boolean;
  v_value jsonb;
begin
  select c.sql into strict v_sql from one.checks c where c.id = p_id;
  execute format('select count(*)::int, bool_and(ok), (array_agg(value))[1] from (%s) q', v_sql) into v_rows, v_ok, v_value;
  return jsonb_build_object('rows', v_rows, 'ok', v_ok, 'value', v_value);
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text), pg_temp.ce(text) to postgres;
grant execute on function pg_temp.ok(boolean, text) to authenticated;
-- A signed-in owner, for the Apps panels (0024), as 90_ui_apps.sql makes one.
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in') on conflict do nothing;
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001') on conflict do nothing;
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner') on conflict do nothing;
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001', 'email_code')
on conflict do nothing;
create or replace function pg_temp.embed(p_panel text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000c1"}', true);
  set local role authenticated;
  v := one.ui_embed(p_panel);
  reset role;
  return v;
end $$;

-- 1. The app key and the catalogue -----------------------------------------------------------------------------------
select pg_temp.ok((select name = 'Catalogue Engine' from one.apps where key = 'catalogue_engine'), 'catalogue_engine is an app');
select pg_temp.ok(pg_temp.err($q$insert into one.apps (key, name) values ('catalogue_x', 'x')$q$) = '23514', 'an unlisted key is still refused');
select pg_temp.ok((select count(*) = 4 from one.checks where app = 'catalogue') and exists (select 1 from one.apps where key = 'catalogue'),
                  'the shared catalogue area keeps its key and its four checks');
select pg_temp.ok((select count(*) = 5 and bool_and(app = 'catalogue_engine' and kind = 'sql' and not enabled
                                                    and disabled_reason = 'setup:catalogue_engine' and search_path = '' and sql ~ '\mce\.')
                     from one.checks where id ~ '^CE-0[1-5]$'),
                  'CE-01 to CE-05 exist, read schema ce under the empty search_path and ship off for the Setup item');
select pg_temp.ok((select count(*) from one.checks where app = 'catalogue_engine') = 5, 'and the engine has no other check');
select pg_temp.ok((select string_agg(id || ':' || severity || ':' || cadence_s, ',' order by id) from one.checks where app = 'catalogue_engine')
                  = 'CE-01:P2:900,CE-02:P2:900,CE-03:P2:900,CE-04:P3:900,CE-05:P2:900', 'their severities and cadences');
select pg_temp.ok((one.run_check('CE-01') ->> 'status') = 'skipped' and not exists (select 1 from one.due_checks() d where d like 'CE-%'),
                  'an engine check that is off is skipped and never due');
select pg_temp.ok(exists (select 1 from jsonb_array_elements(one.setting('setup_catalog') -> 'items') i
                           where i ->> 'id' = 'catalogue_engine' and i ->> 'validate' = 'engine_schema' and i -> 'unblocks' ? 'CE-05'),
                  'the Setup item catalogue_engine is in the catalogue with its validator');

-- 2. Without schema ce (production until the engine is installed) ------------------------------------------------------
select one.setup_engine_facts() as f0 \gset
select pg_temp.ok((select count(*) = 5 and bool_and(not (t.value ->> 'exists')::boolean and not (t.value ->> 'readable')::boolean)
                     from jsonb_each(:'f0'::jsonb -> 'tables') t), 'the Setup facts name the five tables, all missing: ' || :'f0');
select pg_temp.ok(not exists (select 1 from one.events_sources() where source = 'ce.events'), 'without ce.events the source is left out');
select one.events_refresh() as r0 \gset
select pg_temp.ok(:'r0'::text !~ '_error"' and not (:'r0'::jsonb ? 'ce.events') and (select count(*) from jsonb_object_keys(:'r0'::jsonb)) > 0,
                  'the other sources copy as before, with no error key: ' || :'r0');
select pg_temp.ok(not exists (select 1 from one.event_watermarks where source = 'ce.events'), 'and nothing is recorded as missing, so ONE-01 stays quiet');
select pg_temp.ok((select r ->> 'kind' = 'missing' and not (r ->> 'ok')::boolean from (select pg_temp.embed('catalogue_engine.status') as r) x),
                  'without the engine its Apps panel says it is not on this database (0024)');

-- 3. Stub ce tables: the engine's columns, owned by postgres with RLS on, as the engine's migrations make them -----------
set role postgres;
create schema ce;
create table ce.run (id uuid primary key default gen_random_uuid(), kind text not null, partner_id uuid,
  status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'failed', 'held', 'cancelled')),
  started_at timestamptz, finished_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table ce.job (id bigint generated always as identity primary key, run_id uuid references ce.run (id), stage text not null,
  kind text not null, payload jsonb not null default '{}',
  status text not null default 'queued' check (status in ('queued', 'running', 'succeeded', 'dead', 'paused', 'cancelled')),
  attempts int not null default 0, max_attempts int not null default 5, next_run_at timestamptz not null default now(),
  locked_by text, locked_until timestamptz, last_error text, finished_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint job_lock check ((status = 'running') = (locked_by is not null and locked_until is not null)));
create table ce.heartbeat (component text primary key, last_ok_at timestamptz, last_error_at timestamptz, last_error text,
  detail jsonb not null default '{}', expected_interval_s int not null, updated_at timestamptz not null default now());
create table ce.health (id bigint generated always as identity primary key, metric text not null, partner_id uuid, value numeric,
  status text not null check (status in ('ok', 'warn', 'alert')), detail jsonb not null default '{}', message text,
  observed_at timestamptz not null default now());
create table ce.events (id bigint generated always as identity primary key, occurred_at timestamptz not null default now(),
  type text not null, partner_id uuid, run_id uuid, actor text not null default 'system', payload jsonb not null default '{}');
alter table ce.run enable row level security;
alter table ce.job enable row level security;
alter table ce.heartbeat enable row level security;
alter table ce.health enable row level security;
alter table ce.events enable row level security;
-- The engine's published contract, as 0024's panels read it: a partner table, review items, conflicts, and ce_pub.
create table ce.partner (id uuid primary key default gen_random_uuid(), slug text not null, name text not null);
create table ce.review_item (id uuid primary key default gen_random_uuid(), queue text not null, status text not null default 'open');
create table ce.conflict (id uuid primary key default gen_random_uuid(), status text not null default 'open');
create schema ce_pub;
create table ce.publication (id bigint generated always as identity primary key, partner_id uuid references ce.partner (id), number int not null,
  status text not null, created_at timestamptz not null default now(), built_at timestamptz, published_by text, note text,
  counts jsonb not null default '{}', checksum text, supersedes bigint, rolled_back_at timestamptz, rolled_back_by text, restored_at timestamptz, error text);
create view ce_pub.catalogue_versions_v1 as
  select p.id as version_id, p.partner_id, pa.name as partner, pa.slug as partner_slug, p.number, p.status, p.created_at as published_at, p.built_at,
         p.published_by, p.note, p.counts, p.checksum, p.supersedes, p.rolled_back_at, p.rolled_back_by, p.restored_at, p.error
    from ce.publication p join ce.partner pa on pa.id = p.partner_id;
create function ce_pub.engine_status() returns jsonb language sql stable set search_path = '' as $f$
  select jsonb_build_object('generated_at', now(),
    'partners', coalesce((select jsonb_agg(jsonb_build_object('partner', pa.slug, 'name', pa.name,
                            'live_version', (select jsonb_build_object('id', p.id, 'number', p.number) from ce.publication p where p.partner_id = pa.id and p.status = 'live'))) from ce.partner pa), '[]'),
    'queue', coalesce((select jsonb_object_agg(s.status, s.n) from (select status, count(*) as n from ce.job group by 1) s), '{}'),
    'review_open', (select count(*) from ce.review_item where status = 'open'),
    'conflicts_open', (select count(*) from ce.conflict where status in ('open', 'asked_partner')));
$f$;
alter table ce.partner enable row level security;
alter table ce.review_item enable row level security;
alter table ce.conflict enable row level security;
alter table ce.publication enable row level security;
insert into ce.partner (id, slug, name) values ('00000000-0000-0000-0000-0000000000a1', 'degreepartner', 'degreepartner.com');
insert into ce.publication (partner_id, number, status, published_by, counts, created_at, built_at)
values ('00000000-0000-0000-0000-0000000000a1', 1, 'superseded', 'owner@eduwit.in', '{"programmes": 1100, "added": 1100}', now() - interval '2 days', now() - interval '2 days'),
       ('00000000-0000-0000-0000-0000000000a1', 2, 'live', 'owner@eduwit.in', '{"programmes": 1123, "added": 23, "changed": 40}', now() - interval '1 hour', now() - interval '1 hour');
reset role;

-- 0024: the Apps panels read the contract as the owner, redacted like every app's answer.
select pg_temp.embed('catalogue_engine.status') as e1 \gset
select pg_temp.ok((:'e1'::jsonb ->> 'ok')::boolean and (:'e1'::jsonb #>> '{data,partners,0,live_version,number}') = '2'
                  and (:'e1'::jsonb #>> '{data,review_open}') = '0', 'the status panel names the live version: ' || :'e1');
select pg_temp.embed('catalogue_engine.versions') as e2 \gset
select pg_temp.ok((:'e2'::jsonb ->> 'ok')::boolean and jsonb_array_length(:'e2'::jsonb -> 'data') = 2
                  and (:'e2'::jsonb #>> '{data,0,status}') = 'live' and (:'e2'::jsonb #>> '{data,0,counts,changed}') = '40',
                  'the versions panel lists the versions, newest first: ' || :'e2');
select pg_temp.ok((select (r ->> 'ok')::boolean and (r #>> '{data,conflicts_open}') = '0' and jsonb_typeof(r #> '{data,jobs}') = 'object'
                     from (select pg_temp.embed('catalogue_engine.queue') as r) x), 'the queue panel answers on empty tables');

select one.setup_engine_facts() as f1 \gset
select pg_temp.ok((select count(*) = 5 and bool_and((t.value ->> 'exists')::boolean and (t.value ->> 'readable')::boolean
                                                    and t.value -> 'missing_columns' = '[]')
                     from jsonb_each(:'f1'::jsonb -> 'tables') t), 'with the tables, every one exists, is readable and has its columns: ' || :'f1');
begin;
set local role postgres;
alter table ce.run rename column updated_at to changed_at;
select pg_temp.ok((one.setup_engine_facts() #> '{tables,ce.run,missing_columns}') = '["updated_at"]', 'a renamed column is named as missing');
rollback;

-- Empty tables: every check answers one row, ok.
set role postgres;
select pg_temp.ok((select bool_and((pg_temp.ce(id) ->> 'rows')::int = 1 and (pg_temp.ce(id) ->> 'ok')::boolean)
                     from one.checks where app = 'catalogue_engine'), 'on empty tables every engine check answers one row, ok');
reset role;

-- A passing fixture: fresh, monthly and never-seen workers; live queue; an alert that recovered and one older than 24 h.
insert into ce.heartbeat (component, last_ok_at, last_error_at, expected_interval_s) values
  ('db:health_collect', now() - interval '5 minutes', null, 900),
  ('worker:capture', now() - interval '30 minutes', now() - interval '2 hours', 900),
  ('worker:monthly', now() - interval '40 days', null, 2764800),
  ('worker:never', null, null, 900);
insert into ce.run (id, kind, partner_id, status) values
  ('00000000-0000-0000-0000-00000000c001', 'monthly', '00000000-0000-0000-0000-0000000000a1', 'succeeded'),
  ('00000000-0000-0000-0000-00000000c002', 'onboard', '00000000-0000-0000-0000-0000000000a2', 'running');
insert into ce.job (run_id, stage, kind, status, next_run_at, locked_by, locked_until) values
  ('00000000-0000-0000-0000-00000000c001', 'capture', 'capture.page', 'succeeded', now() - interval '5 days', null, null),
  ('00000000-0000-0000-0000-00000000c002', 'extract', 'extract.page', 'queued', now() - interval '1 day', null, null),
  ('00000000-0000-0000-0000-00000000c002', 'verify', 'verify.programme', 'running', now() - interval '1 hour', 'worker-1', now() + interval '5 minutes');
insert into ce.health (metric, partner_id, status, message, observed_at) values
  ('db.total_mb', null, 'ok', null, now() - interval '10 minutes'),
  ('queue.dead', null, 'warn', '1 job(s) stopped after repeated failures and need a look.', now() - interval '10 minutes'),
  ('storage.engine_mb', null, 'alert', 'Engine files use 990 MB, over the 900 MB cap; new uploads are refused.', now() - interval '2 hours'),
  ('storage.engine_mb', null, 'ok', null, now() - interval '10 minutes'),
  ('db.engine_mb', null, 'alert', 'The engine uses 210 MB of database, over its 200 MB budget.', now() - interval '30 hours');
set role postgres;
select pg_temp.ce('CE-01') as p1 \gset
select pg_temp.ok((:'p1'::jsonb ->> 'ok')::boolean and (:'p1'::jsonb #>> '{value,components}')::int = 4 and :'p1'::jsonb #> '{value,subjects}' = '[]',
                  'CE-01 passes: fresh, monthly within 3 × its interval, never-seen not counted: ' || :'p1');
select pg_temp.ok((pg_temp.ce('CE-02') ->> 'ok')::boolean and (pg_temp.ce('CE-02') #>> '{value,count}')::int = 0, 'CE-02 passes with no dead job');
select pg_temp.ce('CE-03') as p3 \gset
select pg_temp.ok((:'p3'::jsonb ->> 'ok')::boolean and (:'p3'::jsonb #>> '{value,warnings}')::int = 1 and (:'p3'::jsonb #>> '{value,alerts}')::int = 0,
                  'CE-03 passes: a recovered alert and one older than 24 h do not count, a warning is counted: ' || :'p3');
select pg_temp.ok((pg_temp.ce('CE-04') ->> 'ok')::boolean, 'CE-04 passes: queued a day, leased for 5 more minutes');
select pg_temp.ok((pg_temp.ce('CE-05') ->> 'ok')::boolean and (pg_temp.ce('CE-05') #>> '{value,held}')::int = 0, 'CE-05 passes with no held run');
reset role;

-- A failing fixture on top of it.
insert into ce.heartbeat (component, last_ok_at, last_error_at, last_error, expected_interval_s) values
  ('worker:extract', now() - interval '3 hours', null, null, 900),
  ('worker:check', null, now() - interval '1 minute', 'connection refused', 900);
insert into ce.run (id, kind, partner_id, status, updated_at) values
  ('00000000-0000-0000-0000-00000000c003', 'monthly', '00000000-0000-0000-0000-0000000000a3', 'held', now() - interval '1 hour');
insert into ce.job (run_id, stage, kind, status, attempts, next_run_at, locked_by, locked_until, last_error) values
  ('00000000-0000-0000-0000-00000000c002', 'capture', 'capture.page', 'dead', 5, now() - interval '1 hour', null, null, 'HTTP 403 from the portal'),
  ('00000000-0000-0000-0000-00000000c002', 'publish', 'publish.partner', 'dead', 5, now() - interval '1 hour', null, null, 'gate refused'),
  ('00000000-0000-0000-0000-00000000c002', 'discover', 'discover.sitemap', 'queued', 0, now() - interval '4 days', null, null, null),
  ('00000000-0000-0000-0000-00000000c002', 'resolve', 'resolve.institution', 'running', 1, now() - interval '3 hours', 'worker-2', now() - interval '2 hours', null);
insert into ce.health (metric, partner_id, status, message, observed_at) values
  ('db.total_mb', null, 'alert', 'The shared database is at 460 MB of the Free plan''s 500 MB.', now() - interval '1 minute'),
  ('queue.dead_job', '00000000-0000-0000-0000-0000000000a2', 'alert', 'Job capture.page stopped after 5 attempts.', now() - interval '1 minute');
set role postgres;
select pg_temp.ce('CE-01') as x1 \gset
select pg_temp.ok((:'x1'::jsonb ->> 'rows')::int = 1 and not (:'x1'::jsonb ->> 'ok')::boolean
                  and :'x1'::jsonb #> '{value,subjects}' = '["worker:check", "worker:extract"]' and (:'x1'::jsonb #>> '{value,stale}')::int = 2,
                  'CE-01 fails, one subject per stalled component (3 h old, and read but never ok): ' || :'x1');
select pg_temp.ce('CE-02') as x2 \gset
select pg_temp.ok(not (:'x2'::jsonb ->> 'ok')::boolean and (:'x2'::jsonb #>> '{value,count}')::int = 2
                  and jsonb_array_length(:'x2'::jsonb #> '{value,ids}') = 2 and :'x2'::jsonb #> '{value,stages}' = '["capture", "publish"]'
                  and :'x2'::text !~ 'HTTP 403|gate refused', 'CE-02 fails with the count, stages and ids, never the error text: ' || :'x2');
select pg_temp.ce('CE-03') as x3 \gset
select pg_temp.ok(not (:'x3'::jsonb ->> 'ok')::boolean and :'x3'::jsonb #> '{value,subjects}' = '["db.total_mb", "queue.dead_job"]'
                  and (:'x3'::jsonb #>> '{value,alerts}')::int = 2 and jsonb_array_length(:'x3'::jsonb #> '{value,messages}') = 2
                  and :'x3'::text ~ '460 MB of the Free plan', 'CE-03 fails, one subject per metric, with the engine''s messages: ' || :'x3');
select pg_temp.ce('CE-04') as x4 \gset
select pg_temp.ok(not (:'x4'::jsonb ->> 'ok')::boolean and (:'x4'::jsonb #>> '{value,queued_overdue}')::int = 1
                  and (:'x4'::jsonb #>> '{value,lease_expired}')::int = 1 and jsonb_array_length(:'x4'::jsonb #> '{value,ids}') = 2,
                  'CE-04 fails: queued 4 days past its time, and a lease expired 2 h ago: ' || :'x4');
select pg_temp.ce('CE-05') as x5 \gset
select pg_temp.ok(not (:'x5'::jsonb ->> 'ok')::boolean and (:'x5'::jsonb #>> '{value,held}')::int = 1
                  and :'x5'::jsonb #> '{value,subjects}' = '["00000000-0000-0000-0000-00000000c003"]',
                  'CE-05 fails, one subject per held run: ' || :'x5');
reset role;

-- 4. Validating the Setup item switches the five on, and the runner then reads the engine (rolled back) ---------------
begin;
select pg_temp.ok((one.setup_validated('catalogue_engine', true, 'local test', 'owner@eduwit.in') ->> 'checks_on')::int = 5,
                  'one validation switches the five checks on');
select pg_temp.ok((select bool_and(enabled and disabled_reason is null) from one.checks where app = 'catalogue_engine'), 'all five are on');
set local role postgres;
-- (Each write and the read of what it wrote are separate statements: a statement does not see its own function's writes.)
select pg_temp.ok((one.run_check('CE-05') ->> 'status') = 'fail', 'the tick''s runner fails CE-05 on the held run');
select pg_temp.ok((select severity = 'P2' from one.incidents where check_id = 'CE-05' and app = 'catalogue_engine' and resolved_at is null),
                  'and opens a P2 for the app');
select pg_temp.ok((one.run_check('CE-04') ->> 'status') = 'fail', 'the runner fails CE-04 on the stuck queue');
select pg_temp.ok((select severity = 'P3' from one.incidents where check_id = 'CE-04' and resolved_at is null), 'and opens a P3');
-- Once validated, a ce.events that goes missing counts like any missing source again (D-042).
drop table ce.events;
select pg_temp.ok(exists (select 1 from one.events_sources() where source = 'ce.events'), 'after validation the source stays listed without its table');
select pg_temp.ok((one.events_copy_safe('ce.events', 'catalogue_engine', (select sql from one.events_sources() where source = 'ce.events')) ->> 'ce.events') = '-1',
                  'its copy reports the source missing');
select pg_temp.ok((select last_status = 'source_missing' from one.event_watermarks where source = 'ce.events'), 'and records it, for ONE-01');
rollback;
select pg_temp.ok((select bool_and(not enabled) from one.checks where app = 'catalogue_engine') and to_regclass('ce.events') is not null
                  and not exists (select 1 from one.incidents where app = 'catalogue_engine'), 'the rollback left the checks off and no incident');

-- 5. Ask's app_status for the engine, with its ce-* cron job -----------------------------------------------------------
insert into cron.job (jobname, schedule, command) values ('ce-health', '*/15 * * * *', 'select ce.health_collect()');
select one.ai_tool_data('app_status', '{"app": "catalogue_engine"}') as st \gset
select pg_temp.ok((:'st'::jsonb ->> 'app') = 'catalogue_engine' and jsonb_array_length(:'st'::jsonb -> 'checks') = 5
                  and (select count(*) = 1 from jsonb_array_elements(:'st'::jsonb -> 'cron_jobs') j where j ->> 'job' = 'ce-health'),
                  'app_status answers for the engine: its five checks and its ce-health job: ' || left(:'st', 300));
select pg_temp.ok(pg_temp.err($q$select one.ai_tool_data('app_status', '{"app": "catalogue_x"}')$q$) = '22023', 'an unknown app is still refused');
delete from cron.job where jobname = 'ce-health';

-- 6. Events with ce.events: listed, copied once, redacted -------------------------------------------------------------
insert into ce.events (type, partner_id, run_id, actor, payload) values
  ('run.started', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000c002', 'worker:capture', '{"programmes": 12}'),
  ('publish.done', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000c002', 'worker:publish',
   '{"changed": 3, "contact_email": "someone@example.com"}'),
  ('health.alert', null, null, 'system', '{"metric": "db.total_mb", "message": "The shared database is at 460 MB."}');
select pg_temp.ok(exists (select 1 from one.events_sources() where source = 'ce.events' and app = 'catalogue_engine')
                  and exists (select 1 from one.events_due() where source = 'ce.events'), 'with ce.events the source is listed and due');
select pg_temp.ok((one.events_copy_safe('ce.events', 'catalogue_engine', (select sql from one.events_sources() where source = 'ce.events')) ->> 'ce.events') = '3',
                  'its three events are copied');
select pg_temp.ok((select count(*) = 3 and bool_and(source_table = 'ce.events' and actor_type = 'engine' and lead_id is null and payload ? 'run_id')
                     from one.events where app = 'catalogue_engine'), 'as catalogue_engine events, actor engine, no lead');
select pg_temp.ok((select actor_id = 'worker:publish' and payload #>> '{payload,changed}' = '3' and payload::text !~ 'someone@example.com'
                     from one.events where app = 'catalogue_engine' and type = 'publish.done'), 'the payload is kept and redacted like every source''s');
select pg_temp.ok((one.events_copy_safe('ce.events', 'catalogue_engine', (select sql from one.events_sources() where source = 'ce.events')) ->> 'ce.events') = '0'
                  and (select last_status = 'ok' and last_id = (select max(id) from ce.events) from one.event_watermarks where source = 'ce.events'),
                  'a second copy adds nothing; the watermark is at the newest id');
select one.events_refresh() as r1 \gset
select pg_temp.ok(:'r1'::text !~ '_error"', 'a full event refresh with ce.events has no error key: ' || :'r1');

-- 7. Clean up: the engine goes again, and its source with it ----------------------------------------------------------
delete from one.events where app = 'catalogue_engine';
delete from one.event_watermarks where source = 'ce.events';
set role postgres;
drop schema ce cascade;
drop schema ce_pub cascade;
reset role;
select pg_temp.ok((select r ->> 'kind' = 'missing' from (select pg_temp.embed('catalogue_engine.versions') as r) x), 'the panels say missing again');
select pg_temp.ok(not exists (select 1 from one.events_sources() where source = 'ce.events')
                  and (select bool_and(not (t.value ->> 'exists')::boolean) from jsonb_each(one.setup_engine_facts() -> 'tables') t),
                  'without the engine again, the source is left out and the facts say missing');
