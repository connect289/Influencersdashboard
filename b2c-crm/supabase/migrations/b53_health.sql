-- B2C CRM b53 (4 Nov 2026): a machine health report, and messages that stopped mid-send are no longer lost.
--
-- 1. b2c.health(): what Spark's /api/health reports (service role only): the timers, the app answering them, the
--    feeds to and from the master lead table, sending, connectors, the programme cache, Claude and bulk jobs, each with a
--    level (ok, warn, bad). Counts, ages, timer names and connector keys only: no student, phone, email or lead id. It
--    reads at most the newest 5,000 timer runs (cron.job_run_details has no index but its primary key; about three
--    hours of runs) and the last 600 timer calls, so one call costs a few milliseconds. "ok" is false when a core part
--    is bad (no timers, the minute timer silent for 10 minutes, the timers not pointed at the site, or no timer call
--    answered in 15 minutes); the route adds the configuration, the database and file storage.
-- 2. Sending: b2c.send_take took up to 50 messages, marked them "sending" and the app recorded their outcomes in one call
--    at the end. A run that ended before that call (the 60-second limit on a busy minute, a crash) left every message of
--    the batch "sending" for ever: never sent again, never reported. Now:
--      - send_take stamps taken_at;
--      - the app records outcomes ten at a time, stops starting sends near its time limit and hands the rest back with
--        b2c.send_release(ids) (back to queued, the attempt not counted);
--      - b2c.send_unstick(minutes) marks a message still "sending" that many minutes after it was taken as failed. It
--        is never sent again automatically: the app may have sent it before it stopped, and a student must not get a
--        message twice. Like a final failure in send_done, a failed assignment WhatsApp falls back to email, and the
--        admins get one notice (Connectors). Eduwit One's FIX-SENDQ-B2C calls it on B2C-07.
--    b2c.system_health() counts those messages in its "sending" row.
-- Idempotent.

alter table b2c.send_queue add column if not exists taken_at timestamptz;
create index if not exists send_queue_sending_taken_idx on b2c.send_queue (taken_at) where status = 'sending';

-- ---------- redefined: send_take stamps taken_at (production's b42 definition otherwise) ----------
create or replace function b2c.send_take(p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with c as (select id from b2c.send_queue where status = 'queued' and not_before <= now()
                and not (purpose = 'assignment' and channel = 'whatsapp' and lead_id is not null and b2c.witty_busy(lead_id))
              order by not_before limit p_limit for update skip locked),
  u as (update b2c.send_queue q set status = 'sending', attempts = attempts + 1, taken_at = now() from c where q.id = c.id
        returning q.id, q.channel, q.lead_id, q.to_address, q.payload, q.purpose, q.wa_message_id)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'channel', u.channel, 'lead_id', u.lead_id, 'to', u.to_address, 'payload', u.payload,
                  'purpose', u.purpose, 'wa_message_id', u.wa_message_id,
                  'live', b2c.live(u.channel) and not b2c.is_test_phone(u.to_address) and not coalesce((select s.is_test from b2c.leads_state s where s.lead_id = u.lead_id), false))), '[]')
    into v from u;
  return v;
end $f$;

-- Messages the app took but did not start (it stopped near its time limit): back to queued, the attempt not counted.
create or replace function b2c.send_release(p_ids bigint[]) returns integer
language sql security definer set search_path = '' as $f$
  with u as (update b2c.send_queue set status = 'queued', attempts = greatest(attempts - 1, 0), taken_at = null
              where id = any (coalesce(p_ids, '{}'::bigint[])) and status = 'sending' returning 1)
  select count(*)::int from u
$f$;

-- Messages still "sending" p_minutes (at least 5) after they were taken: failed, never sent again automatically (the
-- outcome is unknown). At most 500 a call, oldest first. Returns how many it marked.
create or replace function b2c.send_unstick(p_minutes integer default 15) returns integer
language plpgsql security definer set search_path = '' as $f$
declare
  q b2c.send_queue;
  n integer := 0;
  v_err constant text := 'stopped mid-send: the app ended before it recorded the outcome, so it is not sent again automatically (it may have gone out); check with the student and send again if it did not arrive';
