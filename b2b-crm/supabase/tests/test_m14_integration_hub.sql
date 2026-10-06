-- M14 integration hub and the B2C CRM contract, on STAGING, rolled back. Every row of the final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon;

-- leads: one without consent (→ B2C sales), one paid with consent (→ B2C sales, then routed to partners by B2C)
do $x$
declare v_id bigint;
begin
  perform public.lead_intake(jsonb_build_object('phone', '919876502001', 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'Hub One', 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                               'state', 'Delhi', 'source', 'whatsapp_direct', 'classification', 'WARM')));
  perform public.lead_intake(jsonb_build_object('phone', '919876502002', 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'Hub Two', 'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                               'state', 'Delhi', 'source', 'meta_lead_ad', 'classification', 'WARM', 'consent_partner_share_at', now())));
  insert into t select 'lead1', id::text from public.student_leads where whatsapp_number = '919876502001';
  insert into t select 'lead2', id::text from public.student_leads where whatsapp_number = '919876502002';
end $x$;

insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'hub-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'hub-admin@test.local');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a9","role":"authenticated","aal":"aal2","email":"hub-admin@test.local"}', true);
do $x$
declare e jsonb; v_secret text; k jsonb;
begin
  begin perform b2b.webhook_endpoint_save('{"name":"B2C CRM","consumer":"b2c_crm","url":"http://insecure.example","events":["b2c.*"]}');
        insert into r values ('https_required', false, 'saved');
  exception when others then insert into r values ('https_required', sqlerrm like '%https%', sqlerrm); end;
  begin perform b2b.webhook_endpoint_save('{"name":"B2C CRM","consumer":"b2c_crm","url":"https://b2c.example/v1/handoffs","events":["lead.nope"]}');
        insert into r values ('unknown_event_refused', false, 'saved');
  exception when others then insert into r values ('unknown_event_refused', sqlerrm like 'unknown event%', sqlerrm); end;
  e := b2b.webhook_endpoint_save('{"name":"B2C CRM","consumer":"b2c_crm","url":"https://b2c.example/v1/handoffs","events":["b2c.*","b2b.*"]}');
  insert into t values ('endpoint', e ->> 'id');
  begin perform b2b.webhook_endpoint_set_active((e ->> 'id')::bigint, true, 'going live'); insert into r values ('secret_before_active', false, 'activated');
  exception when others then insert into r values ('secret_before_active', sqlerrm like 'generate the signing secret%', sqlerrm); end;
  v_secret := b2b.webhook_endpoint_rotate_secret((e ->> 'id')::bigint);
  insert into t values ('secret', v_secret);
  insert into r values ('secret_shown_once', v_secret like 'whsec_%' and (select secret_id is not null from b2b.webhook_endpoints where id = (e ->> 'id')::bigint), left(v_secret, 10));
  perform b2b.webhook_endpoint_set_active((e ->> 'id')::bigint, true, 'staging test');
  begin perform b2b.webhook_endpoint_save('{"name":"Second B2C","consumer":"b2c_crm","url":"https://x.example/h","events":["b2c.*"]}');
        insert into r values ('one_b2c_endpoint', false, 'saved');
  exception when others then insert into r values ('one_b2c_endpoint', sqlerrm like 'there is already a B2C%', sqlerrm); end;
  k := b2b.create_api_key('B2C CRM service key', array['events']);
  insert into t values ('key', k ->> 'key');
  perform b2b.webhook_test((e ->> 'id')::bigint);
end $x$;
reset role;

-- routing: lead 1 has no consent (B2C sales), lead 2 is paid (B2C sales)
do $x$ begin
  perform set_config('b2b.actor', 'engine', true);
  perform b2b.route_decide((select v::bigint from t where k = 'lead1'), true, 'hub', 'auto');
  perform b2b.route_decide((select v::bigint from t where k = 'lead2'), true, 'hub', 'auto');
end $x$;

insert into r select 'handoffs_queued', count(*) = 2 and bool_and(o.payload ->> 'type' = 'b2c.lead_handed_off' and o.payload -> 'data' ? 'b2c_lane'
    and o.payload -> 'data' ? 'reason' and o.payload ? 'lead_id' and o.status = 'pending'), string_agg(o.payload -> 'data' ->> 'reason', ' ')
  from b2b.integration_outbox o where o.endpoint_id = (select v::bigint from t where k = 'endpoint') and o.event_type = 'b2c.lead_handed_off';
insert into r select 'unsubscribed_not_queued', count(*) = 0, count(*)::text
  from b2b.integration_outbox o where o.endpoint_id = (select v::bigint from t where k = 'endpoint') and o.event_type like 'lead.%';

-- delivery: send, the receiver fails once, then accepts
insert into r select 'tick_sends', (x ->> 'sent')::int = 3, x::text from (select b2b.outbox_tick() x) y;  -- 2 hand-offs + the test ping
insert into r select 'signed_request', q.url = 'https://b2c.example/v1/handoffs' and q.headers ->> 'X-Eduwit-Signature' =
    'sha256=' || encode(extensions.hmac(convert_to((q.headers ->> 'X-Eduwit-Timestamp') || '.' || convert_from(q.body, 'utf8'), 'UTF8'),
                                        convert_to((select v from t where k = 'secret'), 'UTF8'), 'sha256'), 'hex')
    and q.headers ->> 'X-Eduwit-Event' = 'b2c.lead_handed_off' and q.headers ? 'Idempotency-Key', q.headers ->> 'X-Eduwit-Delivery'
  from b2b.integration_outbox o join net.http_request_queue q on q.id = o.net_request_id
 where o.endpoint_id = (select v::bigint from t where k = 'endpoint') and o.event_type = 'b2c.lead_handed_off' order by o.id limit 1;
insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created)
select o.net_request_id, case when o.event_type = 'ping' then 200 else 503 end, 'application/json', '{}', false, null, now()
  from b2b.integration_outbox o where o.status = 'sending';
