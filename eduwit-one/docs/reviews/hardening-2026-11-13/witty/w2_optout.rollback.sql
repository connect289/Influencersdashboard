-- Rollback of w2_optout.sql (Witty opt-out fixes H3 and H4, 13 Nov 2026).
-- Restores w2_try_claim and w2_nurture_due to the production definitions captured on 13 Nov 2026 before the change
-- (pg_get_functiondef, unchanged), then drops the matcher they no longer use. Idempotent. Rows already written by the
-- fix stay as they are: w2_conversations.opted_out, student_leads.is_opted_out and 'lead.opted_out' touchpoints are
-- real opt-outs and must be kept.

CREATE OR REPLACE FUNCTION public.w2_try_claim(p_phone text, p_run text, p_lease_seconds integer DEFAULT 45)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_conv   w2_conversations;
  v_msgs   jsonb;
  v_text   text;
  v_access jsonb;
  v_up     jsonb;
  v_bot    jsonb;
  v_rating smallint;
  v_ids    text[];
  v_ref    jsonb;
  v_src    text;
  v_attr   jsonb;
  v_utm    jsonb;
begin
  insert into w2_conversations (phone) values (p_phone) on conflict (phone) do nothing;
  update w2_conversations
     set lock_id = p_run, lock_until = now() + make_interval(secs => p_lease_seconds)
   where phone = p_phone and (lock_until is null or lock_until < now() or lock_id = p_run)
  returning * into v_conv;
  if not found then
    return jsonb_build_object('acquired', false);
  end if;

  with c as (
    update w2_inbox set claimed_by = p_run
     where phone = p_phone and processed_at is null
    returning *
  )
  select coalesce(jsonb_agg(to_jsonb(c) order by c.received_at), '[]'::jsonb) into v_msgs from c;
  select coalesce(array_agg(m->>'message_id'), '{}') into v_ids from jsonb_array_elements(v_msgs) m;
  select string_agg(coalesce(m->>'content', ''), E'\n' order by m->>'received_at') into v_text from jsonb_array_elements(v_msgs) m;

  -- 1. Bots: a blocked number gets no reply at all; its messages are kept for review.
  if cardinality(v_ids) > 0 then
    if w2_is_blocked(p_phone) then
      v_bot := jsonb_build_object('blocked', true, 'reason', 'already blocked');
    else
      v_bot := w2_bot_check(p_phone);
    end if;
    if (v_bot->>'blocked')::boolean then
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'blocked' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'blocked', true, 'bot', v_bot, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
  end if;

  -- 1b. CRM owns the lead (assigned in-house or sent to a partner): Witty stays silent, the message is logged for the timeline.
  if cardinality(v_ids) > 0 and w2_crm_owned(p_phone) then
    update w2_inbox set processed_at = now() where message_id = any(v_ids);
    update w2_messages set kind = 'crm_paused' where direction = 'in' and message_id = any(v_ids);
    -- W2.2 (B2C CRM): record the unanswered message on the lead, one touchpoint per lead per day; never block Witty.
    begin
      perform lead_intake(jsonb_build_object(
        'source_system', 'witty', 'event_type', 'chat.reenquiry',
        'idempotency_key', p_phone || ':paused:' || to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD'),
        'phone', p_phone, 'lead', '{}'::jsonb));
    exception when others then null;
    end;
    return jsonb_build_object('acquired', true, 'crm_paused', true, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
  end if;

  -- 1c. W2.1 (B2C CRM): a chat Witty paused at escalation, whose lead now sits in B2C (allocation in_house, handed_off)
  --     with no counsellor, gets Witty back. escalated_at stays, so Witty never promises a counsellor twice.
  if cardinality(v_ids) > 0 and v_conv.bot_paused and coalesce(v_conv.state->>'paused_by', '') <> 'agent' and exists (
       select 1 from crm_find_lead(p_phone) l
         join b2b.allocations a on a.id = l.allocation_id and a.lead_id = l.id
        where l.id is not null and l.owner_user_id is null
          and a.destination_type = 'in_house' and a.status = 'handed_off') then
    update w2_conversations
       set bot_paused = false, state = coalesce(state, '{}'::jsonb) || jsonb_build_object('bot_paused', false)
     where phone = p_phone
    returning * into v_conv;
  end if;

  -- 1d. W3: a human agent replied in Chatwoot (w2_agent_pause). Witty stays quiet for 4 hours after the pause, then answers again.
  if cardinality(v_ids) > 0 and coalesce(v_conv.state->>'paused_by', '') = 'agent' then
    if coalesce((v_conv.state->>'paused_at')::timestamptz, now()) > now() - interval '4 hours' then
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'agent_paused' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'agent_paused', true, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
    update w2_conversations
       set bot_paused = false, state = (coalesce(state, '{}'::jsonb) - 'paused_by' - 'paused_at' - 'paused_agent') || jsonb_build_object('bot_paused', false)
     where phone = p_phone
    returning * into v_conv;
  end if;

  -- 2. A one-tap answer to "Was this chat helpful?" is recorded, not answered.
  if cardinality(v_ids) > 0 and v_conv.state ? 'feedback_asked_at' and not coalesce((v_conv.state->>'feedback_done')::boolean, false)
     and (v_conv.state->>'feedback_asked_at')::timestamptz > now() - interval '48 hours' then
    v_rating := w2_parse_rating(v_text);
    if v_rating is not null then
      insert into w2_feedback (phone, source, rating, label, comment, meta)
      values (p_phone, 'student', v_rating, case v_rating when 1 then 'helpful' when -1 then 'not helpful' else 'neutral' end, left(v_text, 500),
              jsonb_build_object('asked_after', v_conv.state->>'feedback_asked_mode'));
      update w2_conversations set state = state || jsonb_build_object('feedback_done', true, 'feedback_rating', v_rating)
       where phone = p_phone returning * into v_conv;
      update w2_inbox set processed_at = now() where message_id = any(v_ids);
      update w2_messages set kind = 'feedback' where direction = 'in' and message_id = any(v_ids);
      return jsonb_build_object('acquired', true, 'feedback', v_rating, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
    end if;
  end if;

  -- 3. Access code: attribution only (W3 soft gate, 16 Oct 2026). Every chat becomes a lead on its first message.
  if v_conv.access_code is not null then
    v_access := jsonb_build_object('status', 'verified', 'code', v_conv.access_code, 'source', v_conv.lead_source, 'attribution', v_conv.attribution);
    -- A direct lead that later types a real code is upgraded once, so ad attribution is not lost.
    if v_conv.access_code = 'DIRECT' and cardinality(v_ids) > 0 and v_text ~* '(access|activation)\s*code' then
      v_up := w2_redeem_code(p_phone, v_text);
      if v_up->>'status' = 'ok' and v_up->>'via' in ('code', 'legacy_code') then
        update w2_conversations
           set access_code = v_up->>'code', access_at = now(), lead_source = v_up->>'source',
               attribution = coalesce(attribution, '{}'::jsonb) || coalesce(v_up->'attribution', '{}'::jsonb) || jsonb_build_object('upgraded_from', 'DIRECT')
         where phone = p_phone
        returning * into v_conv;
        v_access := jsonb_build_object('status', 'verified', 'code', v_conv.access_code, 'source', v_conv.lead_source, 'attribution', v_conv.attribution, 'upgraded', true);
      end if;
    end if;
  else
    v_access := w2_redeem_code(p_phone, v_text);
    if v_access->>'status' = 'ok' then
      update w2_conversations
         set access_code = coalesce(v_access->>'code', 'LEGACY'), access_at = now(), lead_source = v_access->>'source',
             attribution = v_access->'attribution'
       where phone = p_phone
      returning * into v_conv;
    else
      if v_access->>'status' in ('invalid', 'taken', 'expired') then
        insert into w2_security_log (phone, kind, detail) values (p_phone, 'bad_code', jsonb_build_object('status', v_access->>'status', 'code', v_access->>'code'));
      end if;
      if cardinality(v_ids) > 0 then
        -- Bind the conversation now: a click-to-WhatsApp referral makes it an influencer lead, otherwise an organic direct lead.
        select referral into v_ref from w2_inbox where phone = p_phone and referral is not null order by received_at limit 1;
        if v_ref is not null then
          v_utm := '{}'::jsonb;
          if coalesce(v_ref->>'source_url', '') ~ 'utm_' then
            select coalesce(jsonb_object_agg(m[1], m[2]), '{}'::jsonb) into v_utm
              from regexp_matches(v_ref->>'source_url', '(utm_[a-z]+)=([^&#]+)', 'g') m;
          end if;
          -- Vikas, 16 Oct: click-to-WhatsApp entries are influencer leads, not paid Meta leads.
          v_src := 'influencer';
          v_attr := jsonb_strip_nulls(jsonb_build_object('kind', 'influencer', 'source', 'influencer', 'via', 'ctwa',
                      'campaign', coalesce(v_utm->>'utm_campaign', v_ref->>'headline', v_ref->>'source_id'), 'landing_url', v_ref->>'source_url',
                      'click_ids', jsonb_strip_nulls(jsonb_build_object('ctwa_clid', v_ref->>'ctwa_clid', 'source_id', v_ref->>'source_id')),
                      'utm_source', coalesce(v_utm->>'utm_source', 'influencer'), 'utm_medium', coalesce(v_utm->>'utm_medium', 'influencer'),
                      'utm_campaign', v_utm->>'utm_campaign', 'utm_content', v_utm->>'utm_content', 'utm_term', v_utm->>'utm_term',
                      'referral', v_ref, 'first_message_at', now()));
        else
          v_src := 'whatsapp_direct';
          v_attr := jsonb_build_object('kind', 'organic', 'source', 'whatsapp_direct', 'via', 'direct', 'first_message_at', now());
        end if;
        update w2_conversations
           set access_code = 'DIRECT', access_at = now(), lead_source = v_src, attribution = v_attr
         where phone = p_phone
        returning * into v_conv;
        if v_access->>'status' in ('invalid', 'taken', 'expired') and coalesce((v_access->>'attempted')::boolean, false) then
          -- the student typed a code that failed: the gateway shows one correction line, and the chat goes on as a direct lead
          v_access := v_access || jsonb_build_object('bound', true, 'source', v_src, 'attribution', v_attr);
        else
          v_access := jsonb_build_object('status', 'ok', 'via', 'direct', 'code', 'DIRECT', 'source', v_src, 'attribution', v_attr);
        end if;
      end if;
    end if;
  end if;

  return jsonb_build_object('acquired', true, 'conversation', to_jsonb(v_conv), 'messages', v_msgs, 'access', v_access,
                            'activation_code', v_access->>'code', 'lead_source', v_conv.lead_source, 'prompts', w2_turn_prompts(),
                            'kb_ready', exists (select 1 from w2_kb_docs d where d.active and d.chunks > 0),
                            'kb_chunks', (select coalesce(sum(d.chunks), 0) from w2_kb_docs d where d.active));
end $function$;

CREATE OR REPLACE FUNCTION public.w2_nurture_due(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
       -- Witty sends only the first (3-hour) check-in; the B2C CRM owns follow-up after the 18-hour hand-off (decision D3, 16 Oct)
       and coalesce(nurture_step, 0) < 1
       -- routed by the B2B CRM (partner or B2C): the B2C CRM owns outbound nurture from here (Addendum 3, Amendment 1)
       and not exists (select 1 from crm_find_lead(phone) l where l.id is not null and l.destination_type is not null)
     order by nurture_next_at
     limit p_limit
     for update skip locked
  ), upd as (
    update w2_conversations c set nurture_next_at = now() + interval '30 minutes'   -- lease while the worker sends
      from due where c.phone = due.phone
    returning c.phone, c.conversation_id, c.account_id, c.nurture_step + 1 as step, c.last_student_at, c.state, c.lead_source, c.classification, c.eligibility, c.pending_question
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'phone', phone, 'conversation_id', conversation_id, 'account_id', account_id, 'step', step, 'lead_source', lead_source,
           'within_24h', last_student_at > now() - interval '23 hours 30 minutes',
           'idle_minutes', floor(extract(epoch from (now() - coalesce(last_student_at, now()))) / 60),
           'name', split_part(coalesce(state->'profile'->'student_name'->>'value', ''), ' ', 1),
           'course', state->'profile'->'interested_course'->>'value',
           'specialization', state->'profile'->'specialization'->>'value',
           'final_program', case when state->'profile'->'final_program'->>'status' = 'confirmed' then state->'profile'->'final_program' end,
           'language', coalesce(state->>'language', 'english'),
           'ask', coalesce(pending_question, state->>'pending_question', 'NONE'),
           'ask_text', state->>'last_ask_text',
           'enquirer', state->'enquirer',
           'classification', classification, 'eligibility', eligibility,
           'programs_shown', coalesce(state->'flags'->>'programs_shown_key', '') <> '',
           'program_count', coalesce((state->'flags'->>'last_program_count')::int, 0),
           'has_email', state->'profile'->'email_id'->>'status' = 'confirmed',
           'has_name', state->'profile'->'student_name'->>'status' = 'confirmed',
           'turns', coalesce((state->>'turn_count')::int, 0),
           'sent_30d', (select count(*) from w2_nurture_log l where l.phone = upd.phone and l.status = 'sent' and l.created_at > now() - interval '30 days')
         )), '[]'::jsonb) into v from upd;
  return v;
end $function$;

drop function if exists public.w2_is_stop_message(text);
