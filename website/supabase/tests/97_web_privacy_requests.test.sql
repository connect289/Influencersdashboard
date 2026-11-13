-- web17: privacy requests are carried out (audit finding H5, D-096): the copy of data holds only the requester's rows;
-- an erasure removes or anonymises what the website holds, once, by a super admin, on the request of the signed-in
-- account; the CRMs are a checklist the request waits for; every step is audited. Runs on the replica too.
begin;
create temp table r (ok boolean, name text) on commit drop;
create temp table v (k text primary key, val jsonb) on commit drop;
create temp table g (k text primary key, attempt uuid, student uuid, session uuid, lead bigint) on commit drop;
create temp table q (k text primary key, id bigint) on commit drop;

-- Test identities only: example.com addresses, 98765335xx numbers, is_test leads.
create or replace function pg_temp.verify_as(p_key text, p_surface text, p_name text, p_email text, p_phone text) returns void language plpgsql as $$
declare s jsonb; vv jsonb;
begin
  s := public.web_gate_start(jsonb_build_object('idempotency_key', p_key, 'surface', p_surface, 'name', p_name, 'email', p_email, 'phone', p_phone,
         'consent_version', case p_surface when 'gate' then 'web-gate-2026-10-v1' when 'signin' then null else 'web-form-2026-10-v1' end,
         'is_test', true, 'code_hash', 'k-' || p_key,
         'attribution', '{"utm_source":"test","landing_url":"/programmes/online-mba","internal_marker":"not-for-export"}'::jsonb));
  vv := public.web_gate_verify((s->>'attempt_id')::uuid, 'k-' || p_key);
  insert into pg_temp.g values (p_key, (s->>'attempt_id')::uuid, (vv->>'student_id')::uuid, (vv->>'session_id')::uuid, (vv->>'lead_id')::bigint);
end $$;
create or replace function pg_temp.sid(p_key text) returns uuid language sql as $$ select student from pg_temp.g where k = p_key $$;
create or replace function pg_temp.rid(p_key text) returns bigint language sql as $$ select id from pg_temp.q where k = p_key $$;
create or replace function pg_temp.file(p_key text, p_student text, p_kind text) returns void language sql as $$
  insert into pg_temp.q select p_key, (public.web_deletion_request(pg_temp.sid(p_student), p_kind)->>'request_id')::bigint
$$;
create or replace function pg_temp.fulfil(p_key text, p_role text default 'super_admin') returns jsonb language sql as $$
  select public.web_admin_privacy_fulfil(pg_temp.rid(p_key), '00000000-0000-0000-0000-0000000000a1'::uuid, 'sa.pr@example.com', p_role)
$$;
create or replace function pg_temp.export(p_key text, p_role text default 'super_admin') returns jsonb language sql as $$
  select public.web_admin_privacy_export(pg_temp.rid(p_key), '00000000-0000-0000-0000-0000000000a1'::uuid, 'sa.pr@example.com', p_role)
$$;
create or replace function pg_temp.tick(p_key text, p_system text, p_state text, p_note text, p_role text default 'super_admin') returns jsonb language sql as $$
  select public.web_admin_privacy_system(pg_temp.rid(p_key), p_system, p_state, p_note, '00000000-0000-0000-0000-0000000000a1'::uuid, 'sa.pr@example.com', p_role)
$$;
create or replace function pg_temp.mark(p_key text, p_status text, p_note text, p_role text default 'super_admin') returns jsonb language sql as $$
  select public.web_admin_privacy_done(pg_temp.rid(p_key), p_status, p_note, '00000000-0000-0000-0000-0000000000a1'::uuid, 'sa.pr@example.com', p_role)
$$;
-- Rows of the website's personal-data tables that still mention a pattern, as "table=n table=n".
create or replace function pg_temp.mentions(p_pattern text) returns text language plpgsql as $$
declare t text; n bigint; hits text := '';
begin
  foreach t in array array['web_students', 'web_verification_codes', 'web_gate_attempts', 'web_email_verifications', 'web_consents',
    'web_student_sessions', 'web_lead_submissions', 'web_applications', 'web_shortlists', 'web_saved_comparisons', 'web_deletion_requests',
    'web_advisor_sessions', 'web_advisor_messages', 'web_advisor_feedback', 'web_callback_requests', 'web_outbox', 'web_audit_log'] loop
    execute format('select count(*) from public.%I x where to_jsonb(x)::text ~* %L', t, p_pattern) into n;
    if n > 0 then hits := hits || t || '=' || n || ' '; end if;
  end loop;
  return btrim(hits);
end $$;

-- the code ceilings out of the way
update public.web_settings set value = '1000000' where key in ('code_send_hourly_cap', 'code_send_daily_cap');

