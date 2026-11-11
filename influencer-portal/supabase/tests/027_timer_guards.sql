-- Migration 20261111000100_inf_timer_guards: the minute timers call the app only when it has something to do. Jobs:
-- only when inf.job_claim would return a row (5 seconds ahead). Lead sync: every minute while a real sweep recorded its
-- watermark in the last 24 hours, otherwise on minutes 0, 15, 30 and 45. A dispatch is a row in pg_net's request queue.
begin;
\ir _helpers.psql
select plan(40);

-- The dispatcher reads its target from Vault. For this transaction it points at a marker host, so the requests counted
-- below can only be this test's own. Nothing is sent: pg_net's worker never sees uncommitted rows, and all is rolled back.
select vault.update_secret(id, 'http://timer-guards.test/') from vault.secrets where name = 'inf_app_base_url';
select vault.create_secret('http://timer-guards.test/', 'inf_app_base_url')
 where not exists (select 1 from vault.secrets where name = 'inf_app_base_url');
select vault.create_secret('timer-guards-test-key', 'inf_internal_key')
 where not exists (select 1 from vault.secrets where name = 'inf_internal_key');

create function tests.dispatched(p_path text) returns int language sql as $$
  select count(*)::int from net.http_request_queue where url = 'http://timer-guards.test' || p_path;
$$;
create function tests.job(p_status text, p_run_at timestamptz, p_locked_at timestamptz default null) returns bigint language sql as $$
  insert into inf.jobs (kind, status, run_at, locked_at, locked_by)
  values ('test.job', p_status, p_run_at, p_locked_at, case when p_locked_at is not null then 'w0' end) returning id;
$$;

-- A clean slate inside the transaction: the local database may hold seeded jobs and a sweep watermark.
delete from inf.jobs;
delete from inf.sync_state where key = 'lead_sync';

-- ---------------------------------------------------------------------------------------------------------------
-- The function keeps its shape
-- ---------------------------------------------------------------------------------------------------------------
select is((select array[p.prosecdef::text, array_to_string(p.proconfig, ','), pg_get_function_result(p.oid)] from pg_proc p
            where p.oid = 'inf.cron_dispatch(text)'::regprocedure),
          array['true', 'search_path=""', 'void'], 'cron_dispatch is still security definer with an empty search_path');
select is((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = 'inf.cron_dispatch_due(text,timestamptz)'::regprocedure),
          'search_path=""', 'the new check sets an empty search_path too');
select ok(not has_function_privilege('anon', 'inf.cron_dispatch(text)', 'execute')
          and not has_function_privilege('authenticated', 'inf.cron_dispatch(text)', 'execute'), 'clients cannot dispatch');
select ok(not has_function_privilege('anon', 'inf.cron_dispatch_due(text,timestamptz)', 'execute')
          and not has_function_privilege('authenticated', 'inf.cron_dispatch_due(text,timestamptz)', 'execute'),
          'clients cannot call the check');

-- ---------------------------------------------------------------------------------------------------------------
-- Jobs: no call when nothing is claimable
-- ---------------------------------------------------------------------------------------------------------------
select is(inf.cron_dispatch_due('/api/internal/jobs', now()), false, 'no job: nothing to do');
select inf.cron_dispatch('/api/internal/jobs');
select is(tests.dispatched('/api/internal/jobs'), 0, 'no job: no request is queued');

select tests.job('done', now() - interval '1 hour');
select tests.job('dead', now() - interval '1 hour');
select tests.job('cancelled', now() - interval '1 hour');
select is(inf.cron_dispatch_due('/api/internal/jobs', now()), false, 'finished, dead and cancelled jobs are not work');

