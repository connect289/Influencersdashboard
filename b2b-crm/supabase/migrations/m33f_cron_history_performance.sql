-- M33f (15 Oct): the cron run history grows ~58,000 rows a day (29 jobs, several every 5 to 10 seconds) and has only its
-- primary key (runid; the table belongs to supabase_admin, so no index can be added). health_check (anon, 3 s statement
-- timeout) and system_overview scanned all of it 30 to 90 times per call and timed out. Both now read only the newest runs,
-- found through the runid key: health_check the last 6,000 (about 2.5 hours: enough for the 15-minute staleness rule and
-- the latest status of every frequent job), system_overview the last 75,000 (about 30 hours: every daily job's last run and
-- the failures of the last 24 hours). b2b-cron-prune keeps 7 days of history. Re-appliable.

create or replace function b2b.health_check()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_stale int;
  v_failed int;
  v_dead int;
  v_waiting int;
  v_cursor_age numeric;
begin
  -- the latest run and its status per job, from the newest 6,000 runs (about 2.5 hours)
  with last_run as (
    select distinct on (d.jobid) d.jobid, d.start_time, d.status
      from cron.job_run_details d
     where d.runid > (select max(x.runid) - 6000 from cron.job_run_details x)
     order by d.jobid, d.runid desc)
  select count(*) filter (where (j.schedule ~ 'second' or j.schedule ~ '^\* \* \* \* \*$') and coalesce(r.start_time, '-infinity') < now() - interval '15 minutes'),
         count(*) filter (where r.status = 'failed')
    into v_stale, v_failed
    from cron.job j left join last_run r on r.jobid = j.jobid
   where j.jobname like 'b2b-%' and j.active;
  select count(*) filter (where status = 'dead'), count(*) filter (where status in ('pending', 'failed') and created_at < now() - interval '1 hour')
    into v_dead, v_waiting from b2b.integration_outbox where endpoint_id is not null and created_at > now() - interval '7 days';
  select extract(epoch from now() - (value ->> 'last_run')::timestamptz) into v_cursor_age from b2b.b2c_link_state where key = 'cursor';
  return jsonb_build_object(
    'ok', v_stale = 0 and v_failed = 0 and coalesce(v_cursor_age, 0) < 600,
    'at', now(),
    'jobs', jsonb_build_object('stale', v_stale, 'last_run_failed', v_failed),
    'deliveries', jsonb_build_object('dead_7d', v_dead, 'waiting_over_1h', v_waiting),
    'b2c_sync', jsonb_build_object('cursor_age_seconds', round(coalesce(v_cursor_age, 0))));
end $fn$;

create or replace function b2b.system_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_jobs jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  -- the jobs card, from the newest 75,000 runs (about 30 hours)
  with recent as materialized (
    select d.jobid, d.runid, d.start_time, d.status, d.return_message
      from cron.job_run_details d where d.runid > (select max(x.runid) - 75000 from cron.job_run_details x)),
  last_run as (select distinct on (r.jobid) r.jobid, r.start_time, r.status from recent r order by r.jobid, r.runid desc),
  failed as (select r.jobid, count(*) as n from recent r where r.status = 'failed' and r.start_time > now() - interval '1 day' group by r.jobid),
  last_err as (
    select distinct on (r.jobid) r.jobid, left(r.return_message, 200) as msg
      from recent r where r.status = 'failed' and r.start_time > now() - interval '1 day' order by r.jobid, r.runid desc)
  select coalesce(jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'active', j.active,
                             'last_status', r.status, 'last_run', r.start_time, 'last_error', e.msg, 'failed_24h', coalesce(f.n, 0)) order by j.jobname), '[]')
    into v_jobs
    from cron.job j
    left join last_run r on r.jobid = j.jobid
    left join failed f on f.jobid = j.jobid
    left join last_err e on e.jobid = j.jobid
   where j.jobname like 'b2b-%';
  return jsonb_build_object(
    'api_keys', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'scopes', k.scopes, 'prefix', k.key_prefix, 'created_at', k.created_at,
                                                              'last_used_at', k.last_used_at, 'revoked_at', k.revoked_at,
                                                              'expires_at', k.expires_at, 'rate_per_minute', k.rate_per_minute, 'note', k.note,
                                                              'requests_1h', (select coalesce(sum(u.n), 0) from b2b.api_key_usage u where u.api_key_id = k.id and u.minute > now() - interval '1 hour'),
                                                              'requests_24h', (select coalesce(sum(u.n), 0) from b2b.api_key_usage u where u.api_key_id = k.id and u.minute > now() - interval '24 hours'))
                                                   order by k.revoked_at nulls first, k.created_at desc)
                          from b2b.api_keys k), '[]'),
    'api_limits', coalesce((select value from b2b.settings where key = 'api_limits'), '{}'),
    'endpoints', coalesce((select jsonb_agg(to_jsonb(w) - 'secret_id' || jsonb_build_object('has_secret', w.secret_id is not null,
                             'pending', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status in ('pending', 'failed', 'sending')),
                             'dead', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status = 'dead'),
                             'delivered_24h', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status = 'delivered' and o.delivered_at > now() - interval '1 day'))
                           order by w.id) from b2b.webhook_endpoints w), '[]'),
    'deliveries', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'event_type', o.event_type, 'endpoint_id', o.endpoint_id,
                              'endpoint', (select w.name from b2b.webhook_endpoints w where w.id = o.endpoint_id), 'status', o.status, 'attempts', o.attempts,
                              'response_status', o.response_status, 'last_error', o.last_error, 'created_at', o.created_at, 'delivered_at', o.delivered_at,
                              'next_attempt_at', o.next_attempt_at, 'lead_id', (o.payload ->> 'lead_id')::bigint) order by o.id desc)
                            from (select * from b2b.integration_outbox where endpoint_id is not null order by id desc limit 100) o), '[]'),
    'product_events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'source', e.source, 'event_type', e.event_type, 'lead_id', e.lead_id,
                                  'status', e.status, 'result', e.result, 'received_at', e.received_at) order by e.id desc)
                                from (select * from b2b.product_events order by id desc limit 50) e), '[]'),
    'erasure_open', (select count(*) from b2b.erasure_requests where status = 'open'),
    'jobs', v_jobs);
end $fn$;

/* Seven days of run history is enough for the Health screen and the alerts; the rest goes nightly (22:15 UTC, 03:45 IST). */
do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'b2b-cron-prune';
  perform cron.schedule('b2b-cron-prune', '15 22 * * *', $j$delete from cron.job_run_details where start_time < now() - interval '7 days'$j$);
end $cron$;