-- ---------------------------------------------------------------------------------------------------------------
-- Three accounts. A (Asha): Witty gate, application, saved programmes, a chat, a callback; asks for erasure.
-- B (Bala): enquiry, one saved programme, a chat; asks for a copy. C (Chitra): signed in by email only (no lead).
select pg_temp.verify_as('pr-a', 'gate', 'Asha Privacy', 'asha.pr@example.com', '+919876533501');
select pg_temp.verify_as('pr-b', 'enquiry', 'Bala Privacy', 'bala.pr@example.com', '+919876533502');
select pg_temp.verify_as('pr-c', 'signin', null, 'chitra.pr@example.com', null);

select public.web_application_open((select attempt from g where k = 'pr-a'), 'application', 'EDW-PR-TEST1');
select public.web_application_save_step(jsonb_build_object('attempt_id', (select attempt from g where k = 'pr-a'), 'step', 2,
  'student_id', pg_temp.sid('pr-a'), 'data', '{"dob":"2001-02-03","father_name":"Father of Asha Privacy"}'::jsonb));
select public.web_shortlist_merge(pg_temp.sid('pr-a'), array[910001, 910002]::bigint[]);
select public.web_comparison_save(pg_temp.sid('pr-a'), array[910001, 910002]::bigint[]);
insert into v select 'a-open', public.web_advisor_session_open(pg_temp.sid('pr-a'), false, true);
insert into v select 'a-turn', public.web_advisor_turn_commit(jsonb_build_object('session_id', (select val->'session'->>'id' from v where k = 'a-open'),
  'student_id', pg_temp.sid('pr-a'), 'message_id', 'pr-a-m1', 'student_message', 'I am Asha Privacy and I scored 71 percent', 'reply', 'Thanks Asha.',
  'state', '{"profile":{"last_percentage":{"value":"71","confirmed":true}},"flags":{"internal_flag":true}}'::jsonb));
select public.web_advisor_feedback_add(pg_temp.sid('pr-a'), (select (val->>'out_id')::bigint from v where k = 'a-turn'), 1::smallint, 'helpful, says Asha Privacy');
select public.web_callback_request(pg_temp.sid('pr-a'), null, ((now() at time zone 'Asia/Kolkata')::date + 1), 'evening');
-- a form somebody typed with Asha's address and never verified
select public.web_gate_start('{"idempotency_key":"pr-a-unverified","surface":"enquiry","name":"Someone Else","email":"asha.pr@example.com","phone":"+919876533509","consent_version":"web-form-2026-10-v1","is_test":true,"code_hash":"k-x"}');

select public.web_shortlist_merge(pg_temp.sid('pr-b'), array[910003]::bigint[]);
insert into v select 'b-open', public.web_advisor_session_open(pg_temp.sid('pr-b'), false, true);
insert into v select 'b-turn', public.web_advisor_turn_commit(jsonb_build_object('session_id', (select val->'session'->>'id' from v where k = 'b-open'),
  'student_id', pg_temp.sid('pr-b'), 'message_id', 'pr-b-m1', 'student_message', 'Bala here, which MBA suits me?', 'reply', 'Tell me more, Bala.',
  'state', '{"profile":{"interested_course":{"value":"MBA","confirmed":true}},"flags":{"internal_flag":true}}'::jsonb));

select pg_temp.file('a-del', 'pr-a', 'delete');
select pg_temp.file('a-exp', 'pr-a', 'export');
select pg_temp.file('b-exp', 'pr-b', 'export');
select pg_temp.file('b-opt', 'pr-b', 'opt_out');
select pg_temp.file('c-del', 'pr-c', 'delete');
insert into v select 'a-lead-before', to_jsonb(l) from public.student_leads l where l.id = (select lead from g where k = 'pr-a');

-- ---------------------------------------------------------------------------------------------------------------
-- 0. Shape and grants.
insert into r select (select count(*) = 2 from information_schema.columns where table_schema = 'public' and table_name = 'web_deletion_requests'
  and column_name in ('systems', 'leads')), 'the request carries a checklist (systems) and the leads involved';
insert into r select bool_and(has_function_privilege('service_role', f, 'EXECUTE') and not has_function_privilege('anon', f, 'EXECUTE')
    and not has_function_privilege('authenticated', f, 'EXECUTE')), 'admin privacy functions: service role only'
  from unnest(array['public.web_admin_privacy_fulfil(bigint, uuid, text, text)', 'public.web_admin_privacy_export(bigint, uuid, text, text)',
    'public.web_admin_privacy_system(bigint, text, text, text, uuid, text, text)', 'public.web_admin_privacy_done(bigint, text, text, uuid, text, text)',
    'public.web_admin_privacy_requests()', 'public.web_outbox_scrub(bigint)']) f;
