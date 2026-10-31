-- web14: site-wide code ceiling, lead writes for leads not tied to the verified student, outbox worker only when due,
-- daily Witty ceiling (estate audit 30 Oct 2026). Runs on the replica too (no catalogue needed).
begin;
create temp table r (ok boolean, name text) on commit drop;
create temp table v (k text primary key, val jsonb) on commit drop;

-- ---------------------------------------------------------------------------------------------------------------
-- 1. Site-wide hourly ceiling on verification codes (setting code_send_hourly_cap, default 200).
insert into r select (select value = '200'::jsonb from public.web_settings where key = 'code_send_hourly_cap'), 'code ceiling setting exists, default 200';
update public.web_settings set value = to_jsonb((select count(*) from public.web_verification_codes where created_at > now() - interval '1 hour') + 2)
 where key = 'code_send_hourly_cap';
insert into v select 'c1', public.web_gate_start('{"idempotency_key":"cap-1","surface":"enquiry","email":"cap1@example.com","phone":"+919876511101","name":"Cap One","code_hash":"h"}');
insert into v select 'c2', public.web_gate_start('{"idempotency_key":"cap-2","surface":"enquiry","email":"cap2@example.com","phone":"+919876511102","name":"Cap Two","code_hash":"h"}');
insert into v select 'c3', public.web_gate_start('{"idempotency_key":"cap-3","surface":"enquiry","email":"cap3@example.com","phone":"+919876511103","name":"Cap Three","code_hash":"h"}');
insert into r select (select val->>'status' from v where k = 'c1') = 'code_sent' and (select val->>'status' from v where k = 'c2') = 'code_sent', 'codes sent below the ceiling';
insert into r select (select val->>'reason' from v where k = 'c3') = 'site_busy', 'start refused at the ceiling';
insert into r select not exists (select 1 from public.web_gate_attempts where idempotency_key = 'cap-3'), 'a refused start leaves no attempt behind';
update public.web_verification_codes set resend_after = now() - interval '1 second' where attempt_id = (select (val->>'attempt_id')::uuid from v where k = 'c1');
insert into r select (public.web_gate_resend((select (val->>'attempt_id')::uuid from v where k = 'c1'), 'h2') ->> 'reason') = 'site_busy', 'resend refused at the ceiling';
update public.web_settings set value = '0' where key = 'code_send_hourly_cap';
insert into r select (public.web_gate_start('{"idempotency_key":"cap-4","surface":"signin","email":"cap4@example.com","code_hash":"h"}') ->> 'reason') = 'site_busy', 'a ceiling of 0 stops every send';
update public.web_settings set value = '"lots"' where key = 'code_send_hourly_cap';
insert into r select (public.web_gate_start('{"idempotency_key":"cap-5","surface":"signin","email":"cap5@example.com","code_hash":"h"}') ->> 'status') = 'code_sent', 'an invalid setting falls back to the default ceiling';
-- only super admins change it through the admin
insert into r select (public.web_admin_setting('code_send_hourly_cap', '300', gen_random_uuid(), 'editor@example.com', 'content_editor') ->> 'error') = 'forbidden', 'content editors cannot change the code ceiling';
insert into r select (public.web_admin_setting('code_send_hourly_cap', '300', gen_random_uuid(), 'admin@example.com', 'super_admin') ->> 'ok')::boolean, 'super admins can';
insert into r select (select value = '300'::jsonb from public.web_settings where key = 'code_send_hourly_cap'), 'the new ceiling is stored';
update public.web_settings set value = '1000000' where key = 'code_send_hourly_cap';

-- ---------------------------------------------------------------------------------------------------------------
-- 2. Lead writes. A lead whose confirmed email is someone else's, an enrolled lead or a CRM-owned lead gets the
--    website's fields fill-empty only; a new lead and the same student behave as before.
-- helper: start + verify one gate/form attempt in this test
create temp table g (k text primary key, attempt uuid, student uuid, session uuid, lead bigint) on commit drop;
create or replace function pg_temp.verify_as(p_key text, p_surface text, p_name text, p_email text, p_phone text) returns void language plpgsql as $$
declare s jsonb; vv jsonb;
begin
  s := public.web_gate_start(jsonb_build_object('idempotency_key', p_key, 'surface', p_surface, 'name', p_name, 'email', p_email, 'phone', p_phone,
         'consent_version', case when p_surface = 'gate' then 'web-gate-2026-10-v1' else 'web-form-2026-10-v1' end, 'is_test', true, 'code_hash', 'k-' || p_key));
  vv := public.web_gate_verify((s->>'attempt_id')::uuid, 'k-' || p_key);
  insert into pg_temp.g values (p_key, (s->>'attempt_id')::uuid, (vv->>'student_id')::uuid, (vv->>'session_id')::uuid, (vv->>'lead_id')::bigint);
