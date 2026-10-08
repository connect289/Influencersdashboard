-- A3 fixture: the consent wording the test leads carry
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners, active, lawyer_approved_at) values ('test-partner-share:v1', 'web_form', '{partner_share}', 'test', true, true, now()) on conflict (version) do nothing;
-- M17 intake on STAGING, rolled back: the import wizard (stage, preview, courses, commit, hold, release, B2C choice,
-- rollback), the Intake API (idempotency, refusals), Google lead forms, Meta Lead Ads (verify, signature, apply) and
-- manual entry. Every row of the final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;

-- an existing lead, so one import row merges
select public.lead_intake('{"phone":"919876503202","source_system":"crm","event_type":"lead.created","lead":{"full_name":"Existing One","interested_course":"BBA"}}');

insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'intake-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000c1', 'intake-admin@test.local');
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000c2', 'nobody@test.local', 'authenticated', 'authenticated');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated","aal":"aal2","email":"intake-admin@test.local"}', true);

-- ---------- import wizard ----------
do $x$
declare e text; v_id bigint; x jsonb; c jsonb;
begin
  begin perform b2b.import_create('{"file_name":"a.csv","mapping":{"Name":"full_name"}}'); e := 'created'; exception when others then e := sqlerrm; end;
  insert into r values ('import_needs_phone', e = 'map a column to the phone number', e);
  begin perform b2b.import_create('{"file_name":"a.csv","mapping":{"Name":"full_name","Mobile":"phone","Other":"phone"}}'); e := 'created'; exception when others then e := sqlerrm; end;
  insert into r values ('import_one_column_per_field', e = 'each lead field can be mapped from one column only', e);

  v_id := b2b.import_create('{"file_name":"fair.csv","template_name":"Education fair","mapping":{"Name":"full_name","Mobile":"phone","Mail":"email","Course":"course","City":"city","Junk":"ignore"}}');
  insert into t values ('imp1', v_id::text);
  x := b2b.import_stage_rows(v_id, 1, '[
    {"Name":"ANKIT SHARMA","Mobile":"98765 03201","Mail":"Ankit@Example.com","Course":"Online M.B.A","City":"Delhi"},
    {"Name":"Ankit again","Mobile":"+91-98765-03201","Mail":"not-an-email","Course":"MBA"},
    {"Name":"Bad Number","Mobile":"12345","Course":"MBA"},
    {"Name":"Test Row","Mobile":"919000000071","Course":"MBA"},
    {"Name":"Existing","Mobile":"9876503202","Course":"Underwater Basket Weaving"}]');
  insert into r values ('staged', (x ->> 'staged')::int = 5 and (x ->> 'total')::int = 5, x::text);
  x := b2b.import_preview(v_id);
  insert into r values ('preview_counts', (x -> 'preview' ->> 'new')::int = 1 and (x -> 'preview' ->> 'duplicate_in_file')::int = 1
                          and (x -> 'preview' ->> 'invalid')::int = 1 and (x -> 'preview' ->> 'test')::int = 1 and (x -> 'preview' ->> 'merge')::int = 1
                          and (x -> 'problems' ->> 'invalid email (dropped)')::int = 1, (x -> 'preview')::text || (x -> 'problems')::text);
  insert into r values ('row_normalised', exists (select 1 from jsonb_array_elements(x -> 'sample') s
                          where s -> 'lead' ->> 'full_name' = 'Ankit Sharma' and s -> 'lead' ->> 'email' = 'ankit@example.com' and s -> 'lead' ->> 'phone' = '919876503201'), null);
  c := b2b.import_courses(v_id);
  insert into r values ('courses_matched', exists (select 1 from jsonb_array_elements(c) z where z ->> 'text' = 'MBA' and (z ->> 'confidence')::numeric = 1 and z ->> 'key' = 'mba')
                          and exists (select 1 from jsonb_array_elements(c) z where z ->> 'text' = 'Underwater Basket Weaving' and z ->> 'key' is null), c::text);
  perform b2b.import_set_course(v_id, 'Online M.B.A', 'mba');
  begin perform b2b.import_set_course(v_id, 'MBA', 'no_such_course'); e := 'set'; exception when others then e := sqlerrm; end;
  insert into r values ('course_must_exist', e = 'that course is not in the catalogue', e);

  begin perform b2b.import_commit(v_id, '{"source_label":"Education fair","routing_choice":"hold","consent":{"where":"x"}}'); e := 'committed'; exception when others then e := sqlerrm; end;
  insert into r values ('commit_needs_consent', e like 'give the consent basis%', e);
  begin perform b2b.import_commit(v_id, '{"source_label":"Education fair","routing_choice":"route","consent":{"where":"Stall sign-up sheet","when":"2026-10-01","text":"I agree to be contacted about courses","purposes":["sales"]}}');
        e := 'committed'; exception when others then e := sqlerrm; end;
  insert into r values ('route_needs_partner_consent', e like 'to route to partners%', e);
  x := b2b.import_commit(v_id, '{"source_label":"Education fair","campaign":"Oct fair","routing_choice":"hold",
                                 "consent":{"where":"Stall sign-up sheet","when":"2026-10-01","text":"I agree to be contacted about courses and shared with partner universities","purposes":["sales","partner_share"]}}');
  while (x ->> 'left')::int > 0 loop x := b2b.import_continue(v_id); end loop;
  x := b2b.import_preview(v_id);
  insert into r values ('import_done', x -> 'import' ->> 'status' = 'done' and (x -> 'import' -> 'counts' ->> 'imported')::int = 4
                          and (x -> 'import' -> 'counts' ->> 'skipped')::int = 1 and (x -> 'import' -> 'counts' ->> 'created')::int = 2
                          and (x -> 'import' -> 'counts' ->> 'merged')::int = 2 and (x ->> 'can_rollback')::boolean, (x -> 'import' -> 'counts')::text);