insert into r select bool_and(not has_function_privilege('service_role', f, 'EXECUTE') and not has_function_privilege('anon', f, 'EXECUTE')
    and not has_function_privilege('authenticated', f, 'EXECUTE')), 'the erase and copy helpers cannot be called by any API role'
  from unnest(array['public.web_privacy_erase(uuid)', 'public.web_privacy_export_doc(uuid)', 'public.web_privacy_close(bigint, uuid, text)',
    'public.web_privacy_leads(uuid)', 'public.web_privacy_counts(uuid)', 'public.web_privacy_requester_problem(uuid, text)']) f;
insert into r select bool_and(p.prosrc ~* 'from public\.web_deletion_requests where id = p_id for update'), 'every admin step locks the request row'
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('web_admin_privacy_fulfil', 'web_admin_privacy_export', 'web_admin_privacy_system', 'web_admin_privacy_done');
insert into r select (select count(*) = 5 and bool_and(status = 'open' and systems = '{}'::jsonb and leads = '[]'::jsonb) from public.web_deletion_requests
  where id in (select id from q)), 'filing a request changes nothing by itself (open, empty checklist)';
insert into r select (select count(*) = 3 from public.web_students where id in (pg_temp.sid('pr-a'), pg_temp.sid('pr-b'), pg_temp.sid('pr-c')) and deleted_at is null),
  'filing a request erases nothing';

-- 1. The list tells the admin what a request covers before anything is done.
insert into v select 'list0', public.web_admin_privacy_requests();
insert into r select (select (e->'preview'->'counts'->>'chat_messages')::int = 2 and (e->'preview'->'counts'->>'saved_programmes')::int = 2
    and (e->'preview'->'counts'->>'applications')::int = 1 and e->'preview'->>'requester_problem' is null
    and jsonb_array_length(e->'preview'->'leads') = 1 and (e->'preview'->'leads'->0->>'lead_id')::bigint = (select lead from g where k = 'pr-a')
    and e->'preview'->'other_open' = jsonb_build_array(pg_temp.rid('a-exp'))
  from v, jsonb_array_elements(val) e where k = 'list0' and (e->>'id')::bigint = pg_temp.rid('a-del')),
  'list: an open erasure shows counts, the lead and the account''s other open request';
insert into r select (select not (e ? 'preview') from v, jsonb_array_elements(val) e where k = 'list0' and (e->>'id')::bigint = pg_temp.rid('b-opt')),
  'list: opt-out requests are unchanged';

-- ---------------------------------------------------------------------------------------------------------------
-- 2. Copy of data (export).
insert into r select (pg_temp.export('b-exp', 'content_editor')->>'error') = 'forbidden', 'copy: only a super admin can download it';
insert into r select (pg_temp.export('b-exp', 'viewer')->>'error') = 'forbidden', 'copy: a viewer cannot download it';
insert into r select (pg_temp.fulfil('b-exp')->>'error') = 'not_downloaded', 'copy: cannot be recorded as sent before it was downloaded';
insert into v select 'b-doc', pg_temp.export('b-exp');
insert into r select (select (val->>'ok')::boolean and val->'export'->'profile'->>'email' = 'bala.pr@example.com'
    and val->'export'->'profile'->>'phone' = '+919876533502' and val->'export'->'profile'->>'name' = 'Bala Privacy' from v where k = 'b-doc'),
  'copy: the requester''s profile';
insert into r select (select jsonb_array_length(val->'export'->'saved_programmes') = 1
    and (val->'export'->'saved_programmes'->0->>'catalogue_programme_id')::bigint = 910003
    and jsonb_array_length(val->'export'->'enquiries') = 1 and val->'export'->'enquiries'->0->>'phone' = '+919876533502'
    and val->'export'->'enquiries'->0->'visit'->>'utm_source' = 'test'
    and jsonb_array_length(val->'export'->'consents') >= 1 and val->'export'->'consents'->0->>'text' like 'I agree%'
    and jsonb_array_length(val->'export'->'chats') = 1 and val->'export'->'chats'->0->'messages'->0->>'text' like 'Bala here%'
    and val->'export'->'chats'->0->'what_you_told_witty'->'interested_course'->>'value' = 'MBA'
    and jsonb_array_length(val->'export'->'privacy_requests') = 2 and val->'export'->'request'->>'kind' = 'export' from v where k = 'b-doc'),
  'copy: saved programmes, enquiries, consents with their text, chats, earlier requests';
insert into r select (select (val->'export')::text !~* 'asha|chitra|someone else|9876533501|9876533509|EDW-PR-TEST1' from v where k = 'b-doc'),
  'copy: nothing that belongs to another account';
