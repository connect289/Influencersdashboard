-- M22 B2C CRM link on STAGING, rolled back: the record and its versions, the webhook queued to the B2C endpoint, the
-- tick, the API (schema, get, feed, lookup, update, activity) with keys, idempotency, version conflicts and field rules,
-- release when a lead leaves B2C, the Admin's settings, resync, inspector and overview. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b7","role":"authenticated","aal":"aal2","email":"m22-admin@test.local"}', true)
$f$;
/* the API is called as anon, like the /v1 routes */
create function pg_temp.api(fn text, args jsonb) returns jsonb language plpgsql as $f$
declare res jsonb;
begin
  execute 'set local role anon';
  execute format('select b2b.%I(%s)', fn, (select string_agg(format('%s => %L::%s', key, value #>> '{}',
      case when key in ('p_lead_id', 'p_after') then 'bigint' when key = 'p_limit' then 'int' when key = 'p' then 'jsonb' else 'text' end), ', ')
    from jsonb_each(args))) into res;
  execute 'reset role';
  return res;
end $f$;
grant execute on function pg_temp.api(text, jsonb) to anon;

insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000b7', 'm22-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000b7', 'm22-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000b8', 'nobody22@test.local', 'authenticated', 'authenticated');
insert into b2b.api_keys (name, scopes, key_prefix, key_hash)
values ('m22 b2c', '{b2c}', 'eb2b_m22test', encode(extensions.digest('eb2b_m22test_key_0001', 'sha256'), 'hex')),
       ('m22 intake only', '{intake}', 'eb2b_m22intk', encode(extensions.digest('eb2b_m22test_key_0002', 'sha256'), 'hex'));
-- the B2C endpoint, subscribed to b2c.*
do $x$
declare v_secret uuid := vault.create_secret('whsec_m22_test_secret_000000000000000000000000000000', 'b2b_m22_test_' || gen_random_uuid(), 'm22 test');
begin
  update b2b.webhook_endpoints set url = 'https://b2c.example.test/hooks/b2b', events = '{b2c.*,b2b.*}', active = true, secret_id = v_secret where consumer = 'b2c_crm';
  if not found then
    insert into b2b.webhook_endpoints (name, consumer, url, events, active, secret_id) values ('B2C CRM (m22 test)', 'b2c_crm', 'https://b2c.example.test/hooks/b2b', '{b2c.*,b2b.*}', true, v_secret);
  end if;
end $x$;
update b2b.settings set value = '{}' where key = 'b2c_link';

