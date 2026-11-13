-- web16: opt-outs only for the student's own lead, no silent phone change on the signed-in path, daily code ceiling and
-- per-inbox code limit, outbox steps that survive a retry, non-Latin queries, health detail (audit 12 Nov 2026, D-095).
-- Runs on the replica too (the search checks hold with or without a catalogue).
begin;
create temp table r (ok boolean, name text) on commit drop;
create temp table v (k text primary key, val jsonb) on commit drop;
create temp table g (k text primary key, attempt uuid, student uuid, session uuid, lead bigint) on commit drop;
create or replace function pg_temp.verify_as(p_key text, p_surface text, p_name text, p_email text, p_phone text) returns void language plpgsql as $$
declare s jsonb; vv jsonb;
begin
  s := public.web_gate_start(jsonb_build_object('idempotency_key', p_key, 'surface', p_surface, 'name', p_name, 'email', p_email, 'phone', p_phone,
         'consent_version', case when p_surface = 'gate' then 'web-gate-2026-10-v1' else 'web-form-2026-10-v1' end, 'is_test', true, 'code_hash', 'k-' || p_key));
  vv := public.web_gate_verify((s->>'attempt_id')::uuid, 'k-' || p_key);
  insert into pg_temp.g values (p_key, (s->>'attempt_id')::uuid, (vv->>'student_id')::uuid, (vv->>'session_id')::uuid, (vv->>'lead_id')::bigint);
end $$;
insert into r select (select value = '1500'::jsonb from public.web_settings where key = 'code_send_daily_cap'), 'daily code ceiling setting exists, default 1,500';
-- the ceilings out of the way for the lead checks
update public.web_settings set value = '1000000' where key in ('code_send_hourly_cap', 'code_send_daily_cap');

-- ---------------------------------------------------------------------------------------------------------------
-- 1a. Withdrawing contact consent opts out the student's own lead, as before.
select pg_temp.verify_as('af-own', 'enquiry', 'Ravi Kumar', 'ravi.af@example.com', '+919876533401');
insert into r select public.web_lead_tie('+919876533401', 'ravi.af@example.com') is null, 'tie: the lead the student created is theirs';
insert into v select 'w-own', public.web_consent_withdraw((select student from g where k = 'af-own'), array['sales', 'partner_share']);
insert into r select (select is_opted_out from public.student_leads where id = (select lead from g where k = 'af-own')), 'own lead: opted out';
insert into r select not (select (val->>'needs_confirmation')::boolean from v where k = 'w-own')
  and not exists (select 1 from public.web_deletion_requests where student_id = (select student from g where k = 'af-own')), 'own lead: no counsellor request';

-- 1b. Someone else's lead (another confirmed email) is not opted out; a counsellor confirms it.
select public.lead_intake('{"phone":"919876533402","source_system":"witty","event_type":"lead.created","is_test":true,
  "lead":{"full_name":"Lead Owner","email":"owner.af@example.com","is_email_confirmed":true}}');
select pg_temp.verify_as('af-other', 'enquiry', 'Not Owner', 'notowner.af@example.com', '+919876533402');
insert into r select public.web_lead_tie('+919876533402', 'notowner.af@example.com') = 'other_confirmed_email', 'tie: another confirmed email';
insert into v select 'w-other', public.web_consent_withdraw((select student from g where k = 'af-other'), array['sales', 'partner_share']);
insert into r select (select not coalesce(is_opted_out, false) from public.student_leads where whatsapp_number = '919876533402'), 'other lead: not opted out';
insert into r select (select (val->>'ok')::boolean and (val->>'needs_confirmation')::boolean and val->'lead' = 'null'::jsonb from v where k = 'w-other'),
  'other lead: the answer says a confirmation is needed, nothing reached the lead';
insert into r select (select count(*) = 1 and bool_and(status = 'open' and note like '%other_confirmed_email%' and note like '%+919876533402%')
  from public.web_deletion_requests where student_id = (select student from g where k = 'af-other') and kind = 'opt_out'), 'other lead: one open opt-out request with the reason';