end $x$;
reset role;

insert into t select 'new1', id::text from public.student_leads where whatsapp_number = '919876503201';
insert into t select 'old1', id::text from public.student_leads where whatsapp_number = '919876503202';
insert into r select 'lead_written', l.interested_course = 'MBA' and l.lead_source = 'education_fair' and l.campaign = 'Oct fair'
    and l.email_id = 'ankit@example.com' and l.consent_partner_share_at is not null and l.consent_text_version = 'import:' || pg_temp.v('imp1'),
  l.interested_course || ' ' || l.lead_source || ' ' || coalesce(l.campaign, '-')
  from public.student_leads l where l.id = pg_temp.v('new1')::bigint;
insert into r select 'merge_keeps_existing', l.student_name = 'Existing One' and l.interested_course = 'BBA', l.student_name || ' ' || l.interested_course
  from public.student_leads l where l.id = pg_temp.v('old1')::bigint;
insert into r select 'held_for_review', b2b.lead_readiness(l) -> 'missing' ? 'held for review' and b2b.lead_class(l) ->> 'class' = 'qualified'
    and b2b.pool_lead(l, true) ->> 'group' = 'held', (b2b.lead_readiness(l))::text
  from public.student_leads l where l.id = pg_temp.v('new1')::bigint;
insert into r select 'template_saved', exists (select 1 from b2b.import_templates where name = 'Education fair' and mapping ->> 'Mobile' = 'phone'), null;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated","aal":"aal2","email":"intake-admin@test.local"}', true);
do $x$
declare n int; v_id bigint; x jsonb;
begin
  n := b2b.intake_release(pg_temp.v('imp1')::bigint, null);
  insert into r values ('release', n >= 1, n::text);
  -- a second import that goes to B2C nurture
  v_id := b2b.import_create('{"file_name":"nurture.csv","mapping":{"Name":"full_name","Mobile":"phone","Course":"course"}}');
  insert into t values ('imp2', v_id::text);
  perform b2b.import_stage_rows(v_id, 1, '[{"Name":"Nurture Me","Mobile":"9876503203","Course":"MBA"}]');
  x := b2b.import_commit(v_id, '{"source_label":"old list","routing_choice":"b2c","b2c_lane":"nurture",
                                 "consent":{"where":"Website newsletter","when":"2026-09-01","text":"I agree to be contacted about courses","purposes":["sales"]}}');
  insert into r values ('b2c_import_done', x ->> 'status' = 'done', x::text);