end $$;

-- an existing lead (from WhatsApp) with a confirmed email
select public.lead_intake('{"phone":"919876522201","source_system":"witty","event_type":"lead.created","is_test":true,
  "lead":{"full_name":"Meera Iyer","is_name_confirmed":true,"email":"meera@example.com","is_email_confirmed":true,"interested_course":"MBA"}}');
insert into v select 'meera', to_jsonb(l) from public.student_leads l where whatsapp_number = '919876522201';

-- a verified visitor whose email is not the lead's confirmed email
select pg_temp.verify_as('l-other', 'enquiry', 'Other Person', 'other@example.com', '+919876522201');
insert into r select (select lead from g where k = 'l-other') = (select (val->>'id')::bigint from v where k = 'meera'), 'same phone: the existing lead is used (no duplicate)';
insert into r select (select student_name = 'Meera Iyer' and email_id = 'meera@example.com' and interested_course = 'MBA' and name_confirmed and email_confirmed
  from public.student_leads where whatsapp_number = '919876522201'), 'another confirmed email: name, email and course are kept';
insert into r select exists (select 1 from public.touchpoints t where t.lead_id = (select (val->>'id')::bigint from v where k = 'meera') and t.source_system = 'web_agent_unverified'),
  'the visit is still recorded on the lead, as an unverified website touch';
insert into r select (select result->>'web_trust' from public.web_lead_submissions where idempotency_key = 'web:verify:' || (select attempt from g where k = 'l-other')) = 'other_confirmed_email',
  'the submission records why the website did not overwrite';
-- application steps and submit on that attempt: fill-empty only too
select public.web_application_open((select attempt from g where k = 'l-other'), 'enquiry', 'EDW-26-LIMT1');
select public.web_application_save_step(jsonb_build_object('attempt_id', (select attempt from g where k = 'l-other'), 'student_id', (select student from g where k = 'l-other'),
  'step', 2, 'data', '{}'::jsonb, 'lead', '{"highest_qualification":"Graduation","interested_course":"BBA"}'::jsonb));
insert into r select (select interested_course = 'MBA' and highest_qualification = 'Graduation' from public.student_leads where whatsapp_number = '919876522201'),
  'application step: empty fields filled, existing course kept';
select public.web_application_submit(jsonb_build_object('attempt_id', (select attempt from g where k = 'l-other'), 'student_id', (select student from g where k = 'l-other'),
  'data', '{}'::jsonb, 'lead', '{"interested_course":"BCA"}'::jsonb));
insert into r select (select interested_course = 'MBA' from public.student_leads where whatsapp_number = '919876522201'), 'submit: existing course kept';

-- Witty turns for that student: no overwrite and no change of the lead's classification
insert into v select 'w-open', public.web_advisor_session_open((select student from g where k = 'l-other'), false, true);
select public.web_advisor_turn_commit(jsonb_build_object('session_id', (select val->'session'->>'id' from v where k = 'w-open'),
  'student_id', (select student from g where k = 'l-other'), 'message_id', 'lim-m1', 'student_message', 'join now', 'reply', 'ok', 'answer_mode', 'HANDOFF',
  'classification', 'HOT', 'event_type', 'lead.escalated', 'lead', '{"classification":"HOT","full_name":"Other Person","interested_course":"BCA"}'::jsonb));
insert into r select (select student_name = 'Meera Iyer' and interested_course = 'MBA' and lead_status = 'UNQUALIFIED' and temperature is null and not is_sales_ready
  from public.student_leads where whatsapp_number = '919876522201'), 'chat turn: name, course and classification kept';
-- callback: fills an empty preferred time
insert into r select (public.web_callback_request((select student from g where k = 'l-other'), (select (val->'session'->>'id')::uuid from v where k = 'w-open'),
  ((now() at time zone 'Asia/Kolkata')::date + 1), 'morning') ->> 'ok')::boolean
  and (select preferred_counseling_time like 'Callback %morning%' from public.student_leads where whatsapp_number = '919876522201'), 'callback fills an empty preferred time';
-- an opt-out from the website still applies (it only ever reduces contact)
select public.web_consent_withdraw((select student from g where k = 'l-other'), array['sales', 'partner_share']);
insert into r select (select is_opted_out from public.student_leads where whatsapp_number = '919876522201'), 'opt-out still reaches the lead';

-- the same student (same confirmed email) behaves as before: trusted, details updated
select public.lead_intake('{"phone":"919876522202","source_system":"witty","event_type":"lead.created","is_test":true,
  "lead":{"full_name":"Arjun S","email":"arjun@example.com","is_email_confirmed":true,"interested_course":"MBA"}}');
