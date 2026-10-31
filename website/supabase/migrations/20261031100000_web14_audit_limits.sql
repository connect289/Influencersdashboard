-- =====================================================================================================================
-- web14 · Limits from the estate audit of 30 Oct 2026 (approved by the owner on 31 Oct; docs/DECISIONS.md D-086–D-089):
--   1. A site-wide ceiling on verification codes per hour (setting code_send_hourly_cap, default 200; students' codes,
--      not the admin second factor). Above it web_gate_start / web_gate_resend answer 'site_busy' and the app alerts.
--   2. Every lead write goes through web_lead_intake(): an existing lead that is not tied to the verified student
--      (its confirmed email is another one, it is enrolled, or a CRM team owns it) receives the website's fields as a
--      fill-empty-only update (an untrusted source for lead_intake) instead of overwriting them. New leads and the same
--      student behave as before. lead_intake() itself is unchanged.
--   3. The outbox worker job calls the site only when a job is due (or unverified pushes are on): web_outbox_tick().
--      The catalogue poll job runs with a 30 s statement timeout.
--   4. A site-wide daily ceiling on Witty turns and model spend (setting web_advisor_daily_cap, default 2000 turns /
--      25 USD per India day), counted in web_advisor_daily; the app opens its circuit breaker above it.
-- The two new ceilings, and the settings that point the database jobs at the site, are super-admin only.
-- Idempotent (create or replace / if not exists / on conflict). Rollback:
-- supabase/rollbacks/20261031100000_web14_audit_limits.rollback.sql.
-- =====================================================================================================================