select b2b.outbox_tick();
insert into r select 'retry_with_backoff', count(*) = 2 and bool_and(o.status = 'failed' and o.next_attempt_at > now() and o.last_error like 'HTTP 503%'), max(o.last_error)
  from b2b.integration_outbox o where o.event_type = 'b2c.lead_handed_off';
insert into r select 'ping_delivered', count(*) = 1, null from b2b.integration_outbox o where o.event_type = 'ping' and o.status = 'delivered';
update b2b.integration_outbox set next_attempt_at = now() - interval '1 second' where status = 'failed';
select b2b.outbox_tick();
insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created)
select o.net_request_id, 200, 'application/json', '{}', false, null, now() from b2b.integration_outbox o where o.status = 'sending';
select b2b.outbox_tick();
insert into r select 'delivered_after_retry', count(*) = 2 and bool_and(o.attempts = 2 and o.response_status = 200), string_agg(o.status, ' ')
  from b2b.integration_outbox o where o.event_type = 'b2c.lead_handed_off';

-- reconciliation API
set local role anon;
do $x$
declare v jsonb; c bigint;
begin
  v := b2b.api_b2c_handoffs('wrong-key', null, null, 50);
  insert into r values ('handoffs_key_required', (v ->> 'status')::int = 401, v::text);
  v := b2b.api_b2c_handoffs((select t.v from t where k = 'key'), now() - interval '1 minute', null, 50);
  insert into r values ('handoffs_feed', jsonb_array_length(v -> 'result' -> 'events') = 2 and v -> 'result' ->> 'next_after' is not null
                        and v -> 'result' -> 'events' -> 0 ->> 'type' = 'b2c.lead_handed_off', left(v::text, 200));
  c := (v -> 'result' ->> 'next_after')::bigint;
  v := b2b.api_b2c_handoffs((select t.v from t where k = 'key'), null, c, 50);
  -- nothing new: no events, and the cursor stays where it was
  insert into r values ('handoffs_cursor', jsonb_array_length(v -> 'result' -> 'events') = 0 and (v -> 'result' ->> 'next_after')::bigint = c, left(v::text, 120));
end $x$;

-- events from the B2C CRM
do $x$
declare
  v jsonb; ts text := floor(extract(epoch from now()))::bigint::text; body text; sec text := (select t.v from t where k = 'secret');
  l1 text := (select t.v from t where k = 'lead1');
