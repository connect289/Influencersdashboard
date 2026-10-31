-- M34 estate-audit fixes on STAGING, rolled back (needs m34a, m34b and m34c applied). Every row must say ok = true.
--   m34a  b2c_money_of, b2c_status_of, is_live and mapping_ready are not callable by public, anon or authenticated
--         (service_role keeps them), while the Admin reads and the referral API that use them still answer;
--         reroute_check refuses an account that is not on the team and answers the Admin
--   m34b  a training run without enough matured outcomes is logged as ml.training_skipped, not ml.model_failed; any other
--         training error still logs ml.model_failed
--   m34c  a refused signature is logged at most once a minute per alert type, partner and source; the answer is unchanged
begin;
-- hold the ML tick's lock so an overlapping staging cron run cannot make the calls below return busy; rollback releases it
select pg_advisory_xact_lock(hashtext('b2b.ml_tick'));
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.claims(p_sub text, p_email text) returns void language sql as $f$
  select set_config('request.jwt.claims', json_build_object('sub', p_sub, 'role', 'authenticated', 'aal', 'aal2', 'email', p_email)::text, true) $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;

insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-0000000000f1', 'm34-admin@test.local', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-0000000000f2', 'm34-stranger@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000f1', 'm34-admin@test.local');

-- ---------- m34a: grants ----------
insert into r select 'helpers_internal', bool_and(not has_function_privilege('public', f, 'execute') and not has_function_privilege('anon', f, 'execute')
                                                   and not has_function_privilege('authenticated', f, 'execute') and has_function_privilege('service_role', f, 'execute')),
                     string_agg(f::text, ', ')
  from unnest(array['b2b.b2c_money_of(bigint)'::regprocedure, 'b2b.b2c_status_of(bigint)'::regprocedure, 'b2b.is_live(text)'::regprocedure,
                    'b2b.mapping_ready(bigint)'::regprocedure]) f;
insert into r select 'reroute_check_grants', has_function_privilege('authenticated', 'b2b.reroute_check(bigint)', 'execute')
                     and has_function_privilege('service_role', 'b2b.reroute_check(bigint)', 'execute')
                     and not has_function_privilege('anon', 'b2b.reroute_check(bigint)', 'execute'), null;

-- a lead the B2C CRM holds, with a referral code: the lead table's B2C money column (b2c_money_of) and the referral API's
-- B2C stage (b2c_status_of) are evaluated for it below
do $x$ begin
  perform public.lead_intake(jsonb_build_object('phone', '919876503401', 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'M34 In House', 'interested_course', 'MBA', 'programme_level', 'PG', 'source', 'whatsapp_direct',
                               'classification', 'WARM')));
  insert into t select 'IH', id::text from public.student_leads where whatsapp_number = '919876503401';
  update public.student_leads set destination_type = 'in_house', referral_code = 'M34REF' where id = pg_temp.v('IH')::bigint;
end $x$;

-- a signed-in account that is not on the team: refused
set local role authenticated;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000f2', 'm34-stranger@test.local');
do $x$ declare e text; begin
  e := pg_temp.err('select b2b.reroute_check(1)');
  insert into r values ('reroute_check_refuses_stranger', e like '42501%', e);
  e := pg_temp.err('select b2b.b2c_money_of(1)');
  insert into r values ('money_of_refused', e like '42501%', e);
  e := pg_temp.err('select b2b.b2c_status_of(1)');
  insert into r values ('status_of_refused', e like '42501%', e);
  e := pg_temp.err($q$select b2b.is_live('routing')$q$);
  insert into r values ('is_live_refused', e like '42501%', e);
  e := pg_temp.err('select b2b.mapping_ready(1)');
  insert into r values ('mapping_ready_refused', e like '42501%', e);
end $x$;

