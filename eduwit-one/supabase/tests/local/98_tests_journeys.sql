-- The journeys' seams and the purge (migration 0016): phones handed out by the database and kept from the runner,
-- facts that answer only for the run's own test leads, the leak counts, Witty's reset under its own search_path, and a
-- purge that keeps partner-routed leads. The app tables these read are stubbed here, not in 01_app_stubs.sql, because
-- the checks must keep seeing them as missing; this file drops them again at the end. Local test cluster only.
\set ON_ERROR_STOP 1
do $$ begin
  if current_database() <> 'rehearsal' or to_regclass('public.stub_health') is null then
    raise exception 'refused: this test rewrites fixtures and runs only on the local test cluster';
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
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text) to service_role;
create or replace function pg_temp.check_ok(p_id text) returns boolean language plpgsql as $$
declare v boolean;
begin
  execute (select sql from one.checks where id = p_id) into v;
  return v;
end $$;

-- Stubs, owned by postgres as on production, with the columns 0016 reads (measured on production 23 Oct).
set role postgres;
alter table public.student_leads add column lead_source text, add column lead_status text, add column destination_type text,
  add column deleted_at timestamptz, add column first_contacted_at timestamptz, add column contact_attempts int, add column merged_into_id bigint;
alter table public.w2_conversations add column classification text;
alter table public.w2_messages add column sent boolean;
alter table b2b.allocations add column destination_type text, add column partner_id bigint, add column is_test boolean, add column origin text,
  add column reference text, add column b2c_lane text;
create table public.w2_test_runs (id bigserial primary key, run_tag text, summary jsonb, results jsonb, created_at timestamptz default now());
create table public.w2_inbox (message_id text primary key, phone text, content text, received_at timestamptz default now());
create table b2b.partners (id bigserial primary key, slug text, status text, test_endpoint text);
create table b2b.engine_decisions (id bigserial primary key, lead_id bigint);
create table b2b.push_requests (id bigserial primary key, allocation_id bigint, url text, sandbox boolean, status_code int, outcome text);
create table b2b.partner_activities (id bigserial primary key, lead_id bigint, kind text);
create table b2b.integration_outbox (id bigserial primary key, target text, payload jsonb, status text);
create table b2b.b2c_writes (id bigserial primary key, lead_id bigint, kind text, status text, http_status int, created_at timestamptz default now());
create table b2c.lead_records (lead_id bigint primary key, held_by_b2c boolean, is_test boolean);
create table b2c.leads_state (lead_id bigint primary key, is_test boolean, deleted_at timestamptz);
create table b2c.outbox (id bigserial primary key, kind text, lead_id bigint, status text, created_at timestamptz default now());
create table b2c.fact_leads (lead_id bigint primary key, is_test boolean, deleted boolean, handed_off_at timestamptz);
create table b2c.journey_runs (id bigserial primary key, journey_id bigint, lead_id bigint, step_idx int, status text, is_test boolean);
create table b2c.send_queue (id bigserial primary key, channel text, lead_id bigint, to_address text, status text, created_at timestamptz default now());
create function b2b.is_test_phone(p text) returns boolean language sql immutable set search_path = '' as $$
  select regexp_replace(coalesce(p, ''), '\D', '', 'g') ~ '^(910000[0-9]{6}|9190000000[0-9]{2})$';
$$;
reset role;

truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
delete from one.test_runs;
select coalesce(max(id), 0) as sl_max from public.student_leads \gset
select coalesce(max(id), 0) as msg_max from public.w2_messages \gset
select coalesce(max(id), 0) as ob_max from public.w2_outbox \gset
select coalesce(max(id), 0) as al_max from b2b.allocations \gset
create temp table t_conv as select phone from public.w2_conversations;
create temp table t_saved as select key, value from one.settings where key = 'test_identities';
create temp table t_tests as select id, enabled, disabled_reason from one.tests;
update one.tests set enabled = true, disabled_reason = null where id in ('T-B2B-INTAKE', 'T-B2B-PUSH', 'T-HANDOFF', 'T-B2C-NURTURE', 'T-WITTY-TURN', 'T-WITTY-QUALIFY');