insert into r select (select (val->'export')::text !~* 'junk|ip_hash|device_hash|idempotency|code_hash|lead_id|internal_flag|internal_marker|UNQUALIFIED|processed_by|prompt_tokens|sa\.pr@example\.com|"note"'
  from v where k = 'b-doc'), 'copy: no internal fields, staff names or notes';
insert into r select (select status = 'open' and systems->'website'->>'state' = 'pending' and systems->'website'->>'downloaded_at' is not null
    and systems->'website'->>'downloaded_by' = 'sa.pr@example.com' from public.web_deletion_requests where id = pg_temp.rid('b-exp')),
  'copy: the download is marked on the request, which stays open';
insert into r select (select count(*) = 1 and bool_and(actor_email = 'sa.pr@example.com' and after::text !~* 'bala|9876533502') from public.web_audit_log
  where action = 'privacy.export_downloaded' and entity_id = pg_temp.rid('b-exp')::text), 'copy: the download is audited (counts only)';
insert into r select (pg_temp.fulfil('b-exp', 'content_editor')->>'error') = 'forbidden', 'copy: only a super admin can record it as sent';
insert into v select 'b-ful', pg_temp.fulfil('b-exp');
insert into r select (select (val->>'ok')::boolean and not (val->>'already')::boolean and val->>'status' = 'open'
    and val->'systems'->'website'->>'state' = 'done' and val->'systems'->'website'->>'did' = 'copy_sent'
    and val->'systems'->'spark'->>'state' = 'pending' and val->'systems'->'b2b'->>'state' = 'pending'
    and jsonb_array_length(val->'leads') = 1 and val->'leads'->0->>'tie' is null from v where k = 'b-ful'),
  'copy sent: website done, Spark and B2B pending for the account''s lead';
insert into v select 'b-ful2', pg_temp.fulfil('b-exp');
insert into r select (select (val->>'ok')::boolean and (val->>'already')::boolean from v where k = 'b-ful2')
  and (select count(*) = 1 from public.web_audit_log where action = 'privacy.copy_sent' and entity_id = pg_temp.rid('b-exp')::text),
  'copy sent twice: the second call changes nothing';
insert into r select (select email_norm = 'bala.pr@example.com' and full_name = 'Bala Privacy' and phone_e164 = '+919876533502' and deleted_at is null
    from public.web_students where id = pg_temp.sid('pr-b'))
  and (select count(*) = 1 from public.web_shortlists where student_id = pg_temp.sid('pr-b'))
  and (select count(*) = 2 from public.web_advisor_messages m join public.web_advisor_sessions a on a.id = m.session_id where a.student_id = pg_temp.sid('pr-b')),
  'a copy request erases nothing';
insert into r select (pg_temp.tick('b-exp', 'spark', 'not_applicable', ' ')->>'error') = 'note_required', 'checklist: a tick needs a note';
insert into r select (pg_temp.tick('b-exp', 'witty', 'done', 'a note')->>'error') = 'bad_system', 'checklist: only Spark and B2B can be ticked';
insert into r select (pg_temp.tick('b-exp', 'website', 'done', 'a note')->>'error') = 'bad_system', 'checklist: the website step cannot be ticked by hand';
insert into r select (pg_temp.tick('b-exp', 'spark', 'pending', 'a note')->>'error') = 'bad_state', 'checklist: done or not applicable only';
insert into r select (pg_temp.tick('b-exp', 'spark', 'done', 'a note', 'content_editor')->>'error') = 'forbidden', 'checklist: super admin only';
insert into v select 'b-t1', pg_temp.tick('b-exp', 'spark', 'not_applicable', 'Never handed to Spark');
insert into r select (select (val->>'ok')::boolean and val->>'status' = 'open' and val->'systems'->'spark'->>'by' = 'sa.pr@example.com' from v where k = 'b-t1'),
  'checklist: one system ticked, the request stays open';
insert into v select 'b-t2', pg_temp.tick('b-exp', 'b2b', 'done', 'Lead copy sent by email, ticket 41');
insert into r select (select (val->>'ok')::boolean and val->>'status' = 'done' from v where k = 'b-t2')
  and (select status = 'done' and processed_by = 'sa.pr@example.com' and processed_at is not null and email_norm = 'bala.pr@example.com'
       from public.web_deletion_requests where id = pg_temp.rid('b-exp')),
  'checklist: every system done → the copy request is done (it keeps its address)';