-- the Admin: reroute_check answers, and the definer reads that call the four helpers still work
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000f1', 'm34-admin@test.local');
do $x$ declare x jsonb; k jsonb; begin
  x := b2b.reroute_check(-1);
  insert into r values ('reroute_check_admin', x ? 'allowed' and not (x ->> 'allowed')::boolean and x ->> 'why' = 'not an open partner allocation', x::text);
  x := b2b.leads_list(jsonb_build_object('q', pg_temp.v('IH'), 'include_test', true, 'limit', 5));
  insert into r values ('leads_list_works', jsonb_array_length(x -> 'rows') = 1 and (x -> 'rows' -> 0) ? 'b2c_money', left(x::text, 200));
  x := b2b.command_center();
  insert into r values ('command_center_works', x is not null, left(x::text, 200));
  x := b2b.mapping_overview();
  insert into r values ('mapping_overview_works', x is not null, left(x::text, 200));
  k := b2b.create_api_key('m34 referrals key', array['referrals']);
  insert into t values ('RK', k ->> 'key');
end $x$;
reset role;
-- since m34d a referrals key reads only the codes it is linked to
do $x$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'b2b' and table_name = 'api_keys' and column_name = 'referral_codes') then
    execute $q$update b2b.api_keys set referral_codes = '{M34REF}' where name = 'm34 referrals key'$q$;
  end if;
end $x$;
-- the referral API (anon, a referrals key) reads b2c_status_of inside its definer context
set local role anon;
do $x$ declare x jsonb; begin
  x := b2b.api_referral_outcomes(pg_temp.v('RK'), 'm34ref', null, 10);
  insert into r values ('referral_api_works', (x ->> 'ok')::boolean and jsonb_array_length(x -> 'result' -> 'outcomes') = 1, x::text);
end $x$;
reset role;

-- ---------- m34b: a training run without enough matured outcomes is skipped, not failed ----------
update b2b.settings set value = value || '{"auto_train":false}' where key = 'ml';
-- the longest maturity the engine allows (365 days), so no outcome of the staging data counts as matured
update b2b.settings set value = value || jsonb_build_object('a3_fixed', coalesce(value -> 'a3_fixed', '{}') || '{"matured_days":365}')
 where key = 'engine';
update b2b.ml_models set status = 'retired' where status = 'training';
with x as (insert into b2b.ml_models (version, requested_by) values ('m34-no-data', 'test') returning id) insert into t select 'M1', id::text from x;
insert into t select 'tick1', b2b.ml_tick()::text;
insert into r select 'no_data_is_skipped', m.status = 'failed' and m.error like 'not enough matured outcomes%'
                     and (select count(*) from b2b.events where type = 'ml.training_skipped' and payload ->> 'version' = 'm34-no-data'
                            and payload ->> 'reason' like 'not enough matured outcomes%') = 1
                     and not exists (select 1 from b2b.events where type = 'ml.model_failed' and payload ->> 'version' = 'm34-no-data'),
                     m.status || ' ' || coalesce(m.error, '') || ' ' || pg_temp.v('tick1')
  from b2b.ml_models m where m.id = pg_temp.v('M1')::bigint;
-- any other training error (here a broken setting) is still a failed model
update b2b.settings set value = value || '{"iterations":"not a number"}' where key = 'ml';
insert into b2b.ml_models (version, requested_by) values ('m34-broken', 'test');
insert into t select 'tick2', b2b.ml_tick()::text;
insert into r select 'other_errors_still_fail', m.status = 'failed'
                     and exists (select 1 from b2b.events where type = 'ml.model_failed' and payload ->> 'version' = 'm34-broken')
                     and not exists (select 1 from b2b.events where type = 'ml.training_skipped' and payload ->> 'version' = 'm34-broken'),
                     m.status || ' ' || coalesce(m.error, '') || ' ' || pg_temp.v('tick2')
  from b2b.ml_models m where m.version = 'm34-broken';

