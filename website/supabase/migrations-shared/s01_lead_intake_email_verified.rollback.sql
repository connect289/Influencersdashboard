-- Rollback for s01: restores public.lead_intake exactly as read from production. Grants are
-- unchanged by s01, so CREATE OR REPLACE keeps them.
CREATE OR REPLACE FUNCTION public.lead_intake(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_phone   text := crm_norm_phone(p->>'phone');
  v_sys     text := coalesce(p->>'source_system', 'api');
  v_evt     text := coalesce(p->>'event_type', 'lead.updated');
  v_trusted boolean := v_sys in ('witty', 'web_agent', 'crm');   -- crm = a person editing on the lead screen
  v_lead    jsonb := coalesce(p->'lead', '{}'::jsonb);
  v_in      jsonb := '{}'::jsonb;
  v_row     student_leads;
  v_id      bigint;
  v_action  text;
  v_set     text;
  v_cls     text;
  v_k       text;
  v_v       jsonb;
  v_col     text;
  v_map     jsonb := '{"phone":"whatsapp_number","full_name":"student_name","email":"email_id","is_name_confirmed":"name_confirmed",
    "is_email_confirmed":"email_confirmed","programme_level":"program_level","academic_score_raw":"academic_percentage_gpa",
    "work_experience_raw":"work_experience_years","annual_budget_raw":"annual_budget","location_raw":"current_city_country",
    "preferred_call_time":"preferred_counseling_time","classification":"lead_status","classification_ai":"lead_classification",
    "readiness":"admission_readiness","eligibility":"eligibility_status","conversation_phase":"lead_stage","last_intent":"intent_type",
    "ai_extraction_confidence":"extraction_confidence","source":"lead_source","access_code":"activation_code","device_type":"device",
    "device_fingerprint":"fingerprint","notes":"Comments"}'::jsonb;
  v_allowed text[] := array['alternate_phone','student_name','email_id','name_confirmed','email_confirmed','preferred_language','city','state','country',
    'current_city_country','enquirer_relation','guardian_name','guardian_phone','interested_course','interested_specialization','field_of_interest',
    'interested_university','university_preference','program_level','study_mode_preference','highest_qualification','current_study',
    'academic_percentage_gpa','academic_score_pct','work_experience_years','work_experience_years_num','current_job_role','annual_budget',
    'annual_budget_inr','enrollment_timeline','primary_motivation','preferred_counseling_time','programme_segment',
    'lead_status','lead_classification','admission_readiness','eligibility_status','lead_stage','intent_type','extraction_confidence',
    'lead_source','channel','source_detail','campaign','utm_source','utm_medium','utm_campaign','utm_content','utm_term','click_ids',
    'landing_url','referrer_url','referral_code','referred_by_code','activation_code','ip_address','device','fingerprint',
    'consent_sales_at','consent_marketing_at','consent_partner_share_at','consent_text_version',
    'first_agent_channel','chatwoot_conversation_id','web_session_id','is_bot_paused','last_agent_message_at','Comments'];
  v_first   text[] := array['lead_source','channel','source_detail','campaign','utm_source','utm_medium','utm_campaign','utm_content','utm_term',
    'click_ids','landing_url','referrer_url','referral_code','referred_by_code','activation_code','ip_address','device','fingerprint',
    'consent_sales_at','consent_marketing_at','consent_partner_share_at','consent_text_version','first_agent_channel'];
