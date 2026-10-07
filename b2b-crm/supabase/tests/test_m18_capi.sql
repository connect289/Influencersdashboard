-- M18 conversions (CAPI) on STAGING, rolled back: hashing, identifiers, milestones, event building (Meta and Google),
-- consent and test gates, idempotency, the junk signal, holding while switched off, sending (pg_net, never delivered:
-- the transaction is rolled back), answers (sent, rejected, retry, Meta's batch split), settings and the Admin's reads.
-- Every row of the final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;

-- a clean slate for the sender in this transaction
update b2b.capi_state set value = jsonb_build_object('at', now()) where key = 'scan';
update b2b.live_switches set live = false where scope in ('capi_meta', 'capi_google');

-- ---------- leads ----------
-- A: a Meta Lead Ads lead with every consent; routed to B2C, contacted, applied, enrolled
insert into t select 'A', (b2b.intake_lead('{"full_name":"Capi Meta","phone":"919876504101","email":" Capi.Meta@Gmail.com ","course":"MBA"}',
  jsonb_build_object('source_system', 'meta', 'lead_source', 'meta_lead_ad', 'click_ids', '{"leadgen_id":"1234567890123","form_id":"55"}'::jsonb,
                     'consent', jsonb_build_object('sales_at', now(), 'partner_share_at', now(), 'marketing_at', now()))) ->> 'lead_id');
-- B: a website lead with a gclid and only sales consent
insert into t select 'B', (b2b.intake_lead('{"full_name":"Capi Google","phone":"919876504102","email":"capi.google@example.com","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'click_ids', '{"gclid":"Cj0TESTGCLID"}'::jsonb,
                     'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id');
-- C: a test phone from a Meta ad
insert into t select 'C', (b2b.intake_lead('{"full_name":"Capi Test","phone":"910000004103","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'click_ids', '{"fbclid":"IwTESTFBCLID"}'::jsonb,
                     'consent', jsonb_build_object('sales_at', now(), 'marketing_at', now()))) ->> 'lead_id');
-- D: no ad identifier
insert into t select 'D', (b2b.intake_lead('{"full_name":"Capi Organic","phone":"919876504104","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'consent', jsonb_build_object('sales_at', now(), 'marketing_at', now()))) ->> 'lead_id');
-- E: junk from a Meta ad
insert into t select 'E', (b2b.intake_lead('{"full_name":"Capi Junk","phone":"919876504105","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'click_ids', '{"fbclid":"IwJUNK"}'::jsonb,
                     'consent', jsonb_build_object('sales_at', now(), 'marketing_at', now()))) ->> 'lead_id');

insert into b2b.allocations (lead_id, cycle_no, destination_type, b2c_lane, status, mode, reason)
select v::bigint, 1, 'in_house', 'sales', 'handed_off', 'fallback', 'paid_campaign' from t where k in ('A', 'B', 'C');
update public.student_leads set first_contacted_at = now(), applied_at = now() where id = pg_temp.v('A')::bigint;
insert into public.enrollments (lead_id, cycle_no, status, destination_type, expected_net_revenue_inr, enrolled_on)
values (pg_temp.v('A')::bigint, 1, 'reported', 'in_house', 15000, current_date);
insert into b2b.not_passed (lead_id, reason, fingerprint, decided_at) values (pg_temp.v('E')::bigint, 'junk', 'test-junk', now());

-- ---------- pure functions ----------
insert into r values ('hash_email_meta', b2b.capi_hash_email('  John.Doe@Gmail.com ', 'meta') = encode(extensions.digest('john.doe@gmail.com', 'sha256'), 'hex'), null);
insert into r values ('hash_email_google_gmail_dots', b2b.capi_hash_email('John.Doe@Gmail.com', 'google') = encode(extensions.digest('johndoe@gmail.com', 'sha256'), 'hex'), null);
insert into r values ('hash_email_invalid', b2b.capi_hash_email('nope', 'meta') is null, null);
insert into r values ('hash_phone_meta', b2b.capi_hash_phone('98765 43210', 'meta') = encode(extensions.digest('919876543210', 'sha256'), 'hex'), null);
insert into r values ('hash_phone_google_e164', b2b.capi_hash_phone('+91 98765 43210', 'google') = encode(extensions.digest('+919876543210', 'sha256'), 'hex'), null);
insert into r select 'ids_from_click_ids', b2b.capi_ids(l) = '{"leadgen_id":"1234567890123"}', b2b.capi_ids(l)::text
  from public.student_leads l where l.id = pg_temp.v('A')::bigint;
insert into r select 'milestones_A', string_agg(m.stage, ',' order by m.stage) = 'applied,contacted,enrolled,lead,partner_accepted,ready_to_route'
                       and bool_or(m.stage = 'enrolled' and m.value_inr = 15000), string_agg(m.stage || '=' || coalesce(m.value_inr::text, ''), ',')
  from public.student_leads l, b2b.capi_milestones(l) m where l.id = pg_temp.v('A')::bigint;

-- ---------- event building ----------
select b2b.capi_lead_sync(v::bigint) from t where k in ('A', 'B', 'C', 'D', 'E');
insert into r select 'meta_events_A', count(*) = 5 and bool_and(status = 'pending') and not bool_or(platform = 'google'), string_agg(stage || ':' || status, ' ')
  from b2b.conversion_events where lead_id = pg_temp.v('A')::bigint;
insert into r select 'meta_payload_crm', payload ->> 'action_source' = 'system_generated' and payload -> 'user_data' ->> 'lead_id' = '1234567890123'
                       and jsonb_typeof(payload -> 'user_data' -> 'lead_id') = 'number'
                       and payload -> 'user_data' -> 'em' ->> 0 = encode(extensions.digest('capi.meta@gmail.com', 'sha256'), 'hex')
                       and payload -> 'user_data' -> 'ph' ->> 0 = encode(extensions.digest('919876504101', 'sha256'), 'hex')
                       and payload -> 'custom_data' ->> 'value' = '15000' and payload -> 'custom_data' ->> 'currency' = 'INR'
                       and payload -> 'custom_data' ->> 'lead_event_source' = 'Eduwit CRM' and event_id = pg_temp.v('A') || ':enrolled:1'
                       and event_name = 'Enrolled' and match_keys @> '{lead_id,email,phone}', payload::text
  from b2b.conversion_events where lead_id = pg_temp.v('A')::bigint and stage = 'enrolled';
insert into r select 'no_raw_pii', not exists (select 1 from b2b.conversion_events where payload::text ilike '%gmail%' or payload::text like '%9876504101%'), null;
insert into r select 'google_no_consent_skipped', count(*) = 2 and bool_and(status = 'skipped' and reason = 'no consent') and bool_and(platform = 'google'),
                       string_agg(platform || ':' || stage || ':' || status, ' ')
  from b2b.conversion_events where lead_id = pg_temp.v('B')::bigint;
insert into r select 'google_payload', payload ->> 'gclid' = 'Cj0TESTGCLID' and payload ->> 'orderId' = pg_temp.v('B') || ':ready_to_route:1'
                       and payload ->> 'conversionDateTime' like '%+05:30' and jsonb_array_length(payload -> 'userIdentifiers') = 2
                       and payload -> 'userIdentifiers' -> 1 ->> 'hashedPhoneNumber' = encode(extensions.digest('+919876504102', 'sha256'), 'hex'), payload::text
  from b2b.conversion_events where lead_id = pg_temp.v('B')::bigint and stage = 'ready_to_route';
insert into r select 'test_lead_dry_run', count(*) > 0 and bool_and(status = 'dry_run' and is_test), string_agg(stage || ':' || status, ' ')
  from b2b.conversion_events where lead_id = pg_temp.v('C')::bigint;
insert into r select 'website_event_fbc', payload ->> 'action_source' = 'website' and payload -> 'user_data' ->> 'fbc' like 'fb.1.%.IwTESTFBCLID', payload::text
  from b2b.conversion_events where lead_id = pg_temp.v('C')::bigint and stage = 'ready_to_route';
insert into r select 'no_identifier_no_events', not exists (select 1 from b2b.conversion_events where lead_id = pg_temp.v('D')::bigint), null;
insert into r select 'junk_signal_off', not exists (select 1 from b2b.conversion_events where lead_id = pg_temp.v('E')::bigint), null;

-- idempotent; consent arriving later revives the skipped events
insert into r select 'sync_idempotent', b2b.capi_lead_sync(pg_temp.v('A')::bigint) = 0, null;
update public.student_leads set consent_marketing_at = now() where id = pg_temp.v('B')::bigint;
insert into t select 'revived', b2b.capi_lead_sync(pg_temp.v('B')::bigint)::text;
insert into r select 'consent_revives', pg_temp.v('revived') = '2'
                       and not exists (select 1 from b2b.conversion_events where lead_id = pg_temp.v('B')::bigint and status <> 'pending'), pg_temp.v('revived');
-- the junk signal
update b2b.settings set value = value || '{"junk_capi_signal": true}' where key = 'engine';
select b2b.capi_lead_sync(pg_temp.v('E')::bigint);
insert into r select 'junk_signal_on', count(*) = 1 and min(stage) = 'disqualified' and min(event_name) = 'Disqualified Lead', string_agg(stage, ' ')
  from b2b.conversion_events where lead_id = pg_temp.v('E')::bigint;

-- the scan finds changed leads
update public.student_leads set applied_at = now() where id = pg_temp.v('B')::bigint;
update b2b.settings set value = jsonb_set(value, '{google,map,applied,enabled}', 'true') where key = 'capi';
insert into t select 'scan', b2b.capi_scan(100)::text;
insert into r select 'scan_finds_change', (pg_temp.v('scan')::jsonb ->> 'events')::int >= 1
                       and exists (select 1 from b2b.conversion_events where lead_id = pg_temp.v('B')::bigint and stage = 'applied' and platform = 'google'), pg_temp.v('scan');

-- ---------- sending ----------
select b2b.capi_send();
insert into r select 'held_while_off', count(*) filter (where status = 'held') = count(*) and min(reason) = 'switched off', string_agg(distinct status || '/' || coalesce(reason, ''), ' ')
  from b2b.conversion_events where not is_test and status not in ('skipped', 'dry_run');

-- ---------- the Admin ----------
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000d1', 'capi-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000d1', 'capi-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000d2', 'nobody2@test.local', 'authenticated', 'authenticated');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000d1","role":"authenticated","aal":"aal2","email":"capi-admin@test.local"}', true);
do $x$
declare e text; o jsonb; c jsonb;
begin
  o := b2b.capi_overview();
  insert into r values ('overview_blockers', o -> 'switches' -> 'meta' -> 'blockers' ? 'no dataset ID' and o -> 'switches' -> 'meta' -> 'blockers' ? 'no access token'
                          and o -> 'switches' -> 'google' -> 'blockers' ? 'no customer ID' and not (o -> 'settings' -> 'meta' ->> 'token')::boolean, (o -> 'switches')::text);
  insert into r values ('overview_match', (o -> 'match' -> 'meta' -> 'keys' ->> 'lead_id')::int = 5, (o -> 'match')::text);
  begin perform b2b.capi_settings_save('{"meta":{"dataset_id":"abc"}}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('dataset_must_be_number', e = 'the Meta dataset (pixel) ID is a number', e);
  begin perform b2b.capi_settings_save('{"google":{"map":{"enrolled":{"action":"conversion 5","enabled":true}}}}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('action_format', e like 'a conversion action looks like%', e);
  perform b2b.capi_settings_save(jsonb_build_object(
    'meta', jsonb_build_object('dataset_id', '123456789012345', 'token', 'EAATESTTOKEN-NOT-REAL', 'test_event_code', 'TEST123'),
    'google', jsonb_build_object('customer_id', '123-456-7890', 'client_id', 'test-client.apps.googleusercontent.com', 'client_secret', 'TEST-CLIENT-SECRET',
                                 'refresh_token', '1//TEST-REFRESH-TOKEN', 'developer_token', 'TEST-DEV-TOKEN',
                                 'map', jsonb_build_object('ready_to_route', jsonb_build_object('action', 'customers/1234567890/conversionActions/111', 'enabled', true),
                                                           'partner_accepted', jsonb_build_object('action', 'customers/1234567890/conversionActions/222', 'enabled', true),
                                                           'applied', jsonb_build_object('action', null, 'enabled', true)))));
  o := b2b.capi_overview();
  insert into r values ('settings_saved', o -> 'settings' -> 'meta' ->> 'dataset_id' = '123456789012345' and (o -> 'settings' -> 'meta' ->> 'token')::boolean
                          and o -> 'settings' -> 'google' ->> 'customer_id' = '1234567890' and (o -> 'settings' -> 'google' ->> 'refresh_token')::boolean
                          and o::text not like '%TEST-REFRESH-TOKEN%' and o::text not like '%EAATESTTOKEN%'
                          and jsonb_array_length(o -> 'switches' -> 'meta' -> 'blockers') = 0, (o -> 'settings')::text);
  perform b2b.set_live_switch('capi_meta', true, 'staging test');
  perform b2b.set_live_switch('capi_google', true, 'staging test');
  c := b2b.capi_lead_check(pg_temp.v('A')::bigint, false);
  insert into r values ('lead_check', c -> 'ids' ->> 'leadgen_id' = '1234567890123' and jsonb_array_length(c -> 'milestones') = 6
                          and jsonb_array_length(c -> 'events') = 5, left(c::text, 300));
  begin perform b2b.capi_retry(-1); e := 'retried'; exception when others then e := sqlerrm; end;
  insert into r values ('retry_needs_failed', e like 'only a failed%', e);
end $x$;
reset role;

-- live and configured: Meta batches go out, Google first asks for an access token
select b2b.capi_send();
insert into r select 'meta_sending', count(*) = 6 and count(distinct request_id) = 1 and bool_and(attempts = 1), count(*) || ' rows, ' || count(distinct request_id) || ' calls'
  from b2b.conversion_events where platform = 'meta' and status = 'sending';
insert into r select 'meta_request', q.url = 'https://graph.facebook.com/v21.0/123456789012345/events'
                       and convert_from(q.body, 'UTF8')::jsonb ->> 'test_event_code' = 'TEST123'
                       and jsonb_array_length(convert_from(q.body, 'UTF8')::jsonb -> 'data') = 6
                       and q.headers ->> 'Authorization' = 'Bearer EAATESTTOKEN-NOT-REAL', q.url
  from net.http_request_queue q where q.id = (select max(request_id) from b2b.conversion_events where platform = 'meta');
insert into r select 'google_token_requested', (value ->> 'request_id') is not null, value::text from b2b.capi_state where key = 'google_token';
insert into r select 'google_no_action_held', count(*) = 1 and min(reason) = 'no conversion action for this stage', string_agg(stage || ':' || status, ' ')
  from b2b.conversion_events where platform = 'google' and status = 'held';

-- answers: Meta refuses the batch (400) → split into singles; then one single is accepted and one refused
insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created)
select distinct request_id, 400, 'application/json', '{"error":{"message":"Invalid parameter","code":100}}', false, null, now()
  from b2b.conversion_events where platform = 'meta' and status = 'sending';
-- the token comes back
insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created)
select (value ->> 'request_id')::bigint, 200, 'application/json', '{"access_token":"ya29.TEST-ACCESS","expires_in":3599}', false, null, now()
  from b2b.capi_state where key = 'google_token';
select b2b.capi_collect();
insert into r select 'meta_batch_split', count(*) = 6 and bool_and(status = 'pending' and reason = 'solo'), string_agg(distinct status, ' ')
  from b2b.conversion_events where platform = 'meta' and not is_test and status not in ('skipped', 'dry_run');
insert into r select 'google_token_stored', (value ->> 'expires_at')::timestamptz > now() + interval '50 minutes' and (value ->> 'secret_id') is not null, null
  from b2b.capi_state where key = 'google_token';

select b2b.capi_send();
insert into r select 'meta_singles', count(*) = 6 and count(distinct request_id) = 6, count(distinct request_id)::text
  from b2b.conversion_events where platform = 'meta' and status = 'sending';
insert into r select 'google_upload', count(*) = 2 and count(distinct request_id) = 1, string_agg(stage, ' ')
  from b2b.conversion_events where platform = 'google' and status = 'sending';
insert into r select 'google_request', q.url = 'https://googleads.googleapis.com/v21/customers/1234567890/conversionUploads:uploadClickConversions'
                       and q.headers ->> 'developer-token' = 'TEST-DEV-TOKEN' and q.headers ->> 'Authorization' = 'Bearer ya29.TEST-ACCESS'
                       and (convert_from(q.body, 'UTF8')::jsonb ->> 'partialFailure')::boolean
                       and convert_from(q.body, 'UTF8')::jsonb -> 'conversions' -> 0 ->> 'conversionAction' = 'customers/1234567890/conversionActions/111', q.url
  from net.http_request_queue q where q.id = (select max(request_id) from b2b.conversion_events where platform = 'google');

insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created)
select c.request_id, case when c.stage = 'contacted' then 400 when c.stage = 'applied' then 503 else 200 end, 'application/json',
       case when c.stage = 'contacted' then '{"error":{"message":"Invalid event","code":100}}' else '{"events_received":1}' end, false, null, now()
  from b2b.conversion_events c where c.platform = 'meta' and c.status = 'sending';
