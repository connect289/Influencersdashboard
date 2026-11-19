-- Rollback of web23: the three functions return to their definitions before web23 (copied from production on
-- 19 Nov 2026). The two columns, the 'guardian' consent channel and its consent text stay: consents already recorded
-- point at that text, and the columns are harmless without the functions that fill them. Remove the age field and the
-- checkbox from the website's forms in the same change, or under-18 enquiries are accepted without the consent.
CREATE OR REPLACE FUNCTION public.web_gate_start(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_email text := lower(btrim(p->>'email'));
  v_attempt public.web_gate_attempts;
  v_recent int;
  v_screen jsonb;
  v_cap text;
begin
  v_screen := public.web_email_screen(v_email, p->>'phone', p->>'ip_hash');
  if not (v_screen->>'ok')::boolean then return v_screen; end if;
  -- web16: per inbox (canonical address), not per spelling
  select count(*) into v_recent from public.web_verification_codes
   where public.web_email_canonical(target) = public.web_email_canonical(v_email) and created_at > now() - interval '1 hour';
  if v_recent >= 5 then return jsonb_build_object('ok', false, 'reason', 'too_many_codes'); end if;
  -- web14/web16: site-wide hourly and daily ceilings
  v_cap := public.web_code_cap_state();
  if v_cap is not null then
    perform public.web_code_cap_hit(v_cap);
    return jsonb_build_object('ok', false, 'reason', 'site_busy', 'cap', v_cap);
  end if;

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
end $function$;

CREATE OR REPLACE FUNCTION public.web_gate_start_trusted(p jsonb, p_student uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; s public.web_students;
begin
  select * into s from public.web_students where id = p_student and deleted_at is null;
  if s.id is null or s.email_norm <> lower(btrim(p->>'email')) then return jsonb_build_object('ok', false, 'reason', 'session_mismatch'); end if;
  if s.phone_e164 is not null and nullif(p->>'phone', '') is not null and p->>'phone' <> s.phone_e164 then
    return jsonb_build_object('ok', false, 'reason', 'phone_changed');
  end if;
  insert into public.web_gate_attempts (idempotency_key, surface, context, full_name, email_norm, phone_e164, consent_version, consent_marketing,
    attribution, junk_score, junk_reasons, ip_hash, device_hash, turnstile_ok, is_test)
  values (p->>'idempotency_key', p->>'surface', coalesce(p->'context', '{}'), p->>'name', s.email_norm, p->>'phone', p->>'consent_version',
    coalesce((p->>'marketing')::boolean, false), coalesce(p->'attribution', '{}'), coalesce((p->>'junk_score')::int, 0),
    coalesce(array(select jsonb_array_elements_text(p->'junk_reasons')), '{}'), p->>'ip_hash', p->>'device_hash', (p->>'turnstile_ok')::boolean,
    coalesce((p->>'is_test')::boolean, false))
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.web_gate_attempts where idempotency_key = p->>'idempotency_key';
    return jsonb_build_object('ok', true, 'status', 'already_verified', 'attempt_id', v_id);
  end if;
  return public.web_gate_complete(v_id, null, 'session') || jsonb_build_object('attempt_id', v_id);
end $function$;

CREATE OR REPLACE FUNCTION public.web_gate_complete(p_attempt uuid, p_ua_hash text, p_method text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;
