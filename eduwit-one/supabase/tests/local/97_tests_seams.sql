-- The seams the journeys use (migration 0016): a fact or an action only for a run in flight whose test may use it;
-- T-ALERT's synthetic incident and test delivery; synthetic incidents left out of the digest. Local test cluster only.
\set ON_ERROR_STOP 1
-- The histories are append-only in production (D-085); this local test may rewrite them, as one.retention() does.
select set_config('one.history_writer', 'on', false);
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

truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
delete from one.test_runs;
create temp table t_saved as select key, value from one.settings where key in ('alerts', 'test_identities');
update one.tests set enabled = true, disabled_reason = null where id = 'T-ALERT';

set role service_role;
select (one.test_run_start('T-ALERT', 'manual', 'T-ALERT:seams-1', 'r', 90) ->> 'id')::bigint as run \gset
-- 1. Only the run's own test's kinds ----------------------------------------------------------------------------------------
select pg_temp.ok(pg_temp.err(format('select one.test_act(%s, %L)', :run, 'witty.send')) = '42501', 'T-ALERT cannot use another test''s seam');
select pg_temp.ok(pg_temp.err(format('select one.test_act(%s, %L)', 999999, 'alert.open')) = '22023', 'nor a run that is not in flight');

-- 2. T-ALERT: a synthetic incident and a test delivery to Resend's test address while no mailbox is set ----------------------
select one.test_act(:run, 'alert.open') as opened \gset
reset role;
select pg_temp.ok((select i.check_id = 'ONE-SYNTH' and i.severity = 'P2' and 'synthetic' = any (i.tags) and (i.evidence -> 'value' ->> 'synthetic')::boolean
                     from one.incidents i where i.id = (:'opened'::jsonb ->> 'incident_id')::bigint), 'a synthetic P2 incident on ONE-SYNTH: ' || :'opened');
select pg_temp.ok((select recipient = 'delivered@resend.dev' and kind = 'test' and status = 'pending' from one.deliveries where idempotency_key = 'test:' || :run),
                  'its delivery goes to Resend''s test address, never a real inbox');
select pg_temp.ok((select artefacts ? 'alert.open' from one.test_runs where id = :run), 'the action is recorded on the run');
update one.deliveries set status = 'sent', provider_id = 're_123', sent_at = now() where idempotency_key = 'test:' || :run;
set role service_role;
select pg_temp.ok((one.test_fact(:run, 'alert.delivery') ->> 'provider_id') = 're_123', 'the step sees the delivery sent');
select pg_temp.ok((one.test_act(:run, 'alert.close', jsonb_build_object('incident_id', (:'opened'::jsonb ->> 'incident_id')::bigint)) ->> 'closed')::boolean,
                  'and closes the incident');
reset role;
select pg_temp.ok((select resolved_by = 'test:T-ALERT' and acknowledged_at is not null and resolution = 'accepted' from one.incidents
                    where id = (:'opened'::jsonb ->> 'incident_id')::bigint), 'acknowledged and resolved by the test');

-- 3. With a test mailbox set, that is where it goes ------------------------------------------------------------------------
update one.settings set value = value || '{"mailbox": "one-tests@eduwit.in"}' where key = 'test_identities';
set role service_role;
select one.test_run_finish(:run, 'r', true, null, '[]', null);
select (one.test_run_start('T-ALERT', 'manual', 'T-ALERT:seams-2', 'r', 90) ->> 'id')::bigint as run2 \gset
select one.test_act(:run2, 'alert.open');
reset role;
select pg_temp.ok((select recipient = 'one-tests@eduwit.in' from one.deliveries where idempotency_key = 'test:' || :run2), 'the test mailbox when set');

-- 4. Synthetic incidents are not in the P2 digest -----------------------------------------------------------------------------
select pg_temp.ok((select count(*) from one.incidents where check_id = 'ONE-SYNTH' and (opened_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date) >= 1,
                  'there is a synthetic incident today');
update one.settings set value = value || '{"p2_digest_hour_ist": 0, "p2_digest_min_count": 0}' where key = 'alerts';
select pg_temp.ok((one.digest() ->> 'p2_today')::int = 0, 'and the digest does not count it');

truncate one.deliveries, one.incidents restart identity cascade;
delete from one.test_runs;
update one.settings s set value = t.value from t_saved t where s.key = t.key;
