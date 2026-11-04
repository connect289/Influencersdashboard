-- M34e outbound addresses on STAGING, rolled back (needs m34e). The database calls only addresses on the public internet:
-- b2b.url_allowed (the same lists as web/lib/url-safety.test.ts), the save functions refuse other addresses, and a stored
-- one is refused where pg_net is called (pushes, webhook deliveries). Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;

-- ---------- the rule ----------
insert into r select 'url_refused', bool_and(not b2b.url_allowed(u)), coalesce(string_agg(u, ' ') filter (where b2b.url_allowed(u)), 'all refused')
  from unnest(array[
    'http://crm.partner.com/api',
    'https://localhost/x', 'https://LOCALHOST:8443/', 'https://localhost./',
    'https://127.0.0.1/', 'https://127.1/', 'https://2130706433/', 'https://0x7f000001/', 'https://0177.0.0.1/',
    'https://10.0.0.5/', 'https://172.16.3.4/', 'https://172.31.255.255/', 'https://192.168.1.1/',
    'https://169.254.169.254/latest/meta-data/', 'https://100.100.100.200/', 'https://0.0.0.0/', 'https://255.255.255.255/', 'https://224.0.0.1/',
    'https://[::1]/', 'https://[fd00:ec2::254]/',
    'https://metadata.google.internal/computeMetadata/v1/', 'https://kong:8000/', 'https://db/', 'https://rest.internal/',
    'https://printer.local/', 'https://api.default.svc.cluster.local/', 'https://router.lan/',
    'https://127.0.0.1.nip.io/', 'https://10.0.0.1.sslip.io/', 'https://7f000001.c0a80001.rbndr.us/', 'https://foo.lvh.me/', 'https://127-0-0-1.partner.com/',
    'https://partner.com@127.0.0.1/', 'https://user:pass@partner.com/', 'https://partner.com\@127.0.0.1/', 'https://partner .com/',
    'https://partner.com:0/', 'https://partner.com:70000/']) u;
insert into r select 'url_allowed', bool_and(b2b.url_allowed(u)), coalesce(string_agg(u, ' ') filter (where not b2b.url_allowed(u)), 'all allowed')
  from unnest(array[
    'https://crm.partner.com/api/leads', 'https://api-in21.leadsquared.com/v2/', 'https://login.salesforce.com',
    'https://www.zohoapis.in/crm/v2', 'https://partner.com:8443/x', 'https://8.8.8.8/', 'https://b2c.example/v1/handoffs',
    'https://crm.eduwit.in', 'https://xn--bcher-kva.example/', 'https://172.32.0.1/', 'https://100.128.0.1/', 'https://192.169.0.1/',
    'HTTPS://CRM.PARTNER.COM/Leads?x=1']) u;
insert into r select 'url_allowed_internal', not has_function_privilege('anon', 'b2b.url_allowed(text)', 'execute')
  and not has_function_privilege('authenticated', 'b2b.url_allowed(text)', 'execute'), null;

-- ---------- saving ----------
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000e5', 'm34e-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000e5', 'm34e-admin@test.local');
with x as (insert into b2b.partners (slug, name, status, adapter_type) values ('m34e-inhouse', 'M34e In-house', 'onboarding', 'inhouse') returning id)
insert into t select 'IH', id::text from x;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e5","role":"authenticated","aal":"aal2","email":"m34e-admin@test.local"}', true);
do $x$ declare e text; begin
  e := pg_temp.err($q$select b2b.partner_save('{"slug":"m34e-private","name":"M34e private","api_base_url":"https://10.1.2.3/leads"}')$q$);
  insert into r values ('partner_api_url_refused', e like '22023 API base URL: an https address on the public internet%', e);
  e := pg_temp.err($q$select b2b.partner_save('{"slug":"m34e-loopback","name":"M34e loopback","test_endpoint":"https://localhost/test"}')$q$);
  insert into r values ('partner_test_endpoint_refused', e like '22023 test endpoint: an https address on the public internet%', e);
  e := pg_temp.err($q$select b2b.webhook_endpoint_save('{"name":"M34e metadata","consumer":"other","url":"https://169.254.169.254/hook","events":["b2c.*"]}')$q$);
  insert into r values ('endpoint_url_refused', e like '22023 the URL must be an https address on the public internet%', e);
  e := pg_temp.err(format($q$select b2b.partner_adapter_save(%s, '{"env":"live","settings":{"create_url":"https://192.168.0.10/api/leads","auth_type":"none"}}')$q$, pg_temp.v('IH')));
  insert into r values ('adapter_create_url_refused', e like '22023 create url must be an https address on the public internet%', e);
end $x$;
reset role;

-- ---------- sending: an address stored before m34e is refused where pg_net is called ----------
-- a push (a test allocation goes to the partner's test endpoint)
with x as (insert into b2b.partners (slug, name, status, adapter_type, test_endpoint) values ('m34e-push', 'M34e push', 'active', 'generic_rest', 'https://10.9.8.7/leads') returning id)
insert into t select 'PP', id::text from x;
insert into public.student_leads (whatsapp_number, student_name, interested_course, lead_source) values ('919876534501', 'M34e Push', 'MBA', 'website');
with x as (
  insert into b2b.allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, mode, attempt_no, is_test, origin)
  select id, 1, 'm34e', 'partner', pg_temp.v('PP')::bigint, 'queued', 'commission_first', 1, true, 'auto' from public.student_leads where whatsapp_number = '919876534501'
  returning id)
insert into t select 'PA', id::text from x;
select set_config('b2b.actor', 'engine', true);
select b2b.push_dispatch(100);
insert into r select 'push_refused', a.last_error like 'the partner address is not allowed%'
  and not exists (select 1 from b2b.push_requests q where q.allocation_id = a.id)
  and not exists (select 1 from net.http_request_queue q where q.url like 'https://10.9.8.7%'), a.status || ' ' || coalesce(a.last_error, '')
  from b2b.allocations a where a.id = pg_temp.v('PA')::bigint;
-- a webhook delivery
with x as (insert into b2b.webhook_endpoints (name, consumer, url, events, secret_id, active)
           values ('M34e private hook', 'other', 'https://169.254.169.254/hook', '{b2c.*}', vault.create_secret('whsec_m34e_test_only', 'm34e_test_hook_secret'), true)
           returning id)
insert into t select 'EP', id::text from x;
insert into b2b.integration_outbox (event_type, target, payload, idempotency_key, status, next_attempt_at, endpoint_id)
values ('ping', 'other', '{"type":"ping","test":true}', 'm34e-ping-' || pg_temp.v('EP'), 'pending', now() - interval '1 minute', pg_temp.v('EP')::bigint);
select b2b.outbox_tick();
insert into r select 'delivery_refused', o.status = 'dead' and o.last_error like 'the endpoint address is not allowed%'
  and not exists (select 1 from net.http_request_queue q where q.url = 'https://169.254.169.254/hook')
  and exists (select 1 from b2b.events e where e.type = 'alert.webhook_dead' and (e.payload ->> 'outbox_id')::bigint = o.id), o.status || ' ' || coalesce(o.last_error, '')
  from b2b.integration_outbox o where o.idempotency_key = 'm34e-ping-' || pg_temp.v('EP');

select name, ok, detail from r order by ok, name;
rollback;
