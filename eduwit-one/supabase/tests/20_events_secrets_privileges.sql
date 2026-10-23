-- Event copy, the app call, secrets, the privilege audit and least privilege. Local test cluster only.
\set ON_ERROR_STOP 1
create or replace function pg_temp.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'ASSERT FAILED: %', p_msg; end if;
end $$;
-- Runs a statement as a role and reports whether it was refused for lack of privilege.
create or replace function pg_temp.refused(p_role text, p_sql text) returns boolean language plpgsql as $$
begin
  execute format('set local role %I', p_role);
  begin
    execute p_sql;
  exception when insufficient_privilege then
    reset role;
    return true;
  end;
  reset role;
  return false;
end $$;

-- 1. Events: copied with the lead resolved and contact fields removed; copying again adds nothing ---------------------
insert into public.student_leads (whatsapp_number, student_name) values ('919999000001', 'Test Student');
insert into public.w2_events (phone, type, run_id, payload) values ('+91 99990 00001', 'turn', 'r1', '{"x": 1}');
set role postgres;
select one.events_refresh();
select pg_temp.ok((select lead_id = (select id from public.student_leads limit 1) from one.events where source_table = 'public.w2_events'), 'w2 event resolved to its lead');
select pg_temp.ok((select not (payload ? 'phone') from one.events where source_table = 'public.w2_events'), 'phone removed from the payload');
create temp table t_ev as select one.events_refresh() as r;
select pg_temp.ok((select (r ->> 'public.w2_events')::int = 0 from t_ev), 'a second copy adds nothing');
select pg_temp.ok((select last_status = 'source_missing' from one.event_watermarks where source = 'public.web_funnel_events'), 'missing source recorded as source_missing');
select pg_temp.ok((select (count(*) = 1) from one.events where source_table = 'public.w2_events'), 'exactly one copy of the event');

-- 2. The app call is a no-op until configured, then carries the bearer key ----------------------------------------------
select pg_temp.ok(one.job_call('/api/internal/tick') is null, 'job_call does nothing without a base URL');
reset role;
insert into vault.secrets (name, secret) values ('one_internal_key', 'test-key-not-real'), ('b2b_whatsapp_token', 'not-for-one');
set role postgres;
select one.settings_put('app', '{"base_url": "https://one.example.test", "timezone": "Asia/Kolkata"}', 'owner@eduwit.in');
select pg_temp.ok(one.job_call('/api/internal/tick') is not null, 'job_call sends once configured');
reset role;
select pg_temp.ok((select url = 'https://one.example.test/api/internal/tick' and headers ->> 'authorization' = 'Bearer test-key-not-real'
                     from net.http_request_queue order by id desc limit 1), 'job_call posts to the base URL with the bearer key');
set role postgres;
select one.settings_put('app', '{"base_url": null, "timezone": "Asia/Kolkata"}', 'owner@eduwit.in');

-- 3. Secrets: only Eduwit One's own, never another app's token ----------------------------------------------------------
do $$ begin
  perform one.secret('b2b_whatsapp_token');
  raise exception 'ASSERT FAILED: one.secret returned another app''s token';
exception when insufficient_privilege then null;
end $$;
select pg_temp.ok((select array_agg(n) from one.vault_names() n) = array['one_internal_key'], 'vault_names lists only Eduwit One''s names');

-- 4. Privilege audit: the first run is the baseline; a new anon SECURITY DEFINER function is flagged --------------------
create temp table t_pa as select one.privilege_audit() as r;
select pg_temp.ok((select (r ->> 'unacknowledged')::int = 0 from t_pa), 'existing functions form the baseline');
reset role;
create function public.new_anon_rpc() returns int language sql security definer as $$ select 2 $$;
grant execute on function public.new_anon_rpc() to anon;
set role postgres;
select pg_temp.ok((one.privilege_audit() ->> 'unacknowledged')::int = 1, 'a new anon-executable SECURITY DEFINER function is flagged');
reset role;

-- 5. Least privilege (spec §13) ---------------------------------------------------------------------------------------
select pg_temp.ok(not pg_temp.refused('eduwit_one_reader', 'select count(*) from public.student_leads'), 'reader can read student_leads');
select pg_temp.ok(pg_temp.refused('eduwit_one_reader', 'update public.student_leads set student_name = student_name'), 'reader cannot update student_leads');
select pg_temp.ok(pg_temp.refused('eduwit_one_reader', 'delete from b2b.events'), 'reader cannot delete from an app table');
select pg_temp.ok(pg_temp.refused('eduwit_one_reader', 'insert into one.settings (key, value) values (''x'', ''{}'')'), 'reader cannot write schema one');
select pg_temp.ok(pg_temp.refused('eduwit_one_reader', 'select one.secret(''one_internal_key'')'), 'reader cannot read secrets');
select pg_temp.ok(pg_temp.refused('eduwit_one_fixer', 'select count(*) from public.student_leads'), 'fixer has no grants at all');
select pg_temp.ok(pg_temp.refused('service_role', $q$insert into one.checks (id, app, title, kind, sql, severity, cadence_s) values ('X-1', 'platform', 't', 'sql', 'select true as ok, null::jsonb as value', 'P3', 60)$q$), 'service role cannot add a check');
select pg_temp.ok(pg_temp.refused('service_role', $q$update one.checks set sql = 'select true as ok, null::jsonb as value' where id = 'PLAT-01'$q$), 'service role cannot change a check''s sql');
select pg_temp.ok(not pg_temp.refused('service_role', $q$update one.checks set enabled = true, updated_by = 'test' where id = 'PLAT-01'$q$), 'service role can change a check''s switch');
select pg_temp.ok(pg_temp.refused('service_role', 'select one.secret(''one_internal_key'')'), 'service role cannot read secrets through SQL');
select pg_temp.ok(pg_temp.refused('anon', 'select count(*) from one.settings'), 'anon cannot see schema one');
select pg_temp.ok(pg_temp.refused('authenticated', 'select one.health()'), 'authenticated cannot call one.*');

-- 6. A check's sql cannot change data, even when written by a migration ------------------------------------------------
set role postgres;
do $$ begin
  insert into one.checks (id, app, title, kind, sql, severity, cadence_s)
  values ('X-2', 'platform', 't', 'sql', 'with d as (delete from one.audit returning 1) select true as ok, null::jsonb as value', 'P3', 60);
  raise exception 'ASSERT FAILED: a data-changing check was accepted';
exception when check_violation then null;
end $$;

-- 7. Nightly: baselines captured, idempotent within a day ---------------------------------------------------------------
create temp table t_n as select one.nightly() as r;
select pg_temp.ok((select r::text !~ '_error"' from t_n), 'nightly report has no error keys: ' || (select r::text from t_n));
select pg_temp.ok(one.nightly() ? 'skipped', 'a second nightly the same day does nothing');
select pg_temp.ok(exists (select 1 from one.baselines where key = 'lead_intake_md5'), 'lead_intake baseline captured');
select pg_temp.ok(exists (select 1 from one.ai_tasks where kind = 'brief'), 'brief task queued');
reset role;