begin
  if p_minutes is null or p_minutes < 5 then
    raise exception 'send_unstick: p_minutes must be at least 5' using errcode = '22023';
  end if;
  for q in select * from b2c.send_queue
            where status = 'sending' and coalesce(taken_at, not_before) < now() - make_interval(mins => p_minutes)
            order by coalesce(taken_at, not_before), id limit 500 for update skip locked loop
    update b2c.send_queue set status = 'failed', error = v_err where id = q.id;
    if q.wa_message_id is not null then
      update b2c.wa_messages set status = 'failed', error = v_err, status_at = now() where id = q.wa_message_id and status = 'queued';
    end if;
    if q.purpose = 'assignment' and q.channel = 'whatsapp' then
      perform b2c.assignment_email(q.lead_id, null);
    end if;
    n := n + 1;
  end loop;
  if n > 0 then
    perform b2c.notify_admins('send_failed', 'Messages stopped mid-send',
                              n || ' message(s) stopped while sending and were marked failed, not sent again (they may have gone out). Assignment WhatsApps fell back to email.',
                              '/w/connectors', null, 'sendstuck:' || to_char(now(), 'YYYYMMDDHH24MI'));
  end if;
  return n;
end $f$;

-- The machine health report behind /api/health (see the header). Service role only.
create or replace function b2c.health() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare
  v_ids bigint[] := '{}'; v_jobs int := 0; v_inactive int := 0; v_failed jsonb := '[]'; v_minute_at timestamptz; v_minute_status text;
  v_base text := b2c.setting('app') ->> 'base_url'; v_keyed boolean; v_calls jsonb := '{}';
  v_timers jsonb; v_app jsonb; v_outbox jsonb; v_inbox jsonb; v_sending jsonb; v_conn jsonb; v_prog jsonb; v_ai jsonb; v_bulk jsonb;
  n1 int; n2 int; n3 int; n4 int; t1 timestamptz; t2 timestamptz; v_cap numeric; v_spent numeric; v_keys jsonb;
  v_core_bad boolean; v_any_bad boolean; v_any_warn boolean; v_checks jsonb;
