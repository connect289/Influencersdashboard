-- W1: Witty changes for Addendum 3 (Vikas, 7 Oct 2026: "Make required changes to Witty", "Push changes to Witty and take
-- it to live production"). Shared Witty objects in schema public; the n8n half of the release patches the live workflow
-- "Eduwit Witty" (PKPs7tXg9bej8AgX): neutral hand-off wording, the consent line naming admission partners, and the
-- escalation signals. Bodies below are production's 7 Oct definitions with only the marked changes.
--   w2_crm_owned    PART 8.3: Witty goes quiet only when a partner has ACCEPTED the lead (b2b.allocations.status =
--                   'accepted') or a B2C counsellor is assigned (owner_user_id, lead not with a partner). A queued or
--                   pushed partner allocation (hold window) and B2C leads with no counsellor (sales or qualification
--                   nurture) keep Witty talking. Allocations of the legacy Eduwit CRM keep the old rule.
--   w2_nurture_due  Witty's proactive follow-ups stop once the lead is routed anywhere (destination_type set): the B2C
--                   CRM sends the welcome message and its journeys (Amendment 1), so the student never gets nudges
--                   from two numbers. Witty still answers every inbound message (w2_crm_owned above).
--   w2_crm_payload  PART 7.1: sends consent_partner_share_at and consent_text_version from Witty's state (set when the
--                   consent line naming admission partners is shown). lead_intake already accepts both (write-once).
--   w2_commit_turn  PART 8.4 / Addendum 1 §4b: a student message with an interest intent (fees, eligibility, a human,
--                   apply, pay after placement, accepted offer) on a lead the B2C CRM holds is logged as touchpoint
--                   'lead.interest', the explicit interest signal.
--   w2_prompts      the extractor's few-shot example quotes Witty's new hand-off offer wording.
-- Re-running crm/sql/001_lead_intake.sql (Eduwit CRM) or n8n's "Setup Request" webhook would revert these: copy them there.

create or replace function public.w2_crm_owned(p_phone text)
returns boolean language sql stable as $fn$
  select coalesce((
    select (l.owner_user_id is not null and l.destination_type is distinct from 'partner')         -- B2C counsellor assigned
        or exists (select 1 from b2b.allocations a                                                  -- a partner accepted it
                    where a.id = l.allocation_id and a.lead_id = l.id
                      and a.destination_type = 'partner' and a.status = 'accepted')
        or (l.destination_type = 'partner'                                                           -- legacy Eduwit CRM allocation
            and not exists (select 1 from b2b.allocations a where a.id = l.allocation_id and a.lead_id = l.id))
      from crm_find_lead(p_phone) l where l.id is not null), false);
$fn$;

create or replace function public.w2_nurture_due(p_limit integer default 100)
returns jsonb language plpgsql as $fn$
declare
  v jsonb;
  v_hour int := extract(hour from now() at time zone 'Asia/Kolkata');
begin
  if v_hour < 9 or v_hour >= 20 then
    return '[]'::jsonb;
  end if;
  with due as (
    select phone from w2_conversations
     where nurture_next_at <= now() and not opted_out and not bot_paused and access_code is not null
       and classification in ('UNQUALIFIED', 'PROGRAM_MISMATCH') and not w2_is_test(phone)
       -- routed by the B2B CRM (partner or B2C): the B2C CRM owns outbound nurture from here (Addendum 3, Amendment 1)
       and not exists (select 1 from crm_find_lead(phone) l where l.id is not null and l.destination_type is not null)
     order by nurture_next_at
     limit p_limit
     for update skip locked
  ), upd as (
    update w2_conversations c set nurture_next_at = now() + interval '30 minutes'   -- lease while the worker sends
      from due where c.phone = due.phone
    returning c.phone, c.conversation_id, c.account_id, c.nurture_step + 1 as step, c.last_student_at, c.state, c.lead_source
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'phone', phone, 'conversation_id', conversation_id, 'account_id', account_id, 'step', step, 'lead_source', lead_source,
           'within_24h', last_student_at > now() - interval '23 hours 30 minutes',
           'name', split_part(coalesce(state->'profile'->'student_name'->>'value', ''), ' ', 1),
           'course', state->'profile'->'interested_course'->>'value',
           'language', coalesce(state->>'language', 'english'),
           'ask_text', state->>'last_ask_text',
           'enquirer', state->'enquirer',
           'sent_30d', (select count(*) from w2_nurture_log l where l.phone = upd.phone and l.status = 'sent' and l.created_at > now() - interval '30 days')
         )), '[]'::jsonb) into v from upd;
  return v;
