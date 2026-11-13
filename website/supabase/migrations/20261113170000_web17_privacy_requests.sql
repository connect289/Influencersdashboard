-- =====================================================================================================================
-- web17 · Privacy requests are carried out, not only recorded (website audit of 12 Nov 2026, finding H5;
-- docs/DECISIONS.md D-096). A "delete my data" or "send me a copy of my data" request filed from a signed-in account
-- (web_deletion_requests, kinds delete / export) used to be marked done by hand. Now a super admin fulfils it in
-- Admin → Privacy requests:
--   1. Copy of data: web_admin_privacy_export() returns one JSON document with what the WEBSITE holds for the account
--      that filed the request (profile, consents, enquiries, applications, saved programmes, chats, callbacks, earlier
--      requests). The admin downloads it and sends it to the account's address; web_admin_privacy_fulfil() then records
--      that it was sent.
--   2. Erasure: web_admin_privacy_fulfil() erases or anonymises what the WEBSITE holds (web_privacy_erase). The consent
--      ledger and the request log stay, without identity. Never automatic: one explicit call per request, on a locked
--      row, a second call changes nothing.
--   3. The shared lead and the two CRMs are NOT touched from here. The CRMs erase through their own audited, signed-in
--      admin actions (Spark: b2c.lead_erase; B2B: b2b.lead_anonymise), which the website must not call or bypass. The
--      request carries a checklist instead (web_deletion_requests.systems: website, spark, b2b); the admin ticks each
--      CRM after doing it there (web_admin_privacy_system) and the request becomes done only when every system is done
--      or not applicable. "B2B done" on an erasure is accepted only when the account's own lead is already anonymised.
--   4. web_admin_privacy_done() no longer marks a delete / export request done (that is what fulfilling is for); it
--      still rejects them (with a note) and still closes opt-out requests.
-- Every step writes web_audit_log (ids, kinds and counts only, never the person's details).
-- No shared object is created or changed; public.student_leads is only read (ids, anonymised_at), like web_lead_tie.
-- Idempotent (create or replace / if not exists). Rollback:
-- supabase/rollbacks/20261113170000_web17_privacy_requests.rollback.sql (an erasure itself cannot be rolled back).
-- =====================================================================================================================

-- ---------------------------------------------------------------------------------------------------------------------
-- The checklist on the request.
--   systems: {"website": {"state": "pending" | "done", ...}, "spark": {"state": "pending" | "done" | "not_applicable", ...},
--             "b2b": {...}}; empty until an admin starts on the request.
--   leads:   [{"lead_id": 123, "tie": null | reason}] as found when the website step ran (the website's own records are
--            erased by then). tie null = this account's own lead (web_lead_tie); a reason = confirm in the CRM first.
alter table public.web_deletion_requests add column if not exists systems jsonb not null default '{}'::jsonb;
alter table public.web_deletion_requests add column if not exists leads jsonb not null default '[]'::jsonb;

-- ---------------------------------------------------------------------------------------------------------------------
-- Internal helpers (no role may call them directly; the admin functions below run them as the owner).

-- The shared leads this account's enquiries reached: the current lead of every phone number the account verified with
-- (and whether web_lead_tie treats it as the account's own), plus lead ids the website recorded that no longer resolve
-- from a phone ('recorded_only': merged, deleted or already erased). Ids only; read-only. search_path = public, pg_temp
-- like web_lead_tie (crm_find_lead resolves its table through it); every name here is qualified.
create or replace function public.web_privacy_leads(p_student uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare s public.web_students; v jsonb;
begin
  select * into s from public.web_students where id = p_student;
  if s.id is null then return '[]'::jsonb; end if;
  with phones as (
    select s.phone_e164 as phone where s.phone_e164 is not null
    union
    select a.phone_e164 from public.web_gate_attempts a where a.student_id = p_student and a.phone_e164 is not null
  ), by_phone as (
    select (public.crm_find_lead(public.crm_norm_phone(ph.phone))).id as lead_id, public.web_lead_tie(ph.phone, s.email_norm) as tie
      from phones ph
  ), recorded as (
    select s.lead_id as lead_id where s.lead_id is not null
    union select a.lead_id from public.web_gate_attempts a where a.student_id = p_student and a.lead_id is not null
    union select x.lead_id from public.web_applications x where x.student_id = p_student and x.lead_id is not null
    union select x.lead_id from public.web_advisor_sessions x where x.student_id = p_student and x.lead_id is not null
    union select x.lead_id from public.web_consents x where x.student_id = p_student and x.lead_id is not null
    union select x.lead_id from public.web_callback_requests x where x.student_id = p_student and x.lead_id is not null
  ), found as (
    select b.lead_id, b.tie, 0 as pref from by_phone b where b.lead_id is not null
    union all
    select r.lead_id, 'recorded_only', 1 from recorded r
  )
  select coalesce(jsonb_agg(jsonb_build_object('lead_id', z.lead_id, 'tie', z.tie) order by z.lead_id), '[]'::jsonb) into v
    from (select distinct on (f.lead_id) f.lead_id, f.tie from found f order by f.lead_id, f.pref, f.tie nulls first) z;
  return v;
end $$;

-- How much the website holds for an account (counts only): shown to the admin before an erasure and kept in the audit row.
create or replace function public.web_privacy_counts(p_student uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'enquiries', (select count(*) from public.web_gate_attempts where student_id = p_student),
    'applications', (select count(*) from public.web_applications where student_id = p_student),
    'chats', (select count(*) from public.web_advisor_sessions where student_id = p_student),
    'chat_messages', (select count(*) from public.web_advisor_messages m join public.web_advisor_sessions a on a.id = m.session_id
                       where a.student_id = p_student),
    'saved_programmes', (select count(*) from public.web_shortlists where student_id = p_student),
    'comparisons', (select count(*) from public.web_saved_comparisons where student_id = p_student),
    'callbacks', (select count(*) from public.web_callback_requests where student_id = p_student),
    'consents', (select count(*) from public.web_consents where student_id = p_student),
    'sessions', (select count(*) from public.web_student_sessions where student_id = p_student))
$$;

-- The copy of data: only rows tied to this account by its verified sign-in (student_id), never rows matched by email or
-- phone alone (an unverified form could have been typed by someone else). Left out on purpose: internal fields (junk
-- score, hashes, idempotency keys, code hashes, lead ids, staff notes and names, Witty's working state other than the
-- profile the student gave, models, token counts).
create or replace function public.web_privacy_export_doc(p_student uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'format', 'eduwit-website-data-copy',
    'version', 1,
    'generated_at', now(),
    'scope', 'Data the eduwit.in website holds for this account. Records of your enquiry in Eduwit''s admission systems are provided separately.',
    'profile', (select jsonb_build_object('email', s.email_norm, 'name', s.full_name, 'phone', s.phone_e164,
                  'email_verified_at', s.email_verified_at, 'phone_verified_at', s.phone_verified_at,
                  'created_at', s.created_at, 'last_seen_at', s.last_seen_at)
                  from public.web_students s where s.id = p_student),
    'consents', coalesce((select jsonb_agg(jsonb_build_object('version', c.version, 'text', t.body, 'purposes', to_jsonb(c.purposes),
                  'given_on', c.surface, 'granted_at', c.granted_at, 'withdrawn_at', c.withdrawn_at) order by c.granted_at, c.id)
                  from public.web_consents c left join public.web_consent_texts t on t.version = c.version where c.student_id = p_student), '[]'::jsonb),
    'email_verifications', coalesce((select jsonb_agg(jsonb_build_object('email', e.email_norm, 'verified_at', e.verified_at,
                  'method', e.method) order by e.verified_at, e.id)
                  from public.web_email_verifications e where e.student_id = p_student), '[]'::jsonb),
    'sign_ins', coalesce((select jsonb_agg(jsonb_build_object('created_at', x.created_at, 'expires_at', x.expires_at,
                  'signed_out_at', x.revoked_at, 'last_seen_at', x.last_seen_at) order by x.created_at)
                  from public.web_student_sessions x where x.student_id = p_student), '[]'::jsonb),
    'enquiries', coalesce((select jsonb_agg(jsonb_build_object('form', a.surface, 'submitted_at', a.submitted_at, 'verified_at', a.verified_at,
                  'name', a.full_name, 'email', a.email_norm, 'phone', a.phone_e164, 'programme', a.context,
                  'consent_version', a.consent_version, 'updates_consent', a.consent_marketing,
                  'visit', (select coalesce(jsonb_object_agg(k.key, k.value), '{}'::jsonb) from jsonb_each(a.attribution) k
                             where k.key in ('utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term', 'landing_url',
                                             'referrer_url', 'referred_by_code', 'device_type', 'click_ids', 'ad_consent')))
                  order by a.submitted_at, a.id)
                  from public.web_gate_attempts a where a.student_id = p_student), '[]'::jsonb),
    'applications', coalesce((select jsonb_agg(jsonb_build_object('reference', x.reference, 'kind', x.kind, 'status', x.status,
                  'created_at', x.created_at, 'updated_at', x.updated_at, 'submitted_at', x.submitted_at, 'programme', x.context,
                  'catalogue_programme_id', x.offering_id, 'other_programme_ids', to_jsonb(x.preferred_offering_ids),
                  'answers', x.steps) order by x.created_at, x.id)
                  from public.web_applications x where x.student_id = p_student), '[]'::jsonb),
    'saved_programmes', coalesce((select jsonb_agg(jsonb_build_object('catalogue_programme_id', h.catalog_program_id,
                  'programme', o.programme_name, 'university', o.uni_name, 'saved_at', h.created_at) order by h.created_at, h.catalog_program_id)
                  from public.web_shortlists h left join public.web_offering_search o on o.id = h.catalog_program_id
                  where h.student_id = p_student), '[]'::jsonb),
    'comparisons', coalesce((select jsonb_agg(jsonb_build_object('catalogue_programme_ids', to_jsonb(c.offering_ids),
                  'saved_at', c.created_at) order by c.created_at, c.id)
                  from public.web_saved_comparisons c where c.student_id = p_student), '[]'::jsonb),
    'chats', coalesce((select jsonb_agg(jsonb_build_object('started_at', a.created_at, 'last_message_at', a.last_turn_at,
                  'ended_at', a.ended_at, 'language', a.language, 'what_you_told_witty', coalesce(a.state -> 'profile', '{}'::jsonb),
                  'messages', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                                 'from', case m.direction when 'in' then 'you' else 'witty' end, 'text', m.content, 'at', m.created_at,
                                 'your_rating', f.rating, 'your_comment', f.comment)) order by m.id)
                               from public.web_advisor_messages m left join public.web_advisor_feedback f on f.message_id = m.id
                              where m.session_id = a.id and m.kind in ('chat', 'reply')), '[]'::jsonb)) order by a.created_at, a.id)
                  from public.web_advisor_sessions a where a.student_id = p_student), '[]'::jsonb),
    'callback_requests', coalesce((select jsonb_agg(jsonb_build_object('date', b.slot_date, 'slot', b.slot, 'requested_at', b.created_at)
                  order by b.created_at, b.id)
                  from public.web_callback_requests b where b.student_id = p_student), '[]'::jsonb),
    'privacy_requests', coalesce((select jsonb_agg(jsonb_build_object('kind', q.kind, 'status', q.status, 'requested_at', q.requested_at,
                  'completed_at', q.processed_at) order by q.requested_at, q.id)
                  from public.web_deletion_requests q where q.student_id = p_student), '[]'::jsonb))
