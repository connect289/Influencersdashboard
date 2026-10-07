-- M31d: Addendum 3 readiness (docs/B2B_CRM_ADDENDUM_3.md PART 2, PART 3 R5/R7/R9 and the Definitions, Amendment 1).
--   is_chat_lead       (m7a, replaced)  Witty and website-agent chats, decided at their hand-off point; never a lead the
--                                       B2C CRM created
--   spam_check         (new)            R5 spam: a phone Witty has blocked, a disposable email domain, or a burst of leads
--                                       from one IP address or device in the hour before the lead was created
--   lead_class         (m17a, replaced) R5 junk / programme mismatch and R7/R9 'qualified' (Witty: its HOT/WARM/COLD label;
--                                       other sources: course plus a valid contact), with the Admin's Pass to CRM override
--   lead_readiness     (m17a, replaced) the PART 2 hand-off point with Amendment 1's 18 hours for unqualified Witty leads,
--                                       the wait for a partner-sharing consent answer, and when to look again
--   lead_wait_set      (new)            stores a wait in b2b.lead_waits (also for m31e, m31f and m31k)
--   route_ready_leads  (m17a, replaced) the minute sweep: waits stored outside the window and invalidated by any change to the
--                                       lead, a 90-day window on updated_at, the Not passed exclusion kept, a 2-second time
--                                       box, lock_timeout 2 s, one lead per exception block; stops only when the routing
--                                       switch is off or the engine is disabled (the retired kill switch is not read)
-- Return shapes are supersets of m17a's, so the m24b route_decide keeps working until m31f replaces it (its outcomes
-- differ; routing stays off for the whole series).
-- Witty data (public.w2_inbox, w2_messages, w2_blocks) is read only, through the m31b helpers. Nothing here writes
-- student_leads, Witty or the catalogue; route_ready_leads writes b2b.lead_waits, b2b.review_flags and b2b.events and calls
-- route_decide.
-- Cron 'b2b-route-ready-leads' now runs route_ready_leads(25). An existing job is changed in place (cron.alter_job), so a
-- job paused for the promotion window stays paused.

-- Leads the sweep retries whatever their age (critic B17).
create index if not exists lead_waits_retry_idx on b2b.lead_waits (lead_id) where why in ('error', 'reroute_error', 'locked');

-- ---------- which leads are decided at a chat hand-off point (PART 2) ----------
/* A Witty or website-agent chat: the source or channel says so, the website agent's session or the first agent channel
   is set, or Witty or the website agent recorded a touchpoint for the lead. Never a lead created in the B2C CRM
   (engine.b2c_sources), which is decided at intake (R6). */
create or replace function b2b.is_chat_lead(l public.student_leads)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select case
    when lower(coalesce(l.lead_source, '')) in (select lower(x) from jsonb_array_elements_text(coalesce(
           (select s.value -> 'b2c_sources' from b2b.settings s where s.key = 'engine' and jsonb_typeof(s.value -> 'b2c_sources') = 'array'),
           '["b2c_created","b2c_whatsapp"]'::jsonb)) x) then false
    else lower(coalesce(l.lead_source, '')) ~ '(whatsapp|witty|website_agent|web_agent)'
         or lower(coalesce(l.channel, '')) = 'whatsapp'
         or nullif(trim(coalesce(l.web_session_id, '')), '') is not null
         or nullif(trim(coalesce(l.first_agent_channel, '')), '') is not null
         or exists (select 1 from public.touchpoints t where t.lead_id = l.id and t.source_system in ('web_agent', 'witty')) end;
$fn$;