begin
  -- timers: the b2c-* jobs, and the latest run of each among the newest 5,000 runs
  if to_regclass('cron.job') is not null then
    execute $q$select coalesce(array_agg(j.jobid), '{}'), count(*)::int,
                      count(*) filter (where coalesce((to_jsonb(j) ->> 'active')::boolean, true) = false)::int
                 from cron.job j where j.jobname like 'b2c-%'$q$ into v_ids, v_jobs, v_inactive;
    if to_regclass('cron.job_run_details') is not null and v_jobs > 0 then
      execute $q$with recent as materialized (
                   select distinct on (r.jobid) r.jobid, r.status, r.start_time from cron.job_run_details r
                    where r.runid > coalesce((select max(x.runid) from cron.job_run_details x), 0) - 5000 and r.jobid = any ($1)
                      and r.status in ('succeeded', 'failed') and r.return_message is distinct from 'job startup timeout'
                    order by r.jobid, r.runid desc)
                 select coalesce(jsonb_agg(j.jobname order by j.jobname) filter (where d.status = 'failed'), '[]'),
                        max(d.start_time) filter (where j.jobname = 'b2c-minute'), max(d.status) filter (where j.jobname = 'b2c-minute')
                   from recent d join cron.job j on j.jobid = d.jobid$q$ using v_ids into v_failed, v_minute_at, v_minute_status;
    end if;
  end if;
  v_timers := jsonb_build_object('jobs', v_jobs, 'inactive', v_inactive, 'failed', v_failed, 'minute_last_at', v_minute_at,
    'level', case when v_jobs = 0 then 'bad'
                  when to_regclass('cron.job_run_details') is not null and (v_minute_at is null or v_minute_at < now() - interval '10 minutes' or v_minute_status = 'failed') then 'bad'
                  when v_inactive > 0 or jsonb_array_length(v_failed) > 0 then 'warn' else 'ok' end);

  -- the app answering the timers: only Spark's own calls (b2c.job_calls, the last 600)
  select exists (select 1 from vault.decrypted_secrets where name = 'b2c_internal_key') into v_keyed;
  if v_base is not null and v_keyed and to_regclass('net._http_response') is not null then
    execute $q$with ids as (select (e ->> 'id')::bigint as id, (e ->> 'at')::timestamptz as at from b2c.job_calls c, jsonb_array_elements(c.calls) e)
                 select jsonb_build_object(
                   'calls_15m', count(*) filter (where ids.at > now() - interval '15 minutes' and ids.at < now() - interval '2 minutes'),
                   'ok_15m', count(r.id) filter (where ids.at > now() - interval '15 minutes' and r.status_code < 400),
                   'failed_1h', count(r.id) filter (where ids.at > now() - interval '1 hour' and (r.status_code is null or r.status_code >= 400)),
                   'unanswered_1h', count(*) filter (where r.id is null and ids.at > now() - interval '1 hour' and ids.at < now() - interval '3 minutes'),
                   'last_answer_at', max(r.created))
                   from ids left join net._http_response r on r.id = ids.id$q$ into v_calls;
  end if;
  v_app := v_calls || jsonb_build_object('pointed', v_base is not null and v_keyed,
    'level', case when v_base is null or not v_keyed then 'bad'
                  when to_regclass('net._http_response') is null then 'warn'
                  when (v_calls ->> 'calls_15m')::int > 0 and (v_calls ->> 'ok_15m')::int = 0 then 'bad'
                  when (v_calls ->> 'failed_1h')::int > 0 or (v_calls ->> 'unanswered_1h')::int > 0 then 'warn' else 'ok' end);

  -- the feeds to and from the master lead table
  select count(*) filter (where status = 'queued'), count(*) filter (where status in ('failed', 'refused', 'conflict') and created_at > now() - interval '24 hours'),
         count(*) filter (where status in ('failed', 'refused', 'conflict') and created_at > now() - interval '7 days'), min(created_at) filter (where status = 'queued')
    into n1, n2, n3, t1 from b2c.outbox;
  v_outbox := jsonb_build_object('queued', n1, 'failed_24h', n2, 'failed_7d', n3, 'oldest_queued_at', t1,
    'level', case when n2 > 0 or t1 < now() - interval '60 minutes' then 'bad' when n3 > 0 or t1 < now() - interval '30 minutes' then 'warn' else 'ok' end);
  select count(*) filter (where status = 'error'), count(*) filter (where status = 'stored' and received_at < now() - interval '10 minutes'), max(received_at)
    into n1, n2, t1 from b2c.inbox;
  v_inbox := jsonb_build_object('errors', n1, 'waiting_10m', n2, 'last_event_at', t1,
    'level', case when n1 > 0 then 'bad' when n2 > 0 then 'warn' else 'ok' end);

  -- sending
  select count(*) filter (where status = 'queued'), count(*) filter (where status = 'queued' and not_before < now() - interval '15 minutes'),
         count(*) filter (where status = 'sending' and coalesce(taken_at, not_before) < now() - interval '15 minutes'),
         count(*) filter (where status = 'failed' and created_at > now() - interval '24 hours')
    into n1, n2, n3, n4 from b2c.send_queue;
  v_sending := jsonb_build_object('queued', n1, 'overdue_15m', n2, 'stuck_sending', n3, 'failed_24h', n4,
    'level', case when n3 > 0 or n2 > 0 then 'bad' when n4 > 0 then 'warn' else 'ok' end);

  -- connectors whose last answer was an error (keys only)
  select coalesce(jsonb_agg(key order by key), '[]') into v_keys from b2c.connector_status
   where last_error_at is not null and (last_ok_at is null or last_error_at > last_ok_at);
  v_conn := jsonb_build_object('erroring', v_keys, 'level', case when jsonb_array_length(v_keys) > 0 then 'warn' else 'ok' end);

  -- the programme cache against the shared catalogue
  select max(catalog_updated_at), count(*) into t1, n1 from b2c.programme_cache;
  t2 := null;
  if to_regclass('public.catalog_programs') is not null then
    execute 'select max(updated_at) from public.catalog_programs' into t2;
  end if;
  v_prog := jsonb_build_object('programmes', n1, 'cache_at', t1, 'catalogue_at', t2,
    'level', case when t2 is not null and n1 = 0 then 'bad' when t2 is not null and t1 < t2 - interval '60 minutes' then 'warn' else 'ok' end);

  -- Claude
  v_spent := b2c.ai_spent_today();
  v_cap := (b2c.setting('ai') ->> 'daily_cap_inr')::numeric;
  select count(*) into n1 from b2c.ai_calls where not ok and at > now() - interval '24 hours';
  v_ai := jsonb_build_object('spent_today_inr', round(v_spent, 2), 'cap_inr', v_cap, 'failed_24h', n1,
    'level', case when coalesce(v_cap, 0) > 0 and v_spent >= v_cap then 'warn' when n1 > 0 then 'warn' else 'ok' end);

  -- bulk jobs waiting or running for over 30 minutes
  select count(*) into n1 from b2c.bulk_jobs where status in ('queued', 'running') and created_at < now() - interval '30 minutes';
  v_bulk := jsonb_build_object('stalled', n1, 'level', case when n1 > 0 then 'warn' else 'ok' end);

  v_checks := jsonb_build_object('timers', v_timers, 'app', v_app, 'outbox', v_outbox, 'inbox', v_inbox, 'sending', v_sending,
                                 'connectors', v_conn, 'programmes', v_prog, 'ai', v_ai, 'jobs', v_bulk);
  v_core_bad := v_timers ->> 'level' = 'bad' or v_app ->> 'level' = 'bad';
  select bool_or(c.value ->> 'level' = 'bad'), bool_or(c.value ->> 'level' = 'warn') into v_any_bad, v_any_warn from jsonb_each(v_checks) c;
  return jsonb_build_object('at', now(), 'ok', not v_core_bad,
                            'status', case when v_core_bad then 'down' when v_any_bad or v_any_warn then 'degraded' else 'ok' end,
                            'checks', v_checks);