$$;

-- Erases or anonymises everything the website holds for an account. Kept, without identity: the account row as a
-- tombstone (other rows point at it), the consent ledger (marked withdrawn; DPDP record), the verification log, the
-- enquiry / application / chat rows as bare counters for the funnels (surface, dates, status), and the lead-write keys
-- (so nothing is written to the lead twice). Removed: chat messages and feedback, saved programmes, comparisons,
-- callbacks, sign-in sessions, never-verified form attempts with this email. Queued emails and events for this address
-- are cancelled. Nothing outside web_* tables is touched. Returns counts only.
create or replace function public.web_privacy_erase(p_student uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  s public.web_students; v_email text; v_att uuid[]; v_sess uuid[]; v_reqs text[]; v_counts jsonb; n_unverified int; n_out int;
begin
  select * into s from public.web_students where id = p_student for update;
  if s.id is null or s.deleted_at is not null then return jsonb_build_object('erased', false); end if;
  v_email := s.email_norm;
  v_counts := public.web_privacy_counts(p_student);
  select coalesce(array_agg(a.id), '{}') into v_att from public.web_gate_attempts a
   where a.student_id = p_student or (a.student_id is null and a.email_norm = v_email);
  select coalesce(array_agg(a.id), '{}') into v_sess from public.web_advisor_sessions a where a.student_id = p_student;
  select coalesce(array_agg(q.id::text), '{}') into v_reqs from public.web_deletion_requests q where q.student_id = p_student;

  -- Witty: the conversation goes; the session stays as a counter (turns, cost, classification) with no state.
  delete from public.web_callback_requests where student_id = p_student;
  delete from public.web_advisor_feedback where session_id = any (v_sess);
  delete from public.web_advisor_messages where session_id = any (v_sess);
  update public.web_advisor_sessions set state = '{}'::jsonb, lead_id = null, ended_at = coalesce(ended_at, now()) where id = any (v_sess);

  delete from public.web_shortlists where student_id = p_student;
  delete from public.web_saved_comparisons where student_id = p_student;
  delete from public.web_student_sessions where student_id = p_student;

  -- Applications and enquiries: answers and identity go; kind, status and dates stay for the funnels.
  update public.web_applications set steps = '{}'::jsonb, context = '{}'::jsonb, eligibility_note = null, preferred_offering_ids = '{}',
         lead_id = null, reference = 'erased-' || id::text, updated_at = now()
   where student_id = p_student or attempt_id = any (v_att);
  update public.web_verification_codes set target = 'erased', code_hash = 'erased', consumed_at = coalesce(consumed_at, now())
   where attempt_id = any (v_att) or target = v_email;
  update public.web_email_verifications set email_norm = 'erased' where student_id = p_student;
  -- a form that was never verified has nothing depending on it
  delete from public.web_gate_attempts where id = any (v_att) and student_id is null and verified_at is null;
  get diagnostics n_unverified = row_count;
  update public.web_gate_attempts set full_name = null, email_norm = 'erased', phone_e164 = null, context = '{}'::jsonb,
         attribution = '{}'::jsonb, ip_hash = null, device_hash = null, lead_id = null, idempotency_key = 'erased:' || id::text
   where id = any (v_att);

  -- Consent ledger: kept (version, purposes, dates, the lead it was given for), marked withdrawn, without the network hash.
  update public.web_consents set withdrawn_at = coalesce(withdrawn_at, now()), ip_hash = null where student_id = p_student;
  -- Lead-write keys stay so a replay still does nothing; their stored answers go.
  update public.web_lead_submissions set result = null, student_id = null where student_id = p_student;

  -- Queued or finished side effects that carry this address (emails, Conversions API events): cancelled and emptied.
  update public.web_outbox set payload = jsonb_build_object('erased', true), locked_until = null,
         last_error = case when status = 'done' then last_error else 'cancelled: data erased' end,
         processed_at = case when status = 'done' then processed_at else now() end, status = 'done'
   where lower(payload ->> 'email') = v_email;
  get diagnostics n_out = row_count;

  -- This account's requests and their audit rows: no address, name or phone number in the notes; closed requests lose
  -- the address now, the open one (being fulfilled) when it closes (web_privacy_close).
  update public.web_deletion_requests set
         note = regexp_replace(replace(replace(note, v_email, '[email erased]'), coalesce(nullif(btrim(s.full_name), ''), v_email), '[erased]'),
                               '\+?[0-9]{10,}', '[number erased]', 'g')
   where student_id = p_student and note is not null;
  update public.web_deletion_requests set email_norm = 'erased' where student_id = p_student and status <> 'open';
  update public.web_audit_log set before = before - 'email_norm' - 'note', after = after - 'note'
   where entity = 'web_deletion_requests' and entity_id = any (v_reqs);

  -- The account: a tombstone. The same email can sign up again later as a new account.
  update public.web_students set email_norm = 'erased-' || id::text || '@erased.invalid', phone_e164 = null, full_name = null,
         lead_id = null, email_verified_at = null, phone_verified_at = null, last_seen_at = null, deleted_at = now()
   where id = p_student;

  return jsonb_build_object('erased', true,
    'counts', v_counts || jsonb_build_object('unverified_forms', n_unverified, 'queued_jobs', n_out));
end $$;

-- Closes the request once the website and every applicable system are done. For an erasure the requester's address
-- leaves the request row too, after a last confirmation email is queued (the outbox worker empties that job once it has
-- sent it: web_outbox_scrub). Returns whether it closed.
create or replace function public.web_privacy_close(p_id bigint, p_actor uuid, p_actor_email text)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
declare r public.web_deletion_requests;
begin
  select * into r from public.web_deletion_requests where id = p_id for update;
  if r.id is null or r.status <> 'open' or r.kind not in ('delete', 'export') then return false; end if;
  if coalesce(r.systems -> 'website' ->> 'state', '') <> 'done'
     or coalesce(r.systems -> 'spark' ->> 'state', '') not in ('done', 'not_applicable')
     or coalesce(r.systems -> 'b2b' ->> 'state', '') not in ('done', 'not_applicable') then
    return false;
  end if;
  if r.kind = 'delete' then
    perform public.web_outbox_enqueue('email_confirmation', 'privacy_done:' || r.id,
      jsonb_build_object('kind', 'privacy_done', 'request', r.kind, 'email', r.email_norm));
  end if;
  update public.web_deletion_requests set status = 'done', processed_at = now(), processed_by = p_actor_email,
         email_norm = case when r.kind = 'delete' then 'erased' else email_norm end
   where id = r.id;
  insert into public.web_audit_log (actor, actor_email, action, entity, entity_id, after)
  values (p_actor, p_actor_email, 'privacy.fulfilled', 'web_deletion_requests', r.id::text,
    jsonb_build_object('kind', r.kind, 'website', r.systems -> 'website' ->> 'state', 'spark', r.systems -> 'spark' ->> 'state',
                       'b2b', r.systems -> 'b2b' ->> 'state'));
  return true;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Admin functions (service role; the website checks the staff session first and the functions check the role again).

-- The verified requester of a request: the signed-in account that filed it, still there and still under that address.
-- Returns null when it is, otherwise the reason.
create or replace function public.web_privacy_requester_problem(p_student uuid, p_email text)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when p_student is null then 'no_verified_requester'
    when not exists (select 1 from public.web_students s where s.id = p_student) then 'no_verified_requester'
    when exists (select 1 from public.web_students s where s.id = p_student and s.deleted_at is not null) then 'account_erased'
    when not exists (select 1 from public.web_students s where s.id = p_student and s.email_norm = p_email) then 'requester_mismatch'
  end
$$;

-- The copy of data for an export request, for the admin to download and send. Read-only apart from the audit row and a
-- "downloaded" mark on the request (the "sent" step below needs it). Can be downloaded again until the request is rejected.
create or replace function public.web_admin_privacy_export(p_id bigint, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare r public.web_deletion_requests; v_why text; v_doc jsonb;
begin
  if not public.web_admin_role_ok(p_role, 'super_admin') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into r from public.web_deletion_requests where id = p_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.kind <> 'export' then return jsonb_build_object('ok', false, 'error', 'wrong_kind'); end if;
  if r.status = 'rejected' then return jsonb_build_object('ok', false, 'error', 'rejected'); end if;
  v_why := public.web_privacy_requester_problem(r.student_id, r.email_norm);
  if v_why is not null then return jsonb_build_object('ok', false, 'error', v_why); end if;
  v_doc := public.web_privacy_export_doc(r.student_id)
    || jsonb_build_object('request', jsonb_build_object('id', r.id, 'kind', r.kind, 'requested_at', r.requested_at));
  if r.status = 'open' and not (r.systems ? 'website') then
    update public.web_deletion_requests
       set systems = jsonb_build_object('website', jsonb_build_object('state', 'pending', 'downloaded_at', now(), 'downloaded_by', p_actor_email))
     where id = r.id;
  end if;
  insert into public.web_audit_log (actor, actor_email, action, entity, entity_id, after)
  values (p_actor, p_actor_email, 'privacy.export_downloaded', 'web_deletion_requests', r.id::text,
    jsonb_build_object('counts', public.web_privacy_counts(r.student_id)));
  return jsonb_build_object('ok', true, 'request_id', r.id, 'export', v_doc);
end $$;

-- The explicit step on one request, by a super admin:
--   delete: erases the website's data for the account that filed it (irreversible);
--   export: records that the downloaded copy was sent to the account's address.
-- Then the checklist starts: Spark and B2B are 'pending' when the account's enquiries reached a shared lead, otherwise
-- 'not_applicable' and the request closes at once. The request row is locked, so two admins cannot run it twice; a
-- second call answers already = true and changes nothing.
create or replace function public.web_admin_privacy_fulfil(p_id bigint, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  r public.web_deletion_requests; v_why text; v_other jsonb; v_leads jsonb; v_counts jsonb; v_crm text; v_site jsonb;
  v_systems jsonb; v_closed boolean;
begin
  if not public.web_admin_role_ok(p_role, 'super_admin') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into r from public.web_deletion_requests where id = p_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.kind not in ('delete', 'export') then return jsonb_build_object('ok', false, 'error', 'wrong_kind'); end if;
  if r.status = 'rejected' then return jsonb_build_object('ok', false, 'error', 'rejected'); end if;
  if r.status = 'done' or r.systems -> 'website' ->> 'state' = 'done' then
    return jsonb_build_object('ok', true, 'already', true, 'kind', r.kind, 'status', r.status, 'systems', r.systems, 'leads', r.leads);
  end if;
  -- the account row is locked from here to the end, so it cannot change while it is checked, read and erased
  perform 1 from public.web_students where id = r.student_id for update;
  v_why := public.web_privacy_requester_problem(r.student_id, r.email_norm);
  if v_why is not null then return jsonb_build_object('ok', false, 'error', v_why); end if;

  if r.kind = 'delete' then
    -- An open opt-out needs the phone number and an open copy request needs the data: both go with the erasure.
    select jsonb_agg(o.id order by o.id) into v_other from public.web_deletion_requests o
     where o.student_id = r.student_id and o.id <> r.id and o.status = 'open';
    if v_other is not null then return jsonb_build_object('ok', false, 'error', 'other_requests_open', 'requests', v_other); end if;
  elsif r.systems -> 'website' ->> 'downloaded_at' is null then
    return jsonb_build_object('ok', false, 'error', 'not_downloaded');
  end if;

  v_leads := public.web_privacy_leads(r.student_id);
  if r.kind = 'delete' then
    v_counts := public.web_privacy_erase(r.student_id) -> 'counts';
    v_site := jsonb_build_object('state', 'done', 'did', 'erased', 'at', now(), 'by', p_actor_email, 'counts', v_counts);
  else
    v_counts := public.web_privacy_counts(r.student_id);
    v_site := coalesce(r.systems -> 'website', '{}'::jsonb)
      || jsonb_build_object('state', 'done', 'did', 'copy_sent', 'at', now(), 'by', p_actor_email, 'counts', v_counts);
  end if;
  v_crm := case when jsonb_array_length(v_leads) = 0 then 'not_applicable' else 'pending' end;
  v_systems := jsonb_build_object('website', v_site, 'spark', jsonb_build_object('state', v_crm), 'b2b', jsonb_build_object('state', v_crm));
  update public.web_deletion_requests set systems = v_systems, leads = v_leads where id = r.id;
  insert into public.web_audit_log (actor, actor_email, action, entity, entity_id, after)
  values (p_actor, p_actor_email, case when r.kind = 'delete' then 'privacy.website_erased' else 'privacy.copy_sent' end,
    'web_deletion_requests', r.id::text,
    jsonb_build_object('kind', r.kind, 'counts', v_counts, 'leads', v_leads, 'spark', v_crm, 'b2b', v_crm));
  v_closed := public.web_privacy_close(r.id, p_actor, p_actor_email);
  return jsonb_build_object('ok', true, 'already', false, 'kind', r.kind, 'status', case when v_closed then 'done' else 'open' end,
    'systems', v_systems, 'leads', v_leads, 'counts', v_counts);
end $$;

-- Ticks one CRM on the checklist after the admin did the work there: 'done' (erased, or its copy sent) or
-- 'not_applicable' (that CRM holds nothing for this person, or the lead is not this person's), with a note saying what
-- was done. Only after the website step. For an erasure, "b2b done" is accepted only when every lead that is the
-- account's own is anonymised (or gone) in the shared lead table. Closes the request when nothing is pending.
create or replace function public.web_admin_privacy_system(p_id bigint, p_system text, p_state text, p_note text,
  p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare r public.web_deletion_requests; v_now text; v_live jsonb; v_systems jsonb; v_closed boolean;
begin
  if not public.web_admin_role_ok(p_role, 'super_admin') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_system is null or p_system not in ('spark', 'b2b') then return jsonb_build_object('ok', false, 'error', 'bad_system'); end if;
  if p_state is null or p_state not in ('done', 'not_applicable') then return jsonb_build_object('ok', false, 'error', 'bad_state'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then return jsonb_build_object('ok', false, 'error', 'note_required'); end if;
  select * into r from public.web_deletion_requests where id = p_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.kind not in ('delete', 'export') then return jsonb_build_object('ok', false, 'error', 'wrong_kind'); end if;
  v_now := r.systems -> p_system ->> 'state';
  if v_now = p_state then
    return jsonb_build_object('ok', true, 'already', true, 'status', r.status, 'systems', r.systems);
  end if;
  if r.status <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  if coalesce(r.systems -> 'website' ->> 'state', '') <> 'done' then return jsonb_build_object('ok', false, 'error', 'website_first'); end if;
  if v_now is distinct from 'pending' then return jsonb_build_object('ok', false, 'error', 'already_set'); end if;
  if r.kind = 'delete' and p_system = 'b2b' and p_state = 'done' then
    select jsonb_agg(l.id order by l.id) into v_live
      from jsonb_array_elements(r.leads) e join public.student_leads l on l.id = (e ->> 'lead_id')::bigint
     where e ->> 'tie' is null and l.anonymised_at is null;
    if v_live is not null then return jsonb_build_object('ok', false, 'error', 'lead_not_erased', 'leads', v_live); end if;
  end if;
  v_systems := jsonb_set(r.systems, array[p_system],
    jsonb_build_object('state', p_state, 'at', now(), 'by', p_actor_email, 'note', left(btrim(p_note), 300)));
  update public.web_deletion_requests set systems = v_systems where id = r.id;
  insert into public.web_audit_log (actor, actor_email, action, entity, entity_id, after)
  values (p_actor, p_actor_email, 'privacy.system_' || p_state, 'web_deletion_requests', r.id::text,
    jsonb_build_object('kind', r.kind, 'system', p_system, 'state', p_state));
  v_closed := public.web_privacy_close(r.id, p_actor, p_actor_email);
  return jsonb_build_object('ok', true, 'already', false, 'status', case when v_closed then 'done' else 'open' end, 'systems', v_systems);
end $$;

-- web9's function, changed: the row is locked and only an open request can be closed; a delete / export request cannot be
-- marked done here (web_admin_privacy_fulfil does that) and can be rejected only with a note and only before the
-- website step ran; the audit row no longer copies the requester's address or the request note. Opt-out requests
-- close as before.
create or replace function public.web_admin_privacy_done(p_id bigint, p_status text, p_note text, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare r public.web_deletion_requests;
begin
  if not public.web_admin_role_ok(p_role, 'super_admin') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_status is null or p_status not in ('done', 'rejected') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  select * into r from public.web_deletion_requests where id = p_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  if r.kind in ('delete', 'export') then
    if p_status = 'done' then return jsonb_build_object('ok', false, 'error', 'use_fulfil'); end if;
    if r.systems -> 'website' ->> 'state' = 'done' then return jsonb_build_object('ok', false, 'error', 'fulfil_started'); end if;
    if length(btrim(coalesce(p_note, ''))) < 3 then return jsonb_build_object('ok', false, 'error', 'note_required'); end if;
  end if;
  update public.web_deletion_requests set status = p_status, processed_at = now(), processed_by = p_actor_email, note = left(p_note, 500)
   where id = r.id;
  insert into public.web_audit_log (actor, actor_email, action, entity, entity_id, before, after)
  values (p_actor, p_actor_email, 'privacy.' || p_status, 'web_deletion_requests', p_id::text,
    to_jsonb(r) - 'email_norm' - 'note', jsonb_build_object('status', p_status, 'note', p_note));
  return jsonb_build_object('ok', true);
end $$;

-- web9's list, with what the admin needs before starting on an open delete / export request: whether the requester is
-- still the account that filed it, how much the website holds, the shared leads involved and the account's other open
-- requests (an erasure waits for them).
create or replace function public.web_admin_privacy_requests()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(r) || case
      when r.status = 'open' and r.kind in ('delete', 'export') and coalesce(r.systems -> 'website' ->> 'state', '') <> 'done' then
        jsonb_build_object('preview', jsonb_build_object(
          'requester_problem', public.web_privacy_requester_problem(r.student_id, r.email_norm),
          'counts', public.web_privacy_counts(r.student_id),
          'leads', public.web_privacy_leads(r.student_id),
          'other_open', (select coalesce(jsonb_agg(o.id order by o.id), '[]'::jsonb) from public.web_deletion_requests o
                          where o.student_id = r.student_id and o.id <> r.id and o.status = 'open')))
      else '{}'::jsonb end order by r.requested_at desc, r.id desc), '[]'::jsonb)
  from public.web_deletion_requests r
$$;

-- The outbox worker empties the "your data was erased" email job once it has sent it, so the address does not stay in
-- the queue's history. Only that kind of job.
create or replace function public.web_outbox_scrub(p_id bigint)
returns void language sql volatile security definer set search_path = '' as $$
  update public.web_outbox set payload = jsonb_build_object('kind', 'privacy_done', 'erased', true)
   where id = p_id and kind = 'email_confirmation' and payload ->> 'kind' = 'privacy_done';
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Grants: the admin functions are service role only (Supabase grants new public functions to the API roles by default);
-- the helpers are for the owner alone.
do $$
declare f text;
begin
  foreach f in array array[
    'public.web_admin_privacy_export(bigint, uuid, text, text)', 'public.web_admin_privacy_fulfil(bigint, uuid, text, text)',
    'public.web_admin_privacy_system(bigint, text, text, text, uuid, text, text)',
    'public.web_admin_privacy_done(bigint, text, text, uuid, text, text)', 'public.web_admin_privacy_requests()',
    'public.web_outbox_scrub(bigint)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  foreach f in array array[
    'public.web_privacy_leads(uuid)', 'public.web_privacy_counts(uuid)', 'public.web_privacy_export_doc(uuid)',
    'public.web_privacy_erase(uuid)', 'public.web_privacy_close(bigint, uuid, text)',
    'public.web_privacy_requester_problem(uuid, text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end $$;