insert into r select not exists (select 1 from public.web_outbox where dedupe_key = 'privacy_done:' || pg_temp.rid('b-exp')), 'a copy request sends no "erased" email';
insert into r select (pg_temp.tick('b-exp', 'b2b', 'done', 'again')->>'already')::boolean, 'checklist: the same tick twice changes nothing';
insert into r select (pg_temp.tick('b-exp', 'b2b', 'not_applicable', 'changed my mind')->>'error') = 'not_open', 'checklist: a finished request is not reopened';
insert into r select (pg_temp.export('b-exp')->>'ok')::boolean, 'copy: can be downloaded again after it was sent';
insert into r select (select count(*) = 1 from public.web_audit_log where action = 'privacy.fulfilled' and entity_id = pg_temp.rid('b-exp')::text), 'completion audited once';

-- ---------------------------------------------------------------------------------------------------------------
-- 3. Requests of another kind or status are refused; a non-admin can do nothing.
insert into r select (pg_temp.fulfil('b-opt')->>'error') = 'wrong_kind', 'an opt-out request cannot be fulfilled as an erasure or a copy';
insert into r select (pg_temp.export('b-opt')->>'error') = 'wrong_kind' and (pg_temp.export('a-del')->>'error') = 'wrong_kind', 'only a copy request has a download';
insert into r select (pg_temp.tick('b-opt', 'spark', 'done', 'a note')->>'error') = 'wrong_kind', 'an opt-out request has no checklist';
insert into r select (pg_temp.tick('a-del', 'spark', 'done', 'Erased in Spark')->>'error') = 'website_first', 'checklist: not before the website step';
insert into r select (pg_temp.mark('a-del', 'done', 'done by hand')->>'error') = 'use_fulfil' and (pg_temp.mark('a-exp', 'done', 'done by hand')->>'error') = 'use_fulfil',
  'an erasure or copy request cannot be marked done by hand any more';
insert into r select (pg_temp.mark('a-exp', 'rejected', '')->>'error') = 'note_required', 'rejecting an erasure or copy request needs a note';
insert into r select (pg_temp.mark('a-exp', 'rejected', 'a note', 'content_editor')->>'error') = 'forbidden', 'only a super admin rejects';
insert into r select (pg_temp.fulfil('a-del', 'content_editor')->>'error') = 'forbidden' and (pg_temp.fulfil('a-del', 'viewer')->>'error') = 'forbidden'
  and (pg_temp.fulfil('a-del', null)->>'error') = 'forbidden', 'erasure: only a super admin';
insert into v select 'a-blocked', pg_temp.fulfil('a-del');
insert into r select (select val->>'error' = 'other_requests_open' and val->'requests' = jsonb_build_array(pg_temp.rid('a-exp')) from v where k = 'a-blocked'),
  'erasure: waits while the account has another open request';
insert into r select (select email_norm = 'asha.pr@example.com' and full_name = 'Asha Privacy' and deleted_at is null from public.web_students where id = pg_temp.sid('pr-a'))
  and (select count(*) = 2 from public.web_shortlists where student_id = pg_temp.sid('pr-a')), 'refused calls erased nothing';
insert into r select (pg_temp.mark('a-exp', 'rejected', 'Asked for erasure instead')->>'ok')::boolean, 'a copy request can be rejected with a note';
insert into r select (pg_temp.fulfil('a-exp')->>'error') = 'rejected' and (pg_temp.export('a-exp')->>'error') = 'rejected', 'a rejected request cannot be fulfilled or downloaded';
insert into r select (pg_temp.mark('a-exp', 'rejected', 'again')->>'error') = 'not_open', 'a closed request is not closed again';
insert into r select (select not (before ? 'email_norm') and not (before ? 'note') and before->>'kind' = 'export' from public.web_audit_log
  where action = 'privacy.rejected' and entity_id = pg_temp.rid('a-exp')::text), 'the audit row of a closed request no longer copies the address';
insert into v select 'b-opt-done', pg_temp.mark('b-opt', 'done', 'Confirmed by phone');
insert into r select (select (val->>'ok')::boolean from v where k = 'b-opt-done')
  and (select status = 'done' and processed_by = 'sa.pr@example.com' from public.web_deletion_requests where id = pg_temp.rid('b-opt')), 'opt-out requests close as before';

-- ---------------------------------------------------------------------------------------------------------------
-- 4. Erasure.
insert into v select 'a-ful', pg_temp.fulfil('a-del');
insert into r select (select (val->>'ok')::boolean and not (val->>'already')::boolean and val->>'status' = 'open'
    and val->'systems'->'website'->>'state' = 'done' and val->'systems'->'website'->>'did' = 'erased' and val->'systems'->'website'->>'by' = 'sa.pr@example.com'
    and (val->'counts'->>'chat_messages')::int = 2 and (val->'counts'->>'saved_programmes')::int = 2 and (val->'counts'->>'applications')::int = 1
    and (val->'counts'->>'unverified_forms')::int = 1 and (val->'counts'->>'queued_jobs')::int >= 1 from v where k = 'a-ful'),
  'erasure: done on the website, with counts of what went';