select public.web_consent_withdraw((select student from g where k = 'af-other'), array['sales', 'partner_share']);
insert into r select (select count(*) = 1 from public.web_deletion_requests where student_id = (select student from g where k = 'af-other') and kind = 'opt_out'),
  'a second withdrawal does not add a second request';
insert into r select (select (after->>'lead_opt_out') = 'needs_confirmation' from public.web_audit_log
  where action = 'student.consent_withdrawn' and entity_id = (select student from g where k = 'af-other')::text order by id desc limit 1), 'the audit row says why';
insert into r select (select count(*) = 0 from public.web_consents where student_id = (select student from g where k = 'af-other') and withdrawn_at is null and purposes && array['sales']),
  'the student''s own consent is withdrawn either way';
-- marketing only: neither the lead nor a request
select public.web_consent_withdraw((select student from g where k = 'af-own'), array['marketing']);
insert into r select not exists (select 1 from public.web_deletion_requests where student_id = (select student from g where k = 'af-own')), 'marketing withdrawal: no request';

-- 1c. The other web14 reasons, and a phone without a lead.
select public.lead_intake('{"phone":"919876533403","source_system":"witty","event_type":"lead.created","is_test":true,"lead":{"full_name":"Enrolled AF"}}');
update public.student_leads set enrollment_status = 'enrolled' where whatsapp_number = '919876533403';
insert into r select public.web_lead_tie('+919876533403', 'x.af@example.com') = 'enrolled', 'tie: enrolled';
select public.lead_intake('{"phone":"919876533404","source_system":"witty","event_type":"lead.created","is_test":true,"lead":{"full_name":"Owned AF"}}');
update public.student_leads set owner_user_id = gen_random_uuid() where whatsapp_number = '919876533404';
insert into r select public.web_lead_tie('+919876533404', 'x.af@example.com') = 'crm_owned', 'tie: CRM-owned';
insert into r select public.web_lead_tie('+919876533404', null) = 'email_not_verified', 'tie: no verified email';
insert into r select public.web_lead_tie('+919876533499', 'x.af@example.com') is null, 'tie: no lead yet';
insert into r select public.web_lead_tie('not a phone', 'x.af@example.com') is null, 'tie: not a phone';

-- 1d. The signed-in path never replaces the student's phone number without a code.
insert into v select 't-other', public.web_gate_start_trusted(jsonb_build_object('idempotency_key', 'af-trusted-1', 'surface', 'enquiry', 'name', 'Ravi Kumar',
  'email', 'ravi.af@example.com', 'phone', '+919876533402', 'consent_version', 'web-form-2026-10-v1', 'is_test', true), (select student from g where k = 'af-own'));
insert into r select (select val->>'reason' = 'phone_changed' and not (val->>'ok')::boolean from v where k = 't-other'), 'trusted path with another number: refused (phone_changed)';
insert into r select not exists (select 1 from public.web_gate_attempts where idempotency_key = 'af-trusted-1'), 'refused: no attempt left behind';
insert into r select (select phone_e164 = '+919876533401' from public.web_students where id = (select student from g where k = 'af-own')), 'refused: the stored number is unchanged';
insert into v select 't-same', public.web_gate_start_trusted(jsonb_build_object('idempotency_key', 'af-trusted-2', 'surface', 'enquiry', 'name', 'Ravi Kumar',
  'email', 'ravi.af@example.com', 'phone', '+919876533401', 'consent_version', 'web-form-2026-10-v1', 'is_test', true), (select student from g where k = 'af-own'));
insert into r select (select val->>'status' = 'verified' from v where k = 't-same'), 'trusted path with the stored number: verified without a code';
-- a student without a number yet (signed in by email only) may add one on the signed-in path
select public.web_gate_start('{"idempotency_key":"af-signin","surface":"signin","email":"nophone.af@example.com","code_hash":"k-si"}');
insert into v select 'si', public.web_gate_verify((select id from public.web_gate_attempts where idempotency_key = 'af-signin'), 'k-si');
insert into v select 't-new', public.web_gate_start_trusted(jsonb_build_object('idempotency_key', 'af-trusted-3', 'surface', 'enquiry', 'name', 'New Phone',
  'email', 'nophone.af@example.com', 'phone', '+919876533405', 'consent_version', 'web-form-2026-10-v1', 'is_test', true), (select (val->>'student_id')::uuid from v where k = 'si'));