end $fn$;

create or replace function public.w2_crm_payload(p_phone text, p_event text, p_key text, p jsonb)
returns jsonb language plpgsql stable as $fn$
declare
  c  w2_conversations;
  s  jsonb;
  pr jsonb;
  a  jsonb;
  v_lead jsonb;
begin
  select * into c from w2_conversations where phone = p_phone;
  s  := coalesce(c.state, '{}'::jsonb);
  pr := coalesce(s->'profile', '{}'::jsonb);
  a  := coalesce(c.attribution, '{}'::jsonb);
  v_lead := jsonb_strip_nulls(jsonb_build_object(
    'full_name',            w2_pv(pr, 'student_name'),
    'is_name_confirmed',    pr->'student_name'->>'status' = 'confirmed',
    'email',                w2_pv(pr, 'email_id'),
    'is_email_confirmed',   pr->'email_id'->>'status' = 'confirmed',
    'interested_course',    w2_pv(pr, 'interested_course'),
    'interested_specialization', w2_pv(pr, 'specialization'),
    'field_of_interest',    w2_pv(pr, 'field_of_interest'),
    'university_preference', w2_pv(pr, 'university_preference'), 'interested_university', case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'university' end,
    'programme_level',      w2_pv(pr, 'program_level'),
    'study_mode_preference', w2_pv(pr, 'study_mode_preference'),
    'highest_qualification', w2_pv(pr, 'highest_qualification'),
    'current_study',        w2_pv(pr, 'current_study'),
    'academic_score_raw',   w2_pv(pr, 'academic_score'),
    'academic_score_pct',   crm_num(w2_pv(pr, 'academic_score')),
    'work_experience_raw',  w2_pv(pr, 'work_experience_years'),
    'work_experience_years_num', crm_num(w2_pv(pr, 'work_experience_years')),
    'current_job_role',     w2_pv(pr, 'current_job_role'),
    'annual_budget_raw',    w2_pv(pr, 'annual_budget'),
    'annual_budget_inr',    crm_num(w2_pv(pr, 'annual_budget')),
    'enrollment_timeline',  w2_pv(pr, 'enrollment_timeline'),
    'primary_motivation',   w2_pv(pr, 'primary_motivation'),
    'location_raw',         w2_pv(pr, 'current_city_country')
  )) || jsonb_strip_nulls(jsonb_build_object(   -- two objects: jsonb_build_object takes at most 100 arguments
    'preferred_language',   s->>'language',
    'enquirer_relation',    s->'enquirer'->>'relation',
    'guardian_name',        case when s->'enquirer'->>'relation' in ('father', 'mother', 'parent') then s->'enquirer'->>'name' end,
    'classification',       c.classification,
    'classification_ai',    c.classification,
    'readiness',            c.readiness,
    'eligibility',          c.eligibility,
    'conversation_phase',   s->>'phase',
    'last_intent',          (select string_agg(x, ',') from jsonb_array_elements_text(coalesce(p->'event'->'payload'->'intents', '[]'::jsonb)) x),
    'source',               c.lead_source,
    'channel',              'whatsapp',
    'source_detail',        a->>'kind',
    'campaign',             coalesce(a->>'campaign', a->>'utm_campaign', a->>'parent_campaign'),
    'utm_source',           a->>'utm_source',
    'utm_medium',           a->>'utm_medium',
    'utm_campaign',         a->>'utm_campaign',
    'utm_content',          a->>'utm_content',
    'utm_term',             a->>'utm_term',
    'click_ids',            a->'click_ids',
    'landing_url',          a->>'landing_url',
    'referrer_url',         a->>'referrer',
    'referred_by_code',     a->>'via',
    'access_code',          nullif(c.access_code, 'LEGACY'),
    'ip_address',           a->>'ip',
    'device_type',          a->>'device_type',
    'device_fingerprint',   a->>'fingerprint',
    'consent_sales_at',     c.consent_at,
    -- Addendum 3 PART 7.1: set by Witty when the consent line naming admission partners is shown
    'consent_partner_share_at', case when s->>'consent_partner_share_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_partner_share_at')::timestamptz end,
    'consent_text_version', s->>'consent_text_version',
    'is_opted_out',         c.opted_out,
    'first_agent_channel',  'whatsapp',
    'chatwoot_conversation_id', c.conversation_id,
    'is_bot_paused',        c.bot_paused,
    'last_agent_message_at', case when coalesce(p->'log'->>'content', '') <> '' then now() end
  ));
  return jsonb_build_object('source_system', 'witty', 'event_type', p_event, 'idempotency_key', p_key, 'phone', p_phone,
                            'lead', v_lead, 'attribution', a, 'occurred_at', coalesce((a->>'first_click_at')::timestamptz, c.created_at),
                            'is_test', w2_is_test(p_phone));