end $x$;
reset role;
insert into r select 'released', not (b2b.lead_readiness(l) -> 'missing' ? 'held for review'), null from public.student_leads l where l.id = pg_temp.v('new1')::bigint;
insert into t select 'new2', id::text from public.student_leads where whatsapp_number = '919876503203';
insert into r select 'b2c_choice_preview', x ->> 'destination' = 'in_house' and x ->> 'reason' = 'import_choice' and x ->> 'b2c_lane' = 'nurture' and x ->> 'mode' = 'rule', x::text
  from (select b2b.route_decide(pg_temp.v('new2')::bigint, false, null, 'auto') x) y;
select set_config('b2b.actor', 'engine', true);
select b2b.route_decide(pg_temp.v('new2')::bigint, true, null, 'auto');
insert into r select 'b2c_choice_committed', l.destination_type = 'in_house' and a.reason = 'import_choice' and a.b2c_lane = 'nurture'
    and (select released_at is not null from b2b.intake_directives where lead_id = l.id), a.reason
  from public.student_leads l join b2b.allocations a on a.id = l.allocation_id where l.id = pg_temp.v('new2')::bigint;

-- ---------- rollback ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated","aal":"aal2","email":"intake-admin@test.local"}', true);
do $x$
declare x jsonb; e text;
begin
  begin perform b2b.import_rollback(pg_temp.v('imp1')::bigint, ''); e := 'rolled back'; exception when others then e := sqlerrm; end;
  insert into r values ('rollback_needs_reason', e = 'give a reason', e);
  x := b2b.import_rollback(pg_temp.v('imp1')::bigint, 'wrong file uploaded');
  insert into r values ('rollback', (x ->> 'deleted')::int = 2 and (x ->> 'kept')::int = 1, x::text);   -- the duplicate row's lead is the new lead
  x := b2b.import_rollback(pg_temp.v('imp2')::bigint, 'try');
  insert into r values ('rollback_keeps_routed', (x ->> 'deleted')::int = 0 and (x ->> 'kept')::int = 1, x::text);
end $x$;
reset role;
insert into r select 'rolled_back_rows', (select deleted_at is not null from public.student_leads where id = pg_temp.v('new1')::bigint)
    and (select deleted_at is null from public.student_leads where id = pg_temp.v('old1')::bigint)
    and (select status from b2b.imports where id = pg_temp.v('imp1')::bigint) = 'rolled_back', null;

-- ---------- Intake API ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated","aal":"aal2","email":"intake-admin@test.local"}', true);
insert into t select 'key', b2b.create_api_key('m17 website', array['intake']) ->> 'key';
reset role;
do $x$
declare x jsonb; b jsonb := '{"lead":{"phone":"98765 03204","full_name":"Api Lead","email":"api@example.com","course":"MBA","city":"Pune"},
                              "source":"website_form","campaign":"seo","consent":{"sales_at":"2026-10-06T10:00:00+05:30","partner_share_at":"2026-10-06T10:00:00+05:30","text_version":"web-v3"},
                              "phone_verified":true,"click_ids":{"msclkid":"abc"}}';
begin
  x := b2b.api_intake_lead(pg_temp.v('key'), 'idem-1', b);
  insert into r values ('api_created', (x ->> 'status')::int = 201 and x -> 'result' ->> 'action' = 'created' and x -> 'result' -> 'routing' ->> 'outlook' = 'partners', x::text);
  insert into t values ('api_lead', x -> 'result' ->> 'lead_id');
  x := b2b.api_intake_lead(pg_temp.v('key'), 'idem-1', b);
  insert into r values ('api_replay', (x ->> 'status')::int = 200 and (x ->> 'replayed')::boolean, x::text);
  x := b2b.api_intake_lead(pg_temp.v('key'), 'idem-1', b || '{"campaign":"other"}');
  insert into r values ('api_conflict', (x ->> 'status')::int = 409, x::text);
  x := b2b.api_intake_lead('eb2b_wrong', 'idem-2', b);
  insert into r values ('api_bad_key', (x ->> 'status')::int = 401, x::text);
  x := b2b.api_intake_lead(pg_temp.v('key'), null, b);
  insert into r values ('api_needs_idempotency', (x ->> 'status')::int = 400, x::text);
  x := b2b.api_intake_lead(pg_temp.v('key'), 'idem-3', '{"lead":{"phone":"9876503204","shoe_size":"9"}}');
  insert into r values ('api_unknown_field', (x ->> 'status')::int = 400 and x ->> 'error' like 'unknown lead fields: shoe_size%', x::text);
  x := b2b.api_intake_lead(pg_temp.v('key'), 'idem-4', '{"lead":{"phone":"12"}}');
  insert into r values ('api_bad_phone', (x ->> 'status')::int = 422, x::text);
