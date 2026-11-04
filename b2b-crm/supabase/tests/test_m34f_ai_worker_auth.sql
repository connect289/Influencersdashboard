-- M34f AI worker wake-up on STAGING, rolled back (needs m34e and m34f): the worker key is saved in Vault through AI settings
-- (an active ai_worker key only), the database sends it as a Bearer token when it wakes /v1/ai/tick, and it wakes only a
-- public worker address. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000f6', 'm34f-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000f6', 'm34f-admin@test.local');
-- the optimiser on, nothing queued from staging's own data (rolled back)
update b2b.settings set value = value || '{"enabled": true}' where key = 'ai';
update b2b.ai_runs set status = 'skipped' where status in ('queued', 'running');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000f6","role":"authenticated","aal":"aal2","email":"m34f-admin@test.local"}', true);
do $x$ declare e text; k jsonb; begin
  e := pg_temp.err($q$select b2b.ai_settings_save('{"worker_url":"https://127.0.0.1"}', 'm34f test')$q$);
  insert into r values ('worker_url_must_be_public', e like '22023 the worker address must be an https address on the public internet%', e);
  e := pg_temp.err($q$select b2b.ai_settings_save('{"worker_key":"eb2b_not_a_real_key_0123456789"}', 'm34f test')$q$);
  insert into r values ('worker_key_must_be_a_worker_key', e like '22023 the worker key must be an active API key%', e);
  k := b2b.create_api_key('m34f intake only', array['intake']);
  e := pg_temp.err(format($q$select b2b.ai_settings_save(jsonb_build_object('worker_key', %L), 'm34f test')$q$, k ->> 'key'));
  insert into r values ('worker_key_needs_the_scope', e like '22023 the worker key must be an active API key%', e);
  k := b2b.create_api_key('m34f worker', array['ai_worker']);
  insert into t values ('KEY', k ->> 'key');
  perform b2b.ai_settings_save(jsonb_build_object('worker_url', 'https://crm.example.com/', 'worker_key', k ->> 'key'), 'm34f test');
  perform b2b.ai_run_now('light_check', 'm34f test');
end $x$;
reset role;
insert into r select 'settings_record_only_the_flag', (b2b.ai_cfg() ->> 'worker_key_set')::boolean and not (b2b.ai_cfg()::text like '%' || pg_temp.v('KEY') || '%')
  and not exists (select 1 from b2b.settings_versions v where v.key = 'ai' and v.value::text like '%' || pg_temp.v('KEY') || '%'), null;
insert into r select 'key_in_vault', exists (select 1 from vault.decrypted_secrets s where s.name = 'b2b_ai_worker_key' and s.decrypted_secret = pg_temp.v('KEY')), null;
insert into r select 'wake_sends_the_key', exists (select 1 from net.http_request_queue q where q.url = 'https://crm.example.com/v1/ai/tick'
                                                     and q.headers ->> 'Authorization' = 'Bearer ' || pg_temp.v('KEY')),
  (select string_agg(q.url, ' ') from net.http_request_queue q where q.url like '%/v1/ai/tick');
-- a stored internal address is never woken
update b2b.settings set value = value || '{"worker_url": "https://10.0.0.1"}' where key = 'ai';
insert into r select 'wake_refuses_internal', (x ->> 'woken')::boolean is false and x ->> 'why' = 'the worker address is not allowed', x::text
  from (select b2b.ai_wake() x) y;
insert into r select 'wake_internal', not has_function_privilege('anon', 'b2b.ai_wake()', 'execute') and not has_function_privilege('authenticated', 'b2b.ai_wake()', 'execute'), null;
select name, ok, detail from r order by ok, name;
rollback;