-- H: a lead B2C holds; P: a partner's lead
insert into t select 'H', (b2b.intake_lead('{"full_name":"Link Held","phone":"919876504701","email":"link.held@example.com","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id');
insert into t select 'P', (b2b.intake_lead('{"full_name":"Link Partner","phone":"919876504702","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id');
with a as (insert into b2b.allocations (lead_id, cycle_no, destination_type, b2c_lane, status, mode, reason)
           values (pg_temp.v('H')::bigint, 1, 'in_house', 'sales', 'handed_off', 'fallback', 'paid_campaign') returning id)
update public.student_leads l set destination_type = 'in_house', allocation_id = a.id, allocated_at = now(), allocation_reason = 'paid_campaign'
  from a where l.id = pg_temp.v('H')::bigint;
update public.student_leads set destination_type = 'partner', partner_id = 20, allocated_at = now() where id = pg_temp.v('P')::bigint;
update b2b.b2c_link_state set value = jsonb_build_object('at', now() - interval '1 minute') where key = 'cursor';

select b2b.b2c_sync_tick();
insert into r select 'synced_held_only', exists (select 1 from b2b.b2c_sync where lead_id = pg_temp.v('H')::bigint and in_scope and version = 1)
                       and not exists (select 1 from b2b.b2c_sync where lead_id = pg_temp.v('P')::bigint), null;
insert into r select 'webhook_queued', count(*) = 1 and bool_and(o.payload -> 'data' -> 'record' -> 'student' ->> 'name' = 'Link Held'
                       and o.payload -> 'data' ->> 'version' = '1' and o.payload ->> 'id' = 'lead_' || pg_temp.v('H') || '_v1'
                       and o.idempotency_key = o.endpoint_id || ':lead_' || pg_temp.v('H') || '_v1'), string_agg(o.status, ' ')
  from b2b.integration_outbox o join b2b.webhook_endpoints w on w.id = o.endpoint_id and w.consumer = 'b2c_crm'
 where o.event_type = 'b2c.lead_upserted' and (o.payload ->> 'lead_id')::bigint = pg_temp.v('H')::bigint;
insert into r select 'record_shape', x -> 'allocation' ->> 'destination' = 'in_house' and x -> 'allocation' ->> 'b2c_lane' = 'sales'
                       and x -> 'student' ->> 'phone' = '919876504701' and x -> 'student' ->> 'email' = 'link.held@example.com'
                       and x -> 'pipeline' ? 'stage' and not x ? 'whatsapp_number' and (x ->> 'held_by_b2c')::boolean, left(x::text, 300)
  from (select b2b.b2c_record(l) x from public.student_leads l where l.id = pg_temp.v('H')::bigint) y;
insert into r select 'unchanged_not_resent', (b2b.b2c_sync_lead(pg_temp.v('H')::bigint) ->> 'changed')::boolean = false, null;

-- ---------- the API ----------
insert into r select 'bad_key', (pg_temp.api('api_b2c_schema', '{"p_key":"nope"}') ->> 'status')::int = 401, null;
insert into r select 'wrong_scope', (pg_temp.api('api_b2c_schema', '{"p_key":"eb2b_m22test_key_0002"}') ->> 'status')::int = 401, null;
insert into r select 'schema', (x ->> 'ok')::boolean and jsonb_array_length(x -> 'result' -> 'fields') > 60
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'fields') f where f ->> 'field' = 'stage' and (f ->> 'writable')::boolean)
                       and exists (select 1 from jsonb_array_elements(x -> 'result' -> 'fields') f where f ->> 'field' = 'phone' and not (f ->> 'writable')::boolean)
                       and x -> 'result' -> 'stages' @> '[{"key":"assigned"}]', null
  from (select pg_temp.api('api_b2c_schema', '{"p_key":"eb2b_m22test_key_0001"}') x) y;
