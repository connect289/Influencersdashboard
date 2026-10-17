-- web7: email verification gate → student, session, consent ledger, and the lead through the real lead_intake();
-- duplicates, first-touch protection, application steps and submit, opt-out, limits. Runs on the replica too.
begin;
create temp table r (ok boolean, name text) on commit drop;
create temp table v (k text primary key, val jsonb) on commit drop;

-- screening
insert into r select (public.web_gate_start('{"idempotency_key":"t-0","surface":"enquiry","email":"x@mailinator.com","phone":"+919876500001","name":"Test","code_hash":"h"}') ->> 'reason') = 'disposable_email', 'disposable email refused';
insert into public.web_block_list (kind, value, reason) values ('email', 'blocked@example.com', 'test');
insert into r select (public.web_gate_start('{"idempotency_key":"t-00","surface":"enquiry","email":"blocked@example.com","phone":"+919876500001","name":"Test","code_hash":"h"}') ->> 'reason') = 'blocked', 'block list applied';

-- start → code
insert into v select 'start', public.web_gate_start(jsonb_build_object('idempotency_key', 't-1', 'surface', 'application', 'name', 'Asha Rao',
  'email', 'Asha.Rao@Example.com', 'phone', '+919876500001', 'consent_version', 'web-form-2026-10-v1', 'marketing', true, 'is_test', true,
  'code_hash', 'h1', 'junk_score', 0, 'context', jsonb_build_object('offering_id', (select min(id) from public.web_offering_search where visible), 'programme_label', 'MBA Marketing'),
  'attribution', '{"utm_source":"google","utm_medium":"cpc","utm_campaign":"mba-oct","click_ids":{"gclid":"G1"},"landing_url":"/programmes/online-mba","referred_by_code":"CREATOR1"}'::jsonb));
insert into r select (select val->>'status' from v where k = 'start') = 'code_sent', 'code sent';
insert into r select (select email_norm from public.web_gate_attempts where idempotency_key = 't-1') = 'asha.rao@example.com', 'email normalised';
insert into r select (public.web_gate_resend((select (val->>'attempt_id')::uuid from v where k = 'start'), 'h2') ->> 'reason') = 'too_soon', 'resend only after 30 seconds';

-- wrong then right code
insert into r select (public.web_gate_verify((select (val->>'attempt_id')::uuid from v where k = 'start'), 'nope') ->> 'reason') = 'wrong_code', 'wrong code rejected';
insert into v select 'verify', public.web_gate_verify((select (val->>'attempt_id')::uuid from v where k = 'start'), 'h1', 'ua');
insert into r select (select val->>'status' from v where k = 'verify') = 'verified', 'right code verifies';
insert into r select (select (val->>'lead_id') is not null from v where k = 'verify'), 'lead created at verification';

-- the lead, as lead_intake wrote it
insert into v select 'lead', to_jsonb(l) from public.student_leads l where id = (select (val->>'lead_id')::bigint from v where k = 'verify');
insert into r select (select val->>'lead_source' = 'website_form' and val->>'channel' = 'web_form' from v where k = 'lead'), 'form lead: lead_source website_form, channel web_form (D-009)';
insert into r select (select val->>'student_name' = 'Asha Rao' and val->>'email_id' = 'asha.rao@example.com' and (val->>'email_confirmed')::boolean from v where k = 'lead'), 'name, email and email-confirmed flag';
insert into r select (select val->>'whatsapp_number' like '%9876500001' and val->>'phone_verified_at' is null from v where k = 'lead'), 'phone stored, not marked verified (no OTP)';
insert into r select (select val->>'utm_source' = 'google' and val->>'referred_by_code' = 'CREATOR1' and val->'click_ids'->>'gclid' = 'G1' from v where k = 'lead'), 'attribution and creator code on the lead';
insert into r select (select val->>'consent_text_version' = 'web-form-2026-10-v1' and val->>'consent_sales_at' is not null and val->>'consent_partner_share_at' is not null and val->>'consent_marketing_at' is not null from v where k = 'lead'), 'consent version and timestamps';
-- (the production-schema replica has no catalogue rows, so the context check only applies where the catalogue exists)
insert into r select (select val->>'interested_course' is not null and val->>'interested_university' is not null from v where k = 'lead')
  or not exists (select 1 from public.web_offering_search), 'programme context from the catalogue';