insert into r select (select val->'leads' = jsonb_build_array(jsonb_build_object('lead_id', (select lead from g where k = 'pr-a'), 'tie', null))
    and val->'systems'->'spark'->>'state' = 'pending' and val->'systems'->'b2b'->>'state' = 'pending' from v where k = 'a-ful'),
  'erasure: the account''s own lead is listed; Spark and B2B are pending';
insert into r select (select email_norm = 'erased-' || id::text || '@erased.invalid' and full_name is null and phone_e164 is null and lead_id is null
    and email_verified_at is null and deleted_at is not null from public.web_students where id = pg_temp.sid('pr-a')), 'erasure: the account is a tombstone';
insert into r select public.web_session_check((select session from g where k = 'pr-a')) is null
  and not exists (select 1 from public.web_student_sessions where student_id = pg_temp.sid('pr-a')), 'erasure: signed out everywhere';
insert into r select not exists (select 1 from public.web_shortlists where student_id = pg_temp.sid('pr-a'))
  and not exists (select 1 from public.web_saved_comparisons where student_id = pg_temp.sid('pr-a'))
  and not exists (select 1 from public.web_callback_requests where student_id = pg_temp.sid('pr-a')), 'erasure: saved programmes, comparisons and callbacks removed';
insert into r select not exists (select 1 from public.web_advisor_messages where session_id = (select (val->'session'->>'id')::uuid from v where k = 'a-open'))
  and not exists (select 1 from public.web_advisor_feedback where session_id = (select (val->'session'->>'id')::uuid from v where k = 'a-open'))
  and (select state = '{}'::jsonb and ended_at is not null and lead_id is null and turns = 1 from public.web_advisor_sessions
        where id = (select (val->'session'->>'id')::uuid from v where k = 'a-open')), 'erasure: the chat is removed; the session stays as a bare counter';
insert into r select (select steps = '{}'::jsonb and context = '{}'::jsonb and reference = 'erased-' || id::text and lead_id is null and kind = 'application'
    from public.web_applications where attempt_id = (select attempt from g where k = 'pr-a')), 'erasure: the application keeps no answers or reference';
insert into r select (select email_norm = 'erased' and full_name is null and phone_e164 is null and attribution = '{}'::jsonb and context = '{}'::jsonb
    and ip_hash is null and lead_id is null and idempotency_key = 'erased:' || id::text and verified_at is not null and surface = 'gate'
    from public.web_gate_attempts where id = (select attempt from g where k = 'pr-a')), 'erasure: the verified form keeps only its kind and dates';
insert into r select not exists (select 1 from public.web_gate_attempts where idempotency_key = 'pr-a-unverified'), 'erasure: an unverified form with the address is removed';
insert into r select not exists (select 1 from public.web_verification_codes where target = 'asha.pr@example.com')
  and (select count(*) >= 2 from public.web_verification_codes where target = 'erased'), 'erasure: codes keep no address (still counted for the ceilings)';
insert into r select (select count(*) >= 1 and bool_and(withdrawn_at is not null and ip_hash is null and version is not null and granted_at is not null)
    from public.web_consents where student_id = pg_temp.sid('pr-a')), 'erasure: the consent ledger is kept, marked withdrawn';
insert into r select (select bool_and(email_norm = 'erased') from public.web_email_verifications where student_id = pg_temp.sid('pr-a')), 'erasure: the verification log keeps no address';
insert into r select not exists (select 1 from public.web_lead_submissions where student_id = pg_temp.sid('pr-a'))
  and exists (select 1 from public.web_lead_submissions where idempotency_key = 'web:verify:' || (select attempt from g where k = 'pr-a')::text and result is null),
  'erasure: lead-write keys stay (no second write), without their answers';
insert into r select not exists (select 1 from public.web_outbox where payload::text ~* 'asha')
  and (select count(*) >= 1 and bool_and(status = 'done') from public.web_outbox where payload = '{"erased": true}'::jsonb),
  'erasure: queued emails and events for the address are cancelled and emptied';
insert into r select pg_temp.mentions('asha\.pr@example\.com|asha privacy|9876533501') = 'web_deletion_requests=1',
  'erasure: only the open request still holds the address (found: ' || pg_temp.mentions('asha\.pr@example\.com|asha privacy|9876533501') || ')';