insert into r select 'get_held', (x ->> 'ok')::boolean and x -> 'result' ->> 'version' = '1' and x -> 'result' -> 'record' ->> 'id' = pg_temp.v('H'), left(x::text, 200)
  from (select pg_temp.api('api_b2c_lead_get', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'))) x) y;
insert into r select 'get_partner_lead_404', (x ->> 'status')::int = 404, x::text
  from (select pg_temp.api('api_b2c_lead_get', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('P'))) x) y;
insert into r select 'feed', exists (select 1 from jsonb_array_elements(x -> 'result' -> 'leads') e where e ->> 'lead_id' = pg_temp.v('H') and e ->> 'type' = 'b2c.lead_upserted'
                                       and e -> 'record' -> 'student' ->> 'name' = 'Link Held')
                       and (x -> 'result' ->> 'next_after')::bigint >= (select seq from b2b.b2c_sync where lead_id = pg_temp.v('H')::bigint), left(x::text, 200)
  from (select pg_temp.api('api_b2c_leads_feed', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_after', (select seq - 1 from b2b.b2c_sync where lead_id = pg_temp.v('H')::bigint), 'p_limit', 50)) x) y;
insert into r select 'lookup', (x -> 'result' -> 'leads' -> 0 ->> 'lead_id') = pg_temp.v('H') and (x -> 'result' -> 'leads' -> 0 ->> 'held_by_b2c')::boolean, left(x::text, 200)
  from (select pg_temp.api('api_b2c_lead_lookup', '{"p_key":"eb2b_m22test_key_0001","p_phone":"98765 04701","p_email":null}') x) y;

-- update: stage, owner, attempts
insert into t select 'u1', pg_temp.api('api_b2c_lead_update', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'),
  'p', '{"request_id":"m22-r1","if_version":1,"actor":{"id":"u-7","email":"priya@eduwit.in","name":"Priya"},"set":{"stage":"assigned","owner_user_id":"11111111-2222-3333-4444-555555555555","contact_attempts":2,"city":" Pune "}}'))::text;
insert into r select 'update_applied', (x ->> 'ok')::boolean and x -> 'result' ->> 'version' = '2' and x -> 'result' -> 'changed' @> '["stage","owner_user_id","contact_attempts","city"]'
                       and x -> 'result' -> 'record' -> 'pipeline' ->> 'stage' = 'assigned', left(x::text, 300)
  from (select pg_temp.v('u1')::jsonb x) y;
insert into r select 'update_written', l.stage = 'assigned' and l.owner_user_id = '11111111-2222-3333-4444-555555555555' and l.contact_attempts = 2 and l.city = 'Pune'
                       and l.stage_changed_at is not null and l.updated_by = 'b2c_crm:priya@eduwit.in', l.stage || ' ' || coalesce(l.updated_by, '')
  from public.student_leads l where l.id = pg_temp.v('H')::bigint;
insert into r select 'update_audited', exists (select 1 from b2b.events e where e.type = 'b2c.lead_updated' and e.lead_id = pg_temp.v('H')::bigint and e.actor_type = 'b2c_crm'
                       and e.payload -> 'changes' -> 'stage' ->> 'to' = 'assigned' and e.payload -> 'actor' ->> 'name' = 'Priya')
                       and exists (select 1 from b2b.b2c_writes w where w.request_id = 'm22-r1' and w.status = 'applied' and w.version_after = 2), null;
insert into r select 'update_echo_queued', count(*) = 2, string_agg(o.payload -> 'data' ->> 'version' || ':' || o.status || ':' || coalesce(o.payload -> 'data' ->> 'origin', '-'), ' ')
  from b2b.integration_outbox o where o.event_type = 'b2c.lead_upserted' and (o.payload ->> 'lead_id')::bigint = pg_temp.v('H')::bigint;
insert into r select 'replay', (x ->> 'replayed')::boolean and x -> 'result' ->> 'version' = '2' and b2b.b2c_version(pg_temp.v('H')::bigint) = 2, left(x::text, 200)
  from (select pg_temp.api('api_b2c_lead_update', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'),
          'p', '{"request_id":"m22-r1","set":{"stage":"lost"}}')) x) y;
insert into r select 'version_conflict', (x ->> 'status')::int = 409 and x ->> 'version' = '2' and x -> 'record' -> 'pipeline' ->> 'stage' = 'assigned', left(x::text, 200)
  from (select pg_temp.api('api_b2c_lead_update', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'),
          'p', '{"request_id":"m22-r2","if_version":1,"set":{"stage":"counselled"}}')) x) y;
insert into r select 'field_rules', (x ->> 'status')::int = 422 and x -> 'fields' ->> 'phone' = 'is read-only for the B2C CRM'
                       and x -> 'fields' ->> 'stage' = 'is not a known stage' and x -> 'fields' ->> 'email' = 'is not an email address'
                       and x -> 'fields' ->> 'shoe_size' = 'unknown field' and x -> 'fields' ->> 'temperature' = 'must be hot, warm or cold', x::text
  from (select pg_temp.api('api_b2c_lead_update', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'),
          'p', '{"request_id":"m22-r3","set":{"phone":"9999999999","stage":"flying","email":"nope","shoe_size":9,"temperature":"boiling"}}')) x) y;