-- ---------- R5 spam ----------
/* 'spam:witty_block'          the phone is blocked by Witty now (engine.spam.use_witty_blocks; public.w2_blocks read
                                directly, critic A1)
   'spam:disposable_email'     the email domain (or a subdomain of it) is in engine.spam.disposable_email_domains
   'spam:ip_burst'             at least N other non-test leads with the same ip_address were created in the hour before
                               this lead (so this one is lead N+1 or later); N = engine.spam.max_leads_per_ip_hour (5)
   'spam:fingerprint_burst'    the same with the device fingerprint; N = engine.spam.max_leads_per_fingerprint_hour (5)
   null otherwise, and always for test leads. Only leads created before this one count (same created_at: lower id), so the
   answer does not change with the time of the decision (critic B14). N = 0 turns a burst rule off. */
create or replace function b2b.spam_check(l public.student_leads)
returns text language plpgsql stable security definer set search_path = '' as $fn$
declare
  sp jsonb := coalesce((select s.value -> 'spam' from b2b.settings s where s.key = 'engine' and jsonb_typeof(s.value -> 'spam') = 'object'), '{}');
  v_digits text := regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g');
  v_dom text := substring(lower(trim(coalesce(l.email_id, ''))) from '@([^@]+)$');
  v_ip text := nullif(trim(coalesce(l.ip_address, '')), '');
  v_fp text := nullif(trim(coalesce(l.fingerprint, '')), '');
  v_n int;
begin
  if coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number) then return null; end if;

  if coalesce(case when lower(sp ->> 'use_witty_blocks') in ('true', 'false') then (sp ->> 'use_witty_blocks')::boolean end, true)
     and length(v_digits) >= 10 and b2b.witty_blocked(v_digits) then
    return 'spam:witty_block';
  end if;

  v_dom := trim(trailing '.' from coalesce(v_dom, ''));
  if v_dom <> '' and exists (
       select 1 from jsonb_array_elements_text(case when jsonb_typeof(sp -> 'disposable_email_domains') = 'array'
                                                    then sp -> 'disposable_email_domains' else '[]'::jsonb end) d
        where lower(trim(d)) <> '' and (v_dom = lower(trim(d)) or v_dom like '%.' || lower(trim(d)))) then
    return 'spam:disposable_email';
  end if;

  if l.created_at is null then return null; end if;
  v_n := case when (sp ->> 'max_leads_per_ip_hour') ~ '^[0-9]+$' then (sp ->> 'max_leads_per_ip_hour')::int end;
  if v_ip is not null and coalesce(v_n, 0) > 0
     and (select count(*) from (select 1 from public.student_leads x
                                 where x.created_at >= l.created_at - interval '1 hour' and x.created_at <= l.created_at
                                   and (x.created_at < l.created_at or x.id < l.id)
                                   and x.ip_address = l.ip_address and x.id <> l.id
                                   and not coalesce(x.is_test, false) and not b2b.is_test_phone(x.whatsapp_number)
                                 limit v_n) q) >= v_n then
    return 'spam:ip_burst';
  end if;
  v_n := case when (sp ->> 'max_leads_per_fingerprint_hour') ~ '^[0-9]+$' then (sp ->> 'max_leads_per_fingerprint_hour')::int end;
  if v_fp is not null and coalesce(v_n, 0) > 0
     and (select count(*) from (select 1 from public.student_leads x
                                 where x.created_at >= l.created_at - interval '1 hour' and x.created_at <= l.created_at
                                   and (x.created_at < l.created_at or x.id < l.id)
                                   and x.fingerprint = l.fingerprint and x.id <> l.id
                                   and not coalesce(x.is_test, false) and not b2b.is_test_phone(x.whatsapp_number)
                                 limit v_n) q) >= v_n then
    return 'spam:fingerprint_burst';
  end if;
  return null;
end $fn$;