set role service_role;
select (one.test_run_start('T-B2B-INTAKE', 'manual', 'T-B2B-INTAKE:j-1', 'r', 90) ->> 'id')::bigint as run \gset
-- 1. Kinds are per test --------------------------------------------------------------------------------------------------------
select pg_temp.ok(pg_temp.err(format('select one.test_fact(%s, %L, %L)', :run, 'b2c.journey', '{"lead_id": 1}')) = '42501', 'T-B2B-INTAKE cannot read T-B2C-NURTURE''s facts');
select pg_temp.ok(pg_temp.err(format('select one.test_act(%s, %L)', :run, 'alert.open')) = '42501', 'nor act as T-ALERT');

-- 2. A phone from Eduwit One's slice ------------------------------------------------------------------------------------------
reset role;
select '9100009' || lpad((:run % 100000)::text, 5, '0') as phone \gset
set role service_role;
select one.test_act(:run, 'phone.allocate') as alloc \gset
reset role;
select pg_temp.ok((:'alloc'::jsonb ->> 'phone') = :'phone', 'the phone is 9100009 and five digits of the run: ' || :'alloc');
select pg_temp.ok((select artefacts -> 'phones' = jsonb_build_array(:'phone') from one.test_runs where id = :run), 'the run holds its phone');
set role service_role;
select one.test_run_save(:run, 'r', 90, '[]', '{"phones": ["910000000001"], "lead_id": 7}', null);
reset role;
select pg_temp.ok((select artefacts -> 'phones' = jsonb_build_array(:'phone') and artefacts ->> 'lead_id' = '7' and artefacts ? 'phone.allocate'
                     from one.test_runs where id = :run), 'the runner adds artefacts but cannot change the phones or drop the database''s');
update one.settings set value = value || '{"run_phone_prefix": "9100001"}' where key = 'test_identities';
set role service_role;
select pg_temp.ok(pg_temp.err(format('select one.test_act(%s, %L)', :run, 'phone.allocate')) = '22023', 'a prefix outside 9100009 is refused');
reset role;
update one.settings set value = value || '{"run_phone_prefix": "91000091234"}' where key = 'test_identities';
set role service_role;
select pg_temp.ok(pg_temp.err(format('select one.test_act(%s, %L)', :run, 'phone.allocate')) = '22023',
                  'so is a longer one, which would leave too few phones for concurrent runs');
reset role;
update one.settings s set value = t.value from t_saved t where s.key = t.key;

-- 3. Facts answer only for the run's own test leads, without contact fields ------------------------------------------------
insert into public.student_leads (whatsapp_number, is_test, lead_source, lead_status, created_at) values (:'phone', true, 'b2b_api', 'new', now())
returning id as lead \gset
insert into public.student_leads (whatsapp_number, is_test) values ('919812345678', false) returning id as real_lead \gset
insert into public.student_leads (whatsapp_number, is_test) values ('910000123456', true) returning id as other_lead \gset
set role service_role;
select pg_temp.ok(pg_temp.err(format('select one.test_fact(%s, %L, %L)', :run, 'lead', jsonb_build_object('lead_id', :real_lead))) = '42501', 'a real lead is refused');
select pg_temp.ok(pg_temp.err(format('select one.test_fact(%s, %L, %L)', :run, 'lead', jsonb_build_object('lead_id', :other_lead))) = '42501',
                  'so is a test lead on a phone the run was not given');