-- ---------------------------------------------------------------------------------------------------------------------
-- Settings
insert into public.web_settings (key, value, description) values
  ('code_send_hourly_cap', '200'::jsonb,
   'Most email verification codes the whole site sends in any hour (forms, Witty gate, student sign-in). Above it people are asked to try again a little later and the site logs an alert. 0 stops all sends.'),
  ('web_advisor_daily_cap', '{"turns": 2000, "cost_usd": 25}'::jsonb,
   'Most Witty turns and model spend (USD) per India day for the whole site. Above either, Witty pauses until midnight IST and visitors get the guided finder and a counsellor.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Site-wide code ceiling
create index if not exists web_verification_codes_created_idx on public.web_verification_codes (created_at);

-- True when the codes created in the last hour reach the ceiling (counting stops at the ceiling).
create or replace function public.web_code_cap_reached()
returns boolean language sql stable security definer set search_path = '' as $$
  with cap as (
    select coalesce((select least(floor((s.value #>> '{}')::numeric), 1000000)::int from public.web_settings s
                      where s.key = 'code_send_hourly_cap' and jsonb_typeof(s.value) = 'number' and (s.value #>> '{}')::numeric >= 0), 200) as n
  )
  select (select count(*) from (select 1 from public.web_verification_codes c
                                 where c.created_at > now() - interval '1 hour' limit (select n from cap)) x) >= (select n from cap)
$$;

create or replace function public.web_gate_start(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(p->>'email'));
  v_attempt public.web_gate_attempts;
  v_recent int;
  v_screen jsonb;
begin
  v_screen := public.web_email_screen(v_email, p->>'phone', p->>'ip_hash');
  if not (v_screen->>'ok')::boolean then return v_screen; end if;
  select count(*) into v_recent from public.web_verification_codes where target = v_email and created_at > now() - interval '1 hour';
  if v_recent >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_codes'); end if;
  -- web14: site-wide hourly ceiling
  if public.web_code_cap_reached() then return jsonb_build_object('ok', false, 'reason', 'site_busy'); end if;

  insert into public.web_gate_attempts as a (idempotency_key, surface, context, full_name, email_norm, phone_e164, consent_version,
    consent_marketing, attribution, junk_score, junk_reasons, ip_hash, device_hash, turnstile_ok, is_test)
  values (p->>'idempotency_key', p->>'surface', coalesce(p->'context', '{}'), p->>'name', v_email, p->>'phone', p->>'consent_version',
    coalesce((p->>'marketing')::boolean, false), coalesce(p->'attribution', '{}'), coalesce((p->>'junk_score')::int, 0),
    coalesce(array(select jsonb_array_elements_text(p->'junk_reasons')), '{}'), p->>'ip_hash', p->>'device_hash',
    (p->>'turnstile_ok')::boolean, coalesce((p->>'is_test')::boolean, false))
  on conflict (idempotency_key) do update set
    full_name = excluded.full_name, email_norm = excluded.email_norm, phone_e164 = excluded.phone_e164,
    consent_version = excluded.consent_version, consent_marketing = excluded.consent_marketing, context = excluded.context,
    junk_score = excluded.junk_score, junk_reasons = excluded.junk_reasons, submitted_at = now()
  where a.verified_at is null
  returning * into v_attempt;
  if v_attempt.id is null then
    select * into v_attempt from public.web_gate_attempts where idempotency_key = p->>'idempotency_key';
    return jsonb_build_object('ok', true, 'status', 'already_verified', 'attempt_id', v_attempt.id);
  end if;

  update public.web_verification_codes set consumed_at = now() where attempt_id = v_attempt.id and consumed_at is null;
  insert into public.web_verification_codes (attempt_id, channel, target, code_hash, expires_at, resend_after)
  values (v_attempt.id, 'email', v_email, p->>'code_hash', now() + interval '10 minutes', now() + interval '30 seconds');
  update public.web_gate_attempts set code_sent_at = now() where id = v_attempt.id;
  return jsonb_build_object('ok', true, 'status', 'code_sent', 'attempt_id', v_attempt.id, 'resend_in', 30);
end $$;

create or replace function public.web_gate_resend(p_attempt uuid, p_code_hash text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_a public.web_gate_attempts; v_last public.web_verification_codes; v_recent int;
begin
  select * into v_a from public.web_gate_attempts where id = p_attempt;
  if v_a.id is null or v_a.verified_at is not null then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  select * into v_last from public.web_verification_codes where attempt_id = p_attempt order by created_at desc limit 1;
  if v_last.resend_after > now() then
    return jsonb_build_object('ok', false, 'reason', 'too_soon', 'resend_in', ceil(extract(epoch from v_last.resend_after - now())));
  end if;
  select count(*) into v_recent from public.web_verification_codes where target = v_a.email_norm and created_at > now() - interval '1 hour';
  if v_recent >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_codes'); end if;
  -- web14: site-wide hourly ceiling
  if public.web_code_cap_reached() then return jsonb_build_object('ok', false, 'reason', 'site_busy'); end if;
  update public.web_verification_codes set consumed_at = now() where attempt_id = p_attempt and consumed_at is null;
  insert into public.web_verification_codes (attempt_id, channel, target, code_hash, expires_at, resend_after)
  values (p_attempt, 'email', v_a.email_norm, p_code_hash, now() + interval '10 minutes', now() + interval '30 seconds');
  return jsonb_build_object('ok', true, 'status', 'code_sent', 'attempt_id', p_attempt, 'resend_in', 30, 'email', v_a.email_norm);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. One wrapper for every website lead write.
-- p is the lead_intake payload; p_verified_email is the email the website has verified for this student (null for the
-- optional push of unverified attempts). When the phone already has a lead that is not tied to that email — its
-- confirmed email is another one, it is enrolled, or a CRM team owns it (w2_crm_owned) — the payload goes to
-- lead_intake as source 'web_agent_unverified' (lead_intake trusts only witty, web_agent and crm, so it fills empty
-- fields only), and a classification is dropped when the lead already has one (lead_intake would otherwise apply it to
-- the temperature and sales-ready flags whatever the source). An opt-out still applies. The result says which case it
-- was ('web_trust'). search_path = public (pg_temp last) like the D-055 wrappers: crm_find_lead and w2_crm_owned are
-- shared SQL functions that resolve their tables through it; every name here is still qualified.
create or replace function public.web_lead_intake(p jsonb, p_verified_email text)
returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_phone text := public.crm_norm_phone(p->>'phone');
  v_email text := lower(btrim(coalesce(p_verified_email, '')));
  v_lead public.student_leads;
  v_why text;
  v_p jsonb := p;
begin
  if v_phone is not null and length(v_phone) >= 10 then
    v_lead := public.crm_find_lead(v_phone);
  end if;
  if v_lead.id is not null then
    v_why := case
      when v_email = '' then 'email_not_verified'
      when coalesce(v_lead.email_confirmed, false) and lower(btrim(coalesce(v_lead.email_id, ''))) <> v_email then 'other_confirmed_email'
      when v_lead.enrollment_status is not null then 'enrolled'
      when coalesce(public.w2_crm_owned(v_phone), false) then 'crm_owned'
    end;
  end if;
  if v_why is not null then
    v_p := v_p || jsonb_build_object('source_system', 'web_agent_unverified');
    if v_lead.lead_status is not null and jsonb_typeof(v_p->'lead') = 'object' then
      v_p := jsonb_set(v_p, '{lead}', (v_p->'lead') - 'classification' - 'lead_status');
    end if;
  end if;
  return public.lead_intake(v_p) || jsonb_build_object('web_trust', coalesce(v_why, 'trusted'));
end $$;

create or replace function public.web_gate_complete(p_attempt uuid, p_ua_hash text, p_method text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_a public.web_gate_attempts; v_s public.web_students; v_sid uuid; v_ct public.web_consent_texts; v_res jsonb; v_key text;
begin
  select * into v_a from public.web_gate_attempts where id = p_attempt for update;
  insert into public.web_students as s (email_norm, phone_e164, full_name, email_verified_at, last_seen_at)
  values (v_a.email_norm, v_a.phone_e164, v_a.full_name, now(), now())
  on conflict (email_norm) do update set phone_e164 = coalesce(excluded.phone_e164, s.phone_e164),
    full_name = coalesce(excluded.full_name, s.full_name), email_verified_at = coalesce(s.email_verified_at, now()),
    last_seen_at = now(), deleted_at = null
  returning * into v_s;
  insert into public.web_email_verifications (student_id, email_norm, attempt_id, method) values (v_s.id, v_a.email_norm, v_a.id, p_method);
  insert into public.web_student_sessions (student_id, expires_at, last_seen_at, ua_hash) values (v_s.id, now() + interval '90 days', now(), p_ua_hash)
  returning id into v_sid;
  update public.web_gate_attempts set verified_at = now(), student_id = v_s.id where id = v_a.id returning * into v_a;

  if v_a.consent_version is not null then
    select * into v_ct from public.web_consent_texts where version = v_a.consent_version;
    insert into public.web_consents (student_id, version, purposes, surface, ip_hash) values (v_s.id, v_ct.version, v_ct.purposes, v_a.surface, v_a.ip_hash);
    if v_a.consent_marketing then
      insert into public.web_consents (student_id, version, purposes, surface, ip_hash)
      select v_s.id, version, purposes, v_a.surface, v_a.ip_hash from public.web_consent_texts where channel = 'marketing' and active limit 1;
    end if;
  end if;

  -- Lead: exactly once per attempt (web_lead_submissions), through the website's wrapper of lead_intake (D-009, web14).
  if v_a.phone_e164 is not null and v_a.surface <> 'signin' then
    v_key := 'web:verify:' || v_a.id::text;
    insert into public.web_lead_submissions (idempotency_key, student_id, kind) values (v_key, v_s.id, v_a.surface || '.verified')
    on conflict do nothing;
    if found then
      v_res := public.web_lead_intake(public.web_lead_payload(v_a, v_sid, 'lead.verified') || jsonb_build_object('idempotency_key', v_key), v_a.email_norm);
      update public.web_lead_submissions set result = v_res where idempotency_key = v_key;
      update public.web_gate_attempts set lead_id = (v_res->>'lead_id')::bigint, lead_action = v_res->>'action' where id = v_a.id;
      update public.web_students set lead_id = coalesce(lead_id, (v_res->>'lead_id')::bigint) where id = v_s.id;
      update public.web_consents set lead_id = (v_res->>'lead_id')::bigint where student_id = v_s.id and lead_id is null;
      perform public.web_outbox_enqueue('capi_lead', 'capi_lead:' || v_a.id::text,
        jsonb_build_object('event_id', v_a.id, 'email', v_a.email_norm, 'phone', v_a.phone_e164, 'surface', v_a.surface,
                           'attribution', v_a.attribution, 'marketing_consent', v_a.consent_marketing));
    end if;
  end if;
  return jsonb_build_object('ok', true, 'status', 'verified', 'student_id', v_s.id, 'session_id', v_sid,
    'lead_id', coalesce((v_res->>'lead_id')::bigint, v_s.lead_id), 'lead_action', v_res->>'action', 'email', v_s.email_norm);
end $$;

create or replace function public.web_application_save_step(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_app public.web_applications; v_a public.web_gate_attempts; v_step int := (p->>'step')::int; v_data jsonb := coalesce(p->'data', '{}');
  v_lead jsonb := case when jsonb_typeof(p->'lead') = 'object' then p->'lead' else '{}' end; v_key text; v_res jsonb;
begin
  select * into v_app from public.web_applications where attempt_id = (p->>'attempt_id')::uuid for update;
  if v_app.id is null then return jsonb_build_object('ok', false, 'reason', 'no_application'); end if;
  -- Only the verified student who owns the application (from the signed session) may change it.
  if v_app.student_id is distinct from (p->>'student_id')::uuid then return jsonb_build_object('ok', false, 'reason', 'not_owner'); end if;
  select * into v_a from public.web_gate_attempts where id = v_app.attempt_id;
  update public.web_applications set steps = jsonb_set(steps, array[v_step::text], v_data), updated_at = now(),
    status = case when status = 'submitted' then status else 'step_' || least(4, v_step)::text end,
    preferred_offering_ids = case when p ? 'preferred_offering_ids' then array(select jsonb_array_elements_text(p->'preferred_offering_ids')::bigint) else preferred_offering_ids end,
    eligibility_note = coalesce(p->>'eligibility_note', eligibility_note)
  where id = v_app.id;
  -- Enrich the same lead (approved update path: lead_intake through web_lead_intake; first-touch fields never change).
  if v_a.phone_e164 is not null and v_lead <> '{}' then
    v_key := 'web:step:' || v_app.id::text || ':' || v_step || ':' || md5(v_lead::text);
    insert into public.web_lead_submissions (idempotency_key, student_id, kind) values (v_key, v_app.student_id, 'application.step_' || v_step)
    on conflict do nothing;
    if found then
      v_res := public.web_lead_intake(jsonb_build_object('phone', v_a.phone_e164, 'source_system', 'web_agent', 'event_type', 'lead.updated',
        'lead', v_lead, 'idempotency_key', v_key, 'is_test', v_a.is_test), v_a.email_norm);
      update public.web_lead_submissions set result = v_res where idempotency_key = v_key;
    end if;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.web_application_submit(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_app public.web_applications; v_a public.web_gate_attempts; v_key text; v_res jsonb;
begin
  select * into v_app from public.web_applications where attempt_id = (p->>'attempt_id')::uuid for update;
  if v_app.id is null then return jsonb_build_object('ok', false, 'reason', 'no_application'); end if;
  if v_app.student_id is distinct from (p->>'student_id')::uuid then return jsonb_build_object('ok', false, 'reason', 'not_owner'); end if;
  if v_app.status = 'submitted' then return jsonb_build_object('ok', true, 'reference', v_app.reference, 'status', 'already_submitted'); end if;
  select * into v_a from public.web_gate_attempts where id = v_app.attempt_id;
  update public.web_applications set status = 'submitted', submitted_at = now(), updated_at = now(),
    steps = steps || jsonb_build_object('final', coalesce(p->'data', '{}')) where id = v_app.id;
  v_key := 'web:submit:' || v_app.id::text;
  insert into public.web_lead_submissions (idempotency_key, student_id, kind) values (v_key, v_app.student_id, v_app.kind || '.submitted')
  on conflict do nothing;
  if found and v_a.phone_e164 is not null then
    v_res := public.web_lead_intake(jsonb_build_object('phone', v_a.phone_e164, 'source_system', 'web_agent',
      'event_type', case when v_app.kind = 'application' then 'lead.application_requested' else 'lead.enquiry' end,
      'lead', jsonb_strip_nulls(case when jsonb_typeof(p->'lead') = 'object' then p->'lead' else '{}' end || jsonb_build_object('last_intent', case when v_app.kind = 'application' then 'wants_to_apply' else 'enquiry' end)),
      'idempotency_key', v_key, 'is_test', v_a.is_test), v_a.email_norm);
    update public.web_lead_submissions set result = v_res where idempotency_key = v_key;
    perform public.web_outbox_enqueue('email_confirmation', 'email_confirmation:' || v_app.id::text,
      jsonb_build_object('kind', v_app.kind, 'reference', v_app.reference, 'email', v_a.email_norm, 'name', v_a.full_name, 'context', v_app.context));
    if v_app.kind = 'application' then
      perform public.web_outbox_enqueue('capi_submit_application', 'capi_submit:' || v_app.id::text,
        -- event_id = the application reference, the same id the browser Pixel sends (de-duplication, D-047)
        jsonb_build_object('event_id', v_app.reference, 'email', v_a.email_norm, 'phone', v_a.phone_e164, 'attribution', v_a.attribution,
                           'marketing_consent', v_a.consent_marketing));
    end if;
  end if;
  return jsonb_build_object('ok', true, 'reference', v_app.reference, 'status', 'submitted');
end $$;

-- Withdraw consent: recorded in the ledger; withdrawing sales/partner consent opts the lead out of contact
-- (lead_intake can only turn is_opted_out on). Marketing-only withdrawal does not opt out of the enquiry itself.
create or replace function public.web_consent_withdraw(p_student uuid, p_purposes text[])
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare s public.web_students; v_res jsonb;
begin
  select * into s from public.web_students where id = p_student;
  if s.id is null then return jsonb_build_object('ok', false); end if;
  update public.web_consents set withdrawn_at = now() where student_id = p_student and withdrawn_at is null and purposes && p_purposes;
  if p_purposes && array['sales', 'partner_share'] and s.phone_e164 is not null then
    v_res := public.web_lead_intake(jsonb_build_object('phone', s.phone_e164, 'source_system', 'web_agent', 'event_type', 'lead.opted_out',
      'lead', jsonb_build_object('is_opted_out', true), 'idempotency_key', 'web:optout:' || p_student::text || ':' || extract(epoch from now())::bigint), s.email_norm);
  end if;
  insert into public.web_audit_log (action, entity, entity_id, after) values ('student.consent_withdrawn', 'web_students', p_student::text, to_jsonb(p_purposes));
  return jsonb_build_object('ok', true, 'lead', v_res);
end $$;

-- Optional (setting push_unverified_gate_leads, default off): gate attempts never verified are pushed to lead_intake as
-- unverified after N minutes. Called by the outbox worker's cron. No verified email: an existing lead is never overwritten.
create or replace function public.web_push_unverified()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_on boolean; v_min int; a public.web_gate_attempts; n int := 0; v_key text; v_res jsonb;
begin
  select coalesce((select value = 'true'::jsonb from public.web_settings where key = 'push_unverified_gate_leads'), false) into v_on;
  if not v_on then return jsonb_build_object('enabled', false); end if;
  select coalesce((select (value #>> '{}')::int from public.web_settings where key = 'push_unverified_after_minutes'), 60) into v_min;
  for a in select * from public.web_gate_attempts where verified_at is null and pushed_unverified_at is null and phone_e164 is not null
             and junk_score < 50 and submitted_at < now() - make_interval(mins => v_min) order by submitted_at limit 50 for update skip locked loop
    v_key := 'web:unverified:' || a.id::text;
    insert into public.web_lead_submissions (idempotency_key, kind) values (v_key, a.surface || '.unverified') on conflict do nothing;
    if found then
      v_res := public.web_lead_intake(public.web_lead_payload(a, null, 'lead.unverified',
        jsonb_build_object('is_email_confirmed', false, 'source_detail', a.surface || '_unverified')) || jsonb_build_object('idempotency_key', v_key), null);
      update public.web_lead_submissions set result = v_res where idempotency_key = v_key;
      update public.web_gate_attempts set pushed_unverified_at = now(), lead_id = (v_res->>'lead_id')::bigint where id = a.id;
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('enabled', true, 'pushed', n);
end $$;

create or replace function public.web_callback_request(p_student uuid, p_session uuid, p_date date, p_slot text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare st public.web_students; v_id bigint; v_res jsonb; v_label text;
begin
  select * into st from public.web_students where id = p_student and deleted_at is null;
  if st.id is null or st.phone_e164 is null then return jsonb_build_object('ok', false, 'reason', 'no_phone'); end if;
  if p_date < (now() at time zone 'Asia/Kolkata')::date or p_date > (now() at time zone 'Asia/Kolkata')::date + 14 then
    return jsonb_build_object('ok', false, 'reason', 'bad_date');
  end if;
  v_label := 'Callback ' || to_char(p_date, 'Dy DD Mon') || ', ' || case p_slot when 'morning' then 'morning (9am–12pm)' when 'afternoon' then 'afternoon (12–4pm)' else 'evening (4–8pm)' end;
  -- The same slot again: already booked, nothing new reaches the lead. At most 3 requests a day per student.
  select id into v_id from public.web_callback_requests where student_id = p_student and slot_date = p_date and slot = p_slot;
  if v_id is not null then return jsonb_build_object('ok', true, 'id', v_id, 'label', v_label, 'duplicate', true); end if;
  if (select count(*) from public.web_callback_requests where student_id = p_student and created_at > now() - interval '1 day') >= 3 then
    return jsonb_build_object('ok', false, 'reason', 'too_many');
  end if;
  insert into public.web_callback_requests (student_id, session_id, lead_id, slot_date, slot)
  values (p_student, p_session, st.lead_id, p_date, p_slot)
  on conflict (student_id, slot_date, slot) do nothing returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', true, 'label', v_label, 'duplicate', true); end if;
  v_label := 'Callback ' || to_char(p_date, 'Dy DD Mon') || ', ' || case p_slot when 'morning' then 'morning (9am–12pm)' when 'afternoon' then 'afternoon (12–4pm)' else 'evening (4–8pm)' end;
  v_res := public.web_lead_intake(jsonb_build_object('phone', st.phone_e164, 'source_system', 'web_agent', 'event_type', 'lead.updated',
    'idempotency_key', 'web:callback:' || v_id, 'lead', jsonb_build_object('preferred_call_time', v_label, 'last_intent', 'asks_human')), st.email_norm);
  return jsonb_build_object('ok', true, 'id', v_id, 'label', v_label, 'lead', v_res);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Daily Witty ceiling: one counter row per India day, written by web_advisor_turn_commit (retries are not counted).
create table if not exists public.web_advisor_daily (
  day date primary key,                          -- India date (Asia/Kolkata)
  turns integer not null default 0,
  cost_usd numeric(12, 5) not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.web_advisor_daily enable row level security;
revoke all on public.web_advisor_daily from anon, authenticated, public;

create or replace function public.web_advisor_turn_commit(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  s public.web_advisor_sessions; st public.web_students; v_turn int; v_in bigint; v_out bigint; v_res jsonb; v_key text;
  v_phone text; v_lead jsonb := case when jsonb_typeof(p->'lead') = 'object' then p->'lead' else '{}' end;
  u jsonb := coalesce(p->'usage', '{}');
begin
  select * into s from public.web_advisor_sessions where id = (p->>'session_id')::uuid for update;
  if s.id is null or s.student_id is distinct from (p->>'student_id')::uuid then return jsonb_build_object('ok', false, 'reason', 'not_owner'); end if;
  select * into st from public.web_students where id = s.student_id;
  v_turn := s.turns + 1;
  v_phone := ltrim(coalesce(st.phone_e164, ''), '+');

  insert into public.web_advisor_messages (phone, direction, kind, message_id, run_id, content, sent, meta, session_id)
  values (v_phone, 'in', 'chat', p->>'message_id', p->>'run_id', left(p->>'student_message', 4000), true,
          jsonb_build_object('client_id', p->>'message_id'), s.id)
  on conflict (session_id, message_id) where direction = 'in' do nothing
  returning id into v_in;
  if v_in is null then
    return jsonb_build_object('ok', true, 'status', 'duplicate');
  end if;
  insert into public.web_advisor_messages (phone, direction, kind, run_id, content, answer_mode, reply_source, model, prompt_tokens,
    cached_tokens, output_tokens, latency_ms, verify_errors, sent, meta, session_id)
  values (v_phone, 'out', 'reply', p->>'run_id', p->>'reply', p->>'answer_mode', p->>'reply_source', p->>'model',
    (u->>'prompt_tokens')::int, (u->>'cached_tokens')::int, (u->>'output_tokens')::int, (p->>'latency_ms')::int,
    p->'verify_errors', true, coalesce(p->'meta', '{}'), s.id)
  returning id into v_out;

  update public.web_advisor_sessions set
    state = coalesce(p->'state', state), turns = v_turn, last_turn_at = now(),
    classification = coalesce(p->>'classification', classification), readiness = coalesce(p->>'readiness', readiness),
    eligibility = coalesce(p->>'eligibility', eligibility), phase = coalesce(p->>'phase', phase),
    language = coalesce(p->>'language', language), agent_core_version = coalesce(p->>'agent_core_version', agent_core_version),
    prompt_tokens = prompt_tokens + coalesce((u->>'prompt_tokens')::int, 0),
    cached_tokens = cached_tokens + coalesce((u->>'cached_tokens')::int, 0),
    output_tokens = output_tokens + coalesce((u->>'output_tokens')::int, 0),
    cost_usd = cost_usd + coalesce((u->>'cost_usd')::numeric, 0),
    escalated_at = case when (p->>'escalate')::boolean then coalesce(escalated_at, now()) else escalated_at end
  where id = s.id;

  -- web14: the site-wide daily counter (turns and spend per India day)
  insert into public.web_advisor_daily as d (day, turns, cost_usd)
  values ((now() at time zone 'Asia/Kolkata')::date, 1, coalesce((u->>'cost_usd')::numeric, 0))
  on conflict (day) do update set turns = d.turns + 1, cost_usd = d.cost_usd + excluded.cost_usd, updated_at = now();

  -- Lead: same key set as w2_crm_payload, source_system web_agent (D-009), web channel stamps (first-touch).
  if st.phone_e164 is not null and coalesce(p->>'event_type', '') <> '' then
    v_key := 'web:' || s.id::text || ':' || v_turn;
    insert into public.web_lead_submissions (idempotency_key, student_id, kind) values (v_key, s.student_id, 'advisor.' || (p->>'event_type'))
    on conflict do nothing;
    if found then
      v_res := public.web_lead_intake(jsonb_build_object('phone', st.phone_e164, 'source_system', 'web_agent', 'event_type', p->>'event_type',
        'idempotency_key', v_key, 'is_test', s.is_test, 'occurred_at', now(),
        'lead', jsonb_strip_nulls(v_lead || jsonb_build_object('web_session_id', s.id::text, 'channel', 'web', 'first_agent_channel', 'web',
          'source', 'website_agent', 'last_agent_message_at', now()))), st.email_norm);
      update public.web_lead_submissions set result = v_res where idempotency_key = v_key;
      update public.web_advisor_sessions set lead_id = coalesce(lead_id, (v_res->>'lead_id')::bigint) where id = s.id;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'turn', v_turn, 'in_id', v_in, 'out_id', v_out, 'lead', v_res);
end $$;

-- Today's Witty usage against the ceiling, and the seconds until the India-midnight reset.
create or replace function public.web_advisor_daily_check()
returns jsonb language sql stable security definer set search_path = '' as $$
  with cap as (
    select coalesce((select s.value from public.web_settings s where s.key = 'web_advisor_daily_cap' and jsonb_typeof(s.value) = 'object'), '{}'::jsonb) as v
  ), lim as (
    select case when jsonb_typeof(v->'turns') = 'number' and (v->>'turns')::numeric >= 0 then (v->>'turns')::numeric else 2000 end as max_turns,
           case when jsonb_typeof(v->'cost_usd') = 'number' and (v->>'cost_usd')::numeric >= 0 then (v->>'cost_usd')::numeric else 25 end as max_cost
      from cap
  ), today as (
    select coalesce(d.turns, 0) as turns, coalesce(d.cost_usd, 0) as cost
      from (select 1) one left join public.web_advisor_daily d on d.day = (now() at time zone 'Asia/Kolkata')::date
  )
  select jsonb_build_object('ok', t.turns < l.max_turns and t.cost < l.max_cost, 'turns', t.turns, 'cost_usd', t.cost,
    'max_turns', l.max_turns, 'max_cost_usd', l.max_cost,
    'reset_seconds', greatest(1, ceil(extract(epoch from
      ((((now() at time zone 'Asia/Kolkata')::date + 1)::timestamp at time zone 'Asia/Kolkata') - now())))::int))
  from today t, lim l
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Outbox worker only when a job is due; the catalogue poll with a statement timeout.
-- Same "due" rule as web_outbox_claim(), plus the optional push of unverified attempts that the worker also runs.
create or replace function public.web_outbox_due()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.web_outbox o
                  where (o.status = 'pending' or (o.status = 'processing' and o.locked_until < now()))
                    and o.next_attempt_at <= now())
      or coalesce((select s.value = 'true'::jsonb from public.web_settings s where s.key = 'push_unverified_gate_leads'), false)
$$;

-- What the pg_cron job web_outbox_worker runs every minute: the HTTP call only when there is work.
create or replace function public.web_outbox_tick()
returns bigint language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.web_outbox_due() then return null; end if;
  return public.web_job_call('/api/internal/outbox');
end $$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'web_outbox_worker') then
      perform cron.schedule('web_outbox_worker', '* * * * *', $j$select public.web_outbox_tick()$j$);
    end if;
    if exists (select 1 from cron.job where jobname = 'web_catalog_poll') then
      perform cron.schedule('web_catalog_poll', '* * * * *', $j$set statement_timeout = '30s'; select public.web_catalog_poll()$j$);
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Admin: the ceilings and the job settings are super-admin only (the admin save path already keeps the rest).
create or replace function public.web_admin_setting(p_key text, p_value jsonb, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.web_admin_role_ok(p_role, case when p_key in ('web_advisor_enabled', 'require_phone_otp', 'push_unverified_gate_leads',
      'push_unverified_after_minutes', 'document_upload_enabled', 'lead_writer', 'web_advisor_models', 'web_advisor_budget',
      'code_send_hourly_cap', 'web_advisor_daily_cap', 'internal_base_url', 'transcript_target') then 'super_admin' else 'content_editor' end) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  -- web_settings_set keeps the history and writes the audit row.
  perform public.web_settings_set(p_key, p_value, p_actor, p_actor_email);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Grants: service role only (Supabase grants new public functions to the API roles by default).
do $$
declare f text;
begin
  foreach f in array array[
    'public.web_code_cap_reached()', 'public.web_gate_start(jsonb)', 'public.web_gate_resend(uuid, text)',
    'public.web_lead_intake(jsonb, text)', 'public.web_gate_complete(uuid, text, text)', 'public.web_application_save_step(jsonb)',
    'public.web_application_submit(jsonb)', 'public.web_consent_withdraw(uuid, text[])', 'public.web_push_unverified()',
    'public.web_callback_request(uuid, uuid, date, text)', 'public.web_advisor_turn_commit(jsonb)', 'public.web_advisor_daily_check()',
    'public.web_outbox_due()', 'public.web_outbox_tick()', 'public.web_admin_setting(text, jsonb, uuid, text, text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