-- ---------- m34c: refused signatures are logged at most once a minute ----------
insert into t select 'L1', coalesce(b2b.log_auth_failure('alert.m34_probe', null, '{"source":"a"}')::text, 'skipped');
insert into t select 'L2', coalesce(b2b.log_auth_failure('alert.m34_probe', null, '{"source":"a"}')::text, 'skipped');
insert into t select 'L3', coalesce(b2b.log_auth_failure('alert.m34_probe', null, '{"source":"b"}')::text, 'skipped');
insert into r select 'auth_failure_throttled', pg_temp.v('L1') <> 'skipped' and pg_temp.v('L2') = 'skipped' and pg_temp.v('L3') <> 'skipped'
                     and (select count(*) from b2b.events where type = 'alert.m34_probe') = 2,
                     pg_temp.v('L1') || ' / ' || pg_temp.v('L2') || ' / ' || pg_temp.v('L3');
insert into r select 'auth_failure_internal', not has_function_privilege('anon', 'b2b.log_auth_failure(text, bigint, jsonb)', 'execute')
                     and not has_function_privilege('authenticated', 'b2b.log_auth_failure(text, bigint, jsonb)', 'execute'), null;
insert into r select 'ingest_grants_kept', bool_and(has_function_privilege('anon', f, 'execute')), string_agg(f::text, ', ')
  from unnest(array['b2b.b2ccrm_event_ingest(text, text, text)'::regprocedure, 'b2b.partner_event_ingest(text, text, text, text)'::regprocedure,
                    'b2b.meta_webhook_ingest(text, text)'::regprocedure, 'b2b.google_leadform_ingest(text)'::regprocedure]) f;
-- the B2C CRM's event webhook: an endpoint with a secret (staging's own, or one made here)
set local role authenticated;
select pg_temp.claims('aaaaaaaa-0000-0000-0000-0000000000f1', 'm34-admin@test.local');
do $x$ declare e jsonb; w bigint; begin
  select id into w from b2b.webhook_endpoints where consumer = 'b2c_crm';
  if w is null then
    e := b2b.webhook_endpoint_save('{"name":"M34 B2C","consumer":"b2c_crm","url":"https://b2c.example/v1/handoffs","events":["b2c.*"]}');
    w := (e ->> 'id')::bigint;
  end if;
  if (select secret_id from b2b.webhook_endpoints where id = w) is null then perform b2b.webhook_endpoint_rotate_secret(w); end if;
end $x$;
reset role;
insert into t select 'B0', count(*)::text from b2b.events where type = 'alert.b2c_bad_signature' and occurred_at > now() - interval '1 minute';
set local role anon;
do $x$ declare v1 jsonb; v2 jsonb; v3 jsonb; ts text := floor(extract(epoch from now()))::bigint::text; begin
  v1 := b2b.b2ccrm_event_ingest('{"event_id":"m34-1","type":"b2ccrm.opted_out","data":{}}', ts, 'sha256=bad');
  v2 := b2b.b2ccrm_event_ingest('{"event_id":"m34-2","type":"b2ccrm.opted_out","data":{}}', ts, 'sha256=bad');
  v3 := b2b.b2ccrm_event_ingest('{"event_id":"m34-3","type":"b2ccrm.opted_out","data":{}}', ts, 'sha256=bad');
  insert into r values ('bad_signature_still_401', (v1 ->> 'status')::int = 401 and (v2 ->> 'status')::int = 401 and (v3 ->> 'status')::int = 401
                        and v1 ->> 'error' = 'bad signature', v1::text);
end $x$;
reset role;
insert into r select 'bad_signature_logged_once', c >= 1 and c - pg_temp.v('B0')::int <= 1
                     and not exists (select 1 from b2b.product_events where source = 'b2c_crm' and event_id in ('m34-1', 'm34-2', 'm34-3')),
                     c || ' in the last minute, ' || pg_temp.v('B0') || ' before'
  from (select count(*)::int c from b2b.events where type = 'alert.b2c_bad_signature' and occurred_at > now() - interval '1 minute') x;

select name, ok, detail from r order by ok, name;
rollback;