select tests.job('queued', now() + interval '1 hour');
select is(inf.cron_dispatch_due('/api/internal/jobs', now()), false, 'a job due in an hour is not work yet');
select is(inf.cron_dispatch_due('/api/internal/jobs', now() + interval '59 minutes 54 seconds'), false, 'six seconds before it is due: not yet');
select is(inf.cron_dispatch_due('/api/internal/jobs', now() + interval '59 minutes 56 seconds'), true,
          'four seconds before: the call goes out (5 seconds of slack)');
select tests.job('failed', now() + interval '8 minutes');
select is(inf.cron_dispatch_due('/api/internal/jobs', now()), false, 'a retry still backing off is not work yet');
select is(inf.cron_dispatch_due('/api/internal/jobs', now() + interval '8 minutes'), true, 'a failed job is work once its backoff has passed');
select tests.job('running', now() - interval '6 minutes', now() - interval '5 minutes');
select is(inf.cron_dispatch_due('/api/internal/jobs', now()), false, 'a job running for 5 minutes is not stale');
select is(inf.cron_dispatch_due('/api/internal/jobs', now() + interval '4 minutes 54 seconds'), false, 'six seconds before it turns stale: not yet');
select is(inf.cron_dispatch_due('/api/internal/jobs', now() + interval '4 minutes 56 seconds'), true, 'four seconds before: the call goes out');
select inf.cron_dispatch('/api/internal/jobs');
select is(tests.dispatched('/api/internal/jobs'), 0, 'future, backing-off and running jobs: no request is queued');
select is((select count(*)::int from inf.job_claim('w1', 10, null)), 0, 'and the runner would have claimed nothing');

-- A due job
select tests.job('queued', now());
select is(inf.cron_dispatch_due('/api/internal/jobs', now()), true, 'a due job is work');
select inf.cron_dispatch('/api/internal/jobs');
select is(tests.dispatched('/api/internal/jobs'), 1, 'a due job: one request is queued');
select is((select array[q.method::text, q.timeout_milliseconds::text, q.headers ->> 'x-internal-key', q.headers ->> 'content-type',
                        convert_from(q.body, 'UTF8')]
             from net.http_request_queue q where q.url = 'http://timer-guards.test/api/internal/jobs'),
          array['POST', '25000', (select decrypted_secret from vault.decrypted_secrets where name = 'inf_internal_key'),
                'application/json', '{}'],
          'the request is the one sent before: POST, the internal key, an empty body, 25 s');
select is((select count(*)::int from inf.job_claim('w1', 10, null)), 1, 'the runner claims the due job');
select is(inf.cron_dispatch_due('/api/internal/jobs', now()), false, 'once claimed, nothing is left to call for');

-- A stale running job
select tests.job('running', now() - interval '20 minutes', now() - interval '11 minutes');
select is(inf.cron_dispatch_due('/api/internal/jobs', now()), true, 'a job stuck in running for over 10 minutes is work');
select inf.cron_dispatch('/api/internal/jobs');
select is(tests.dispatched('/api/internal/jobs'), 2, 'a stale running job: a request is queued');
select is((select count(*)::int from inf.job_claim('w2', 10, null)), 1, 'the runner reclaims it');
select is(inf.cron_dispatch_due('/api/internal/jobs', now()), false, 'and again nothing is left');

-- ---------------------------------------------------------------------------------------------------------------
-- Lead sync: every minute only while a real sweep is recent
-- ---------------------------------------------------------------------------------------------------------------
select is((select array_agg(inf.cron_dispatch_due('/api/internal/lead-sync', t) order by t)
             from unnest(array['2026-11-11 10:00:00+00', '2026-11-11 10:15:00+00', '2026-11-11 10:30:59+00',
                               '2026-11-11 10:45:00+00', '2026-11-11 15:45:00+05:30']::timestamptz[]) t),
          array[true, true, true, true, true], 'no sweep yet: the call goes out on minutes 0, 15, 30 and 45 (in any time zone)');