end $fn$;

create or replace function public.w2_commit_turn(p jsonb)
returns jsonb language plpgsql as $fn$
declare
  v_phone text := p->>'phone';
  v_state jsonb := coalesce(p->'state', '{}'::jsonb);
  v_conv  w2_conversations;
  v_outbox_id bigint;
  v_version int;
  v_had_msgs boolean := jsonb_array_length(coalesce(p->'message_ids', '[]'::jsonb)) > 0;
  v_nurture text := coalesce(p->>'nurture', 'keep');
  v_log jsonb := p->'log';
  v_evt text;
  v_key text;
  v_crm jsonb;
  v_res jsonb;
  v_crm_error text;
begin
  update w2_conversations set
    conversation_id  = coalesce((p->>'conversation_id')::bigint, conversation_id),
    account_id       = coalesce((p->>'account_id')::bigint, account_id),
    state            = v_state,
    classification   = coalesce(v_state->>'classification', classification),
    readiness        = coalesce(v_state->>'readiness', readiness),
    eligibility      = coalesce(v_state->>'eligibility', eligibility),
    pending_question = coalesce(v_state->>'pending_question', pending_question),
    bot_paused       = coalesce((v_state->>'bot_paused')::boolean, bot_paused),
    opted_out        = coalesce((v_state->>'opted_out')::boolean, opted_out),
    consent_at       = coalesce((v_state->>'consent_at')::timestamptz, consent_at),
    escalated_at     = coalesce((v_state->>'escalated_at')::timestamptz, escalated_at),
    lead_source      = coalesce(lead_source, v_state->>'lead_source'),
    activation_code  = coalesce(v_state->>'activation_code', activation_code),
    last_student_at  = case when v_had_msgs then now() else last_student_at end,
    nurture_step     = case when v_nurture = 'start' then 0 else nurture_step end,
    nurture_next_at  = case v_nurture when 'start' then now() + interval '3 hours' when 'stop' then null else nurture_next_at end,
    version          = version + 1,
    updated_at       = now()
  where phone = v_phone
  returning * into v_conv;
  v_version := v_conv.version;

  update w2_inbox set processed_at = now()
   where message_id in (select jsonb_array_elements_text(coalesce(p->'message_ids', '[]'::jsonb)));

  insert into w2_fact_log (phone, turn_run, field, value, evidence, op, subject, accepted, reject_reason, model)
  select v_phone, p->>'run_id', f->>'field', f->>'value', f->>'evidence', f->>'op', f->>'subject',
         coalesce((f->>'accepted')::boolean, true), f->>'reason', p->>'model'
    from jsonb_array_elements(coalesce(p->'facts', '[]'::jsonb)) f;

  if p ? 'event' and jsonb_typeof(p->'event') = 'object' then
    insert into w2_events (phone, type, run_id, payload) values (v_phone, coalesce(p->'event'->>'type', 'turn'), p->>'run_id', p->'event'->'payload');
  end if;

  if jsonb_typeof(v_log) = 'object' and coalesce(v_log->>'content', '') <> '' then
    insert into w2_messages (phone, direction, kind, run_id, content, answer_mode, reply_source, model, prompt_tokens, cached_tokens,
                             output_tokens, latency_ms, verify_errors, sent, meta)
    values (v_phone, 'out', coalesce(v_log->>'kind', 'reply'), p->>'run_id', v_log->>'content', v_log->>'answer_mode', v_log->>'reply_source',
            p->>'model', (v_log->>'prompt_tokens')::int, (v_log->>'cached_tokens')::int, (v_log->>'output_tokens')::int,
            (v_log->>'latency_ms')::int, v_log->'verify_errors', (v_log->>'sent')::boolean, v_log->'meta');
  end if;

  -- CRM sync (Eduwit CRM PRD §5): every turn of a gated chat writes the lead through lead_intake(), in this transaction.
  -- A failure never blocks the reply: the payload is queued in w2_outbox and w2_outbox_retry() delivers it later.
  if v_conv.access_code is not null then
    -- Addendum 3 PART 8.4 / Addendum 1 §4b: a student message with an interest intent on a lead the B2C CRM holds is the
    -- explicit interest signal (touchpoint 'lead.interest'); qualification is signalled by 'lead.qualified' and
    -- 'classification_changed' as before.
    v_evt := coalesce(p->'outbox'->>'event_type',
                      case when v_had_msgs
                                and coalesce(p->'event'->'payload'->'intents', '[]'::jsonb)
                                    ?| array['asks_fees', 'asks_eligibility', 'asks_human', 'wants_to_apply', 'pay_after_placement', 'accepted_offer']
                                and exists (select 1 from crm_find_lead(v_phone) l where l.id is not null and l.destination_type = 'in_house')
                           then 'lead.interest' end,
                      'chat.turn');
    v_key := coalesce(p->'outbox'->>'idempotency_key',
                      v_phone || case when v_evt = 'lead.interest' then ':interest:' else ':turn:' end || coalesce(p->>'run_id', ''));
    begin
      v_crm := w2_crm_payload(v_phone, v_evt, v_key, p);
      v_res := lead_intake(v_crm);
      if v_evt <> 'chat.turn' then
        insert into w2_outbox (phone, target, event_type, idempotency_key, payload, status, sent_at, crm_record_id)
        values (v_phone, 'crm', v_evt, v_key, v_crm, 'sent', now(), v_res->>'lead_id')
        on conflict (idempotency_key) do nothing
        returning id into v_outbox_id;
        update w2_conversations set crm_record_id = v_res->>'lead_id' where phone = v_phone;
      end if;
    exception when others then
      v_crm_error := sqlerrm;
      insert into w2_outbox (phone, target, event_type, idempotency_key, payload, status, last_error)
      values (v_phone, 'crm', v_evt, v_key, coalesce(v_crm, jsonb_build_object('phone', v_phone, 'rebuild', true)), 'pending', left(v_crm_error, 2000))
      on conflict (idempotency_key) do update set payload = excluded.payload, status = 'pending', last_error = excluded.last_error, next_attempt_at = now()
      returning id into v_outbox_id;
    end;
  end if;

  return jsonb_build_object('version', v_version, 'outbox_id', v_outbox_id, 'crm', v_res, 'crm_error', v_crm_error);
end $fn$;

-- the extractor's few-shot example quotes what Witty now asks (n8n ENGINE.ASK_TEXT.OFFER_HANDOFF); the prompt cache is
-- rebuilt from w2_prompts by the workflow's 15-minute cache branch
update public.w2_prompts
   set body = replace(body, 'Would you like one of our academic counselors to help you with the next steps?',
                            'Would you like an academic counsellor to help you with the next steps?'),
       version = version + 1, updated_at = now()
 where name = 'extractor' and strpos(body, 'Would you like one of our academic counselors to help you with the next steps?') > 0;
