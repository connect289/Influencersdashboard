-- Phase 3 on the stubbed path (spec §9, §14): a P1 emails, re-sends at 30 and 60 minutes with the second contact,
-- stops when acknowledged; a failing delivery retries once then counts for ONE-01; mutes hold and re-route; a storm
-- sends one alert and suppresses the rest; the P2 digest; developer copies. Local test cluster only.
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
truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
create temp table t_alerts as select value from one.settings where key = 'alerts';
set role postgres;
select one.settings_put('alerts', one.setting('alerts')
  || '{"escalation": {"resend_min": 30, "second_contact_min": 60, "repeat_min": 60, "second_contact": ["second@eduwit.in"]}, "developer_email": "dev@eduwit.in", "p2_digest_hour_ist": 0}',
  'test@eduwit.in', 'alerts test');

-- 1. A P1 queues one email; the sender claims it with the incident and marks it sent ------------------------------
select one.open_or_touch_incident('PLAT-05', 'P1', '{"value": {"spark_base_url": false}}');
set role service_role;
create temp table t_claim as select one.claim_deliveries(10) as c;
select pg_temp.ok((select jsonb_array_length(c) = 1 and c #>> '{0,incident,check_id}' = 'PLAT-05' and c #>> '{0,recipient}' = 'connect@eduwit.in' from t_claim),
                  'one P1 email to the P1 inbox, claimed with its incident: ' || (select c::text from t_claim));
select pg_temp.ok(one.finish_delivery((select (c #>> '{0,id}')::bigint from t_claim), true, null, 'prov-1') = 'sent', 'finished as sent');
reset role;
select pg_temp.ok((select alert_state = 'sent' from one.incidents where check_id = 'PLAT-05'), 'the incident is now "sent"');

-- 2. Unacknowledged: re-sent at 30 min, second contact from 60 min; acknowledging stops it ------------------------
update one.incidents set routed_at = now() - interval '31 minutes' where check_id = 'PLAT-05';
set role postgres;
select one.escalate();
select pg_temp.ok((select count(*) = 1 from one.deliveries where kind = 'escalation' and escalation_level = 1), 'level 1 re-send at 30 min');
select pg_temp.ok((select alert_state = 'escalated_1' from one.incidents where check_id = 'PLAT-05'), 'alert state escalated_1');
select one.escalate();
select pg_temp.ok((select count(*) = 1 from one.deliveries where kind = 'escalation' and escalation_level = 1), 'escalating again in the same window adds nothing');
reset role;
update one.incidents set routed_at = now() - interval '61 minutes' where check_id = 'PLAT-05';
set role postgres;
select one.escalate();
select pg_temp.ok((select count(*) = 2 and bool_or(recipient = 'second@eduwit.in') from one.deliveries where escalation_level = 2), 'level 2 at 60 min reaches the P1 inbox and the second contact');
select one.acknowledge_incident((select id from one.incidents where check_id = 'PLAT-05'), 'owner@eduwit.in');
reset role;
update one.incidents set routed_at = now() - interval '125 minutes' where check_id = 'PLAT-05';
set role postgres;
select one.escalate();
select pg_temp.ok((select count(*) = 0 from one.deliveries where escalation_level >= 3), 'an acknowledged incident stops escalating');
set role service_role;
select one.claim_deliveries(10);
reset role;
select pg_temp.ok((select count(*) = 3 from one.deliveries where kind = 'escalation' and status = 'suppressed'), 'its unsent escalations are closed, not sent');

-- 3. A failing alert retries with a growing wait, is final on its eighth try, and counts for ONE-01 (D-085) -------------
set role postgres;
select one.open_or_touch_incident('B2B-01', 'P1', '{"value": {"ok": false}}');
set role service_role;
create temp table t_fail as select one.claim_deliveries(10) as c;
select pg_temp.ok(one.finish_delivery((select (c #>> '{0,id}')::bigint from t_fail), false, 'status 500') = 'retry', 'first failure retries');
reset role;
update one.deliveries set next_attempt_at = now() where status = 'pending';
set role service_role;
create temp table t_fail2 as select one.claim_deliveries(10) as c;
select pg_temp.ok(one.finish_delivery((select (c #>> '{0,id}')::bigint from t_fail2), false, 'status 500') = 'retry', 'the second failure of an alert retries too (D-085)');
reset role;
select pg_temp.ok((select status = 'pending' and attempts = 2 and next_attempt_at between now() + interval '3 minutes' and now() + interval '5 minutes'
                     from one.deliveries where id = (select (c #>> '{0,id}')::bigint from t_fail2)), 'with a growing wait (2, then 4 minutes)');
update one.deliveries set attempts = 7, next_attempt_at = now() where status = 'pending';
set role service_role;
create temp table t_fail3 as select one.claim_deliveries(10) as c;
select pg_temp.ok(one.finish_delivery((select (c #>> '{0,id}')::bigint from t_fail3), false, 'status 500') = 'failed', 'the eighth failure is final');
reset role;
set role postgres;
select one.run_check('ONE-01');
select pg_temp.ok((select (value ->> 'deliveries_failed_24h')::int = 1 from one.results where check_id = 'ONE-01' order by id desc limit 1), 'ONE-01 sees the failed delivery');

-- 4. A mute holds deliveries; when it ends, the still-open incident is routed again --------------------------------
select one.mute('check', 'B2B-03', 60, 'partner maintenance', 'owner@eduwit.in');
select one.open_or_touch_incident('B2B-03', 'P1', '{"value": {}}');
select pg_temp.ok((select alert_state = 'muted' from one.incidents where check_id = 'B2B-03'), 'a muted check records but does not deliver');
select pg_temp.ok((select count(*) = 0 from one.deliveries d join one.incidents i on i.id = d.incident_id where i.check_id = 'B2B-03'), 'no delivery while muted');
reset role;
update one.mutes set starts_at = now() - interval '2 hours', ends_at = now() - interval '1 second' where target = 'B2B-03';
set role postgres;
select one.escalate();
select pg_temp.ok((select alert_state = 'pending' and alert_seq = 2 from one.incidents where check_id = 'B2B-03'), 'mute over: routed again');
select pg_temp.ok((select count(*) = 1 from one.deliveries d join one.incidents i on i.id = d.incident_id where i.check_id = 'B2B-03'), 'and the alert is queued');

-- 5. A storm: one alert, the P1s around it suppressed and filed under it --------------------------------------------
select one.open_or_touch_incident(c, 'P1', '{"value": {}}')
  from unnest(array['B2B-02', 'B2B-04', 'B2B-05', 'B2B-06', 'B2B-07', 'B2C-01', 'B2C-02', 'B2C-04', 'WEB-01', 'WEB-03', 'INT-01']) c;
select one.run_check('ONE-STORM');
select pg_temp.ok((select severity = 'P1' and alert_state = 'pending' from one.incidents where check_id = 'ONE-STORM' and resolved_at is null), 'the storm opens one P1');
select pg_temp.ok((select count(*) >= 11 from one.incidents i where i.parent_id = (select id from one.incidents where check_id = 'ONE-STORM') and alert_state = 'suppressed'),
                  'the P1s that opened with it are suppressed under it');
select one.open_or_touch_incident('INT-02', 'P1', '{"value": {}}');
select pg_temp.ok((select alert_state = 'suppressed' from one.incidents where check_id = 'INT-02'), 'a P1 during the storm is suppressed too');
select pg_temp.ok((select model_hint = 'deep' from one.ai_tasks t join one.incidents i on i.id = t.incident_id where i.check_id = 'ONE-STORM'), 'the storm triage runs on the deep model');
set role service_role;
create temp table t_storm as select one.claim_deliveries(50) as c;
select pg_temp.ok((select count(*) = 1 from jsonb_array_elements((select c from t_storm)) e where e #>> '{incident,check_id}' = 'ONE-STORM'), 'the storm alert is sent');
select pg_temp.ok((select not exists (select 1 from jsonb_array_elements((select c from t_storm)) e where e #>> '{incident,check_id}' in ('B2B-02', 'WEB-01', 'INT-02'))),
                  'the suppressed P1s are not sent');
reset role;

-- 6. The P2 digest, once a day, with the day's P2 list ---------------------------------------------------------------
set role postgres;
select one.open_or_touch_incident(c, 'P2', '{"value": {}}') from unnest(array['B2B-08', 'B2B-09', 'B2B-10', 'B2B-11', 'B2B-12', 'B2B-13']) c;
select pg_temp.ok((one.digest() ->> 'queued')::int = 1, 'more than 5 P2 today: one digest to the P1 inbox');
select pg_temp.ok((one.digest() ->> 'queued')::int = 0, 'only once a day');
set role service_role;
create temp table t_dig as select e as d from jsonb_array_elements(one.claim_deliveries(50)) e where e ->> 'kind' = 'digest';
select pg_temp.ok((select jsonb_array_length(d -> 'digest') >= 6 from t_dig), 'the digest carries the day''s P2 list');
reset role;

-- 7. A developer copy for incidents tagged "code" -------------------------------------------------------------------
set role postgres;
select one.open_or_touch_incident('PLAT-08', 'P2', '{"value": {}}');
select pg_temp.ok((select count(*) = 1 from one.deliveries where recipient = 'dev@eduwit.in'), 'PLAT-08 (tagged code) copies the developer');

-- 8. A P1 nobody acknowledges for a day: the reminder level stops at 10 (what deliveries allow) instead of failing the
--    whole alerts step (production, 25 to 29 Oct 2026; 0025, D-098) ---------------------------------------------------
set role postgres;
select one.open_or_touch_incident('WEB-02', 'P1', '{"value": {"ok": false}}');
reset role;
update one.incidents set routed_at = now() - interval '20 hours', alert_state = 'sent' where check_id = 'WEB-02';
set role postgres;
select one.escalate();
select pg_temp.ok((select max(d.escalation_level) = 10 and count(*) filter (where d.escalation_level = 10) >= 1
                     from one.deliveries d join one.incidents i on i.id = d.incident_id where i.check_id = 'WEB-02'),
                  'after 20 hours the reminder is level 10, not 20: the alerts step keeps running');
select pg_temp.ok((select alert_state = 'escalated_2' from one.incidents where check_id = 'WEB-02'), 'and the incident is escalated_2');
create temp table t_cap as select count(*) as n from one.deliveries d join one.incidents i on i.id = d.incident_id where i.check_id = 'WEB-02';
select one.escalate();
select pg_temp.ok((select count(*) = (select n from t_cap) from one.deliveries d join one.incidents i on i.id = d.incident_id where i.check_id = 'WEB-02'),
                  'the tenth reminder is the last: another run adds nothing');

reset role;
update one.settings set value = (select value from t_alerts) where key = 'alerts';
truncate one.ai_tasks, one.deliveries, one.actions, one.proposals, one.incidents, one.mutes restart identity cascade;