select pg_temp.verify_as('l-same', 'application', 'Arjun Sharma', 'ARJUN@example.com', '+919876522202');
insert into r select (select student_name = 'Arjun Sharma' from public.student_leads where whatsapp_number = '919876522202'), 'same student: name updated as before';
insert into r select (select result->>'web_trust' from public.web_lead_submissions where idempotency_key = 'web:verify:' || (select attempt from g where k = 'l-same')) = 'trusted', 'same student: trusted';
insert into r select exists (select 1 from public.touchpoints t where t.lead_id = (select lead from g where k = 'l-same') and t.source_system = 'web_agent'), 'same student: web_agent touch as before';

-- a lead without a confirmed email (e.g. WhatsApp only) is enriched as before
select public.lead_intake('{"phone":"919876522203","source_system":"witty","event_type":"lead.created","is_test":true,"lead":{"interested_course":"MBA"}}');
select pg_temp.verify_as('l-noemail', 'enquiry', 'Kavya N', 'kavya@example.com', '+919876522203');
insert into r select (select student_name = 'Kavya N' and email_id = 'kavya@example.com' from public.student_leads where whatsapp_number = '919876522203'), 'no confirmed email on the lead: enriched as before';

-- a new phone creates the lead with the website's details, as before
select pg_temp.verify_as('l-new', 'enquiry', 'Nisha Rao', 'nisha@example.com', '+919876522204');
insert into r select (select student_name = 'Nisha Rao' and email_id = 'nisha@example.com' and lead_source = 'website_form' from public.student_leads where id = (select lead from g where k = 'l-new')), 'new lead: created as before';
insert into r select (select result->>'web_trust' from public.web_lead_submissions where idempotency_key = 'web:verify:' || (select attempt from g where k = 'l-new')) = 'trusted', 'new lead: trusted';

-- an enrolled lead (no confirmed email) is not overwritten
select public.lead_intake('{"phone":"919876522205","source_system":"witty","event_type":"lead.created","is_test":true,"lead":{"full_name":"Enrolled Student"}}');
update public.student_leads set enrollment_status = 'enrolled' where whatsapp_number = '919876522205';
select pg_temp.verify_as('l-enrolled', 'enquiry', 'Someone Else', 'someone@example.com', '+919876522205');
insert into r select (select student_name = 'Enrolled Student' from public.student_leads where whatsapp_number = '919876522205'), 'enrolled lead: name kept';
insert into r select (select result->>'web_trust' from public.web_lead_submissions where idempotency_key = 'web:verify:' || (select attempt from g where k = 'l-enrolled')) = 'enrolled', 'enrolled lead: recorded as enrolled';

-- a lead a B2C counsellor owns is not overwritten
select public.lead_intake('{"phone":"919876522206","source_system":"witty","event_type":"lead.created","is_test":true,"lead":{"full_name":"Owned Student"}}');
update public.student_leads set owner_user_id = gen_random_uuid() where whatsapp_number = '919876522206';
select pg_temp.verify_as('l-owned', 'gate', 'Someone Else', 'someone2@example.com', '+919876522206');
insert into r select (select student_name = 'Owned Student' from public.student_leads where whatsapp_number = '919876522206'), 'CRM-owned lead: name kept';
insert into r select (select result->>'web_trust' from public.web_lead_submissions where idempotency_key = 'web:verify:' || (select attempt from g where k = 'l-owned')) = 'crm_owned', 'CRM-owned lead: recorded as crm_owned';

-- unverified pushes (setting push_unverified_gate_leads) never overwrite an existing lead
select public.lead_intake('{"phone":"919876522207","source_system":"witty","event_type":"lead.created","is_test":true,"lead":{"full_name":"Pushed Student"}}');
select public.web_gate_start('{"idempotency_key":"l-push","surface":"gate","email":"push@example.com","phone":"+919876522207","name":"Not Verified","consent_version":"web-gate-2026-10-v1","is_test":true,"code_hash":"h"}');
update public.web_gate_attempts set submitted_at = now() - interval '2 hours' where idempotency_key = 'l-push';
update public.web_settings set value = 'true' where key = 'push_unverified_gate_leads';
select public.web_push_unverified();
insert into r select (select student_name = 'Pushed Student' from public.student_leads where whatsapp_number = '919876522207'), 'unverified push: existing lead kept';
update public.web_settings set value = 'false' where key = 'push_unverified_gate_leads';