insert into r select (select val->>'status' = 'verified' from v where k = 't-new')
  and (select phone_e164 = '+919876533405' from public.web_students where email_norm = 'nophone.af@example.com'), 'no stored number: the signed-in path adds it';

-- ---------------------------------------------------------------------------------------------------------------
-- 2. Codes: one limit per inbox, and a daily site-wide ceiling.
insert into r select public.web_email_canonical(' J.Doe+news@GoogleMail.com ') = 'jdoe@gmail.com', 'canonical: gmail dots, +tag, googlemail, case';
insert into r select public.web_email_canonical('a.b+x@Yahoo.com') = 'a.b@yahoo.com', 'canonical: other domains keep dots, lose the +tag';
insert into r select public.web_email_canonical('+x@yahoo.com') = '+x@yahoo.com', 'canonical: an address that is only a tag stays as it is';
insert into r select public.web_email_canonical('plain@example.com') = 'plain@example.com', 'canonical: plain address unchanged';
do $$ declare i int; begin
  for i in 1..5 loop
    perform public.web_gate_start(jsonb_build_object('idempotency_key', 'af-inbox-' || i, 'surface', 'signin', 'email', 'An.Inbox+' || i || '@gmail.com', 'code_hash', 'h'));
  end loop;
end $$;
insert into r select (select count(*) = 5 from public.web_verification_codes where target like 'an.inbox+%@gmail.com'), 'five codes to one inbox under five spellings';
insert into r select (select target = 'an.inbox+1@gmail.com' from public.web_verification_codes c join public.web_gate_attempts a on a.id = c.attempt_id
  where a.idempotency_key = 'af-inbox-1'), 'the address is stored as typed (lower case), not canonical';
insert into r select (public.web_gate_start('{"idempotency_key":"af-inbox-6","surface":"signin","email":"aninbox+6@googlemail.com","code_hash":"h"}') ->> 'reason') = 'too_many_codes',
  'a sixth spelling of the same inbox: too many codes';
update public.web_verification_codes set resend_after = now() - interval '1 second'
 where attempt_id = (select id from public.web_gate_attempts where idempotency_key = 'af-inbox-1');
insert into r select (public.web_gate_resend((select id from public.web_gate_attempts where idempotency_key = 'af-inbox-1'), 'h2') ->> 'reason') = 'too_many_codes',
  'resend counts the inbox too';
insert into r select (public.web_gate_start('{"idempotency_key":"af-inbox-7","surface":"signin","email":"another.inbox@gmail.com","code_hash":"h"}') ->> 'status') = 'code_sent',
  'another inbox is not affected';

delete from public.web_code_cap_hits;
update public.web_settings set value = to_jsonb((select count(*) from public.web_verification_codes where created_at > now() - interval '24 hours') + 1)
 where key = 'code_send_daily_cap';
insert into r select (public.web_gate_start('{"idempotency_key":"af-day-1","surface":"signin","email":"day1.af@example.com","code_hash":"h"}') ->> 'status') = 'code_sent', 'below the daily ceiling: sent';
insert into v select 'day-2', public.web_gate_start('{"idempotency_key":"af-day-2","surface":"signin","email":"day2.af@example.com","code_hash":"h"}');
insert into r select (select val->>'reason' = 'site_busy' and val->>'cap' = 'daily' from v where k = 'day-2'), 'at the daily ceiling: site_busy (daily)';
insert into r select (select coalesce(sum(hits), 0) = 1 from public.web_code_cap_hits where cap = 'daily'), 'the refusal is counted';
insert into r select (select (public.web_health()->'codes'->'refused_24h'->>'daily')::int = 1 and public.web_health()->'codes'->>'at_cap' = 'daily'), 'health shows the daily refusals and the ceiling';
update public.web_settings set value = '1' where key = 'code_send_hourly_cap';
insert into r select (public.web_gate_start('{"idempotency_key":"af-hour-1","surface":"signin","email":"hour1.af@example.com","code_hash":"h"}') ->> 'cap') = 'hourly', 'the hourly ceiling is checked first';
insert into r select (public.web_health()->'codes'->'refused_24h'->>'hourly')::int = 1, 'health shows the hourly refusals';
insert into r select (public.web_admin_setting('code_send_daily_cap', '2000', gen_random_uuid(), 'editor@example.com', 'content_editor') ->> 'error') = 'forbidden',
  'content editors cannot change the daily ceiling';