-- ---------- R5 / R7 / R9 classification ----------
/* {class junk|mismatch|qualified|unqualified, reason, missing [codes], detail, override, basis, witty}.
   override: the Admin passed the lead from Not passed (not_passed.passed_at and override set) and its fingerprint has not
   changed since; the lead is then judged on its fields only (no Witty label, no catalogue check, no junk class).
   Without override, first match wins:
     lead_status JUNK                         junk / junk                       basis label
     invalid or blocklisted phone (not test)  junk / invalid_phone|blocked_phone basis phone
     spam_check                               junk / junk, detail spam:<rule>   basis spam
     lead_status PROGRAM_MISMATCH             mismatch / program_mismatch       basis label
     a course is stated (primary or a live secondary interest) and none is in the catalogue (all sources, critic B5)
                                              mismatch / program_mismatch, detail course_not_in_catalogue, basis catalogue
   Witty leads (b2b.is_witty_lead), without override:
     qualified only when lead_status is HOT, WARM or COLD (basis witty_label); otherwise unqualified, missing no_name,
     no_email, no_course for absent fields, or witty_unconfirmed when all three are present. Exception (basis
     completed_by_b2c): an open qualification-nurture hold, name, email, course and programme level all present, and a
     b2c.lead_updated or lead.edited event after the hand-off that changed the name, email, course or programme level.
   Other leads, and any lead under override (basis fields): missing no_course; no_valid_contact (an invalid or blocked
     phone, or spam; reachable only under override); phone_not_verified when phone_verified_at is null and the lead_source
     is in engine.require_verified_phone_sources, or the lead came through the website agent (a web_agent touchpoint or a
     web session) while that list names website_agent or web_agent.
   reason: null when qualified, 'not_qualified' when unqualified. There is no score gate and no university is needed. */
create or replace function b2b.lead_class(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select s.value from b2b.settings s where s.key = 'engine'), '{}');
  v_test boolean := coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number);
  v_status text := upper(coalesce(nullif(trim(l.lead_status), ''), ''));
  v_course text := coalesce(nullif(trim(l.interested_course), ''), nullif(trim(l.field_of_interest), ''));
  v_phone text := case when v_test then null else b2b.phone_problem(l.whatsapp_number) end;
  v_witty boolean := b2b.is_witty_lead(l);
  v_override boolean;
  v_has_course boolean;
  v_spam text;
  v_srcs text[];
  v_base jsonb;
  h jsonb;
  v_h_at timestamptz;
  m text[] := '{}';