-- ---------------------------------------------------------------------------------------------------------------
-- 3. Outbox worker: calls the site only when a job is due (or unverified pushes are on).
delete from public.web_outbox where status in ('pending', 'processing');
insert into r select not public.web_outbox_due(), 'nothing due: no call';
insert into r select public.web_outbox_tick() is null, 'tick does nothing when nothing is due';
select public.web_outbox_enqueue('revalidate', 'lim-later', '{"tags":["x"]}'::jsonb, null, 600);
insert into r select not public.web_outbox_due(), 'a job scheduled for later is not due yet';
select public.web_outbox_enqueue('revalidate', 'lim-now', '{"tags":["x"]}'::jsonb);
insert into r select public.web_outbox_due(), 'a pending job is due';
update public.web_outbox set status = 'processing', locked_until = now() + interval '1 minute' where dedupe_key = 'lim-now';
insert into r select not public.web_outbox_due(), 'a job being processed is not due';
update public.web_outbox set locked_until = now() - interval '1 second' where dedupe_key = 'lim-now';
insert into r select public.web_outbox_due(), 'a job whose lock expired is due again';
delete from public.web_outbox where dedupe_key in ('lim-now', 'lim-later');
update public.web_settings set value = 'true' where key = 'push_unverified_gate_leads';
insert into r select public.web_outbox_due(), 'unverified pushes on: the worker runs every minute';
update public.web_settings set value = 'false' where key = 'push_unverified_gate_leads';
-- where pg_cron schedules the jobs (production, replica): the worker goes through the check, the poll has a timeout
insert into r select not exists (select 1 from pg_extension where extname = 'pg_cron')
  or not exists (select 1 from cron.job where jobname = 'web_outbox_worker')
  or (select command = 'select public.web_outbox_tick()' from cron.job where jobname = 'web_outbox_worker'), 'outbox job runs web_outbox_tick()';
insert into r select not exists (select 1 from pg_extension where extname = 'pg_cron')
  or not exists (select 1 from cron.job where jobname = 'web_catalog_poll')
  or (select command = 'set statement_timeout = ''30s''; select public.web_catalog_poll()' from cron.job where jobname = 'web_catalog_poll'), 'catalogue poll runs with a 30 s statement timeout';

-- ---------------------------------------------------------------------------------------------------------------
-- 4. Daily ceiling on Witty turns and spend (setting web_advisor_daily_cap, default 2000 turns / 25 USD).
insert into r select (select value = '{"turns": 2000, "cost_usd": 25}'::jsonb from public.web_settings where key = 'web_advisor_daily_cap'), 'daily ceiling setting exists with its default';
insert into v select 'd0', public.web_advisor_daily_check();
insert into r select (select (val->>'ok')::boolean and (val->>'max_turns')::numeric = 2000 and (val->>'max_cost_usd')::numeric = 25
  and (val->>'reset_seconds')::int between 1 and 86400 from v where k = 'd0'), 'under the ceiling: ok, with the limits and the time to the IST midnight reset';
select pg_temp.verify_as('d-1', 'gate', 'Daily Cap', 'daily@example.com', '+919876533301');
insert into v select 'd-open', public.web_advisor_session_open((select student from g where k = 'd-1'), false, true);
select public.web_advisor_turn_commit(jsonb_build_object('session_id', (select val->'session'->>'id' from v where k = 'd-open'),
  'student_id', (select student from g where k = 'd-1'), 'message_id', 'dc-1', 'student_message', 'hi', 'reply', 'hello',
  'usage', '{"prompt_tokens":100,"cached_tokens":0,"output_tokens":10,"cost_usd":0.25}'::jsonb));
select public.web_advisor_turn_commit(jsonb_build_object('session_id', (select val->'session'->>'id' from v where k = 'd-open'),
  'student_id', (select student from g where k = 'd-1'), 'message_id', 'dc-1', 'student_message', 'hi', 'reply', 'hello'));
insert into v select 'd1', public.web_advisor_daily_check();
insert into r select (select (val->>'turns')::int = (select (val->>'turns')::int from v where k = 'd0') + 1
  and (val->>'cost_usd')::numeric = (select (val->>'cost_usd')::numeric from v where k = 'd0') + 0.25 from v where k = 'd1'), 'a turn counts once (the retried message does not), with its cost';
update public.web_settings set value = jsonb_build_object('turns', (select (val->>'turns')::int from v where k = 'd1'), 'cost_usd', 25) where key = 'web_advisor_daily_cap';
insert into r select not (public.web_advisor_daily_check() ->> 'ok')::boolean, 'at the turn ceiling: not ok';
update public.web_settings set value = jsonb_build_object('turns', 100000, 'cost_usd', (select (val->>'cost_usd')::numeric from v where k = 'd1')) where key = 'web_advisor_daily_cap';
insert into r select not (public.web_advisor_daily_check() ->> 'ok')::boolean, 'at the spend ceiling: not ok';
update public.web_settings set value = '"bad"' where key = 'web_advisor_daily_cap';
insert into r select (public.web_advisor_daily_check() ->> 'max_turns')::numeric = 2000, 'an invalid setting falls back to the defaults';
insert into r select (public.web_admin_setting('web_advisor_daily_cap', '{"turns":10,"cost_usd":1}', gen_random_uuid(), 'editor@example.com', 'content_editor') ->> 'error') = 'forbidden',
  'content editors cannot change the Witty ceiling';

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