begin
  body := '{"event_id":"b2c-1","type":"b2ccrm.opted_out","data":{"lead_id":' || l1 || '}}';
  v := b2b.b2ccrm_event_ingest(body, ts, 'sha256=bad');
  insert into r values ('b2c_bad_signature', (v ->> 'status')::int = 401, v::text);
  v := b2b.b2ccrm_event_ingest(body, ts, 'sha256=' || encode(extensions.hmac(convert_to(ts || '.' || body, 'UTF8'), convert_to(sec, 'UTF8'), 'sha256'), 'hex'));
  insert into r values ('b2c_opt_out_applied', (v ->> 'ok')::boolean and v ->> 'result' = 'opted out', v::text);
  v := b2b.b2ccrm_event_ingest(body, ts, 'sha256=' || encode(extensions.hmac(convert_to(ts || '.' || body, 'UTF8'), convert_to(sec, 'UTF8'), 'sha256'), 'hex'));
  insert into r values ('b2c_idempotent', v ->> 'result' = 'already received', v::text);
  body := '{"event_id":"b2c-2","type":"b2ccrm.erasure_requested","data":{"lead_id":' || l1 || ',"note":"student asked"}}';
  v := b2b.b2ccrm_event_ingest(body, ts, 'sha256=' || encode(extensions.hmac(convert_to(ts || '.' || body, 'UTF8'), convert_to(sec, 'UTF8'), 'sha256'), 'hex'));
  insert into r values ('b2c_erasure_recorded', (v ->> 'ok')::boolean, v::text);
  body := '{"event_id":"b2c-3","type":"b2ccrm.stage_changed","data":{"lead_id":' || l1 || ',"stage":"assigned"}}';
  v := b2b.b2ccrm_event_ingest(body, (extract(epoch from now())::bigint - 900)::text, 'sha256=x');
  insert into r values ('b2c_old_timestamp', (v ->> 'status')::int = 401, v ->> 'error');
end $x$;
reset role;
insert into r select 'opt_out_on_lead', is_opted_out, null from public.student_leads where id = (select v::bigint from t where k = 'lead1');
insert into r select 'erasure_open', count(*) = 1, null from b2b.erasure_requests where lead_id = (select v::bigint from t where k = 'lead1') and status = 'open';

-- B2C asks to route its lead to partners
set local role anon;
do $x$
declare v jsonb;
begin
  v := b2b.api_route_to_partners((select t.v from t where k = 'key'), (select t.v::bigint from t where k = 'lead1'), 'student now wants a partner');
  insert into r values ('route_needs_consent', (v ->> 'status')::int = 422, v ->> 'error');
  v := b2b.api_route_to_partners((select t.v from t where k = 'key'), (select t.v::bigint from t where k = 'lead2'), 'x');
  insert into r values ('route_needs_reason', (v ->> 'status')::int = 422, v ->> 'error');
  v := b2b.api_route_to_partners((select t.v from t where k = 'key'), (select t.v::bigint from t where k = 'lead2'), 'counsellor: prefers a partner university');
  insert into r values ('route_to_partner', (v ->> 'ok')::boolean and v -> 'result' ->> 'destination' = 'partner', v::text);
end $x$;
reset role;
insert into r select 'manual_allocation', a.mode = 'manual' and a.status = 'queued'
    and exists (select 1 from b2b.allocations c where c.lead_id = a.lead_id and c.destination_type = 'in_house' and c.status = 'closed'), a.mode || ' ' || a.status
  from b2b.allocations a where a.lead_id = (select v::bigint from t where k = 'lead2') and a.destination_type = 'partner';
do $x$
declare a b2b.allocations;
begin
  perform set_config('b2b.actor', 'engine', true);
  select * into a from b2b.allocations where lead_id = (select v::bigint from t where k = 'lead2') and destination_type = 'partner';
  update b2b.allocations set status = 'pushing' where id = a.id;
  perform b2b.apply_created(a.id, 'REC-HUB');
  perform b2b.accept_allocation(a.id);
end $x$;
insert into r select 'routed_to_partner_event', count(*) = 1 and bool_and(o.payload -> 'data' ? 'partner_id'), count(*)::text
  from b2b.integration_outbox o where o.event_type = 'b2b.lead_routed_to_partner';

-- the System screen
set local role authenticated;
do $x$
declare s jsonb;
begin
  s := b2b.system_overview();
  insert into r values ('system_overview', jsonb_array_length(s -> 'endpoints') >= 1 and not (s::text like '%key_hash%') and not (s::text like '%secret_id%')
                        and jsonb_array_length(s -> 'jobs') >= 4 and (s ->> 'erasure_open')::int >= 1,
                        (select string_agg(j ->> 'name', ' ') from jsonb_array_elements(s -> 'jobs') j));
  s := b2b.erasure_requests_open();
  insert into r values ('erasure_listed', jsonb_array_length(s) = 1 and s -> 0 ->> 'name' = 'Hub One', left(s::text, 200));
  begin perform b2b.erasure_request_close((s -> 0 ->> 'id')::bigint, 'done', ''); insert into r values ('erasure_note_required', false, 'closed');
  exception when others then insert into r values ('erasure_note_required', sqlerrm like 'a note is required%', sqlerrm); end;
  perform b2b.erasure_request_close((s -> 0 ->> 'id')::bigint, 'done', 'removed from B2B and both partner CRMs');
  insert into r values ('erasure_closed', jsonb_array_length(b2b.erasure_requests_open()) = 0, null);
end $x$;
reset role;

select name, ok, left(detail, 220) detail from r order by ok, name;
rollback;