begin
  v_override := exists (select 1 from b2b.not_passed np
                         where np.lead_id = l.id and np.passed_at is not null and np.override and np.fingerprint = b2b.np_fingerprint(l));
  v_has_course := v_course is not null
                  or exists (select 1 from b2b.lead_interests i
                              where i.lead_id = l.id and i.removed_at is null and nullif(trim(coalesce(i.course_key, i.course_text, '')), '') is not null);
  v_base := jsonb_build_object('override', v_override, 'witty', v_witty, 'detail', null);

  if not v_override then
    if v_status = 'JUNK' then
      return v_base || jsonb_build_object('class', 'junk', 'reason', 'junk', 'missing', '[]'::jsonb, 'basis', 'label');
    end if;
    if v_phone is not null then
      return v_base || jsonb_build_object('class', 'junk', 'reason', v_phone, 'missing', '[]'::jsonb, 'basis', 'phone');
    end if;
    v_spam := b2b.spam_check(l);
    if v_spam is not null then
      return v_base || jsonb_build_object('class', 'junk', 'reason', 'junk', 'missing', '[]'::jsonb, 'detail', v_spam, 'basis', 'spam');
    end if;
    if v_status = 'PROGRAM_MISMATCH' then
      return v_base || jsonb_build_object('class', 'mismatch', 'reason', 'program_mismatch', 'missing', '[]'::jsonb, 'basis', 'label');
    end if;
    if v_has_course and not b2b.course_known(l) then
      return v_base || jsonb_build_object('class', 'mismatch', 'reason', 'program_mismatch', 'missing', '[]'::jsonb,
                                          'detail', 'course_not_in_catalogue', 'basis', 'catalogue');
    end if;

    -- R9: a Witty lead is qualified by Witty's label
    if v_witty then
      if v_status in ('HOT', 'WARM', 'COLD') then
        return v_base || jsonb_build_object('class', 'qualified', 'reason', null, 'missing', '[]'::jsonb, 'basis', 'witty_label');
      end if;
      if nullif(trim(coalesce(l.student_name, '')), '') is null then m := array_append(m, 'no_name'); end if;
      if nullif(trim(coalesce(l.email_id, '')), '') is null then m := array_append(m, 'no_email'); end if;
      if not v_has_course then m := array_append(m, 'no_course'); end if;
      if cardinality(m) = 0 then
        -- R7 re-decision: the B2C CRM or the Admin completed the details while B2C nurtures the lead (D11)
        if nullif(trim(coalesce(l.program_level, '')), '') is not null then
          h := b2b.b2c_hold(l);
          if h ->> 'kind' = 'qualification_nurture' and coalesce((h ->> 'open')::boolean, false) then
            select a.created_at into v_h_at from b2b.allocations a where a.id = (h ->> 'allocation_id')::bigint;
            if v_h_at is not null and exists (
                 select 1 from b2b.events ev
                  where ev.lead_id = l.id and ev.type in ('b2c.lead_updated', 'lead.edited') and ev.occurred_at > v_h_at
                    and ((ev.type = 'b2c.lead_updated' and jsonb_typeof(ev.payload -> 'changes') = 'object'
                          and (ev.payload -> 'changes') ?| array['name', 'email', 'course', 'programme_level', 'field_of_interest', 'other_courses',
                                                                  'student_name', 'email_id', 'interested_course', 'program_level'])
                      or (ev.type = 'lead.edited' and jsonb_typeof(ev.payload -> 'fields') = 'array'
                          and (ev.payload -> 'fields') ?| array['student_name', 'email_id', 'interested_course', 'program_level', 'field_of_interest']))) then
              return v_base || jsonb_build_object('class', 'qualified', 'reason', null, 'missing', '[]'::jsonb, 'basis', 'completed_by_b2c');
            end if;
          end if;
        end if;
        m := array_append(m, 'witty_unconfirmed');
      end if;
      return v_base || jsonb_build_object('class', 'unqualified', 'reason', 'not_qualified', 'missing', to_jsonb(m), 'basis', 'witty_label');
    end if;
  else
    v_spam := case when v_test then null else b2b.spam_check(l) end;
  end if;

  -- R9 for every other source (and for any lead the Admin passed): a course plus a valid contact
  if not v_has_course then m := array_append(m, 'no_course'); end if;
  if v_phone is not null or v_spam is not null then m := array_append(m, 'no_valid_contact'); end if;
  if l.phone_verified_at is null then
    v_srcs := array(select lower(trim(x)) from jsonb_array_elements_text(
                      case when jsonb_typeof(e -> 'require_verified_phone_sources') = 'array' then e -> 'require_verified_phone_sources'
                           else '["website_agent","web_agent"]'::jsonb end) x);
    if lower(trim(coalesce(l.lead_source, ''))) = any (v_srcs)
       or (v_srcs && array['website_agent', 'web_agent']
           and (nullif(trim(coalesce(l.web_session_id, '')), '') is not null
                or exists (select 1 from public.touchpoints t where t.lead_id = l.id and t.source_system = 'web_agent'))) then
      m := array_append(m, 'phone_not_verified');
    end if;
  end if;
  return v_base || jsonb_build_object('class', case when cardinality(m) = 0 then 'qualified' else 'unqualified' end,
                                      'reason', case when cardinality(m) = 0 then null else 'not_qualified' end,
                                      'missing', to_jsonb(m), 'basis', 'fields');
end $fn$;

-- ---------- stored waits ----------
/* Stores (or replaces) the lead's wait. The sweep skips the lead while decide_after is in the future and
   p_lead_updated_at equals the lead's current updated_at; any later write to the lead re-evaluates it at once. A null
   p_lead_updated_at never makes the sweep skip the lead (the wait is then only its place in the queue). */