select is((select array_agg(inf.cron_dispatch_due('/api/internal/lead-sync', t) order by t)
             from unnest(array['2026-11-11 10:01:00+00', '2026-11-11 10:14:59+00', '2026-11-11 10:16:00+00',
                               '2026-11-11 10:44:00+00', '2026-11-11 10:59:00+00']::timestamptz[]) t),
          array[false, false, false, false, false], 'no sweep yet: no call on the other minutes');
select inf.cron_dispatch('/api/internal/lead-sync');
select is(tests.dispatched('/api/internal/lead-sync'), case when extract(minute from now() at time zone 'UTC')::int % 15 = 0 then 1 else 0 end,
          'no sweep yet: this minute''s run queues a request only on a quarter-hour');

-- Only the sweep's own watermark counts.
insert into inf.sync_state (key, watermark, updated_at) values ('analytics', now(), now())
on conflict (key) do update set watermark = excluded.watermark, updated_at = excluded.updated_at;
select is(inf.cron_dispatch_due('/api/internal/lead-sync', '2026-11-11 10:01:00+00'), false, 'another watermark (analytics) is not a sweep');

-- A sweep long ago: back to the quarter-hours.
insert into inf.sync_state (key, watermark, updated_at) values ('lead_sync', now() - interval '25 hours', now() - interval '25 hours');
select is(inf.cron_dispatch_due('/api/internal/lead-sync', date_trunc('hour', now()) + interval '7 minutes'), false,
          'a sweep 25 hours ago: no call off the quarter-hour');
select is(inf.cron_dispatch_due('/api/internal/lead-sync', date_trunc('hour', now()) + interval '30 minutes'), true,
          'a sweep 25 hours ago: the quarter-hour call still goes out');

-- A recent sweep: every minute, as before.
update inf.sync_state set updated_at = now() - interval '5 minutes' where key = 'lead_sync';
select is((select bool_and(inf.cron_dispatch_due('/api/internal/lead-sync', date_trunc('hour', now()) + make_interval(mins => m)))
             from generate_series(0, 59) m), true, 'a sweep 5 minutes ago: every minute of the hour');
update inf.sync_state set updated_at = now() - interval '23 hours' where key = 'lead_sync';
select is(inf.cron_dispatch_due('/api/internal/lead-sync', now()), true, 'a sweep 23 hours ago still counts as recent');
select inf.cron_dispatch('/api/internal/lead-sync');
select is(tests.dispatched('/api/internal/lead-sync'), 1 + case when extract(minute from now() at time zone 'UTC')::int % 15 = 0 then 1 else 0 end,
          'a recent sweep: a request is queued whatever the minute');

-- The real writer: the sweep's apply with a watermark records it; a backfill or an override (no watermark) does not.
delete from inf.sync_state where key = 'lead_sync';
select tests.act_as_service();
select inf.lead_sync_apply('{"source": "backfill", "watermark": null, "leads": []}'::jsonb);
select tests.reset();
select is((select count(*)::int from inf.sync_state where key = 'lead_sync'), 0, 'a backfill leaves no sweep watermark');
select is(inf.cron_dispatch_due('/api/internal/lead-sync', date_trunc('hour', now()) + interval '7 minutes'), false, 'so a backfill does not switch the minute calls on');
select tests.act_as_service();
select inf.lead_sync_apply(jsonb_build_object('source', 'sweep', 'watermark', now(), 'leads', '[]'::jsonb));
select tests.reset();
select is(inf.cron_dispatch_due('/api/internal/lead-sync', date_trunc('hour', now()) + interval '7 minutes'), true, 'one real sweep switches them on');

-- ---------------------------------------------------------------------------------------------------------------
-- Everything else is dispatched as before
-- ---------------------------------------------------------------------------------------------------------------
select is(inf.cron_dispatch_due('/api/internal/other', '2026-11-11 10:01:00+00'), true, 'any other path is always due');
select inf.cron_dispatch('/api/internal/other');
select is(tests.dispatched('/api/internal/other'), 1, 'and is dispatched');

select * from finish();
rollback;
