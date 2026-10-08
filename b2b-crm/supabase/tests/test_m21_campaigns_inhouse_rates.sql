-- A3 fixture: the consent wording the test leads carry
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at) values ('test-partner-share:v1', 'web_form', '{partner_share}', 'test', true, true, now()) on conflict (version) do nothing;
-- M21 on STAGING, rolled back.
--   Campaigns and CAPI: a paid Meta lead form, an organic Meta lead form, a Google ad click, a UTM-only paid lead and a
--   lead with no ad; the campaign recorded for each; conversions only for the paid platform, tagged with the campaign;
--   the signal ladder (qualified, interested, applied, enrolled) with values; the per-campaign quality report.
--   In-house partner CRM: settings checks, the push request (header auth, wrapper key), its answers (record ID path,
--   the partner's duplicate status) and polling a changes address (dotted status path).
--   Commission levels: partner + programme from the programme sheet (GST included, then GST extra), partner + university,
--   partner-wide, and the order between them.
-- Every row of the final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.admin() returns void language sql as $f$
  select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a7","role":"authenticated","aal":"aal2","email":"m21-admin@test.local"}', true)
$f$;
create function pg_temp.answer(p_id bigint, p_status int, p_body text) returns void language sql as $f$
  insert into net._http_response (id, status_code, content_type, content, timed_out, error_msg, created) values (p_id, p_status, 'application/json', p_body, false, null, now())
$f$;
create function pg_temp.lead_for_20(p_phone text) returns bigint language plpgsql as $f$
declare v_id bigint; a_id bigint;
begin
  perform set_config('b2b.actor', 'engine', true);
  perform public.lead_intake(jsonb_build_object('phone', p_phone, 'source_system', 'crm', 'event_type', 'lead.created',
    'lead', jsonb_build_object('full_name', 'Inhouse Test ' || right(p_phone, 2), 'email', 'inhouse' || right(p_phone, 2) || '@example.com',
                               'interested_course', 'MBA', 'programme_level', 'PG', 'study_mode_preference', 'online',
                               'state', 'Delhi', 'source', 'whatsapp_direct', 'classification', 'WARM', 'consent_partner_share_at', now(), 'consent_text_version', 'test-partner-share:v1')));
  select id into v_id from public.student_leads where whatsapp_number = p_phone;
  perform b2b.route_decide(v_id, true, 'm21', 'auto');
  select id into a_id from b2b.allocations where lead_id = v_id and destination_type = 'partner' and partner_id = 20 order by id desc limit 1;
  return a_id;
end $f$;

update b2b.settings set value = value || '{"consent":"sales"}' where key = 'capi';
update b2b.live_switches set live = false where scope in ('capi_meta', 'capi_google');
update b2b.settings set value = jsonb_set(value, '{exploration_share}', '0') where key = 'engine';
insert into b2b.live_switches (scope, live, reason) values ('partner:20', true, 'm21 test') on conflict (scope) do update set live = true;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000a7', 'm21-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000a7', 'm21-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000a8', 'nobody21@test.local', 'authenticated', 'authenticated');

-- ================= campaigns and CAPI =================
set local role authenticated;
select pg_temp.admin();
select b2b.intake_settings_save('{"meta":{"verify_token":"vtoken-m21-123","app_secret":"msecret-m21-123"}}');
reset role;
do $x$
declare x jsonb; v_body text; v_req bigint;
begin
  -- M: a paid Meta lead form
  v_body := '{"object":"page","entry":[{"id":"P1","changes":[{"field":"leadgen","value":{"leadgen_id":"L-2101","form_id":"F-21","page_id":"P1","ad_id":"AD-1","adgroup_id":"AS-1"}}]}]}';
  perform b2b.meta_webhook_ingest(v_body, 'sha256=' || encode(extensions.hmac(convert_to(v_body, 'UTF8'), convert_to('msecret-m21-123', 'UTF8'), 'sha256'), 'hex'));
  select id into v_req from b2b.intake_requests where source = 'meta' and idempotency_key = 'L-2101';
  x := b2b.meta_lead_apply(v_req, '{"id":"L-2101","created_time":"2026-10-06T09:00:00+0000","form_id":"F-21","campaign_id":"C-100","campaign_name":"Oct MBA",
                                    "adset_id":"AS-1","adset_name":"Delhi 25-34","ad_id":"AD-1","ad_name":"Video A","platform":"fb","is_organic":false,
                                    "field_data":[{"name":"full_name","values":["Paid Meta"]},{"name":"phone_number","values":["+919876504501"]},
                                                  {"name":"email","values":["paid.meta@example.com"]},{"name":"preferred_course","values":["MBA"]}]}');
  insert into t values ('M', x ->> 'lead_id');
  -- O: an organic Meta lead form (a page post, not an ad)
  v_body := '{"object":"page","entry":[{"id":"P1","changes":[{"field":"leadgen","value":{"leadgen_id":"L-2102","form_id":"F-21","page_id":"P1"}}]}]}';
  perform b2b.meta_webhook_ingest(v_body, 'sha256=' || encode(extensions.hmac(convert_to(v_body, 'UTF8'), convert_to('msecret-m21-123', 'UTF8'), 'sha256'), 'hex'));
  select id into v_req from b2b.intake_requests where source = 'meta' and idempotency_key = 'L-2102';
  x := b2b.meta_lead_apply(v_req, '{"id":"L-2102","created_time":"2026-10-06T10:00:00+0000","form_id":"F-21","platform":"fb","is_organic":true,
                                    "field_data":[{"name":"full_name","values":["Organic Meta"]},{"name":"phone_number","values":["+919876504502"]},
                                                  {"name":"preferred_course","values":["MBA"]}]}');
  insert into t values ('O', x ->> 'lead_id');
end $x$;
-- G: a website lead from a Google search ad
insert into t select 'G', (b2b.intake_lead('{"full_name":"Paid Google","phone":"919876504503","email":"paid.google@example.com","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'click_ids', '{"gclid":"Cj0M21GCLID","campaign_id":"G-777"}'::jsonb,
                     'utm', '{"source":"google","medium":"cpc","campaign":"Brand Search"}'::jsonb, 'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id');
-- U: a paid Instagram ad with UTM tags only (no click ID: the platform cannot match it)
insert into t select 'U', (b2b.intake_lead('{"full_name":"Utm Only","phone":"919876504504","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'utm', '{"source":"instagram","medium":"paid_social","campaign":"Diwali"}'::jsonb,
                     'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id');
-- N: no ad at all, only Meta's browser cookie (fbp alone is not an ad click)
insert into t select 'N', (b2b.intake_lead('{"full_name":"No Ad","phone":"919876504505","course":"MBA"}',
  jsonb_build_object('source_system', 'api', 'lead_source', 'website', 'click_ids', '{"fbp":"fb.1.1700000000.123"}'::jsonb,
                     'consent', jsonb_build_object('sales_at', now()))) ->> 'lead_id');

-- the journey: M qualified (B2C sales), counselled, applied, enrolled; G qualified; O, U, N routed to sales too
insert into b2b.allocations (lead_id, cycle_no, destination_type, b2c_lane, status, mode, reason)
select v::bigint, 1, 'in_house', 'sales', 'handed_off', 'fallback', 'paid_campaign' from t where k in ('M', 'G', 'O', 'U', 'N');
update public.student_leads set stage = 'counselled', stage_changed_at = now(), applied_at = now() + interval '1 minute'
 where id = pg_temp.v('M')::bigint;
insert into public.enrollments (lead_id, cycle_no, status, destination_type, expected_net_revenue_inr, enrolled_on)
values (pg_temp.v('M')::bigint, 1, 'reported', 'in_house', 20000, current_date);

insert into r select 'detect_meta_paid', d @> '{"platform":"meta","paid":true,"matchable":true,"click_key":"leadgen_id","campaign_id":"C-100","campaign_name":"Oct MBA","adset_id":"AS-1","ad_id":"AD-1","origin":"meta_lead_form"}',
                       d::text
  from public.student_leads l, b2b.lead_campaign_detect(l) d where l.id = pg_temp.v('M')::bigint;
insert into r select 'detect_meta_organic', d @> '{"platform":"meta","paid":false,"matchable":false}', d::text
  from public.student_leads l, b2b.lead_campaign_detect(l) d where l.id = pg_temp.v('O')::bigint;
insert into r select 'detect_google', d @> '{"platform":"google","paid":true,"matchable":true,"click_key":"gclid","campaign_id":"G-777"}' and d -> 'utm' ->> 'campaign' = 'Brand Search', d::text
  from public.student_leads l, b2b.lead_campaign_detect(l) d where l.id = pg_temp.v('G')::bigint;
insert into r select 'detect_utm_only', d @> '{"platform":"meta","paid":true,"matchable":false}' and d -> 'utm' ->> 'campaign' = 'Diwali', d::text
  from public.student_leads l, b2b.lead_campaign_detect(l) d where l.id = pg_temp.v('U')::bigint;
insert into r select 'detect_no_ad', d @> '{"paid":false}' and d ->> 'platform' = 'none', d::text
  from public.student_leads l, b2b.lead_campaign_detect(l) d where l.id = pg_temp.v('N')::bigint;

insert into r select 'milestones_M', string_agg(m.stage || '=' || coalesce(m.value_inr::text, '-'), ',' order by m.stage)
                       = 'applied=6000.00,contacted=-,enrolled=20000,interested=2250.00,lead=-,partner_accepted=-,qualified=750.00'
                       or string_agg(m.stage || '=' || coalesce(m.value_inr::text, '-'), ',' order by m.stage)
                       = 'applied=6000.00,enrolled=20000,interested=2250.00,lead=-,partner_accepted=-,qualified=750.00',
                       string_agg(m.stage || '=' || coalesce(m.value_inr::text, '-'), ',' order by m.stage)
  from public.student_leads l, b2b.capi_milestones(l) m where l.id = pg_temp.v('M')::bigint;
insert into r select 'interested_before_applied', (select at from b2b.capi_milestones(l) where stage = 'interested') < (select at from b2b.capi_milestones(l) where stage = 'applied'), null
  from public.student_leads l where l.id = pg_temp.v('M')::bigint;

select b2b.capi_lead_sync(v::bigint) from t where k in ('M', 'O', 'G', 'U', 'N');
insert into r select 'events_M_meta_only', string_agg(stage, ',' order by stage) = 'applied,enrolled,interested,qualified' and bool_and(platform = 'meta')
                       and bool_and(campaign_id = 'C-100' and campaign_name = 'Oct MBA') and bool_and(status = 'pending'),
                       string_agg(platform || ':' || stage || ':' || status || ':' || coalesce(campaign_id, '-'), ' ')
  from b2b.conversion_events where lead_id = pg_temp.v('M')::bigint;
insert into r select 'event_names', string_agg(event_name, ',' order by stage) = 'Applicant,Enrolled,Interested,Qualified Lead'
                       or string_agg(event_name, ',' order by stage) like 'Applicant,Enrolled,Interested,%', string_agg(event_name, ',' order by stage)
  from b2b.conversion_events where lead_id = pg_temp.v('M')::bigint;
insert into r select 'event_values', max(value_inr) filter (where stage = 'qualified') = 750 and max(value_inr) filter (where stage = 'interested') = 2250
                       and max(value_inr) filter (where stage = 'applied') = 6000 and max(value_inr) filter (where stage = 'enrolled') = 20000
                       and max(payload -> 'custom_data' ->> 'value') filter (where stage = 'applied') = '6000.00', string_agg(stage || '=' || value_inr, ' ')
  from b2b.conversion_events where lead_id = pg_temp.v('M')::bigint;
insert into r select 'events_G_google_only', count(*) = 1 and bool_and(platform = 'google' and stage = 'qualified' and campaign_id = 'G-777'),
                       string_agg(platform || ':' || stage || ':' || status, ' ')
  from b2b.conversion_events where lead_id = pg_temp.v('G')::bigint;
insert into r select 'no_events_unpaid_or_unmatchable', not exists (select 1 from b2b.conversion_events where lead_id in (pg_temp.v('O')::bigint, pg_temp.v('U')::bigint, pg_temp.v('N')::bigint)), null;
insert into r select 'campaigns_recorded', count(*) = 5 and count(*) filter (where paid) = 3 and count(*) filter (where matchable) = 2
                       and bool_or(lead_id = pg_temp.v('M')::bigint and campaign_id = 'C-100' and adset_name = 'Delhi 25-34' and ad_name = 'Video A'
                                   and form_id = 'F-21' and utm_source = 'facebook' and touched_at < '2026-10-06 09:00:00+00'),
                       string_agg(lead_id || ':' || platform || ':' || paid || ':' || coalesce(campaign_id, campaign_name, '-'), ' ')
  from b2b.lead_campaigns where lead_id in (select v::bigint from t where k in ('M', 'O', 'G', 'U', 'N'));

-- the Admin: the lead check shows the campaign, the report ranks campaigns by quality, settings take values
set local role authenticated;
select pg_temp.admin();
do $x$
declare c jsonb; e text; s jsonb;
begin
  c := b2b.capi_lead_check(pg_temp.v('M')::bigint, false);
  insert into r values ('lead_check_campaign', c -> 'campaign' ->> 'campaign_id' = 'C-100' and not (c -> 'campaign') ? 'ck'
                          and (select bool_and(m -> 'google' = 'null'::jsonb) from jsonb_array_elements(c -> 'milestones') m)
                          and (select count(*) from jsonb_array_elements(c -> 'milestones') m where m -> 'meta' <> 'null'::jsonb) = 4, left(c::text, 400));
  c := b2b.capi_lead_check(pg_temp.v('O')::bigint, false);
  insert into r values ('lead_check_organic_no_preview', (c -> 'campaign' ->> 'paid')::boolean = false
                          and (select bool_and(m -> 'meta' = 'null'::jsonb) from jsonb_array_elements(c -> 'milestones') m), left(c::text, 300));
  c := b2b.capi_campaigns(90, null);
  insert into r values ('report_meta', exists (select 1 from jsonb_array_elements(c -> 'campaigns') x
                                               where x @> '{"platform":"meta","campaign_id":"C-100","leads":1,"matchable":1,"qualified":1,"interested":1,"applied":1,"enrolled":1}'
                                                 and (x ->> 'commission')::numeric = 20000), left((c -> 'campaigns')::text, 500));
  insert into r values ('report_google', exists (select 1 from jsonb_array_elements(c -> 'campaigns') x
                                                 where x @> '{"platform":"google","campaign_id":"G-777","leads":1,"qualified":1,"enrolled":0}'), null);
  insert into r values ('report_utm_only', exists (select 1 from jsonb_array_elements(c -> 'campaigns') x
                                                   where x @> '{"platform":"meta","campaign_name":"Diwali","leads":1,"matchable":0}'), null);
  insert into r values ('report_unpaid', (c ->> 'unpaid')::int >= 2, c ->> 'unpaid');
  c := b2b.capi_campaigns(90, 'google');
  insert into r values ('report_platform_filter', not exists (select 1 from jsonb_array_elements(c -> 'campaigns') x where x ->> 'platform' <> 'google'), null);

  begin perform b2b.capi_settings_save('{"values":{"enrolled":0.5}}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('values_only_early_signals', e = 'values are set for qualified, interested and applied', e);
  begin perform b2b.capi_settings_save('{"values":{"applied":1.5}}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('values_share', e like 'a signal value is a share%', e);
  perform b2b.capi_settings_save('{"values":{"applied":0.5},"base_value_inr":"20000","meta":{"map":{"qualified":{"event":"Qualified Lead","enabled":true},"interested":{"event":"Interested","enabled":false}}}}');
  s := (select value from b2b.settings where key = 'capi');
  insert into r values ('values_saved', s -> 'values' ->> 'applied' = '0.5' and s -> 'values' ->> 'qualified' = '0.05' and s ->> 'base_value_inr' = '20000'
                          and s -> 'meta' -> 'map' -> 'interested' ->> 'enabled' = 'false', (s -> 'values')::text || ' ' || (s ->> 'base_value_inr'));
end $x$;
select pg_temp.admin();
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a8","role":"authenticated","aal":"aal2","email":"nobody21@test.local"}', true);
do $x$ declare e text; begin
  begin perform b2b.capi_campaigns(90, null); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r values ('report_admin_only', e = 'not allowed', e);
end $x$;
reset role;
insert into r select 'value_follows_setting', (select value_inr from b2b.capi_milestones(l) where stage = 'applied') = 10000, null
  from public.student_leads l where l.id = pg_temp.v('M')::bigint;

-- ================= in-house partner CRM =================
update b2b.partners set adapter_type = 'inhouse' where id = 20;
insert into r values
  ('ih_created_path', b2b.json_path_text('{"data":{"lead":{"id":"IH-1"}}}', 'data.lead.id') = 'IH-1', null),
  ('ih_query_auth', b2b.inhouse_query_auth('{"auth_type":"query","auth_name":"apikey","secrets":{"token":"TOK12345"}}', 'https://x.example/leads?src=e')
                    = '&apikey=TOK12345', null),
  ('ih_basic_auth', b2b.inhouse_header_auth('{"auth_type":"basic","secrets":{"token":"user:pass"}}') ->> 'Authorization' = 'Basic dXNlcjpwYXNz', null),
  ('ih_parse_list', b2b.adapter_poll_parse('inhouse', '{"data":{"records":[{"lead_id":"9","stage":{"name":"Applied"},"meta":{"ref":"EDW-5"},"modified_at":"2026-10-07T01:00:00Z"}]}}',
                                           'stage.name', 'meta.ref') @> '[{"record_id":"9","stage":"Applied","reference":"EDW-5","modified":"2026-10-07T01:00:00Z"}]', null),
  ('ih_parse_array', jsonb_array_length(b2b.adapter_poll_parse('inhouse', '[{"id":"1","status":"New"},{"id":"2","status":"Lost"},"x"]', 'status', 'eduwit_reference')) = 2, null);

set local role authenticated;
select pg_temp.admin();
do $x$
declare e text; s jsonb; pv jsonb;
begin
  begin perform b2b.partner_adapter_save(20, '{"env":"live","settings":{"create_url":"http://crm.partner.example/api/leads","auth_type":"header"},"secrets":{"token":"IH-TOKEN-1234"}}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('ih_https_only', e = 'create url must be an https address', e);
  begin perform b2b.partner_adapter_save(20, '{"env":"live","settings":{"create_url":"https://crm.partner.example/api/leads","auth_type":"magic"},"secrets":{"token":"IH-TOKEN-1234"}}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('ih_auth_type_checked', e = 'choose how the CRM checks Eduwit''s key', e);
  begin perform b2b.partner_adapter_save(20, '{"env":"live","settings":{"create_url":"https://crm.partner.example/api/leads","auth_type":"bearer"}}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('ih_token_required', e = 'the token is required', e);
  s := b2b.partner_adapter_save(20, '{"env":"sandbox","settings":{"create_url":"https://sandbox.partner.example/leads","auth_type":"none"}}');
  insert into r values ('ih_no_auth_sandbox', (s -> 'envs' -> 'sandbox' ->> 'configured')::boolean, (s -> 'envs' -> 'sandbox')::text);
  s := b2b.partner_adapter_save(20, '{"env":"live","settings":{"create_url":"https://crm.partner.example/api/leads","auth_type":"header","auth_name":"X-Api-Key",
                                       "wrap_key":"lead","record_id_path":"data.lead.id","duplicate_status":"400"},"secrets":{"token":"IH-TOKEN-1234"}}');
  insert into r values ('ih_saved_no_poll', s::text not like '%IH-TOKEN-1234%' and (s -> 'envs' -> 'live' ->> 'configured')::boolean
                          and s -> 'envs' -> 'live' -> 'settings' ->> 'poll' = 'false', (s -> 'envs' -> 'live')::text);
  pv := b2b.partner_adapter_preview(20, 'live');
  insert into r values ('ih_preview', pv ->> 'url' = 'https://crm.partner.example/api/leads' and pv -> 'headers' ->> 'X-Api-Key' = '••••'
                          and pv -> 'body' -> 'lead' ->> 'source' = 'Eduwit' and pv -> 'body' -> 'lead' ? 'eduwit_reference', left(pv::text, 400));
end $x$;
reset role;
insert into t select 'a1', pg_temp.lead_for_20('919876504601')::text;
insert into t select 'a2', pg_temp.lead_for_20('919876504602')::text;
insert into r select 'ih_routed', pg_temp.v('a1') is not null and pg_temp.v('a2') is not null, pg_temp.v('a1') || ',' || pg_temp.v('a2');
update b2b.allocations set next_push_at = null where id in (pg_temp.v('a1')::bigint, pg_temp.v('a2')::bigint);
select b2b.push_dispatch(100);
insert into r select 'ih_push_request', q.url = 'https://crm.partner.example/api/leads' and q.headers ->> 'X-Api-Key' = 'IH-TOKEN-1234'
                       and convert_from(q.body, 'UTF8')::jsonb -> 'lead' ->> 'eduwit_reference' = a.reference
                       and convert_from(q.body, 'UTF8')::jsonb -> 'lead' ->> 'name' = 'Inhouse Test 01'
                       and convert_from(q.body, 'UTF8')::jsonb -> 'lead' ->> 'course' is not null, convert_from(q.body, 'UTF8')
  from b2b.allocations a join net.http_request_queue q on q.id = a.push_request_id where a.id = pg_temp.v('a1')::bigint;
select pg_temp.answer(push_request_id, 201, '{"ok":true,"data":{"lead":{"id":"IH-77"}}}') from b2b.allocations where id = pg_temp.v('a1')::bigint;
select pg_temp.answer(push_request_id, 400, '{"message":"Mobile number exists","existing_id":"IH-12"}') from b2b.allocations where id = pg_temp.v('a2')::bigint;
select b2b.push_collect();
insert into r select 'ih_created', partner_record_id = 'IH-77' and status in ('pushed', 'accepted'), status || ' ' || coalesce(partner_record_id, '')
  from b2b.allocations where id = pg_temp.v('a1')::bigint;
insert into r select 'ih_duplicate_status', status = 'duplicate' and claim_proof ->> 'existing_record_id' = 'IH-12', status || ' ' || coalesce(claim_proof::text, '')
  from b2b.allocations where id = pg_temp.v('a2')::bigint;
insert into r values
  ('ih_auth_answer', b2b.adapter_push_result_p(20, false, 'inhouse', 401, '{"error":"bad key"}') ->> 'outcome' = 'auth', null),
  ('ih_rejected_answer', b2b.adapter_push_result_p(20, false, 'inhouse', 422, '{"rejected":true,"reason":"course not offered"}') @> '{"outcome":"rejected","reason":"course not offered"}', null),
  ('ih_409_duplicate', b2b.adapter_push_result_p(20, false, 'inhouse', 409, '{}') ->> 'outcome' = 'duplicate', null),
  ('ih_other_adapters_unchanged', b2b.adapter_push_result_p(20, false, 'hubspot', 201, '{"id":"801"}') ->> 'record_id' = '801', null);

-- polling the changes address
set local role authenticated;
select pg_temp.admin();
select b2b.partner_adapter_save(20, '{"env":"live","settings":{"poll_url":"https://crm.partner.example/api/changes?since={since}"},"status_field":"stage.name","poll":true,"poll_minutes":10}');
select b2b.partner_adapter_action(20, 'live', 'poll');
reset role;
insert into r select 'ih_poll_request', q.url like 'https://crm.partner.example/api/changes?since=20%' and q.headers ->> 'X-Api-Key' = 'IH-TOKEN-1234' and q.method = 'GET', q.url
  from b2b.partner_adapter_state s join net.http_request_queue q on q.id = s.poll_request_id where s.partner_id = 20 and s.env = 'live';
select pg_temp.answer(s.poll_request_id, 200, jsonb_build_object('data', jsonb_build_array(
         jsonb_build_object('id', 'IH-77', 'stage', jsonb_build_object('name', 'Counselled'), 'updated_at', '2026-10-07T02:00:00Z',
                            'eduwit_reference', (select reference from b2b.allocations where id = pg_temp.v('a1')::bigint)))) ::text)
  from b2b.partner_adapter_state s where s.partner_id = 20 and s.env = 'live';
select b2b.partner_sync_tick();
insert into r select 'ih_poll_applied', s.poll_request_id is null and s.last_poll_result ->> 'records' = '1' and coalesce(s.last_poll_result ->> 'unmatched', '0') = '0',
                       s.last_poll_result::text || ' ' || coalesce(s.last_poll_error, '')
  from b2b.partner_adapter_state s where s.partner_id = 20 and s.env = 'live';
insert into r select 'ih_poll_event', count(*) filter (where event_type = 'stage' and raw -> 'data' ->> 'stage' = 'Counselled') = 1, string_agg(event_type || ':' || status, ' ')
  from b2b.partner_events where allocation_id = pg_temp.v('a1')::bigint and event_id like 'poll:%';

-- ================= commission levels =================
-- partner 20's current rates end yesterday; university 18 runs programmes 33, 34 and 35
update b2b.rates set valid_from = least(valid_from, current_date - 1), valid_to = current_date - 1 where partner_id = 20 and valid_to is null;
insert into b2b.partner_programme_sources (partner_id, type) values (20, 'upload') on conflict (partner_id) do nothing;
update b2b.partner_programme_sources set commission_includes_gst = true where partner_id = 20;
update b2b.partner_programmes set valid_to = now() where partner_id = 20 and valid_to is null;
with v as (insert into b2b.partner_programme_versions (partner_id, version_no, source_type, status)
           select 20, coalesce(max(version_no), 0) + 1, 'upload', 'draft' from b2b.partner_programme_versions where partner_id = 20 returning id)
insert into t select 'ver', id::text from v;
insert into t select 'other_prog', min(id)::text from public.catalog_programs where university_id is distinct from 18;
insert into b2b.partner_programmes (partner_id, programme_id, program_key, commission, source_version_id)
values (20, 33, 'm21-33', '{"type":"percent","value":12}', pg_temp.v('ver')::bigint),
       (20, 34, 'm21-34', '{"type":"tier","value":"Tier 2"}', pg_temp.v('ver')::bigint),
       (20, 35, 'm21-35', null, pg_temp.v('ver')::bigint);

set local role authenticated;
select pg_temp.admin();
do $x$
declare e text; x jsonb;
begin
  begin perform b2b.rate_save('{"scope":"partner_university","partner_id":20,"university_id":-1,"rate_type":"percent","value":11}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('uni_rate_needs_university', e = 'choose a university', e);
  begin perform b2b.rate_save('{"scope":"university","university_id":18,"rate_type":"percent","value":11}'); e := 'saved';
  exception when others then e := sqlerrm; end;
  insert into r values ('rate_scopes_listed', e like 'rates are set per partner, per university at a partner or per partner programme', e);
  perform b2b.rate_save('{"scope":"partner","partner_id":20,"rate_type":"percent","value":10,"gst_inclusive":false}');
  perform b2b.rate_save('{"scope":"partner_university","partner_id":20,"university_id":18,"rate_type":"percent","value":11,"gst_inclusive":false}');
  x := b2b.rates_confirm_from_offers(20);
  insert into r values ('from_sheet', x @> '{"created":1,"unchanged":0,"ended":0,"tiers_skipped":1,"gst_inclusive":true}', x::text);
  x := b2b.rates_confirm_from_offers(20);
  insert into r values ('from_sheet_again', x @> '{"created":0,"unchanged":1}', x::text);
  x := b2b.programme_commission_gst_save(20, false);
  insert into r values ('gst_extra', x @> '{"created":1,"gst_inclusive":false}', x::text);
end $x$;
reset role;
insert into r select 'precedence_programme', (r1).scope = 'partner_programme' and (r1).value = 12 and not (r1).gst_inclusive and (r1).source = 'file'
                       and (r1).note = 'From the partner''s programme sheet (GST extra)', (r1)::text
  from (select b2b.rate_for(20, 33) r1) x;
insert into r select 'precedence_university', (r1).scope = 'partner_university' and (r1).value = 11 and (r1).university_id = 18, (r1)::text
  from (select b2b.rate_for(20, 35) r1) x;
insert into r select 'precedence_tier_ref_falls_back', (r1).scope = 'partner_university', (r1)::text from (select b2b.rate_for(20, 34) r1) x;
insert into r select 'precedence_partner', (r1).scope = 'partner' and (r1).value = 10, (r1)::text
  from (select b2b.rate_for(20, pg_temp.v('other_prog')::bigint) r1) x;
insert into r select 'one_live_file_rate', count(*) = 1, count(*)::text
  from b2b.rates where scope = 'partner_programme' and partner_id = 20 and programme_id = 33 and source = 'file' and (valid_to is null or valid_to >= current_date) and valid_from <= current_date
                   and id = (b2b.rate_for(20, 33)).id;

-- the commission leaves the sheet: its file rate ends today, the university rate applies from tomorrow
update b2b.partner_programmes set commission = null where partner_id = 20 and programme_id = 33 and valid_to is null;
insert into r select 'commission_left_sheet', (b2b.rates_from_offers(20)) @> '{"ended":1}', null;
insert into r select 'after_sheet_change', (b2b.rate_for(20, 33, current_date + 1)).scope = 'partner_university', null;
insert into r select 'rate_events', count(*) filter (where type = 'rate.from_file') >= 3 and count(*) filter (where type = 'programmes.commission_gst') = 1, null
  from b2b.events where partner_id = 20 and occurred_at >= now() - interval '1 minute';
insert into r select 'scope_check', exists (select 1 from pg_constraint where conname = 'rates_scope_ids_check'), null;

select name, ok, detail from r order by ok, name;
rollback;