create or replace function b2b.lead_wait_set(p_lead_id bigint, p_decide_after timestamptz, p_why text, p_lead_updated_at timestamptz default null)
returns void language sql volatile security definer set search_path = '' as $fn$
  insert into b2b.lead_waits (lead_id, decide_after, why, set_at, lead_updated_at)
  values (p_lead_id, coalesce(p_decide_after, now()), left(coalesce(nullif(trim(p_why), ''), 'waiting'), 200), now(), p_lead_updated_at)
  on conflict (lead_id) do update
    set decide_after = excluded.decide_after, why = excluded.why, set_at = excluded.set_at, lead_updated_at = excluded.lead_updated_at;
$fn$;

-- ---------- PART 2 and Amendment 1: when the decision is made ----------
/* {ready, missing [reasons], is_test, class, class_reason, not_qualified [codes], class_detail, class_basis, override,
    paid (the attribution label when paid, else null), paid_platform, chat, witty, gate, decide_after, last_inbound, wait}.
   missing: 'deleted or merged', 'opted out', 'already routed', 'held for review', then at most one wait:
     'awaiting partner-sharing consent'   an open consent request (R8); until its expiry, now() + 15 min while queued,
                                          now() + 1 min once past expiry (the consent tick closes it)
     'unqualified: waiting for <N> h without a student message'
                                          Amendment 1: an unqualified Witty lead (no override), escalated or bot-paused
                                          included, waits until the student's last own message (w2_inbox / inbound
                                          w2_messages, else created_at) is engine.witty_unqualified_idle_hours old (18,
                                          1-72); Witty's replies never restart it
     'still chatting with Witty' | 'still chatting with the website agent'
                                          any other chat lead before its PART 2 hand-off point (b2b.chat_gate from the
                                          cycle start: escalation, a final programme, or 30 minutes idle)
   gate: intake (other sources: decided at once), inactivity (the 18 hours), or chat_gate's escalated | final_programme |
   idle | chatting; null for leads that are routed, deleted or merged. wait: null, or {kind consent|inactivity|chatting,
   why, until, last_inbound, hours (inactivity), request_id, status, expires_at, context (consent)}; decide_after =
   wait.until. */
create or replace function b2b.lead_readiness(l public.student_leads)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select s.value from b2b.settings s where s.key = 'engine'), '{}');
  m text[] := '{}';
  v_class jsonb := b2b.lead_class(l);
  v_attr jsonb := b2b.lead_attribution(l);
  v_test boolean := coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number);
  v_chat boolean := b2b.is_chat_lead(l);
  v_witty boolean;
  v_paid boolean;
  v_hours numeric := 18;
  v_gate text;
  v_after timestamptz;
  v_last_in timestamptz;
  v_wait jsonb;
  v_why text;
  g jsonb;
  v_req_id bigint;
  v_req_status text;
  v_req_exp timestamptz;
  v_req_ctx text;
