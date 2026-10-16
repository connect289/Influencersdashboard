-- B2C CRM b46: the health check's "app answering the timers" row counts only Spark's own timer calls.
-- The production database is shared with Witty and the B2B CRM, whose pg_net calls (for one, the B2B CRM's test ping to
-- Spark) were being counted; and until the deploy script has pointed the timers at the site the row now says so instead of
-- reading other apps' calls. b2c.job_call records each request id in b2c.job_calls (one row, the last 600 ids).
-- Idempotent.

create table if not exists b2c.job_calls (one boolean primary key default true check (one), calls jsonb not null default '[]'::jsonb);
alter table b2c.job_calls enable row level security;
insert into b2c.job_calls (one) values (true) on conflict do nothing;

create or replace function b2c.job_call(p_path text) returns bigint language plpgsql security definer set search_path = '' as $f$
declare v_base text := b2c.setting('app') ->> 'base_url'; v_key text; v_id bigint; v_calls jsonb;
begin
  if v_base is null then return null; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'b2c_internal_key';
  if v_key is null then return null; end if;
  v_id := net.http_post(url := rtrim(v_base, '/') || p_path, body := '{}'::jsonb,
                        headers := jsonb_build_object('content-type', 'application/json', 'x-internal-key', v_key), timeout_milliseconds := 55000);
  select coalesce(c.calls, '[]'::jsonb) || jsonb_build_array(jsonb_build_object('id', v_id, 'path', p_path, 'at', now())) into v_calls from b2c.job_calls c;
  if v_calls is null then v_calls := jsonb_build_array(jsonb_build_object('id', v_id, 'path', p_path, 'at', now())); end if;
  if jsonb_array_length(v_calls) > 600 then
    select jsonb_agg(e order by n) into v_calls from jsonb_array_elements(v_calls) with ordinality as t(e, n) where n > jsonb_array_length(v_calls) - 600;
  end if;
  insert into b2c.job_calls (one, calls) values (true, v_calls) on conflict (one) do update set calls = excluded.calls;
  return v_id;
end $f$;
revoke execute on function b2c.job_call(text) from public, authenticated;

