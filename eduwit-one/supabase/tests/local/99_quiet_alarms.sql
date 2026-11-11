-- Migration 0038 (D-136): ONE-01 leaves the end-to-end tests out of its slow checks; a WhatsApp line that was never set
-- up passes its heartbeat check and one that has reported keeps the usual rule; the harness scenario setting moved off
-- the old default. (The schema acknowledgement is tested in 99_privileges.sql.) Local cluster only; it tidies up.
\set ON_ERROR_STOP 1
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
-- A check's own SQL, as the tick would run it: (ok, value).
create or replace function pg_temp.run(p_id text) returns jsonb language plpgsql as $$
declare v_ok boolean; v_value jsonb;
begin
  execute (select sql from one.checks where id = p_id) into v_ok, v_value;
  return jsonb_build_object('ok', v_ok, 'value', v_value);
end $$;

-- 1. ONE-01: a slow test is not a slow check; a slow check still is -------------------------------------------------------
delete from one.results where duration_ms > 5000;
insert into one.results (check_id, status, duration_ms) values ('T-WITTY-QUALIFY', 'fail', 85000);
select pg_temp.ok(pg_temp.run('ONE-01') -> 'value' -> 'slow_checks' = '[]'::jsonb, 'a journey that took 85 s is not a slow check');
insert into one.results (check_id, status, duration_ms) values ('B2B-04', 'ok', 9000);
select pg_temp.ok(pg_temp.run('ONE-01') -> 'value' -> 'slow_checks' = '["B2B-04"]'::jsonb, 'a check that took 9 s still is');
delete from one.results where duration_ms > 5000;

-- 2. WhatsApp heartbeats: never set up passes; set up or once reported keeps the usual rule --------------------------------
create temp table t_wa as select value from one.settings where key = 'whatsapp';
create temp table t_hb as select * from one.heartbeats where component like 'whatsapp:%' or component = 'one:app';
delete from one.heartbeats where component like 'whatsapp:%' or component = 'one:app';
-- The app has been answering for an hour, so a component never seen is past its grace.
insert into one.heartbeats (component, last_ok_at, expected_interval_s, created_at) values ('one:app', now(), 60, now() - interval '1 hour');
update one.settings set value = value || '{"phone_ids": {"witty": "111"}}' where key = 'whatsapp';
select pg_temp.ok((pg_temp.run('HB-whatsapp:b2c') ->> 'ok')::boolean and pg_temp.run('HB-whatsapp:b2c') -> 'value' = '{"configured": false}'::jsonb,
                  'Spark''s line, never set up, passes with configured false');
select pg_temp.ok(not (pg_temp.run('HB-whatsapp:witty') ->> 'ok')::boolean and (pg_temp.run('HB-whatsapp:witty') -> 'value' ->> 'never_seen')::boolean,
                  'Witty''s line has a number id and no heartbeat: it fails as before');
insert into one.heartbeats (component, last_ok_at, expected_interval_s) values ('whatsapp:witty', now(), 900);
select pg_temp.ok((pg_temp.run('HB-whatsapp:witty') ->> 'ok')::boolean, 'and passes once the probe has written it');
update one.settings set value = value || '{"phone_ids": {"witty": "111", "b2c": "222"}}' where key = 'whatsapp';
select pg_temp.ok(not (pg_temp.run('HB-whatsapp:b2c') ->> 'ok')::boolean, 'with a number id entered, Spark''s line is expected and fails until it reports');
insert into one.heartbeats (component, last_ok_at, expected_interval_s) values ('whatsapp:b2c', now() - interval '1 day', 900);
update one.settings set value = value || '{"phone_ids": {"witty": "111"}}' where key = 'whatsapp';
select pg_temp.ok(not (pg_temp.run('HB-whatsapp:b2c') ->> 'ok')::boolean,
                  'a line that reported once and went silent fails even after its id is removed');
delete from one.heartbeats where component like 'whatsapp:%' or component = 'one:app';
insert into one.heartbeats select * from t_hb;
update one.settings s set value = t.value from t_wa t where s.key = 'whatsapp';

-- 3. The harness scenario: off the old default ------------------------------------------------------------------------------
select pg_temp.ok(one.setting('n8n') ->> 'test_harness_scenario' = 'one_qualify_hot', 'T-WITTY-QUALIFY plays Eduwit One''s own scenario');

select 'QUIET ALARMS PASSED';