begin
  v_witty := coalesce((v_class ->> 'witty')::boolean, b2b.is_witty_lead(l));
  v_paid := coalesce((v_attr ->> 'paid')::boolean, false);
  if (e ->> 'witty_unqualified_idle_hours') ~ '^[0-9]+(\.[0-9]+)?$' then
    v_hours := least(greatest((e ->> 'witty_unqualified_idle_hours')::numeric, 1), 72);
  end if;

  if l.deleted_at is not null or l.merged_into_id is not null then m := array_append(m, 'deleted or merged'); end if;
  if coalesce(l.is_opted_out, false) then m := array_append(m, 'opted out'); end if;
  if l.destination_type is not null then m := array_append(m, 'already routed'); end if;
  if exists (select 1 from b2b.intake_directives d where d.lead_id = l.id and d.directive = 'hold' and d.released_at is null) then
    m := array_append(m, 'held for review');
  end if;

  if l.destination_type is null and l.deleted_at is null and l.merged_into_id is null then
    if v_witty and v_class ->> 'class' = 'unqualified' and not coalesce((v_class ->> 'override')::boolean, false) then
      -- Amendment 1: 18 hours (Admin) without a message from the student; escalation does not shorten it
      v_gate := 'inactivity';
      v_last_in := b2b.student_last_inbound(b2b.phone_digits(l.whatsapp_number));
      v_after := coalesce(v_last_in, l.created_at) + make_interval(mins => round(v_hours * 60)::int);
      if v_after > now() then
        v_why := 'unqualified: waiting for ' || trim_scale(v_hours)::text || ' h without a student message';
        v_wait := jsonb_build_object('kind', 'inactivity', 'why', v_why, 'until', v_after, 'last_inbound', v_last_in, 'hours', v_hours);
      end if;
    elsif v_chat then
      -- PART 2: escalation, a final programme, or 30 minutes idle, whichever comes first (from the cycle start)
      g := b2b.chat_gate(l, greatest(l.created_at, l.reopened_at));
      v_gate := g ->> 'gate';
      v_last_in := (g ->> 'last_inbound')::timestamptz;
      if not coalesce((g ->> 'open')::boolean, false) then
        v_after := (g ->> 'decide_after')::timestamptz;
        v_why := case when v_witty then 'still chatting with Witty' else 'still chatting with the website agent' end;
        v_wait := jsonb_build_object('kind', 'chatting', 'why', v_why, 'until', v_after, 'last_inbound', v_last_in);
      end if;
    else
      v_gate := 'intake';
    end if;

    -- R8: the student is being asked for partner-sharing consent
    select r.id, r.status, r.expires_at, r.context into v_req_id, v_req_status, v_req_exp, v_req_ctx
      from b2b.consent_requests r
     where r.lead_id = l.id and r.status in ('queued', 'requested', 'sent', 'unsendable')
     order by r.created_at desc, r.id desc limit 1;
    if v_req_id is not null then
      v_after := case when v_req_status = 'queued' or v_req_exp is null then now() + interval '15 minutes'
                      when v_req_exp <= now() then now() + interval '1 minute'
                      else v_req_exp end;
      v_why := 'awaiting partner-sharing consent';
      v_wait := jsonb_build_object('kind', 'consent', 'why', v_why, 'until', v_after, 'last_inbound', v_last_in,
                                   'request_id', v_req_id, 'status', v_req_status, 'expires_at', v_req_exp, 'context', v_req_ctx);
    end if;

    if v_wait is not null then m := array_append(m, v_why); else v_after := null; end if;
  end if;

  return jsonb_build_object('ready', cardinality(m) = 0, 'missing', to_jsonb(m), 'is_test', v_test,
                            'class', v_class ->> 'class', 'class_reason', v_class ->> 'reason',
                            'not_qualified', coalesce(v_class -> 'missing', '[]'::jsonb),
                            'class_detail', v_class ->> 'detail', 'class_basis', v_class ->> 'basis',
                            'override', coalesce((v_class ->> 'override')::boolean, false),
                            'paid', case when v_paid then coalesce(v_attr ->> 'label', v_attr ->> 'platform', 'paid') end,
                            'paid_platform', case when v_paid then v_attr ->> 'platform' end,
                            'chat', v_chat, 'witty', v_witty,
                            'gate', v_gate, 'decide_after', v_after, 'last_inbound', v_last_in, 'wait', v_wait);
end $fn$;

