-- M19 partner CRM adapters on STAGING, rolled back. Response, schema and poll parsing for every CRM; then partner
-- e2e-down (id 20) turned into a LeadSquared partner and then a Zoho partner: settings and secrets, the masked preview,
-- pushes (request shape; created and duplicate answers), OAuth token renewal, polling into partner events, and schema
-- discovery into a snapshot. pg_net requests are queued but never sent (rolled back); answers are simulated.
-- Every row of the final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.answer(p_id bigint, p_status int, p_body text) returns void language sql as $f$
  insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created) values (p_id, p_status, 'application/json', p_body, false, null, now())
$f$;
/* a lead routed to partner 20 (as in test_m16); returns its allocation id */
create function pg_temp.lead_for_20(p_phone text) returns bigint language plpgsql as $f$
declare v_id bigint; a_id bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', p_phone, 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'Adapter Test ' || right(p_phone, 2), 'email', 'adapter' || right(p_phone, 2) || '@example.com',
                               'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                               'state', 'Delhi', 'source', 'whatsapp_direct', 'classification', 'WARM', 'consent_partner_share_at', now())));
  select id into v_id from public.student_leads where whatsapp_number = p_phone;
  perform b2b.route_decide(v_id, true, 'm19', 'auto');
  select id into a_id from b2b.allocations where lead_id = v_id and destination_type = 'partner' and partner_id = 20 order by id desc limit 1;
  return a_id;
end $f$;

update b2b.settings set value = jsonb_set(value, '{exploration_share}', '0') where key = 'engine';
insert into b2b.live_switches (scope, live, reason) values ('partner:20', true, 'm19 test') on conflict (scope) do update set live = true;

-- ---------- pure functions ----------
insert into r select 'values_split_name_phone', v ->> 'first_name' = 'Asha' and v ->> 'last_name' = 'Rani Verma' and v ->> 'phone_dash' = '+91-9876543210'
                       and v ->> 'phone10' = '9876543210' and v ->> 'last_name_required' = 'Rani Verma', v::text
  from (select b2b.adapter_values('{"reference":"EDW-1","student":{"name":"Asha Rani Verma","phone":"+919876543210"}}') v) x;
insert into r select 'record_mapped_fields_win', v ->> 'Phone' = '+91-9876543210' and v ->> 'mx_Course_Code' = 'MBA01' and v ->> 'Source' = 'Partner portal'
                       and v ->> 'mx_Ref' = 'EDW-1' and not v ? 'mx_Eduwit_Reference', v::text
  from (select b2b.adapter_record('leadsquared', '{"reference_field":"mx_Ref"}',
          '{"reference":"EDW-1","student":{"name":"Asha","phone":"+919876543210"},"fields":{"mx_Course_Code":"MBA01","Source":"Partner portal"}}') v) x;
insert into r select 'salesforce_record_required', v ->> 'LastName' = 'Asha' and v ->> 'Company' = 'Individual' and v ->> 'Eduwit_Reference__c' = 'EDW-1', v::text
  from (select b2b.adapter_record('salesforce', '{}', '{"reference":"EDW-1","student":{"name":"Asha"}}') v) x;