insert into r select (select email_norm = 'bala.pr@example.com' and full_name = 'Bala Privacy' and phone_e164 = '+919876533502' and deleted_at is null
    from public.web_students where id = pg_temp.sid('pr-b'))
  and (select count(*) = 1 from public.web_shortlists where student_id = pg_temp.sid('pr-b'))
  and (select email_norm = 'bala.pr@example.com' from public.web_gate_attempts where id = (select attempt from g where k = 'pr-b'))
  and (select count(*) = 2 from public.web_advisor_messages m join public.web_advisor_sessions a on a.id = m.session_id where a.student_id = pg_temp.sid('pr-b'))
  and exists (select 1 from public.web_outbox where payload->>'email' = 'bala.pr@example.com'), 'erasure: another account is untouched';
insert into r select (select to_jsonb(l) = (select val from v where k = 'a-lead-before') from public.student_leads l where l.id = (select lead from g where k = 'pr-a')),
  'erasure: the shared lead is not touched from the website';

-- idempotent; and no way back to "rejected" or "done by hand"
insert into v select 'a-ful2', pg_temp.fulfil('a-del');
insert into r select (select (val->>'ok')::boolean and (val->>'already')::boolean and val->>'status' = 'open' from v where k = 'a-ful2')
  and (select count(*) = 1 from public.web_audit_log where action = 'privacy.website_erased' and entity_id = pg_temp.rid('a-del')::text)
  and (select systems = (select val->'systems' from v where k = 'a-ful') from public.web_deletion_requests where id = pg_temp.rid('a-del')),
  'erasure twice: the second call changes nothing';
insert into r select (pg_temp.mark('a-del', 'rejected', 'changed my mind')->>'error') = 'fulfil_started', 'an erasure that has started cannot be rejected';
insert into r select (select status = 'open' and email_norm = 'asha.pr@example.com' from public.web_deletion_requests where id = pg_temp.rid('a-del')),
  'the request stays open, with the address, while a CRM is pending';
insert into v select 'list1', public.web_admin_privacy_requests();
insert into r select (select not (e ? 'preview') and e->'systems'->'b2b'->>'state' = 'pending' and jsonb_array_length(e->'leads') = 1
  from v, jsonb_array_elements(val) e where k = 'list1' and (e->>'id')::bigint = pg_temp.rid('a-del')), 'list: the checklist replaces the preview';

-- the CRMs: ticked only after the work there; B2B is checked against the shared lead
insert into v select 'a-b2b-early', pg_temp.tick('a-del', 'b2b', 'done', 'Erased in the B2B CRM');
insert into r select (select val->>'error' = 'lead_not_erased' and val->'leads' = jsonb_build_array((select lead from g where k = 'pr-a')) from v where k = 'a-b2b-early'),
  'checklist: "B2B done" is refused while the account''s lead is not anonymised';
-- what the B2B CRM's own erasure leaves on the row (done there by its admin; simulated here on the test lead)
update public.student_leads set student_name = 'Erased', whatsapp_number = 'ERASED-' || id, email_id = null, anonymised_at = now(), deleted_at = now()
 where id = (select lead from g where k = 'pr-a') and is_test;
insert into v select 'a-b2b', pg_temp.tick('a-del', 'b2b', 'done', 'Erased in the B2B CRM, request 7');
insert into r select (select (val->>'ok')::boolean and val->>'status' = 'open' from v where k = 'a-b2b'), 'checklist: B2B done once the lead is anonymised; Spark still pending';
insert into v select 'a-spark', pg_temp.tick('a-del', 'spark', 'done', 'Erased in Spark, reference PR-1');
insert into r select (select (val->>'ok')::boolean and val->>'status' = 'done' from v where k = 'a-spark')
  and (select status = 'done' and processed_by = 'sa.pr@example.com' and processed_at is not null and email_norm = 'erased'
       from public.web_deletion_requests where id = pg_temp.rid('a-del')), 'every system done → the erasure is done and the request loses the address';
insert into r select (select count(*) = 1 and bool_and(kind = 'email_confirmation' and status = 'pending' and payload->>'kind' = 'privacy_done'
    and payload->>'email' = 'asha.pr@example.com') from public.web_outbox where dedupe_key = 'privacy_done:' || pg_temp.rid('a-del')),
  'a last confirmation email is queued for the requester';
select public.web_outbox_scrub((select id from public.web_outbox where dedupe_key = 'privacy_done:' || pg_temp.rid('a-del')));
select public.web_outbox_scrub((select min(id) from public.web_outbox where payload->>'email' = 'bala.pr@example.com'));
insert into r select (select payload = '{"kind": "privacy_done", "erased": true}'::jsonb from public.web_outbox where dedupe_key = 'privacy_done:' || pg_temp.rid('a-del'))
  and exists (select 1 from public.web_outbox where payload->>'email' = 'bala.pr@example.com'), 'once sent, that job is emptied (and only that kind of job)';