select pg_temp.ok(pg_temp.err(format('select one.test_fact(%s, %L)', :run, 'lead')) = '22023', 'a lead fact needs its lead');
select one.test_fact(:run, 'lead', jsonb_build_object('lead_id', :lead)) as fact \gset
select pg_temp.ok((:'fact'::jsonb ->> 'is_test')::boolean and :'fact'::jsonb ->> 'lead_source' = 'b2b_api' and not (:'fact'::jsonb ? 'phone')
                  and :'fact' !~ '9100009', 'the run''s lead, with no phone in it: ' || :'fact');
reset role;
insert into b2b.partners (slug, status, test_endpoint) values ('test-partner', 'active', 'https://sandbox.example/leads') returning id as partner \gset
insert into b2b.allocations (lead_id, status, destination_type, partner_id, is_test, origin, reference)
values (:lead, 'pushed', 'partner', :partner, true, 'sandbox', 'EDW-1') returning id as alloc_id \gset
insert into b2b.push_requests (allocation_id, url, sandbox, status_code, outcome) values (:alloc_id, 'https://sandbox.example/leads', true, 200, 'accepted');
set role service_role;
select one.test_fact(:run, 'b2b.routing', jsonb_build_object('lead_id', :lead)) as routing \gset
select pg_temp.ok((:'routing'::jsonb #>> '{allocations,0,partner}') = 'test-partner', 'routing names the partner: ' || :'routing');

-- 4. The leak count: real leads only, as B2B's command centre counts them ------------------------------------------------------
select (one.test_fact(:run, 'b2b.real_leads_today') ->> 'leads_today')::int as before \gset
reset role;
insert into public.student_leads (whatsapp_number, is_test) values ('919812340001', false), ('919812340002', false), ('919812340003', false),
  ('919000000007', false), ('910000777777', true);
set role service_role;
select pg_temp.ok((one.test_fact(:run, 'b2b.real_leads_today') ->> 'leads_today')::int = :before + 3,
                  'three real leads count; a lead on a B2B test phone (9190000000NN) does not, even unflagged');
select one.test_run_finish(:run, 'r', true, null, '[]', null);

-- 5. Spark's journey sends, compared with the lead's own phone -------------------------------------------------------------
select (one.test_run_start('T-B2C-NURTURE', 'manual', 'T-B2C-NURTURE:j-1', 'r', 90) ->> 'id')::bigint as nrun \gset
select (one.test_act(:nrun, 'phone.allocate') ->> 'phone') as nphone \gset
reset role;
insert into public.student_leads (whatsapp_number, is_test) values (:'nphone', true) returning id as nlead \gset
insert into b2c.journey_runs (journey_id, lead_id, step_idx, status, is_test) values (4, :nlead, 1, 'running', true) returning id as jrun \gset
insert into b2c.journey_runs (journey_id, lead_id, step_idx, status, is_test) values (9, :nlead, 0, 'running', true);
insert into b2c.send_queue (channel, lead_id, to_address, status, created_at) values ('whatsapp', :nlead, '+919812345670', 'dry_run', now() - interval '2 hours');
insert into b2c.send_queue (channel, lead_id, to_address, status) values ('whatsapp', :nlead, '+' || :'nphone', 'dry_run');
select (now() - interval '1 minute')::text as enrolled \gset
set role service_role;
select one.test_fact(:nrun, 'b2c.journey', jsonb_build_object('lead_id', :nlead, 'journey_run_id', :jrun, 'since', :'enrolled')) as j \gset
select pg_temp.ok((:'j'::jsonb ->> 'sends')::int = 1 and (:'j'::jsonb ->> 'sends_to_lead_phone')::int = 1 and (:'j'::jsonb ->> 'sends_live')::int = 0
                  and (:'j'::jsonb #>> '{run,step_idx}')::int = 1 and :'j' !~ '9100009',
                  'the test''s own journey run, and the one dry-run send since enrolment, to the lead''s own phone: ' || :'j');
reset role;
insert into b2c.send_queue (channel, lead_id, to_address, status) values ('whatsapp', :nlead, '+919812345678', 'sent');
set role service_role;
select one.test_fact(:nrun, 'b2c.journey', jsonb_build_object('lead_id', :nlead, 'journey_run_id', :jrun, 'since', :'enrolled')) as j \gset
select pg_temp.ok((:'j'::jsonb ->> 'sends_to_lead_phone')::int = 1 and (:'j'::jsonb ->> 'sends_live')::int = 1, 'a live send elsewhere shows');
select one.test_run_finish(:nrun, 'r', false, 'sent: live', '[]', null);

-- 6. Witty: the harness phones come from Witty's record of the run; the turn needs a trusted test number -----------------------
select (one.test_run_start('T-WITTY-QUALIFY', 'manual', 'T-WITTY-QUALIFY:j-1', 'r', 90) ->> 'id')::bigint as qrun \gset
select pg_temp.ok((one.test_fact(:qrun, 'witty.harness_run') ->> 'found')::boolean is false, 'no harness run yet');
reset role;
insert into public.w2_test_runs (run_tag, summary, results)
values ('one-' || :qrun, '{"passed": 1, "failed": 0}', '[{"phone": "910000000101", "turn": 1}, {"phone": "910000000101", "turn": 2}, {"phone": "919812345678"}]');
insert into public.w2_conversations (phone, classification) values ('910000000101', 'HOT'), ('919812345679', 'HOT');
insert into public.w2_outbox (phone, status) values ('910000000101', 'sent');
insert into public.student_leads (whatsapp_number, is_test, lead_source) values ('910000000101', true, 'witty');
set role service_role;
select pg_temp.ok((one.test_fact(:qrun, 'witty.harness_run') #>> '{summary,passed}')::int = 1, 'the harness run is found by its tag');
select one.test_fact(:qrun, 'witty.qualified', '{"phones": ["919812345679"]}') as q \gset
select pg_temp.ok((:'q'::jsonb ->> 'phones')::int = 1 and (:'q'::jsonb ->> 'hot')::int = 1 and (:'q'::jsonb ->> 'outbox_sent')::int = 1
                  and jsonb_array_length(:'q'::jsonb -> 'leads') = 1 and :'q' !~ '91000000', 'only the harness phone, whatever the caller passes: ' || :'q');
select one.test_run_finish(:qrun, 'r', true, null, '[]', null);
select (one.test_run_start('T-WITTY-TURN', 'manual', 'T-WITTY-TURN:j-1', 'r', 90) ->> 'id')::bigint as trun \gset
reset role;
update one.settings set value = value || '{"whatsapp_number": "15550001111"}' where key = 'test_identities';
set role service_role;
select pg_temp.ok((one.test_fact(:trun, 'witty.trusted') ->> 'trusted_test')::boolean is false, 'an untrusted number is reported');
select pg_temp.ok(pg_temp.err(format('select one.test_fact(%s, %L)', :trun, 'witty.turn')) = '42501', 'and its turn is not read');
reset role;
insert into public.w2_trusted (phone, is_test) values ('15550001111', true);
insert into public.w2_inbox (message_id, phone, content) values ('m1', '15550001111', 'hi');
insert into public.w2_messages (phone, direction, reply_source, sent, latency_ms, verify_errors) values ('15550001111', 'out', 'llm', true, 4200, '[]');
set role service_role;
select one.test_fact(:trun, 'witty.turn') as turn \gset
select pg_temp.ok((:'turn'::jsonb ->> 'inbox')::int = 1 and (:'turn'::jsonb #>> '{replies,0,reply_source}') = 'llm' and :'turn' !~ '1555', 'the turn, without the number: ' || :'turn');
select one.test_run_finish(:trun, 'r', true, null, '[]', null);

-- 7. The purge: due after purge_after_days; partner-routed leads kept; Witty reset on the rest --------------------------------
select pg_temp.ok(jsonb_array_length(one.test_purge_due()) = 0, 'nothing is due before purge_after_days');
reset role;
update one.test_runs set finished_at = now() - interval '4 days' where id in (:run, :nrun);
set role service_role;
select one.test_purge_due() as due \gset
select pg_temp.ok(jsonb_array_length(:'due'::jsonb) = 2, 'both lead runs are due: ' || :'due');
select pg_temp.ok((select (x #>> '{leads,0,with_partner}')::boolean from jsonb_array_elements(:'due'::jsonb) x where (x ->> 'run')::bigint = :run),
                  'the intake run''s lead went to a partner');
select pg_temp.ok((select (x #>> '{leads,0,with_partner}')::boolean is false and (x -> 'phones')::int = 1 and :'due' !~ '9100009'
                     from jsonb_array_elements(:'due'::jsonb) x where (x ->> 'run')::bigint = :nrun), 'the nurture run''s did not, and no phone is listed');
reset role;
select pg_temp.ok(not pg_temp.check_ok('ONE-PURGE'), 'ONE-PURGE reports runs a day overdue');
set role service_role;
select one.test_run_purge(:nrun, '{"spark": {"error": "status 500"}}') as failed \gset
select pg_temp.ok((:'failed'::jsonb ->> 'purged')::boolean is false and (:'failed'::jsonb ->> 'attempts')::int = 1, 'a failed delete keeps the run unpurged: ' || :'failed');
select pg_temp.ok(jsonb_array_length(one.test_purge_due()) = 1, 'and it waits an hour before the next try');
reset role;
update one.test_runs set purge_next_at = now() - interval '1 minute' where id = :nrun;
set role service_role;
select one.test_run_purge(:run, '{"kept": [1]}') as p1 \gset
select one.test_run_purge(:nrun, '{"kept": [], "spark": {"deleted": 1}, "b2b": {"deleted": 1}}') as p2 \gset
reset role;
select pg_temp.ok((:'p1'::jsonb ->> 'purged')::boolean and (:'p2'::jsonb ->> 'purged')::boolean, 'both runs are purged: ' || :'p1' || :'p2');
select pg_temp.ok(exists (select 1 from public.student_leads where id = :lead) and exists (select 1 from public.student_leads where id = :nlead),
                  'nothing is hard-deleted: the apps soft-delete their leads, through the runner');
select pg_temp.ok((select count(*) = 2 from one.test_runs where id in (:run, :nrun) and purged_at is not null and purge_report ? 'kept'), 'and each run keeps its report');
set role service_role;
select pg_temp.ok(pg_temp.err(format('select one.test_run_purge(%s, %L)', :run, '{}')) = '22023', 'a run is purged once');
select pg_temp.ok(jsonb_array_length(one.test_purge_due()) = 0, 'and is no longer due');
reset role;
select pg_temp.ok(pg_temp.check_ok('ONE-PURGE'), 'ONE-PURGE is clear again');
set role service_role;
reset role;

-- 8. A phone that already holds a lead is never handed out again ----------------------------------------------------------------
set role service_role;
select (one.test_run_start('T-B2B-PUSH', 'manual', 'T-B2B-PUSH:j-1', 'r', 90) ->> 'id')::bigint as prun \gset
reset role;
-- The phone this run would get, still holding a soft-deleted lead from 100,000 runs ago.
select '9100009' || lpad((:prun % 100000)::text, 5, '0') as pphone \gset
insert into public.student_leads (whatsapp_number, is_test, deleted_at) values (:'pphone', true, now()) returning id as plead \gset
set role service_role;
select pg_temp.ok(pg_temp.err(format('select one.test_act(%s, %L)', :prun, 'phone.allocate')) = '55000', 'a phone that holds a lead is refused');
select one.test_run_finish(:prun, 'r', false, 'phone in use', '[]', null);
reset role;
select pg_temp.ok(exists (select 1 from public.student_leads where id = :plead), 'and its lead is still there');

-- 9. Eduwit One's own metrics leave test rows out (spec §10) --------------------------------------------------------------------
set role postgres;
create table b2b.lead_campaigns (lead_id bigint, platform text, campaign_name text, utm_campaign text, touched_at timestamptz default now());
reset role;
delete from public.w2_messages; delete from public.touchpoints;
insert into public.w2_trusted (phone, is_test) values ('15550002222', true) on conflict do nothing;
insert into public.w2_messages (phone, direction, reply_source, latency_ms) values
  ('919811122334', 'out', 'counselor', 1000), ('910000900001', 'out', 'counselor', 9000), ('15550002222', 'out', 'counselor', 9000);
insert into public.student_leads (whatsapp_number, is_test) values ('919812349999', false) returning id as mreal \gset
insert into public.student_leads (whatsapp_number, is_test) values ('910000900002', true) returning id as mtest \gset
insert into b2b.lead_campaigns (lead_id, campaign_name) values (:mreal, 'mba_oct'), (:mtest, 'eduwit_one_tests');
insert into public.touchpoints (lead_id, phone, source_system, event_type) values
  (:mreal, '919812349999', 'b2b', 'intake'), (:mtest, '910000900002', 'b2b', 'intake'), (null, '+910000900003', 'witty', 'click');
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000098', 'owner98@eduwit.in') on conflict do nothing;
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-000000000981', '00000000-0000-0000-0000-000000000098') on conflict do nothing;
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000098', 'owner98@eduwit.in', 'owner') on conflict do nothing;
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-000000000981', '00000000-0000-0000-0000-000000000098', 'email_code')
on conflict do nothing;
grant execute on function pg_temp.ok(boolean, text) to authenticated;
set role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000098", "session_id": "00000000-0000-0000-0000-000000000981"}', false);
select pg_temp.ok((select (r #>> '{data,0,replies}')::int = 1 and (r #>> '{data,0,p95_ms}')::int = 1000 from (select one.ui_embed('witty.replies') as r) x),
                  'Witty''s replies count no harness phone and no trusted test number: ' || one.ui_embed('witty.replies')::text);
select pg_temp.ok((select jsonb_array_length(m -> 'leads') = 1 and m #>> '{leads,0,campaign}' = 'mba_oct'
                          and jsonb_array_length(m -> 'touchpoints') = 1 from (select one.ui_marketing(7) as m) x),
                  'Marketing counts no test lead and no harness phone: ' || (one.ui_marketing(7) - 'ms')::text);
reset role;
select set_config('request.jwt.claims', '', false);
delete from one.session_checks where user_id = '00000000-0000-0000-0000-000000000098';
delete from one.users where user_id = '00000000-0000-0000-0000-000000000098';
delete from auth.sessions where user_id = '00000000-0000-0000-0000-000000000098';
delete from auth.users where id = '00000000-0000-0000-0000-000000000098';
delete from public.w2_messages; delete from public.touchpoints;
set role postgres;
drop table b2b.lead_campaigns;
reset role;

-- 9. The Setup validators' facts: the Spark journey named in the test identities ---------------------------------------------
set role postgres;
-- As in Spark: current_version is 0 until the journey is published.
create table b2c.journeys (id bigserial primary key, name text, test_mode boolean, status text, current_version int not null default 0);
create table b2c.journey_versions (journey_id bigint, version int, steps jsonb);
insert into b2c.journeys (name, test_mode, status, current_version) values ('Test nurture', true, 'active', 1), ('Real nurture', false, 'active', 1),
  ('Draft', true, 'draft', 0);
insert into b2c.journey_versions values (1, 1, '[{"type": "whatsapp"}, {"type": "wait"}]'), (2, 1, '[]');
reset role;
set role service_role;
select pg_temp.ok((one.setup_test_facts() #>> '{spark_journey,found}')::boolean is false, 'no journey named, none found');
reset role;
update one.settings set value = value || '{"spark_test_journey_id": "1"}' where key = 'test_identities';
set role service_role;
select one.setup_test_facts() as sf \gset
select pg_temp.ok((:'sf'::jsonb #>> '{spark_journey,test_mode}')::boolean and (:'sf'::jsonb #>> '{spark_journey,steps}')::int = 2
                  and (:'sf'::jsonb #>> '{identities,spark_test_journey_id}') = '1', 'the named journey, in test mode, with its steps: ' || :'sf');
reset role;
update one.settings set value = value || '{"spark_test_journey_id": "3"}' where key = 'test_identities';
set role service_role;
select pg_temp.ok((one.setup_test_facts() #>> '{spark_journey,published}')::boolean is false, 'an unpublished journey (version 0) is not published');
reset role;
update one.settings set value = value || '{"whatsapp_number": "15550002222"}' where key = 'test_identities';
insert into public.w2_trusted (phone, is_test) values ('15550002222', true) on conflict do nothing;
set role service_role;
select pg_temp.ok((one.setup_test_facts() ->> 'whatsapp_trusted')::boolean, 'the test number is reported trusted');
reset role;
update one.settings set value = value || '{"spark_test_journey_id": "2; drop"}' where key = 'test_identities';
set role service_role;
select pg_temp.ok((one.setup_test_facts() #>> '{spark_journey,found}')::boolean is false, 'a malformed id finds nothing');
reset role;
update one.settings s set value = t.value from t_saved t where s.key = t.key;
set role postgres;
drop table b2c.journeys, b2c.journey_versions;
reset role;

-- 9. The proposals for the blocked tests (0017) ------------------------------------------------------------------------------
\ir ../../migrations/0017_seed_test_proposals.sql
select pg_temp.ok((select count(*) = 6 and bool_and(status = 'open' and expires_at is null and change ? 'where' and change ? 'owner_action')
                     from one.proposals where source_key like 'builder:p5-%'), 'six open proposals, each naming where and what');
select pg_temp.ok((select array_agg(source_key) = array['builder:p5-catalogue-test-programme'] from one.proposals
                    where source_key like 'builder:p5-%' and not one.proposal_sensitive(kind, change)),
                  'a test path past Turnstile, a referral code (money) and the B2B fixes are the owner''s; only the hidden programme is the engineer''s');
\ir ../../migrations/0017_seed_test_proposals.sql
select pg_temp.ok((select count(*) = 6 from one.proposals where source_key like 'builder:p5-%'), 'running 0017 again inserts nothing');

-- Clean up: runs, settings, tests, and every stub this file added.
delete from one.test_runs;
truncate one.deliveries, one.incidents restart identity cascade;
update one.settings s set value = t.value from t_saved t where s.key = t.key;
update one.tests s set enabled = t.enabled, disabled_reason = t.disabled_reason from t_tests t where s.id = t.id;
delete from public.student_leads where id > :sl_max;
delete from public.w2_messages where id > :msg_max;
delete from public.w2_outbox where id > :ob_max;
delete from b2b.allocations where id > :al_max;
delete from public.w2_conversations where phone not in (select phone from t_conv);
delete from public.w2_trusted;
set role postgres;
drop function b2b.is_test_phone(text);
drop table public.w2_test_runs, public.w2_inbox, b2b.partners, b2b.engine_decisions, b2b.push_requests, b2b.partner_activities,
  b2b.integration_outbox, b2b.b2c_writes, b2c.lead_records, b2c.leads_state, b2c.outbox, b2c.fact_leads, b2c.journey_runs, b2c.send_queue;
alter table public.student_leads drop column lead_source, drop column lead_status, drop column destination_type, drop column deleted_at,
  drop column first_contacted_at, drop column contact_attempts, drop column merged_into_id;
alter table public.w2_conversations drop column classification;
alter table public.w2_messages drop column sent;
alter table b2b.allocations drop column destination_type, drop column partner_id, drop column is_test, drop column origin, drop column reference,
  drop column b2c_lane;
reset role;