insert into r values
  ('lsq_created', b2b.adapter_push_result('leadsquared', 200, '{"Status":"Success","Message":{"Id":"9f1c-guid"}}') = '{"outcome":"created","record_id":"9f1c-guid"}', null),
  ('lsq_duplicate', b2b.adapter_push_result('leadsquared', 500, '{"Status":"Error","ExceptionType":"MXDuplicateEntryException","ExceptionMessage":"A Lead with same Phone Number already exists."}') ->> 'outcome' = 'duplicate', null),
  ('lsq_auth', b2b.adapter_push_result('leadsquared', 401, '{"Status":"Error","ExceptionType":"MXUnAuthorizedAccessException"}') ->> 'outcome' = 'auth', null),
  ('zoho_created', b2b.adapter_push_result('zoho', 201, '{"data":[{"code":"SUCCESS","details":{"id":"5551"},"status":"success"}]}') ->> 'record_id' = '5551', null),
  ('zoho_duplicate', b2b.adapter_push_result('zoho', 202, '{"data":[{"code":"DUPLICATE_DATA","details":{"api_name":"Phone","duplicate_record":{"id":"4440"}},"message":"duplicate data","status":"error"}]}')
                       @> '{"outcome":"duplicate","existing_record_id":"4440","duplicate_field":"Phone"}', null),
  ('zoho_auth', b2b.adapter_push_result('zoho', 401, '{"code":"INVALID_TOKEN","message":"invalid oauth token"}') ->> 'outcome' = 'auth', null),
  ('sf_created', b2b.adapter_push_result('salesforce', 201, '{"id":"00Q5g000001","success":true,"errors":[]}') ->> 'record_id' = '00Q5g000001', null),
  ('sf_duplicate', b2b.adapter_push_result('salesforce', 400, '[{"errorCode":"DUPLICATES_DETECTED","message":"Use one of these records?","duplicateResult":{"matchResults":[{"matchRecords":[{"record":{"Id":"00Q5g000777"}}]}]}}]')
                       @> '{"outcome":"duplicate","existing_record_id":"00Q5g000777"}', null),
  ('sf_error', b2b.adapter_push_result('salesforce', 400, '[{"errorCode":"REQUIRED_FIELD_MISSING","message":"Required fields are missing: [Company]"}]') ->> 'reason' like 'REQUIRED_FIELD_MISSING%', null),
  ('hubspot_created', b2b.adapter_push_result('hubspot', 201, '{"id":"801","properties":{}}') ->> 'record_id' = '801', null),
  ('hubspot_duplicate', b2b.adapter_push_result('hubspot', 409, '{"status":"error","message":"Contact already exists. Existing ID: 12345","category":"CONFLICT"}') ->> 'existing_record_id' = '12345', null),
  ('meritto_created', b2b.adapter_push_result('meritto', 200, '{"status":true,"message":"Lead created","data":{"lead_id":"NPF-1"}}') ->> 'record_id' = 'NPF-1', null),
  ('meritto_duplicate', b2b.adapter_push_result('meritto', 200, '{"status":false,"message":"Lead already exists"}') ->> 'outcome' = 'duplicate', null);