insert into r select pg_temp.mentions('asha\.pr@example\.com|asha privacy|9876533501') = '',
  'after completion nothing on the website holds the name, address or number (found: ' || pg_temp.mentions('asha\.pr@example\.com|asha privacy|9876533501') || ')';
insert into v select 'a-repeat', jsonb_build_object('tick', pg_temp.tick('a-del', 'spark', 'done', 'again'), 'fulfil', pg_temp.fulfil('a-del'));
insert into r select (select (val->'tick'->>'already')::boolean and (val->'fulfil'->>'already')::boolean from v where k = 'a-repeat')
  and (select count(*) = 1 from public.web_outbox where dedupe_key = 'privacy_done:' || pg_temp.rid('a-del'))
  and (select count(*) = 4 from public.web_audit_log where entity = 'web_deletion_requests' and entity_id = pg_temp.rid('a-del')::text),
  'a finished erasure: every repeat is a no-op';
insert into r select (select array_agg(action order by id) = array['privacy.website_erased', 'privacy.system_done', 'privacy.system_done', 'privacy.fulfilled']
    and bool_and(actor_email = 'sa.pr@example.com' and actor = '00000000-0000-0000-0000-0000000000a1'::uuid)
    from public.web_audit_log where entity = 'web_deletion_requests' and entity_id = pg_temp.rid('a-del')::text), 'every step of the erasure is in the audit log, with who did it';

-- ---------------------------------------------------------------------------------------------------------------
-- 5. An account with no lead: nothing for the CRMs, the request closes with the website step.
insert into v select 'c-ful', pg_temp.fulfil('c-del');
insert into r select (select (val->>'ok')::boolean and val->>'status' = 'done' and val->'leads' = '[]'::jsonb
    and val->'systems'->'spark'->>'state' = 'not_applicable' and val->'systems'->'b2b'->>'state' = 'not_applicable' from v where k = 'c-ful')
  and (select status = 'done' and email_norm = 'erased' from public.web_deletion_requests where id = pg_temp.rid('c-del'))
  and (select deleted_at is not null from public.web_students where id = pg_temp.sid('pr-c')), 'no lead: erased and done in one step';
insert into r select pg_temp.mentions('chitra\.pr@example\.com') = 'web_outbox=1', 'no lead: only the queued confirmation holds the address ('
  || pg_temp.mentions('chitra\.pr@example\.com') || ')';

-- 6. Only the signed-in account that filed the request counts as the requester.
with x as (insert into public.web_deletion_requests (student_id, email_norm, kind) values (pg_temp.sid('pr-a'), 'asha.pr@example.com', 'delete') returning id)
insert into q select 'a-again', id from x;
with x as (insert into public.web_deletion_requests (student_id, email_norm, kind) values (null, 'nobody.pr@example.com', 'delete') returning id)
insert into q select 'no-account', id from x;
with x as (insert into public.web_deletion_requests (student_id, email_norm, kind) values (pg_temp.sid('pr-b'), 'other.pr@example.com', 'export') returning id)
insert into q select 'mismatch', id from x;
insert into r select (pg_temp.fulfil('a-again')->>'error') = 'account_erased', 'a request for an already erased account is refused';
insert into r select (pg_temp.fulfil('no-account')->>'error') = 'no_verified_requester', 'a request without a signed-in account is refused';
insert into r select (pg_temp.export('mismatch')->>'error') = 'requester_mismatch' and (pg_temp.fulfil('mismatch')->>'error') = 'requester_mismatch',
  'a request whose address is not the account''s is refused';
insert into r select (public.web_admin_privacy_fulfil(-1, null, 'sa.pr@example.com', 'super_admin')->>'error') = 'not_found', 'unknown request';
insert into r select (select email_norm = 'bala.pr@example.com' and deleted_at is null from public.web_students where id = pg_temp.sid('pr-b')), 'refusals erased nothing';

-- 7. The same address can sign up again: a new, empty account.
select pg_temp.verify_as('pr-a2', 'signin', null, 'asha.pr@example.com', null);
insert into r select pg_temp.sid('pr-a2') <> pg_temp.sid('pr-a')
  and (select public.web_account(pg_temp.sid('pr-a2'))->'shortlist' = '[]'::jsonb and public.web_account(pg_temp.sid('pr-a2'))->'applications' = '[]'::jsonb
         and public.web_account(pg_temp.sid('pr-a2'))->'requests' = '[]'::jsonb),
  'the same address signs up again as a new account with nothing from before';

do $$ begin
  if exists (select 1 from r where ok is not true) then
    raise exception 'FAILED (%): %', (select count(*) from r where ok is not true), (select string_agg(name, ' | ') from r where ok is not true);
  end if;
  raise notice 'PASS % checks', (select count(*) from r);
end $$;
rollback;
