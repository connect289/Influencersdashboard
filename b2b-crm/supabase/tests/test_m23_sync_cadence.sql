-- M23 sync cadence on STAGING, rolled back: the B2C link in real time, then batched (real students wait for the batch,
-- test leads stay real time, one b2c.leads_batch per interval with each lead at its newest version), the batch write
-- endpoint, the interval setting, and live partner polling every interval instead of every 10 minutes.
-- Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c7","role":"authenticated","aal":"aal2","email":"m23-admin@test.local"}', true)
$f$;
create function pg_temp.hold(p_lead bigint) returns void language sql as $f$
  with a as (insert into b2b.allocations (lead_id, cycle_no, destination_type, b2c_lane, status, mode, reason)
             values (p_lead, 1, 'in_house', 'sales', 'handed_off', 'fallback', 'paid_campaign') returning id)
  update public.student_leads l set destination_type = 'in_house', allocation_id = a.id, allocated_at = now(), allocation_reason = 'paid_campaign'
    from a where l.id = p_lead;
$f$;
create function pg_temp.upserts(p_lead bigint) returns int language sql as $f$
  select count(*)::int from b2b.integration_outbox o where o.event_type = 'b2c.lead_upserted' and (o.payload ->> 'lead_id')::bigint = p_lead;
$f$;

insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000c7', 'm23-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000c7', 'm23-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000c8', 'nobody23@test.local', 'authenticated', 'authenticated');
insert into b2b.api_keys (name, scopes, key_prefix, key_hash) values ('m23 b2c', '{b2c}', 'eb2b_m23test', encode(extensions.digest('eb2b_m23test_key_0001', 'sha256'), 'hex'));
do $x$
declare v_secret uuid := vault.create_secret('whsec_m23_test_secret_000000000000000000000000000000', 'b2b_m23_test_' || gen_random_uuid(), 'm23 test');
begin
  update b2b.webhook_endpoints set url = 'https://b2c.example.test/hooks/b2b', events = '{b2c.*}', active = true, secret_id = v_secret where consumer = 'b2c_crm';
  if not found then
    insert into b2b.webhook_endpoints (name, consumer, url, events, active, secret_id) values ('B2C CRM (m23 test)', 'b2c_crm', 'https://b2c.example.test/hooks/b2b', '{b2c.*}', true, v_secret);
  end if;
end $x$;
update b2b.settings set value = '{"enabled": true, "scope": "held"}' where key = 'b2c_link';
update b2b.settings set value = '{"interval_minutes": 15}' where key = 'sync';