-- ---------- the minute sweep ----------
/* Flags routed leads later classified junk or mismatch (unchanged), then, while the routing switch is live and the engine
   enabled, decides leads that reached their decision point.
   Candidates (at most 500): no destination, not deleted or merged, not test, not opted out; updated in the last 90 days
   (student_leads_updated_at_idx) or with a lead_waits row 'error', 'reroute_error' or 'locked' (critic B17); no open Not
   passed row with the same fingerprint (critic B18); not held for review; not skipped by a stored wait (decide_after in
   the future and lead_updated_at = the lead's updated_at; critic A3). Order: the stored decide_after, else created_at (a
   chat lead never evaluated: created_at + the 30-minute idle time), then id.
   Per lead, in its own exception block, until p_limit decisions (1-200) or 2 seconds: ready -> route_decide(.., 'auto');
   not ready -> lead_waits(decide_after or now() + 5 min, why); lock timeout (lock_timeout 2 s) -> lead_waits(now() + 1 min,
   'locked'); any other error -> routing.error and lead_waits(now() + 15 min, 'error'). A decision that leaves the lead
   without a destination and without a current wait stores one for 5 minutes, so it is not decided again every minute.
   One sweep at a time (advisory lock). Returns the number of decisions. */
create or replace function b2b.route_ready_leads(p_limit int default 50)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  r record;
  n int := 0;
  v_limit int := least(greatest(coalesce(p_limit, 25), 1), 200);
  v_idle int := coalesce((select (s.value -> 'a3_fixed' ->> 'witty_idle_minutes')::int from b2b.settings s
                           where s.key = 'engine' and (s.value -> 'a3_fixed' ->> 'witty_idle_minutes') ~ '^[0-9]+$'), 30);
  v_prev_lt text := current_setting('lock_timeout');
  t0 timestamptz;
  v_l public.student_leads;
  v_ready jsonb;