insert into r select (select (val->>'is_test')::boolean from v where k = 'lead'), 'test lead flagged';
insert into r select (select val->>'ip_address' is null from v where k = 'lead'), 'no IP address sent (D-019)';
insert into r select exists (select 1 from public.touchpoints where lead_id = (select (val->>'lead_id')::bigint from v where k = 'verify') and source_system = 'web_agent'), 'touchpoint recorded as web_agent';

-- identity, session, consent ledger, outbox
insert into r select exists (select 1 from public.web_students where email_norm = 'asha.rao@example.com' and lead_id is not null), 'student linked to the lead';
insert into r select (public.web_session_check((select (val->>'session_id')::uuid from v where k = 'verify')) ->> 'email') = 'asha.rao@example.com', 'session valid';
insert into r select (select count(*) from public.web_consents c join public.web_students s on s.id = c.student_id where s.email_norm = 'asha.rao@example.com') = 2, 'consent ledger: form consent + marketing';
insert into r select exists (select 1 from public.web_outbox where kind = 'capi_lead'), 'Conversions API Lead event queued';
insert into r select exists (select 1 from public.web_email_verifications where email_norm = 'asha.rao@example.com'), 'verification proof stored (A-LEAD-1 pending)';

-- idempotent: verifying again does nothing new
insert into r select (public.web_gate_verify((select (val->>'attempt_id')::uuid from v where k = 'start'), 'h1') ->> 'status') = 'already_verified', 'second verify is a no-op';
insert into r select (select count(*) from public.web_lead_submissions where idempotency_key like 'web:verify:%') = 1, 'lead written exactly once';

-- application steps enrich the same lead; submit marks the application request
insert into r select (public.web_application_open((select (val->>'attempt_id')::uuid from v where k = 'start'), 'application', 'EDW-26-TEST1') ->> 'reference') = 'EDW-26-TEST1', 'application opened';
insert into r select (public.web_application_save_step(jsonb_build_object('attempt_id', (select val->>'attempt_id' from v where k = 'start'), 'step', 2, 'student_id', gen_random_uuid())) ->> 'reason') = 'not_owner', 'another student cannot change the application';
select public.web_application_save_step(jsonb_build_object('attempt_id', (select val->>'attempt_id' from v where k = 'start'), 'step', 2, 'student_id', (select val->>'student_id' from v where k = 'verify'), 
  'data', '{"qualification":"graduation","stream":"B.Com","year":"2021"}'::jsonb, 'lead', '{"highest_qualification":"Graduation — B.Com","academic_score_raw":"72%","academic_score_pct":72}'::jsonb));
insert into r select (select highest_qualification = 'Graduation — B.Com' and academic_score_pct = 72 from public.student_leads where id = (select (val->>'lead_id')::bigint from v where k = 'verify')), 'step 2 enriched the lead';
insert into r select (select steps->'2'->>'year' = '2021' from public.web_applications where reference = 'EDW-26-TEST1'), 'answers without a lead column kept in web_applications';
insert into r select (public.web_application_submit(jsonb_build_object('attempt_id', (select val->>'attempt_id' from v where k = 'start'), 'student_id', (select val->>'student_id' from v where k = 'verify'), 'lead', '{"preferred_call_time":"WhatsApp, evening"}'::jsonb)) ->> 'status') = 'submitted', 'application submitted';
insert into r select (select intent_type = 'wants_to_apply' and preferred_counseling_time = 'WhatsApp, evening' from public.student_leads where id = (select (val->>'lead_id')::bigint from v where k = 'verify')), 'lead marked as an application request';
insert into r select exists (select 1 from public.web_outbox where kind = 'email_confirmation' and payload->>'reference' = 'EDW-26-TEST1')
  and exists (select 1 from public.web_outbox where kind = 'capi_submit_application'), 'confirmation email and SubmitApplication queued';