create or replace function b2c.system_health() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_jobs jsonb := '[]'::jsonb; v_calls jsonb := null; v_ai jsonb; v_checks jsonb := '[]'::jsonb; v_live boolean;
        n_out_q int; n_out_bad int; t_out_old timestamptz; n_sq_q int; n_sq_held int; n_sq_bad int; t_sq_old timestamptz;
        n_in_err int; n_in_stale int; n_unassigned int; n_replies int; n_unlogged int; n_wa_fail int; t_batch timestamptz; t_event timestamptz;
        v_base text := b2c.setting('app') ->> 'base_url'; v_keyed boolean; v_app_level text; v_app_detail text;
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  -- timers
  if to_regclass('cron.job') is not null then
    if to_regclass('cron.job_run_details') is not null then
      -- cron.job_run_details has no index but its primary key and can hold hundreds of thousands of rows: read only the newest 20,000 runs, once.
      execute $q$with recent as materialized (
                   select distinct on (r.jobid) r.jobid, r.status, r.start_time, r.end_time, r.return_message from cron.job_run_details r
                    where r.runid > coalesce((select max(x.runid) from cron.job_run_details x), 0) - 20000 order by r.jobid, r.start_time desc)
                 select coalesce(jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'last_status', d.status, 'last_start', d.start_time,
                                                              'last_end', d.end_time, 'message', left(d.return_message, 200)) order by j.jobname), '[]'::jsonb)
                   from cron.job j left join recent d on d.jobid = j.jobid
                  where j.jobname like 'b2c-%'$q$ into v_jobs;
    else
      execute $q$select coalesce(jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule) order by j.jobname), '[]'::jsonb) from cron.job j where j.jobname like 'b2c-%'$q$ into v_jobs;
    end if;
  end if;
  -- the app's answers to the timers: only the calls b2c.job_call made (the database is shared, so net._http_response also holds
  -- other apps' calls); pg_net keeps responses for a few hours and b2c.job_calls the last 600 request ids.
  select exists (select 1 from vault.decrypted_secrets where name = 'b2c_internal_key') into v_keyed;
  if v_base is null or not v_keyed then
    v_app_level := 'warn'; v_app_detail := 'the timers are not pointed at the site yet: run the deploy script (developer handover, step 5.2)';
  elsif to_regclass('net._http_response') is null then
    v_app_level := 'warn'; v_app_detail := 'no record of calls (pg_net is not installed)';
  else
    execute $q$with ids as (select (e ->> 'id')::bigint as id, (e ->> 'at')::timestamptz as at from b2c.job_calls c, jsonb_array_elements(c.calls) e)
                 select jsonb_build_object('last_at', max(r.created),
                          'failed_last_hour', count(r.id) filter (where r.created > now() - interval '1 hour' and (r.status_code is null or r.status_code >= 400)),
                          'ok_last_hour', count(r.id) filter (where r.created > now() - interval '1 hour' and r.status_code < 400),
                          'unanswered_last_hour', count(*) filter (where r.id is null and ids.at > now() - interval '1 hour' and ids.at < now() - interval '3 minutes'),
                          'calls_last_hour', count(*) filter (where ids.at > now() - interval '1 hour'))
                   from ids left join net._http_response r on r.id = ids.id$q$ into v_calls;
    v_app_level := case when (v_calls ->> 'failed_last_hour')::int > 0 then 'bad'
                        when (v_calls ->> 'unanswered_last_hour')::int > 0 then 'warn'
                        when v_calls ->> 'last_at' is null then 'warn' else 'ok' end;
    v_app_detail := coalesce(v_calls ->> 'ok_last_hour', '0') || ' ok, ' || coalesce(v_calls ->> 'failed_last_hour', '0') || ' failed and '
                    || coalesce(v_calls ->> 'unanswered_last_hour', '0') || ' unanswered in the last hour'
                    || case when v_calls ->> 'last_at' is null then ' (no answer recorded yet)' else '' end;
  end if;
  -- queues and feeds
  select count(*) filter (where status = 'queued'), count(*) filter (where status in ('failed', 'refused', 'conflict') and created_at > now() - interval '7 days'),
         min(created_at) filter (where status = 'queued') into n_out_q, n_out_bad, t_out_old from b2c.outbox;
  select count(*) filter (where status = 'queued'), count(*) filter (where status = 'held'), count(*) filter (where status = 'failed' and created_at > now() - interval '24 hours'),
         min(not_before) filter (where status = 'queued') into n_sq_q, n_sq_held, n_sq_bad, t_sq_old from b2c.send_queue;
  select count(*) filter (where status = 'error'), count(*) filter (where status = 'stored' and received_at < now() - interval '10 minutes') into n_in_err, n_in_stale from b2c.inbox;
  select max(sent_at) into t_batch from b2c.outbox where status = 'applied';
  select max(received_at) into t_event from b2c.inbox;
  select count(*) into n_wa_fail from b2c.wa_messages where direction = 'out' and status = 'failed' and created_at > now() - interval '24 hours';
  -- waiting for a person
  select count(*) into n_unassigned from b2c.leads_state where status = 'active' and owner_id is null and lane = 'sales' and deleted_at is null and not is_test;
  select count(*) into n_replies from b2c.replies where status = 'inbox';
  select count(*) into n_unlogged from b2c.calls where logged_at is null and unlogged_flagged_at is not null and tapped_at > now() - interval '24 hours';
  v_ai := jsonb_build_object('spent_today', b2c.ai_spent_today(), 'cap', (b2c.setting('ai') ->> 'daily_cap_inr')::numeric,
                             'failed_today', (select count(*) from b2c.ai_calls where not ok and at > now() - interval '24 hours'));
  v_live := coalesce((b2c.setting('live_mode') ->> 'whatsapp')::boolean, false) or coalesce((b2c.setting('live_mode') ->> 'email')::boolean, false);
  -- the checks, each with a level
  v_checks := v_checks
    || jsonb_build_object('key', 'timers', 'label', 'Database timers', 'level', case when jsonb_array_length(v_jobs) = 0 then 'bad'
                            when exists (select 1 from jsonb_array_elements(v_jobs) j where j ->> 'last_status' = 'failed') then 'bad'
                            when exists (select 1 from jsonb_array_elements(v_jobs) j where j ->> 'name' = 'b2c-minute' and coalesce((j ->> 'last_start')::timestamptz, now() - interval '1 day') < now() - interval '10 minutes') then 'warn'
                            else 'ok' end,
                          'detail', jsonb_array_length(v_jobs) || ' timers' || coalesce('; last minute tick ' || (select j ->> 'last_start' from jsonb_array_elements(v_jobs) j where j ->> 'name' = 'b2c-minute'), ''))
    || jsonb_build_object('key', 'app', 'label', 'The app answering the timers', 'level', v_app_level, 'detail', v_app_detail)
    || jsonb_build_object('key', 'outbox', 'label', 'Changes to the master lead table', 'level', case when n_out_bad > 0 then 'bad' when t_out_old < now() - interval '30 minutes' then 'warn' else 'ok' end,
                          'detail', n_out_q || ' waiting, ' || n_out_bad || ' failed or refused this week' || coalesce(', last batch ' || t_batch::text, ''))
    || jsonb_build_object('key', 'inbox', 'label', 'Events from the master lead table', 'level', case when n_in_err > 0 then 'bad' when n_in_stale > 0 then 'warn' else 'ok' end,
                          'detail', n_in_err || ' with errors, ' || n_in_stale || ' not yet applied' || coalesce(', last event ' || t_event::text, ''))
    || jsonb_build_object('key', 'sending', 'label', 'WhatsApp and email sending', 'level', case when n_sq_bad > 0 or n_wa_fail > 0 then 'bad' when t_sq_old < now() - interval '15 minutes' then 'warn' else 'ok' end,
                          'detail', n_sq_q || ' queued, ' || n_sq_held || ' held, ' || n_sq_bad || ' failed in 24 h; live mode ' || case when v_live then 'on' else 'off' end)
    || jsonb_build_object('key', 'ai', 'label', 'Claude', 'level', case when (v_ai ->> 'failed_today')::int > 0 then 'warn' when (v_ai ->> 'spent_today')::numeric >= coalesce((v_ai ->> 'cap')::numeric, 0) and coalesce((v_ai ->> 'cap')::numeric, 0) > 0 then 'warn' else 'ok' end,
                          'detail', '₹' || round((v_ai ->> 'spent_today')::numeric) || ' of ₹' || coalesce(v_ai ->> 'cap', '0') || ' today, ' || (v_ai ->> 'failed_today') || ' failed calls')
    || jsonb_build_object('key', 'people', 'label', 'Waiting for a person', 'level', case when n_unassigned > 0 then 'bad' when n_replies > 0 or n_unlogged > 0 then 'warn' else 'ok' end,
                          'detail', n_unassigned || ' unassigned sales leads, ' || n_replies || ' replies to answer, ' || n_unlogged || ' calls not logged in 24 h');
  return jsonb_build_object('at', now(), 'checks', v_checks, 'jobs', v_jobs, 'calls', v_calls, 'ai', v_ai,
                            'overall', case when exists (select 1 from jsonb_array_elements(v_checks) c where c ->> 'level' = 'bad') then 'bad'
                                            when exists (select 1 from jsonb_array_elements(v_checks) c where c ->> 'level' = 'warn') then 'warn' else 'ok' end);
end $f$;