update public.web_settings set value = '"lots"' where key = 'code_send_daily_cap';
insert into r select public.web_code_cap_value('code_send_daily_cap', 1500) = 1500, 'an invalid daily setting falls back to the default';
update public.web_settings set value = '1000000' where key in ('code_send_hourly_cap', 'code_send_daily_cap');

-- ---------------------------------------------------------------------------------------------------------------
-- 4. Outbox: a step recorded as done is still recorded when the job is retried.
delete from public.web_outbox where status in ('pending', 'processing');
select public.web_outbox_enqueue('email_confirmation', 'af-outbox-1', '{"kind":"enquiry"}'::jsonb);
insert into v select 'claim1', (select to_jsonb(c) from public.web_outbox_claim(10, array['email_confirmation']) c where c.dedupe_key = 'af-outbox-1');
insert into r select (select val->'sent_steps' = '[]'::jsonb from v where k = 'claim1'), 'a new job has no step done';
select public.web_outbox_mark_sent((select (val->>'id')::bigint from v where k = 'claim1'), 'email');
select public.web_outbox_mark_sent((select (val->>'id')::bigint from v where k = 'claim1'), 'email');
select public.web_outbox_fail((select (val->>'id')::bigint from v where k = 'claim1'), 'done call timed out');
update public.web_outbox set next_attempt_at = now() - interval '1 second' where dedupe_key = 'af-outbox-1';
insert into v select 'claim2', (select to_jsonb(c) from public.web_outbox_claim(10, array['email_confirmation']) c where c.dedupe_key = 'af-outbox-1');
insert into r select (select val->'sent_steps' = '["email"]'::jsonb and (val->>'attempts')::int = 2 from v where k = 'claim2'), 'the retry sees the email as sent (once)';
update public.web_outbox set status = 'dead' where dedupe_key = 'af-outbox-1';
insert into r select (public.web_health()->'outbox_dead_by_kind'->>'email_confirmation')::int >= 1 and public.web_health()->>'outbox_dead_latest_at' is not null,
  'health lists dead jobs by kind';

-- ---------------------------------------------------------------------------------------------------------------
-- 7. Search: a query in another script matches nothing instead of everything; punctuation alone is still ignored.
insert into v select 'all', public.web_search('{}');
insert into r select (public.web_search('{"q":"एमबीए ऑनलाइन"}') ->> 'total')::int = 0, 'Devanagari query: no match (not every programme)';
insert into r select (public.web_search('{"q":"எம்பிஏ"}') ->> 'total')::int = 0, 'Tamil query: no match';
insert into r select (public.web_search('{"q":"???"}') ->> 'total') = (select val->>'total' from v where k = 'all'), 'punctuation only: ignored as before';
insert into r select (public.web_search('{"q":"  "}') ->> 'total') = (select val->>'total' from v where k = 'all'), 'blank query: everything as before';
insert into r select (select (val->>'total')::int = 0 from v where k = 'all') or (public.web_search('{"q":"mba"}') ->> 'total')::int > 0, 'a Latin query still matches';

do $$ begin
  if exists (select 1 from r where not ok) then
    raise exception 'FAILED (%): %', (select count(*) from r where not ok), (select string_agg(name, ' | ') from r where not ok);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