begin
  perform set_config('b2b.actor', 'engine', true);

  for r in
    insert into b2b.review_flags (lead_id, allocation_id, lead_status, destination_type)
    select l.id, a.id, l.lead_status, a.destination_type
      from public.student_leads l join b2b.allocations a on a.id = l.allocation_id
     where l.destination_type is not null and l.deleted_at is null and upper(coalesce(l.lead_status, '')) in ('JUNK', 'PROGRAM_MISMATCH')
       and a.status in ('queued', 'pushing', 'pushed', 'accepted', 'handed_off') and not a.override and not a.is_test
    on conflict (allocation_id, kind) do nothing
    returning lead_id, allocation_id, lead_status, destination_type
  loop
    perform b2b.log_event('lead.flagged', r.lead_id, r.allocation_id, null, jsonb_build_object('lead_status', r.lead_status, 'destination', r.destination_type));
    if r.destination_type = 'in_house' then
      perform b2b.log_event('b2c.lead_flagged', r.lead_id, r.allocation_id, null,
                            jsonb_build_object('lead_id', r.lead_id, 'classification', r.lead_status, 'allocation_id', r.allocation_id));
    end if;
  end loop;

  if not b2b.is_live('routing') or not coalesce((e ->> 'enabled')::boolean, true) then return 0; end if;
  if not pg_try_advisory_xact_lock(hashtext('b2b.route_ready_leads')) then return 0; end if;

  perform set_config('lock_timeout', '2000', true);
  t0 := clock_timestamp();
  for r in
    with ids as (
      select l.id from public.student_leads l
       where l.updated_at > now() - interval '90 days' and l.destination_type is null
      union
      select w.lead_id from b2b.lead_waits w where w.why in ('error', 'reroute_error', 'locked')
    )
    select l.id, l.updated_at
      from ids
      join public.student_leads l on l.id = ids.id
      left join b2b.lead_waits w on w.lead_id = l.id
     where l.destination_type is null and l.deleted_at is null and l.merged_into_id is null
       and not coalesce(l.is_test, false) and not b2b.is_test_phone(l.whatsapp_number)
       and not coalesce(l.is_opted_out, false)
       and not exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null and np.fingerprint = b2b.np_fingerprint(l))
       and not exists (select 1 from b2b.intake_directives d where d.lead_id = l.id and d.directive = 'hold' and d.released_at is null)
       and not coalesce(w.decide_after > now() and w.lead_updated_at = l.updated_at, false)
     order by coalesce(w.decide_after,
                       l.created_at + case when lower(coalesce(l.lead_source, '')) ~ '(whatsapp|witty|website_agent|web_agent)'
                                             or lower(coalesce(l.channel, '')) = 'whatsapp'
                                             or nullif(trim(coalesce(l.first_agent_channel, '')), '') is not null
                                             or nullif(trim(coalesce(l.web_session_id, '')), '') is not null
                                           then make_interval(mins => v_idle) else interval '0 minutes' end),
              l.id
     limit 500
  loop
    exit when n >= v_limit or clock_timestamp() - t0 > interval '2 seconds';
    begin
      select x.* into v_l from public.student_leads x where x.id = r.id;
      if v_l.id is null or v_l.destination_type is not null or v_l.deleted_at is not null or v_l.merged_into_id is not null then
        continue;
      end if;
      v_ready := b2b.lead_readiness(v_l);
      if coalesce((v_ready ->> 'ready')::boolean, false) then
        perform b2b.route_decide(v_l.id, true, null, 'auto');
        n := n + 1;
        insert into b2b.lead_waits (lead_id, decide_after, why, set_at, lead_updated_at)
        select x.id, now() + interval '5 minutes', 'decided without a destination', now(), x.updated_at
          from public.student_leads x
         where x.id = v_l.id and x.destination_type is null and x.deleted_at is null and x.merged_into_id is null
           and not exists (select 1 from b2b.lead_waits w where w.lead_id = x.id and w.decide_after > now() and w.lead_updated_at = x.updated_at)
        on conflict (lead_id) do update
          set decide_after = excluded.decide_after, why = excluded.why, set_at = excluded.set_at, lead_updated_at = excluded.lead_updated_at;
      else
        perform b2b.lead_wait_set(v_l.id, coalesce((v_ready ->> 'decide_after')::timestamptz, now() + interval '5 minutes'),
                                  coalesce(v_ready -> 'wait' ->> 'why', v_ready -> 'missing' ->> 0, 'not ready'), v_l.updated_at);
      end if;
    exception
      when lock_not_available or deadlock_detected then
        begin
          perform b2b.lead_wait_set(r.id, now() + interval '1 minute', 'locked', r.updated_at);
        exception when others then null;
        end;
      when others then
        begin
          perform b2b.log_event('routing.error', r.id, null, null, jsonb_build_object('error', left(sqlerrm, 300), 'code', sqlstate));
          perform b2b.lead_wait_set(r.id, now() + interval '15 minutes', 'error', r.updated_at);
        exception when others then null;
        end;
    end;
  end loop;
  perform set_config('lock_timeout', v_prev_lt, true);
  return n;
end $fn$;

-- ---------- grants: internal, service_role only (as m7a / m6a / m17a) ----------
revoke execute on function b2b.is_chat_lead(public.student_leads), b2b.spam_check(public.student_leads), b2b.lead_class(public.student_leads),
                           b2b.lead_wait_set(bigint, timestamptz, text, timestamptz), b2b.lead_readiness(public.student_leads),
                           b2b.route_ready_leads(int)
  from public, anon, authenticated;
grant execute on function b2b.is_chat_lead(public.student_leads), b2b.spam_check(public.student_leads), b2b.lead_class(public.student_leads),
                          b2b.lead_wait_set(bigint, timestamptz, text, timestamptz), b2b.lead_readiness(public.student_leads),
                          b2b.route_ready_leads(int)
  to service_role;

-- ---------- cron: 25 leads per run (critic C) ----------
do $cron$
declare v_id bigint;
begin
  select j.jobid into v_id from cron.job j where j.jobname = 'b2b-route-ready-leads' order by j.jobid limit 1;
  if v_id is null then
    perform cron.schedule('b2b-route-ready-leads', '* * * * *', 'select b2b.route_ready_leads(25)');
  else
    perform cron.alter_job(v_id, schedule := '* * * * *', command := 'select b2b.route_ready_leads(25)');
  end if;
end $cron$;