-- duplicate handling: same phone, new email, new campaign → same lead, first-touch kept
select public.web_gate_start(jsonb_build_object('idempotency_key', 't-2', 'surface', 'gate', 'name', 'Asha R', 'email', 'asha2@example.com',
  'phone', '+919876500001', 'consent_version', 'web-gate-2026-10-v1', 'is_test', true, 'code_hash', 'k1', 'attribution', '{"utm_source":"facebook"}'::jsonb));
insert into v select 'verify2', public.web_gate_verify((select id from public.web_gate_attempts where idempotency_key = 't-2'), 'k1');
insert into r select (select (val->>'lead_id')::bigint from v where k = 'verify2') = (select (val->>'lead_id')::bigint from v where k = 'verify')
  and (select val->>'lead_action' from v where k = 'verify2') = 'merged', 'same phone → same lead (lead_intake duplicate rule)';
insert into r select (select utm_source = 'google' and lead_source = 'website_form' from public.student_leads where id = (select (val->>'lead_id')::bigint from v where k = 'verify')), 'first-touch attribution never overwritten';

-- signed-in student skips the code; a mismatched email is refused
insert into r select (public.web_gate_start_trusted(jsonb_build_object('idempotency_key', 't-trust', 'surface', 'enquiry', 'name', 'Asha Rao', 'email', 'asha.rao@example.com',
  'phone', '+919876500001', 'consent_version', 'web-form-2026-10-v1', 'is_test', true), (select id from public.web_students where email_norm = 'asha.rao@example.com')) ->> 'status') = 'verified', 'signed-in student skips the email code';
insert into r select (public.web_gate_start_trusted(jsonb_build_object('idempotency_key', 't-trust2', 'surface', 'enquiry', 'email', 'other@example.com', 'phone', '+919876500001'),
  (select id from public.web_students where email_norm = 'asha.rao@example.com')) ->> 'reason') = 'session_mismatch', 'session cannot verify a different email';

-- limits
select public.web_gate_start(jsonb_build_object('idempotency_key', 't-lim-' || g, 'surface', 'enquiry', 'name', 'L', 'email', 'limit@example.com', 'phone', '+919876500009', 'code_hash', 'c')) from generate_series(1, 5) g;
insert into r select (public.web_gate_start(jsonb_build_object('idempotency_key', 't-lim-6', 'surface', 'enquiry', 'name', 'L', 'email', 'limit@example.com', 'phone', '+919876500009', 'code_hash', 'c')) ->> 'reason') = 'too_many_codes', 'at most 5 codes per email per hour';
select public.web_gate_start(jsonb_build_object('idempotency_key', 't-3', 'surface', 'enquiry', 'name', 'Z', 'email', 'z@example.com', 'phone', '+919876500003', 'code_hash', 'z1'));
select public.web_gate_verify((select id from public.web_gate_attempts where idempotency_key = 't-3'), 'bad') from generate_series(1, 5);
insert into r select (public.web_gate_verify((select id from public.web_gate_attempts where idempotency_key = 't-3'), 'z1') ->> 'reason') = 'too_many_attempts', 'locked after 5 wrong codes';

-- account, opt-out, revocation
insert into r select jsonb_array_length(public.web_shortlist_merge((select id from public.web_students where email_norm = 'asha.rao@example.com'), array[1, 2, 2]::bigint[])) = 2, 'shortlist merged without duplicates';
insert into r select (public.web_account((select id from public.web_students where email_norm = 'asha.rao@example.com')) -> 'applications' -> 0 ->> 'reference') = 'EDW-26-TEST1', 'account lists the application';
select public.web_consent_withdraw((select id from public.web_students where email_norm = 'asha.rao@example.com'), array['sales', 'partner_share']);
insert into r select (select is_opted_out from public.student_leads where id = (select (val->>'lead_id')::bigint from v where k = 'verify')), 'withdrawing consent opts the lead out';
select public.web_session_revoke((select (val->>'session_id')::uuid from v where k = 'verify'));
insert into r select public.web_session_check((select (val->>'session_id')::uuid from v where k = 'verify')) is null, 'revoked session refused';
insert into r select (public.web_push_unverified() ->> 'enabled')::boolean = false, 'pushing unverified gate leads is off by default';

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