-- Google: the first conversion accepted, the others refused
insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created)
select max(request_id), 200, 'application/json',
       '{"results":[{"gclid":"Cj0TESTGCLID","conversionAction":"customers/1234567890/conversionActions/111"},{}],"partialFailureError":{"message":"The click is too old"}}',
       false, null, now()
  from b2b.conversion_events where platform = 'google' and status = 'sending';
select b2b.capi_collect();
insert into r select 'meta_answers', count(*) filter (where status = 'sent') = 4 and count(*) filter (where status = 'rejected' and stage = 'contacted') = 1
                       and count(*) filter (where status = 'failed' and stage = 'applied' and next_attempt_at > now()) = 1,
                       string_agg(stage || ':' || status, ' ')
  from b2b.conversion_events where platform = 'meta' and not is_test and status not in ('skipped', 'dry_run');
insert into r select 'google_answers', count(*) filter (where status = 'sent') = 1 and count(*) filter (where status = 'rejected' and error = 'The click is too old') = 1,
                       string_agg(stage || ':' || status, ' ')
  from b2b.conversion_events where platform = 'google' and status in ('sent', 'rejected');
insert into r select 'alert_logged', exists (select 1 from b2b.events where type = 'alert.capi_failed' and occurred_at >= now()), null;
insert into r select 'dead_after_6', (select b2b.capi_fail(array[id], 'x', null) from b2b.conversion_events where platform = 'meta' and stage = 'applied'
                                       and lead_id = pg_temp.v('A')::bigint) = 0, null;