insert into r select 'refused_writes_nothing', l.stage = 'assigned' and b2b.b2c_version(l.id) = 2, null from public.student_leads l where l.id = pg_temp.v('H')::bigint;
insert into r select 'not_held_409', (x ->> 'status')::int = 409 and x ->> 'error' like 'the B2C CRM does not hold%', x::text
  from (select pg_temp.api('api_b2c_lead_update', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('P'),
          'p', '{"request_id":"m22-r4","set":{"stage":"assigned"}}')) x) y;
insert into r select 'needs_request_id', (pg_temp.api('api_b2c_lead_update', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'),
          'p', '{"set":{"stage":"assigned"}}')) ->> 'status')::int = 400, null;
select pg_temp.api('api_b2c_lead_update', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'), 'p', '{"request_id":"m22-c1","set":{"custom_fields":{"a":1,"b":"x"}}}'));
select pg_temp.api('api_b2c_lead_update', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'), 'p', '{"request_id":"m22-c2","set":{"custom_fields":{"a":null,"c":3}}}'));
insert into r select 'custom_fields_merge', l.custom_fields = '{"b":"x","c":3}', l.custom_fields::text from public.student_leads l where l.id = pg_temp.v('H')::bigint;
insert into r select 'unchanged_write', (x -> 'result' -> 'changed') = '[]' and b2b.b2c_version(pg_temp.v('H')::bigint) = 4, x::text
  from (select pg_temp.api('api_b2c_lead_update', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'), 'p', '{"request_id":"m22-c3","set":{"stage":"assigned"}}')) x) y;

-- activities
insert into t select 'a1', pg_temp.api('api_b2c_activity', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'),
  'p', jsonb_build_object('request_id', 'm22-a1', 'kind', 'call', 'at', now() - interval '5 minutes', 'outcome', 'connected', 'duration_seconds', 240,
                          'note', 'Wants the weekend batch', 'actor', jsonb_build_object('name', 'Priya'))))::text;
select pg_temp.api('api_b2c_activity', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'), 'p', '{"request_id":"m22-a2","kind":"note","note":"Sent brochure"}'));
insert into r select 'activity', (pg_temp.v('a1')::jsonb ->> 'ok')::boolean and l.contact_attempts = 3 and l.first_contacted_at is not null and l.last_contacted_at < now()
                       and l.last_activity_at = now() and b2b.b2c_version(l.id) = 6
                       and exists (select 1 from b2b.events e where e.type = 'b2c.activity' and e.lead_id = l.id and e.payload ->> 'outcome' = 'connected'),
                       l.contact_attempts || ' v' || b2b.b2c_version(l.id)
  from public.student_leads l where l.id = pg_temp.v('H')::bigint;
insert into r select 'activity_kind_checked', (pg_temp.api('api_b2c_activity', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'),
          'p', '{"request_id":"m22-a3","kind":"telepathy"}')) ->> 'status')::int = 400, null;

-- ---------- the Admin ----------
set local role authenticated;
select pg_temp.admin();
do $x$
declare o jsonb; e text; s jsonb; i jsonb;
begin
  o := b2b.b2c_link_overview();
  insert into r values ('overview', (o -> 'checks' ->> 'endpoint')::boolean and (o -> 'checks' ->> 'subscribed')::boolean and (o -> 'checks' ->> 'first_write')::boolean
                          and (o -> 'sync' ->> 'in_scope')::int >= 1 and jsonb_array_length(o -> 'log') > 0 and jsonb_array_length(o -> 'keys') >= 1, left((o -> 'checks')::text, 300));
  begin perform b2b.b2c_link_settings_save('{"scope":"held","writable":["phone"]}', 'test'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('settings_refuse_b2b_field', e like 'these fields cannot be written by the B2C CRM: phone%', e);
  begin perform b2b.b2c_link_settings_save('{"scope":"held","writable":[]}', ''); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('settings_need_reason', e like 'give a reason%', e);
  s := b2b.b2c_link_settings_save('{"enabled":true,"scope":"all","writable":["owner_user_id","sub_stage"]}', 'm22 test: narrow');
  insert into r values ('settings_saved', s ->> 'scope' = 'all' and s -> 'writable' = '["owner_user_id", "sub_stage"]', s::text);
  i := b2b.b2c_link_resync(pg_temp.v('H')::bigint);
  insert into r values ('resync_one', (i ->> 'leads')::int = 1 and (select version from b2b.b2c_sync where lead_id = pg_temp.v('H')::bigint) = 7, i::text);
  i := b2b.b2c_link_lead(pg_temp.v('H')::bigint);
  insert into r values ('inspector', (i ->> 'shared')::boolean and (i ->> 'version')::int = 7 and jsonb_array_length(i -> 'writes') >= 5
                          and jsonb_array_length(i -> 'deliveries') >= 2 and i ->> 'origin' = 'resync', left(i::text, 200));
  s := b2b.webhook_endpoint_save(jsonb_build_object('id', (select id from b2b.webhook_endpoints where consumer = 'b2c_crm'), 'name', 'B2C CRM', 'url', 'https://b2c.example.test/hooks/b2b',
                                                    'events', jsonb_build_array('b2c.lead_upserted', 'b2c.lead_released', 'b2c.lead_handed_off')));
  insert into r values ('endpoint_accepts_sync_events', s -> 'events' @> '["b2c.lead_upserted"]', null);
end $x$;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000b8","role":"authenticated","aal":"aal2","email":"nobody22@test.local"}', true);
do $x$ declare e text; begin
  begin perform b2b.b2c_link_overview(); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r values ('overview_admin_only', e = 'not allowed', e);
end $x$;
reset role;

-- narrowed writable list and scope all
insert into r select 'narrowed_fields', (x ->> 'status')::int = 422 and x -> 'fields' ->> 'stage' = 'is read-only for the B2C CRM', x::text
  from (select pg_temp.api('api_b2c_lead_update', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('H'), 'p', '{"request_id":"m22-n1","set":{"stage":"counselled"}}')) x) y;
select b2b.b2c_sync_lead(pg_temp.v('P')::bigint);
insert into r select 'scope_all_shares_partner_lead', exists (select 1 from b2b.b2c_sync where lead_id = pg_temp.v('P')::bigint and in_scope)
                       and (pg_temp.api('api_b2c_lead_get', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_lead_id', pg_temp.v('P'))) ->> 'ok')::boolean, null;
update b2b.settings set value = value || '{"scope":"held"}' where key = 'b2c_link';

-- the lead leaves B2C
update public.student_leads set destination_type = 'partner', partner_id = 20 where id = pg_temp.v('H')::bigint;
select b2b.b2c_sync_lead(pg_temp.v('H')::bigint);
select b2b.b2c_sync_lead(pg_temp.v('P')::bigint);
insert into r select 'released', s.in_scope = false and s.version = 8
                       and exists (select 1 from b2b.integration_outbox o where o.event_type = 'b2c.lead_released' and (o.payload ->> 'lead_id')::bigint = s.lead_id
                                     and o.payload -> 'data' -> 'record' ->> 'held_by_b2c' = 'false' and not (o.payload -> 'data' -> 'record') ? 'student'), s.version::text
  from b2b.b2c_sync s where s.lead_id = pg_temp.v('H')::bigint;
insert into r select 'released_in_feed', exists (select 1 from jsonb_array_elements(x -> 'result' -> 'leads') e where e ->> 'lead_id' = pg_temp.v('H')
                                                   and e ->> 'type' = 'b2c.lead_released' and e -> 'record' = 'null'), left(x::text, 300)
  from (select pg_temp.api('api_b2c_leads_feed', jsonb_build_object('p_key', 'eb2b_m22test_key_0001', 'p_after', 0, 'p_limit', 500)) x) y;
insert into r select 'released_not_resent', (b2b.b2c_sync_lead(pg_temp.v('H')::bigint) ->> 'changed')::boolean = false, null;

select name, ok, detail from r order by ok, name;
rollback;