insert into r select 'schema_lsq', s -> 'stages' = '[{"stage":"Prospect"},{"stage":"Counselled"}]' and jsonb_array_length(s -> 'fields') = 2, s::text
  from (select b2b.adapter_schema_parse('leadsquared', '[{"SchemaName":"ProspectStage","DisplayName":"Stage","DataType":"Select","Options":[{"Value":"Prospect","Text":"Prospect"},{"Value":"Counselled","Text":"Counselled"}]},
                                                      {"SchemaName":"mx_City","DisplayName":"City","DataType":"String"}]', 'ProspectStage') s) x;
insert into r select 'schema_salesforce', s -> 'stages' = '[{"stage":"Open"},{"stage":"Contacted"}]', s::text
  from (select b2b.adapter_schema_parse('salesforce', '{"fields":[{"name":"Status","label":"Status","type":"picklist","picklistValues":[{"value":"Open","active":true},{"value":"Contacted","active":true},{"value":"Old","active":false}]}]}', 'Status') s) x;
insert into r select 'schema_hubspot', s -> 'stages' = '[{"stage":"NEW"},{"stage":"OPEN"}]', s::text
  from (select b2b.adapter_schema_parse('hubspot', '{"results":[{"name":"hs_lead_status","label":"Lead Status","type":"enumeration","options":[{"value":"NEW"},{"value":"OPEN"},{"value":"X","hidden":true}]}]}', 'hs_lead_status') s) x;
insert into r select 'poll_salesforce', p -> 0 ->> 'record_id' = '00Q1' and p -> 0 ->> 'stage' = 'Working' and p -> 0 ->> 'reference' = 'EDW-9'
                       and not (p -> 0 -> 'fields') ? 'attributes', p::text
  from (select b2b.adapter_poll_parse('salesforce', '{"records":[{"attributes":{"type":"Lead"},"Id":"00Q1","Status":"Working","Eduwit_Reference__c":"EDW-9","LastModifiedDate":"2026-10-07T01:00:00.000+0000"}]}',
                                      'Status', 'Eduwit_Reference__c') p) x;
insert into r select 'poll_hubspot', p -> 0 ->> 'record_id' = '77' and p -> 0 ->> 'stage' = 'OPEN', p::text
  from (select b2b.adapter_poll_parse('hubspot', '{"results":[{"id":"77","properties":{"hs_lead_status":"OPEN","eduwit_reference":"EDW-9"},"updatedAt":"2026-10-07T01:00:00Z"}]}',
                                      'hs_lead_status', 'eduwit_reference') p) x;

-- ---------- LeadSquared partner ----------
update b2b.partners set adapter_type = 'leadsquared' where id = 20;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000e1', 'adapter-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000e1', 'adapter-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000e2', 'nobody3@test.local', 'authenticated', 'authenticated');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated","aal":"aal2","email":"adapter-admin@test.local"}', true);
do $x$
declare e text; s jsonb; pv jsonb;
begin
  begin perform b2b.partner_adapter_save(20, '{"env":"live","settings":{"host":"leadsquared.example.com"},"secrets":{"access_key":"u$abcdef123","secret_key":"0123456789abcdef"}}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('lsq_host_checked', e like 'the LeadSquared API host looks like%', e);
  begin perform b2b.partner_adapter_save(20, '{"env":"live","settings":{"host":"api-in21.leadsquared.com"},"secrets":{"access_key":"u$abcdef123"}}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('lsq_secret_required', e = 'the secret key is required', e);
  s := b2b.partner_adapter_save(20, '{"env":"live","settings":{"host":"api-in21.leadsquared.com"},"secrets":{"access_key":"u$abcdef123","secret_key":"0123456789abcdef"},"poll_minutes":5}');
  insert into r values ('lsq_saved', (s -> 'envs' -> 'live' ->> 'configured')::boolean and s -> 'envs' -> 'live' -> 'secrets_set' = '["access_key", "secret_key"]'
                          and not (s -> 'envs' -> 'live' -> 'settings') ? 'secret_id' and s::text not like '%0123456789abcdef%', s::text);
  -- saving again with empty secrets keeps them
  s := b2b.partner_adapter_save(20, '{"env":"live","settings":{"host":"api-in21.leadsquared.com"},"secrets":{"access_key":"","secret_key":""},"reference_field":"mx_EDW_Ref"}');
  insert into r values ('lsq_secrets_kept', s -> 'envs' -> 'live' -> 'secrets_set' = '["access_key", "secret_key"]' and s -> 'envs' -> 'live' -> 'settings' ->> 'reference_field' = 'mx_EDW_Ref', null);
  pv := b2b.partner_adapter_preview(20, 'live');
  insert into r values ('lsq_preview_masked', pv ->> 'url' = 'https://api-in21.leadsquared.com/v2/LeadManagement.svc/Lead.Create'
                          and pv -> 'headers' ->> 'x-LSQ-AccessKey' = '••••' and pv -> 'headers' ->> 'x-LSQ-SecretKey' = '••••'
                          and exists (select 1 from jsonb_array_elements(pv -> 'body') b where b ->> 'Attribute' = 'mx_EDW_Ref'), left(pv::text, 400));
end $x$;
reset role;

insert into t select 'a1', pg_temp.lead_for_20('919876504201')::text;
insert into t select 'a2', pg_temp.lead_for_20('919876504202')::text;
insert into r select 'routed_to_20', pg_temp.v('a1') is not null and pg_temp.v('a2') is not null, pg_temp.v('a1') || ',' || pg_temp.v('a2');
update b2b.allocations set next_push_at = null where id in (pg_temp.v('a1')::bigint, pg_temp.v('a2')::bigint);
select b2b.push_dispatch(100);
insert into r select 'lsq_push_request', q.url = 'https://api-in21.leadsquared.com/v2/LeadManagement.svc/Lead.Create'
                       and q.headers ->> 'x-LSQ-AccessKey' = 'u$abcdef123' and jsonb_typeof(convert_from(q.body, 'UTF8')::jsonb) = 'array'
                       and exists (select 1 from jsonb_array_elements(convert_from(q.body, 'UTF8')::jsonb) b where b ->> 'Attribute' = 'mx_EDW_Ref' and b ->> 'Value' = a.reference)
                       and exists (select 1 from jsonb_array_elements(convert_from(q.body, 'UTF8')::jsonb) b where b ->> 'Attribute' = 'Phone' and b ->> 'Value' = '+91-9876504201'),
                       q.url
  from b2b.allocations a join net.http_request_queue q on q.id = a.push_request_id where a.id = pg_temp.v('a1')::bigint;
select pg_temp.answer(push_request_id, 200, '{"Status":"Success","Message":{"Id":"lsq-rec-1"}}') from b2b.allocations where id = pg_temp.v('a1')::bigint;
select pg_temp.answer(push_request_id, 500, '{"Status":"Error","ExceptionType":"MXDuplicateEntryException","ExceptionMessage":"A Lead with same Phone Number already exists."}')
  from b2b.allocations where id = pg_temp.v('a2')::bigint;
select b2b.push_collect();
insert into r select 'lsq_created_applied', partner_record_id = 'lsq-rec-1' and status in ('pushed', 'accepted'), status || ' ' || coalesce(partner_record_id, '')
  from b2b.allocations where id = pg_temp.v('a1')::bigint;
insert into r select 'lsq_duplicate_applied', status = 'duplicate' and claim_proof ->> 'crm_message' like 'A Lead with same Phone%', status
  from b2b.allocations where id = pg_temp.v('a2')::bigint;

-- polling: a stage change and fields come back as partner events
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated","aal":"aal2","email":"adapter-admin@test.local"}', true);
select b2b.partner_adapter_action(20, 'live', 'poll');
reset role;
insert into r select 'lsq_poll_request', q.url = 'https://api-in21.leadsquared.com/v2/LeadManagement.svc/Leads.RecentlyModified'
                       and convert_from(q.body, 'UTF8')::jsonb -> 'Columns' ->> 'Include_CSV' like '%ProspectStage%'
                       and convert_from(q.body, 'UTF8')::jsonb -> 'Columns' ->> 'Include_CSV' like '%mx_EDW_Ref%', q.url
  from b2b.partner_adapter_state s join net.http_request_queue q on q.id = s.poll_request_id where s.partner_id = 20 and s.env = 'live';
select pg_temp.answer(s.poll_request_id, 200, jsonb_build_object('RecordCount', 2, 'Leads', jsonb_build_array(
         jsonb_build_object('LeadPropertyList', jsonb_build_array(
           jsonb_build_object('Attribute', 'ProspectID', 'Value', 'lsq-rec-1'), jsonb_build_object('Attribute', 'ProspectStage', 'Value', 'Counselling Done'),
           jsonb_build_object('Attribute', 'mx_EDW_Ref', 'Value', (select reference from b2b.allocations where id = pg_temp.v('a1')::bigint)),
           jsonb_build_object('Attribute', 'ModifiedOn', 'Value', '2026-10-07 01:30:00'))),
         jsonb_build_object('LeadPropertyList', jsonb_build_array(
           jsonb_build_object('Attribute', 'ProspectID', 'Value', 'lsq-other'), jsonb_build_object('Attribute', 'ProspectStage', 'Value', 'Prospect'),
           jsonb_build_object('Attribute', 'ModifiedOn', 'Value', '2026-10-07 01:31:00')))))::text)
  from b2b.partner_adapter_state s where s.partner_id = 20 and s.env = 'live';
select b2b.partner_sync_tick();
insert into r select 'lsq_poll_applied', s.poll_request_id is null and s.last_poll_result ->> 'records' = '2' and s.last_poll_result ->> 'unmatched' = '1'
                       and s.poll_since = '2026-10-07 01:31:00+00', s.last_poll_result::text || ' ' || s.poll_since
  from b2b.partner_adapter_state s where s.partner_id = 20 and s.env = 'live';
insert into r select 'lsq_poll_events', count(*) filter (where event_type = 'stage' and raw -> 'data' ->> 'stage' = 'Counselling Done') = 1
                       and count(*) filter (where event_type = 'update') = 1 and bool_and(raw ->> 'source' = 'poll' and status <> 'received'),
                       string_agg(event_type || ':' || status, ' ')
  from b2b.partner_events where allocation_id = pg_temp.v('a1')::bigint and event_id like 'poll:%';

-- ---------- Zoho partner: OAuth, push, duplicate, schema ----------
update b2b.partners set adapter_type = 'zoho' where id = 20;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated","aal":"aal2","email":"adapter-admin@test.local"}', true);
select b2b.partner_adapter_save(20, '{"env":"live","settings":{"api_domain":"www.zohoapis.in","accounts_domain":"accounts.zoho.in","client_id":"1000.TESTCLIENT"},
                                       "secrets":{"client_secret":"zoho-client-secret","refresh_token":"1000.refresh.token"}}');
reset role;
insert into t select 'a3', pg_temp.lead_for_20('919876504203')::text;
update b2b.allocations set next_push_at = null where id = pg_temp.v('a3')::bigint;
select b2b.push_dispatch(100);
insert into r select 'zoho_waits_for_token', a.push_request_id is null and a.next_push_at > now() and q.url like 'https://accounts.zoho.in/oauth/v2/token?%' and q.url like '%grant_type=refresh_token%'
                       and s.token_request_id is not null, q.url
  from b2b.allocations a, b2b.partner_adapter_state s join net.http_request_queue q on q.id = s.token_request_id
 where a.id = pg_temp.v('a3')::bigint and s.partner_id = 20 and s.env = 'live';
select pg_temp.answer(token_request_id, 200, '{"access_token":"1000.ACCESS.TOKEN","api_domain":"https://www.zohoapis.in","token_type":"Bearer","expires_in":3600}')
  from b2b.partner_adapter_state where partner_id = 20 and env = 'live';
select b2b.partner_sync_tick();
insert into r select 'zoho_token_stored', token_expires_at > now() + interval '50 minutes' and instance_url = 'https://www.zohoapis.in' and b2b.partner_secret(token_secret_id) = '1000.ACCESS.TOKEN', null
  from b2b.partner_adapter_state where partner_id = 20 and env = 'live';
update b2b.allocations set next_push_at = now() where id = pg_temp.v('a3')::bigint;
select b2b.push_dispatch(100);
insert into r select 'zoho_push_request', q.url = 'https://www.zohoapis.in/crm/v5/Leads' and q.headers ->> 'Authorization' = 'Zoho-oauthtoken 1000.ACCESS.TOKEN'
                       and convert_from(q.body, 'UTF8')::jsonb -> 'data' -> 0 ->> 'Eduwit_Reference' = a.reference
                       and convert_from(q.body, 'UTF8')::jsonb -> 'data' -> 0 ->> 'Last_Name' = 'Test 03', q.url
  from b2b.allocations a join net.http_request_queue q on q.id = a.push_request_id where a.id = pg_temp.v('a3')::bigint;
select pg_temp.answer(push_request_id, 202, '{"data":[{"code":"DUPLICATE_DATA","details":{"api_name":"Phone","duplicate_record":{"id":"4440"}},"message":"duplicate data","status":"error"}]}')
  from b2b.allocations where id = pg_temp.v('a3')::bigint;
select b2b.push_collect();
insert into r select 'zoho_duplicate_applied', status = 'duplicate' and claim_proof ->> 'existing_record_id' = '4440', status from b2b.allocations where id = pg_temp.v('a3')::bigint;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e1","role":"authenticated","aal":"aal2","email":"adapter-admin@test.local"}', true);
select b2b.partner_adapter_action(20, 'live', 'schema');
reset role;
select pg_temp.answer(schema_request_id, 200, '{"fields":[{"api_name":"Lead_Status","field_label":"Lead Status","data_type":"picklist","pick_list_values":[{"display_value":"Not Contacted","actual_value":"Not Contacted"},{"display_value":"Contacted","actual_value":"Contacted"}]},{"api_name":"Phone","field_label":"Phone","data_type":"phone"}]}')
  from b2b.partner_adapter_state where partner_id = 20 and env = 'live';
select b2b.partner_sync_tick();
insert into r select 'zoho_schema_snapshot', source = 'api' and schema -> 'stages' = '[{"stage":"Not Contacted"},{"stage":"Contacted"}]', schema::text
  from b2b.partner_schema_snapshots where partner_id = 20 order by id desc limit 1;
insert into r select 'schema_state', last_schema_at is not null and schema_request_id is null, last_schema_error from b2b.partner_adapter_state where partner_id = 20 and env = 'live';

-- the sign-in fails: the push uses its normal retries
update b2b.partner_adapter_state set token_expires_at = null, token_failed_at = now(), token_error = 'CRM sign-in failed: invalid_client' where partner_id = 20 and env = 'live';
insert into t select 'a4', pg_temp.lead_for_20('919876504204')::text;
update b2b.allocations set next_push_at = null where id = pg_temp.v('a4')::bigint;
select b2b.push_dispatch(100);
insert into r select 'token_failure_retries', status = 'pushing' and push_attempts = 1 and last_error like 'CRM sign-in failed%' and next_push_at > now(), status || ' ' || coalesce(last_error, '')
  from b2b.allocations where id = pg_temp.v('a4')::bigint;

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000e2","role":"authenticated","aal":"aal2","email":"nobody3@test.local"}', true);
set local role authenticated;
do $x$
declare e text;
begin
  begin perform b2b.partner_adapter_status(20); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r values ('non_admin_denied', e = 'not allowed', e);
  begin perform b2b.partner_sync_tick(); e := 'ran'; exception when others then e := sqlstate; end;
  insert into r values ('tick_not_for_users', e = '42501', e);
end $x$;
reset role;

select name, ok, detail from r where not ok union all select 'TOTAL', bool_and(ok), count(*)::text from r;
rollback;