-- H: a real student B2C holds; T: a test lead B2C holds; P: a partner's lead
insert into t select 'H', (b2b.intake_lead('{"full_name":"Cadence Held","phone":"919876504801","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id');
insert into t select 'T', (b2b.intake_lead('{"full_name":"Cadence Test","phone":"910000004802","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id');
insert into t select 'P', (b2b.intake_lead('{"full_name":"Cadence Partner","phone":"919876504803","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id');
select pg_temp.hold(pg_temp.v('H')::bigint);
update public.student_leads set destination_type = 'partner', partner_id = 20 where id = pg_temp.v('P')::bigint;

-- real time (the default)
select b2b.b2c_sync_lead(pg_temp.v('H')::bigint);
insert into r select 'realtime_webhook', pg_temp.upserts(pg_temp.v('H')::bigint) = 1, null;
insert into r select 'sync_minutes_default', b2b.sync_minutes() = 15, b2b.sync_minutes()::text;
insert into r select 'realtime_no_batch', b2b.b2c_batch_send(true) ->> 'why' = 'real time', null;

-- the Admin switches to the production cadence
set local role authenticated;
select pg_temp.admin();
do $x$
declare c jsonb; e text;
begin
  c := b2b.b2c_link_settings_save('{"delivery":"batched"}', 'm23 test: integration tested');
  insert into r values ('delivery_saved', c ->> 'delivery' = 'batched' and c ->> 'scope' = 'held' and jsonb_array_length(c -> 'writable') > 30, c::text);
  begin perform b2b.b2c_link_settings_save('{"delivery":"hourly"}', 'test'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('delivery_checked', e = 'delivery is realtime or batched', e);
  begin perform b2b.sync_settings_save(4, 'test'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('interval_checked', e = 'the sync interval is 5 to 60 minutes', e);
  c := b2b.sync_settings_save(20, 'm23 test: twenty');
  insert into r values ('interval_saved', (c ->> 'interval_minutes')::int = 20 and c -> 'b2c' ->> 'delivery' = 'batched' and c -> 'b2c' ->> 'next_batch_at' is not null, left(c::text, 300));
  c := b2b.webhook_endpoint_save(jsonb_build_object('id', (select id from b2b.webhook_endpoints where consumer = 'b2c_crm'), 'name', 'B2C CRM',
                                                    'url', 'https://b2c.example.test/hooks/b2b', 'events', jsonb_build_array('b2c.leads_batch', 'b2c.lead_upserted', 'b2c.lead_released')));
  insert into r values ('endpoint_accepts_batch', c -> 'events' @> '["b2c.leads_batch"]', null);
end $x$;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c8","role":"authenticated","aal":"aal2","email":"nobody23@test.local"}', true);
do $x$ declare e text; begin
  begin perform b2b.sync_cadence(); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r values ('cadence_admin_only', e = 'not allowed', e);
end $x$;
reset role;
insert into r select 'interval_in_use', b2b.sync_minutes() = 20, null;

-- batched: the real student's change waits; the test lead goes at once
update public.student_leads set city = 'Pune' where id = pg_temp.v('H')::bigint;
insert into t select 'h2', b2b.b2c_sync_lead(pg_temp.v('H')::bigint)::text;
insert into r select 'real_student_waits', (pg_temp.v('h2')::jsonb ->> 'batched')::boolean and pg_temp.upserts(pg_temp.v('H')::bigint) = 1, pg_temp.v('h2');
select pg_temp.hold(pg_temp.v('T')::bigint);
select b2b.b2c_sync_lead(pg_temp.v('T')::bigint);
insert into r select 'test_lead_realtime', pg_temp.upserts(pg_temp.v('T')::bigint) = 1, null;
insert into r select 'batch_not_due', (b2b.b2c_batch_send(false) ->> 'batches')::int = 0, null;
update public.student_leads set sub_stage = 'second change' where id = pg_temp.v('H')::bigint;
select b2b.b2c_sync_lead(pg_temp.v('H')::bigint);
-- the interval passes
update b2b.b2c_link_state set value = value || jsonb_build_object('at', now() - interval '21 minutes') where key = 'batch';
insert into t select 'b1', b2b.b2c_batch_send(false)::text;
insert into r select 'batch_sent', (pg_temp.v('b1')::jsonb ->> 'batches')::int = 1 and (pg_temp.v('b1')::jsonb ->> 'leads')::int = 2, pg_temp.v('b1');
insert into r select 'batch_content', count(*) = 1
                       and bool_and(jsonb_array_length(o.payload -> 'data' -> 'leads') = 2)
                       and bool_and(exists (select 1 from jsonb_array_elements(o.payload -> 'data' -> 'leads') x
                                             where x ->> 'lead_id' = pg_temp.v('H') and x ->> 'version' = '3' and x -> 'record' -> 'student' ->> 'city' = 'Pune'
                                               and x -> 'record' -> 'pipeline' ->> 'sub_stage' = 'second change'))
                       and bool_and(o.status = 'pending'), string_agg(left(o.payload::text, 200), ' | ')
  from b2b.integration_outbox o where o.event_type = 'b2c.leads_batch' and o.created_at = now();
insert into r select 'batch_empty_next', (b2b.b2c_batch_send(true) ->> 'leads')::int = 0, null;
insert into r select 'schema_tells_delivery', x -> 'result' ->> 'delivery' = 'batched' and (x -> 'result' ->> 'interval_minutes')::int = 20, null
  from (select b2b.api_b2c_schema('eb2b_m23test_key_0001') x) y;

-- the B2C CRM's own batch of writes
insert into t select 'w', b2b.api_b2c_batch('eb2b_m23test_key_0001', jsonb_build_object('items', jsonb_build_array(
  jsonb_build_object('op', 'update', 'lead_id', pg_temp.v('H')::bigint, 'request_id', 'm23-b1', 'actor', jsonb_build_object('name', 'Priya'), 'set', jsonb_build_object('stage', 'assigned')),
  jsonb_build_object('op', 'activity', 'lead_id', pg_temp.v('H')::bigint, 'request_id', 'm23-b2', 'kind', 'call', 'at', now() - interval '3 minutes', 'outcome', 'connected'),
  jsonb_build_object('op', 'update', 'lead_id', pg_temp.v('P')::bigint, 'request_id', 'm23-b3', 'set', jsonb_build_object('stage', 'assigned')),
  jsonb_build_object('op', 'delete', 'lead_id', pg_temp.v('H')::bigint))))::text;
insert into r select 'batch_writes', (x ->> 'ok')::boolean and (x -> 'result' ->> 'applied')::int = 2
                       and (select string_agg(i ->> 'status', ',' order by n) from jsonb_array_elements(x -> 'result' -> 'items') with ordinality y(i, n)) = '200,200,409,400'
                       and x -> 'result' -> 'items' -> 0 -> 'changed' = '["stage"]', left(x::text, 400)
  from (select pg_temp.v('w')::jsonb x) y;
insert into r select 'batch_writes_applied', l.stage = 'assigned' and l.contact_attempts = 1, l.stage || ' ' || coalesce(l.contact_attempts, 0)
  from public.student_leads l where l.id = pg_temp.v('H')::bigint;
insert into r select 'batch_writes_no_webhook', pg_temp.upserts(pg_temp.v('H')::bigint) = 1, null;
insert into r select 'batch_too_big', (b2b.api_b2c_batch('eb2b_m23test_key_0001', '{"items":[]}') ->> 'status')::int = 400, null;

-- live partner polling: every interval (20 here) unless the partner set its own minutes
update b2b.partners set adapter_type = 'inhouse' where id = 20;
insert into b2b.live_switches (scope, live, reason) values ('partner:20', true, 'm23 test') on conflict (scope) do update set live = true;
set local role authenticated;
select pg_temp.admin();
select b2b.partner_adapter_save(20, '{"env":"live","settings":{"create_url":"https://crm.partner.example/api/leads","auth_type":"header","auth_name":"X-Api-Key",
  "poll_url":"https://crm.partner.example/api/changes?since={since}"},"secrets":{"token":"IH-TOKEN-1234"},"poll":true}');
reset role;
update b2b.partners set outbound_auth = jsonb_set(outbound_auth, '{live}', (outbound_auth -> 'live') - 'poll_minutes') where id = 20;
insert into b2b.partner_adapter_state (partner_id, env, last_poll_at) values (20, 'live', now() - interval '12 minutes')
on conflict (partner_id, env) do update set last_poll_at = excluded.last_poll_at, poll_request_id = null, token_request_id = null;
select b2b.partner_sync_tick();
insert into r select 'no_poll_before_interval', poll_request_id is null, null from b2b.partner_adapter_state where partner_id = 20 and env = 'live';
update b2b.partner_adapter_state set last_poll_at = now() - interval '21 minutes' where partner_id = 20 and env = 'live';
select b2b.partner_sync_tick();
insert into r select 'poll_after_interval', poll_request_id is not null, null from b2b.partner_adapter_state where partner_id = 20 and env = 'live';
set local role authenticated;
select pg_temp.admin();
insert into r select 'cadence_lists_partner', exists (select 1 from jsonb_array_elements(b2b.sync_cadence() -> 'partners') p
                                                     where (p ->> 'id')::int = 20 and (p ->> 'live_minutes')::int = 20 and not (p ->> 'own_minutes')::boolean), null;
reset role;

-- back to real time
set local role authenticated;
select pg_temp.admin();
select b2b.b2c_link_settings_save('{"delivery":"realtime"}', 'm23 test: back');
reset role;
update public.student_leads set sub_stage = 'third change' where id = pg_temp.v('H')::bigint;
select b2b.b2c_sync_lead(pg_temp.v('H')::bigint);
insert into r select 'realtime_again', pg_temp.upserts(pg_temp.v('H')::bigint) = 2, null;

select name, ok, detail from r order by ok, name;
rollback;