begin
  if v_phone is null or length(v_phone) < 10 then
    raise exception 'lead_intake: phone missing or too short (%)', p->>'phone';
  end if;
  for v_k, v_v in select key, value from jsonb_each(v_lead) loop
    v_col := coalesce(v_map->>v_k, v_k);
    if v_col = any(v_allowed) and v_v is not null and jsonb_typeof(v_v) <> 'null' then
      v_in := v_in || jsonb_build_object(v_col, v_v);
    end if;
  end loop;
  if (v_in->>'academic_score_pct') is not null and ((v_in->>'academic_score_pct')::numeric < 0 or (v_in->>'academic_score_pct')::numeric > 100) then
    v_in := v_in - 'academic_score_pct';
  end if;
  v_row := crm_find_lead(v_phone);
  if v_row.id is null then
    insert into student_leads (whatsapp_number, stage, stage_changed_at, cycle_no, country, is_test, updated_by,
                               phone_verified_at, phone_verification_method, first_touch_at, last_touch_at, last_touch_source)
    values (v_phone, 'new', now(), 1, 'India', coalesce((p->>'is_test')::boolean, w2_is_test(v_phone)), v_sys,
            case when v_sys = 'witty' then now() end, case when v_sys = 'witty' then 'whatsapp_inbound' end,
            coalesce((p->>'occurred_at')::timestamptz, now()), now(), v_sys)
    returning * into v_row;
    v_action := 'created';
    v_trusted := true;
  else
    v_action := 'merged';
    if v_row.stage = 'lost' or v_row.enrollment_status is not null then
      update student_leads set stage = 'qualifying', stage_changed_at = now(), reopened_at = now(),
             cycle_no = case when v_row.enrollment_status is not null or coalesce(v_row.lost_at, now()) < now() - interval '90 days' then cycle_no + 1 else cycle_no end,
             lost_reason = null, lost_at = null, is_sales_ready = false, sales_ready_at = null
       where id = v_row.id returning * into v_row;
      v_action := 'reopened';
    end if;
  end if;
  v_id := v_row.id;
  select string_agg(case when v_trusted and not (key = any(v_first)) then format('%I = %L', key, val)
                         else format('%I = coalesce(%I, %L)', key, key, val) end, ', ')
    into v_set
    from (select key, case when jsonb_typeof(value) = 'string' then value #>> '{}' else value::text end as val from jsonb_each(v_in)) kv;
  if v_set is not null then
    execute format('update student_leads set %s, updated_by = %L where id = %s', v_set, v_sys, v_id);
  end if;
  v_cls := upper(coalesce(v_in->>'lead_status', v_row.lead_status, ''));
  update student_leads set
    temperature    = case when v_cls in ('HOT', 'WARM', 'COLD') then lower(v_cls) else temperature end,
    is_opted_out   = is_opted_out or coalesce((v_lead->>'is_opted_out')::boolean, false),
    opted_out_at   = case when not is_opted_out and coalesce((v_lead->>'is_opted_out')::boolean, false) then now() else opted_out_at end,
    is_sales_ready = is_sales_ready or v_cls in ('HOT', 'WARM', 'COLD'),
    sales_ready_at = coalesce(sales_ready_at, case when v_cls in ('HOT', 'WARM', 'COLD') then now() end),
    stage          = case when stage = 'new' and (v_in ? 'interested_course' or v_in ? 'highest_qualification' or v_cls in ('HOT', 'WARM', 'COLD'))
                          then 'qualifying' else stage end,
    stage_changed_at = case when stage = 'new' and (v_in ? 'interested_course' or v_in ? 'highest_qualification' or v_cls in ('HOT', 'WARM', 'COLD'))
                            then now() else stage_changed_at end,
    last_touch_at  = case when v_evt <> 'chat.turn' then now() else last_touch_at end,
    last_touch_source = case when v_evt <> 'chat.turn' then v_sys else last_touch_source end,
    last_activity_at = now()
  where id = v_id returning * into v_row;
  if (v_action <> 'merged' or v_evt <> 'chat.turn') and v_sys <> 'crm' then
    insert into touchpoints (lead_id, phone, source_system, event_type, source, campaign, attribution, idempotency_key, payload, occurred_at)
    values (v_id, v_phone, v_sys, case when v_action = 'created' then 'lead.created' else v_evt end, v_in->>'lead_source', v_in->>'campaign',
            coalesce(p->'attribution', '{}'::jsonb), p->>'idempotency_key', v_lead, coalesce((p->>'occurred_at')::timestamptz, now()))
    on conflict (idempotency_key) do nothing;
  end if;
  return jsonb_build_object('lead_id', v_id, 'action', v_action, 'phone', v_phone, 'stage', v_row.stage,
                            'is_sales_ready', v_row.is_sales_ready, 'is_test', v_row.is_test, 'crm_owned', w2_crm_owned(v_phone));
end $function$
;