update b2b.conversion_events set attempts = 6 where platform = 'meta' and stage = 'applied' and lead_id = pg_temp.v('A')::bigint;
insert into r select 'dead_after_6b', (select b2b.capi_fail(array[id], 'x', null) from b2b.conversion_events where platform = 'meta' and stage = 'applied'
                                        and lead_id = pg_temp.v('A')::bigint) = 1, null;
-- an event older than Meta's window is skipped instead of sent
update b2b.conversion_events set status = 'pending', occurred_at = now() - interval '10 days', next_attempt_at = now()
 where platform = 'meta' and stage = 'applied' and lead_id = pg_temp.v('A')::bigint;
select b2b.capi_send();
insert into r select 'too_old_skipped', status = 'skipped' and reason = 'older than the platform accepts', status
  from b2b.conversion_events where platform = 'meta' and stage = 'applied' and lead_id = pg_temp.v('A')::bigint;
insert into r select 'tick_runs', b2b.capi_tick() ? 'sending', null;

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000d2","role":"authenticated","aal":"aal2","email":"nobody2@test.local"}', true);
set local role authenticated;
do $x$
declare e text;
begin
  begin perform b2b.capi_overview(); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r values ('non_admin_denied', e = 'not allowed', e);
  begin perform b2b.capi_tick(); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('tick_not_for_users', e = '42501', e);
end $x$;
reset role;

select name, ok, detail from r where not ok union all select 'TOTAL', bool_and(ok), count(*)::text from r;
rollback;