end $f$;

-- ---------- redefined: system_health counts messages stopped mid-send (production's b46 definition otherwise) ----------
CREATE OR REPLACE FUNCTION b2c.system_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_jobs jsonb := '[]'::jsonb; v_calls jsonb := null; v_ai jsonb; v_checks jsonb := '[]'::jsonb; v_live boolean;
        n_out_q int; n_out_bad int; t_out_old timestamptz; n_sq_q int; n_sq_held int; n_sq_bad int; n_sq_stuck int; t_sq_old timestamptz;
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
         count(*) filter (where status = 'sending' and coalesce(taken_at, not_before) < now() - interval '15 minutes'),
         min(not_before) filter (where status = 'queued') into n_sq_q, n_sq_held, n_sq_bad, n_sq_stuck, t_sq_old from b2c.send_queue;
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
    || jsonb_build_object('key', 'sending', 'label', 'WhatsApp and email sending', 'level', case when n_sq_bad > 0 or n_wa_fail > 0 or n_sq_stuck > 0 then 'bad' when t_sq_old < now() - interval '15 minutes' then 'warn' else 'ok' end,
                          'detail', n_sq_q || ' queued, ' || n_sq_held || ' held, ' || n_sq_stuck || ' stopped mid-send, ' || n_sq_bad || ' failed in 24 h; live mode ' || case when v_live then 'on' else 'off' end)
    || jsonb_build_object('key', 'ai', 'label', 'Claude', 'level', case when (v_ai ->> 'failed_today')::int > 0 then 'warn' when (v_ai ->> 'spent_today')::numeric >= coalesce((v_ai ->> 'cap')::numeric, 0) and coalesce((v_ai ->> 'cap')::numeric, 0) > 0 then 'warn' else 'ok' end,
                          'detail', '₹' || round((v_ai ->> 'spent_today')::numeric) || ' of ₹' || coalesce(v_ai ->> 'cap', '0') || ' today, ' || (v_ai ->> 'failed_today') || ' failed calls')
    || jsonb_build_object('key', 'people', 'label', 'Waiting for a person', 'level', case when n_unassigned > 0 then 'bad' when n_replies > 0 or n_unlogged > 0 then 'warn' else 'ok' end,
                          'detail', n_unassigned || ' unassigned sales leads, ' || n_replies || ' replies to answer, ' || n_unlogged || ' calls not logged in 24 h');
  return jsonb_build_object('at', now(), 'checks', v_checks, 'jobs', v_jobs, 'calls', v_calls, 'ai', v_ai,
                            'overall', case when exists (select 1 from jsonb_array_elements(v_checks) c where c ->> 'level' = 'bad') then 'bad'
                                            when exists (select 1 from jsonb_array_elements(v_checks) c where c ->> 'level' = 'warn') then 'warn' else 'ok' end);
end $function$;

-- Grants: the new functions are the service role's (the app's machine endpoints); Eduwit One's fixer is granted
-- send_unstick by Eduwit One's own migration. send_take and system_health keep their grants (create or replace).
revoke execute on function b2c.send_release(bigint[]) from public, anon, authenticated;
revoke execute on function b2c.send_unstick(integer) from public, anon, authenticated;
revoke execute on function b2c.health() from public, anon, authenticated;
grant execute on function b2c.send_release(bigint[]) to service_role;
grant execute on function b2c.send_unstick(integer) to service_role;
grant execute on function b2c.health() to service_role;

-- last: nothing in b2c is executable by PUBLIC or anon
revoke execute on all functions in schema b2c from public, anon;