end $x$;
insert into r select 'api_lead_written', l.lead_source = 'website_form' and l.click_ids ->> 'msclkid' = 'abc' and l.consent_text_version = 'web-v3'
    and b2b.lead_class(l) ->> 'class' = 'qualified', l.lead_source || ' ' || (b2b.lead_class(l))::text
  from public.student_leads l where l.id = pg_temp.v('api_lead')::bigint;

-- ---------- Google lead forms and Meta Lead Ads ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated","aal":"aal2","email":"intake-admin@test.local"}', true);
select b2b.intake_settings_save('{"google":{"key":"gkey-12345678"},"meta":{"verify_token":"vtoken-123456","app_secret":"msecret-123456"}}');
reset role;
do $x$
declare x jsonb; v_body text; v_req bigint;
begin
  x := b2b.google_leadform_ingest('{"google_key":"bad","lead_id":"g-1"}');
  insert into r values ('google_bad_key', (x ->> 'status')::int = 401, x::text);
  x := b2b.google_leadform_ingest('{"google_key":"gkey-12345678","lead_id":"g-1","form_id":"999","gcl_id":"G1","campaign_id":"77",
    "user_column_data":[{"column_id":"FULL_NAME","string_value":"Goo Gle"},{"column_id":"PHONE_NUMBER","string_value":"+91 98765 03205"},
                        {"column_id":"EMAIL","string_value":"g@example.com"},{"column_id":"which_course","column_name":"Which course?","string_value":"MBA"}]}');
  insert into r values ('google_first', x ->> 'result' = 'stored' and exists (select 1 from b2b.lead_forms where platform = 'google' and form_ref = '999')
                          and exists (select 1 from b2b.events where type = 'alert.intake_new_form'), x::text);
  x := b2b.google_leadform_ingest('{"google_key":"gkey-12345678","lead_id":"g-1"}');
  insert into r values ('google_replay', x ->> 'result' = 'already received', x::text);

  -- Meta
  insert into r values ('meta_verify', b2b.meta_webhook_verify('subscribe', 'vtoken-123456', 'abc') = 'abc'
                          and b2b.meta_webhook_verify('subscribe', 'nope', 'abc') is null, null);
  v_body := '{"object":"page","entry":[{"id":"P1","changes":[{"field":"leadgen","value":{"leadgen_id":"L-9","form_id":"F-1","page_id":"P1","ad_id":"A1","adgroup_id":"AS1"}}]}]}';
  x := b2b.meta_webhook_ingest(v_body, 'sha256=00');
  insert into r values ('meta_bad_signature', (x ->> 'status')::int = 401, x::text);
  x := b2b.meta_webhook_ingest(v_body, 'sha256=' || encode(extensions.hmac(convert_to(v_body, 'UTF8'), convert_to('msecret-123456', 'UTF8'), 'sha256'), 'hex'));
  select id into v_req from b2b.intake_requests where source = 'meta' and idempotency_key = 'L-9';
  insert into r values ('meta_stored', (x -> 'result' ->> 'leads')::int = 1 and v_req is not null, x::text);
  x := b2b.meta_lead_apply(v_req, '{"id":"L-9","created_time":"2026-10-06T09:00:00+0000","form_id":"F-1","campaign_name":"Oct MBA","platform":"ig",
                                    "field_data":[{"name":"full_name","values":["Meta Person"]},{"name":"phone_number","values":["+919876503206"]},
                                                  {"name":"email","values":["m@example.com"]},{"name":"preferred_course","values":["MBA"]}]}');
  insert into t values ('meta_lead', x ->> 'lead_id');
  insert into r values ('meta_applied', (select status from b2b.intake_requests where id = v_req) = 'done' and x ->> 'action' = 'created', x::text);
end $x$;
insert into r select 'google_lead_written', l.lead_source = 'google_lead_form' and l.click_ids ->> 'gclid' = 'G1' and l."Comments" like '%which_course: MBA%'
    and b2b.paid_signal(l) is not null, l.lead_source || ' ' || coalesce(l."Comments", '-')
  from public.student_leads l where l.whatsapp_number = '919876503205';
insert into r select 'meta_lead_written', l.lead_source = 'meta_lead_ad' and l.utm_source = 'instagram' and l.click_ids ->> 'leadgen_id' = 'L-9'
    and l.campaign = 'Oct MBA' and l.consent_sales_at is not null, l.lead_source || ' ' || coalesce(l.utm_source, '-')
  from public.student_leads l where l.id = pg_temp.v('meta_lead')::bigint;

-- a form mapping makes the course land in the right field
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c1","role":"authenticated","aal":"aal2","email":"intake-admin@test.local"}', true);
do $x$
declare e text; x jsonb;
begin
  begin perform b2b.lead_form_save('{"platform":"google","form_ref":"999","name":"MBA form","field_map":{"which_course":"shoe_size"}}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('form_field_checked', e like 'unknown lead field%', e);
  perform b2b.lead_form_save('{"platform":"google","form_ref":"999","name":"MBA form","field_map":{"which_course":"course"},"defaults":{"study_mode":"online"},
                               "consent_purposes":["sales","partner_share"],"campaign":"Google MBA"}');
  -- manual entry
  begin perform b2b.intake_manual('{"lead":{"phone":"9876503207","full_name":"Walk In"},"route":"hold","consent_purposes":["sales"]}'); e := 'saved'; exception when others then e := sqlerrm; end;
  insert into r values ('manual_needs_consent_where', e like 'say how the student agreed%', e);
  x := b2b.intake_manual('{"lead":{"phone":"9876503207","full_name":"Walk In","course":"MBA"},"route":"hold","consent_purposes":["sales","partner_share"],"consent_where":"walk-in at office"}');
  insert into t values ('manual_lead', x ->> 'lead_id');
  insert into r values ('manual_held', x -> 'routing' -> 'waiting_for' ? 'held for review', x::text);
  x := b2b.intake_overview();
  insert into r values ('overview', jsonb_array_length(x -> 'forms') >= 2 and jsonb_array_length(x -> 'imports') >= 2 and (x -> 'connections' -> 'google' ->> 'key')::boolean
                          and (x -> 'connections' -> 'meta' ->> 'app_secret')::boolean and not (x -> 'connections' -> 'meta' ->> 'page_token')::boolean
                          and (x ->> 'held_manual')::int >= 1, left(x::text, 200));
end $x$;
reset role;
select b2b.google_leadform_ingest('{"google_key":"gkey-12345678","lead_id":"g-2","form_id":"999","user_column_data":[{"column_id":"FULL_NAME","string_value":"Second Goo"},
  {"column_id":"PHONE_NUMBER","string_value":"9876503208"},{"column_id":"which_course","string_value":"MBA"}]}');
insert into r select 'form_mapping_applied', l.interested_course = 'MBA' and l.study_mode_preference = 'online' and l.campaign = 'Google MBA'
    and l.consent_partner_share_at is not null, coalesce(l.interested_course, '-') || ' ' || coalesce(l.study_mode_preference, '-')
  from public.student_leads l where l.whatsapp_number = '919876503208';

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000c2","role":"authenticated","aal":"aal2","email":"nobody@test.local"}', true);
set local role authenticated;
do $x$
declare e text;
begin
  begin perform b2b.intake_overview(); e := 'read'; exception when others then e := sqlerrm; end;
  insert into r values ('non_admin_denied', e = 'not allowed', e);
end $x$;
reset role;

select name, ok, detail from r where not ok union all select 'TOTAL', bool_and(ok), count(*)::text from r;
rollback;
