-- =====================================================================================================================
-- Read-only snapshot of the SHARED production objects the website depends on, extracted from prod-replica
-- (fingerprint-identical to production 2026-10-17). Baseline for the local fresh database only.
-- NEVER apply to production: these objects already exist there and belong to Witty / the CRMs.
-- Regenerate: scripts/db/make-min-snapshot.sh
-- =====================================================================================================================
create schema if not exists b2b;
create extension if not exists pg_trgm with schema public;
create extension if not exists vector with schema public;
create extension if not exists pgcrypto with schema extensions;

CREATE TABLE b2b.allocations (
    id bigint NOT NULL,
    lead_id bigint NOT NULL,
    cycle_no integer DEFAULT 1 NOT NULL,
    segment text,
    destination_type text NOT NULL,
    partner_id bigint,
    reference text,
    status text NOT NULL,
    mode text NOT NULL,
    attempt_no integer DEFAULT 1 NOT NULL,
    reason text,
    cpe_net_inr numeric(12,2),
    ncpl_inr numeric(12,2),
    selection_probability numeric(5,4),
    engine_decision_id bigint,
    is_test boolean DEFAULT false NOT NULL,
    hold_until timestamp with time zone,
    partner_record_id text,
    accepted_at timestamp with time zone,
    outcome text,
    outcome_at timestamp with time zone,
    override boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    b2c_lane text,
    programme_id bigint,
    push_attempts integer DEFAULT 0 NOT NULL,
    next_push_at timestamp with time zone,
    push_request_id bigint,
    pushed_at timestamp with time zone,
    last_error text,
    returning_lead boolean DEFAULT false NOT NULL,
    spot_check boolean DEFAULT false NOT NULL,
    claim_proof jsonb,
    partner_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    partner_custom jsonb DEFAULT '{}'::jsonb NOT NULL,
    mapping_version integer,
    stage text,
    score_inr numeric(14,2),
    p_enroll numeric(6,5),
    effort_factor numeric(5,4),
    sla_factor numeric(5,4),
    segment_exact text,
    interest_rank smallint,
    origin text,
    paid boolean,
    paid_platform text,
    campaign_id text,
    cause text,
    claim_existing_record_id text,
    claim_existing_created_at timestamp with time zone,
    claim_proof_ok boolean,
    lost_at timestamp with time zone,
    lost_grace_until timestamp with time zone,
    lost_detail jsonb,
    lost_prev_stage text,
    lost_revived_at timestamp with time zone,
    lost_count integer DEFAULT 0 NOT NULL,
    recall_reason text,
    model_version text,
    CONSTRAINT allocations_b2c_lane_check CHECK ((((b2c_lane = ANY (ARRAY['sales'::text, 'nurture'::text])) AND (destination_type = 'in_house'::text)) OR ((b2c_lane IS NULL) AND (destination_type = 'partner'::text)))),
    CONSTRAINT allocations_check CHECK (((destination_type = 'partner'::text) = (partner_id IS NOT NULL))),
    CONSTRAINT allocations_check1 CHECK (((destination_type = 'partner'::text) OR (status = ANY (ARRAY['handed_off'::text, 'closed'::text])))),
    CONSTRAINT allocations_destination_type_check CHECK ((destination_type = ANY (ARRAY['partner'::text, 'in_house'::text]))),
    CONSTRAINT allocations_mode_check CHECK ((mode = ANY (ARRAY['commission_first'::text, 'exploration'::text, 'minimum'::text, 'rule'::text, 'manual'::text, 'fallback'::text, 'performance'::text, 'holdout'::text]))),
    CONSTRAINT allocations_origin_check CHECK ((origin = ANY (ARRAY['auto'::text, 'pass'::text, 'to_partners'::text, 'requalify'::text, 'reroute'::text, 'sandbox'::text]))),
    CONSTRAINT allocations_stage_check CHECK ((stage = ANY (ARRAY['A'::text, 'B'::text, 'C'::text]))),
    CONSTRAINT allocations_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'pushing'::text, 'pushed'::text, 'accepted'::text, 'duplicate'::text, 'rejected'::text, 'failed'::text, 'recalled'::text, 'handed_off'::text, 'closed'::text])))
);
CREATE TABLE public.student_leads (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    whatsapp_number text,
    student_name text,
    interested_course text,
    highest_qualification text,
    lead_status text DEFAULT 'UNQUALIFIED'::text,
    is_hot_sent_to_crm boolean DEFAULT false,
    lead_source text,
    referral_code text,
    ip_address text,
    device text,
    fingerprint text,
    activation_code text,
    lead_stage text,
    "Comments" text,
    email_id text,
    academic_percentage_gpa text,
    enrollment_timeline text,
    university_preference text,
    work_experience_years text,
    current_job_role text,
    annual_budget text,
    current_city_country text,
    study_mode_preference text,
    preferred_counseling_time text,
    primary_motivation text,
    enrolled_program text,
    enrolled_university text,
    enrollment_date date,
    admission_readiness text,
    lead_classification text,
    name_confirmed boolean,
    email_confirmed boolean,
    program_level text,
    eligibility_status text,
    extraction_confidence text,
    intent_type text,
    alternate_phone text,
    phone_verified_at timestamp with time zone,
    phone_verification_method text,
    email_verified_at timestamp with time zone,
    preferred_language text,
    city text,
    state text,
    country text DEFAULT 'India'::text,
    enquirer_relation text,
    guardian_name text,
    guardian_phone text,
    interested_specialization text,
    field_of_interest text,
    interested_university text,
    current_study text,
    academic_score_pct numeric(5,2),
    annual_budget_inr numeric(12,2),
    work_experience_years_num numeric(4,1),
    programme_segment text,
    channel text,
    source_detail text,
    campaign text,
    utm_source text,
    utm_medium text,
    utm_campaign text,
    utm_content text,
    utm_term text,
    click_ids jsonb,
    landing_url text,
    referrer_url text,
    referred_by_code text,
    publisher_id bigint,
    first_touch_at timestamp with time zone,
    last_touch_at timestamp with time zone,
    last_touch_source text,
    consent_sales_at timestamp with time zone,
    consent_marketing_at timestamp with time zone,
    consent_partner_share_at timestamp with time zone,
    consent_text_version text,
    is_opted_out boolean DEFAULT false NOT NULL,
    opted_out_at timestamp with time zone,
    opted_out_channels text[],
    email_bounced_at timestamp with time zone,
    stage text,
    sub_stage text,
    stage_changed_at timestamp with time zone,
    temperature text,
    lead_score integer,
    is_sales_ready boolean DEFAULT false NOT NULL,
    sales_ready_at timestamp with time zone,
    owner_user_id uuid,
    team_id bigint,
    assigned_at timestamp with time zone,
    first_contacted_at timestamp with time zone,
    last_contacted_at timestamp with time zone,
    last_activity_at timestamp with time zone,
    contact_attempts integer DEFAULT 0 NOT NULL,
    next_task_due_at timestamp with time zone,
    lost_reason text,
    lost_at timestamp with time zone,
    cycle_no integer DEFAULT 1 NOT NULL,
    reopened_at timestamp with time zone,
    is_duplicate_suspect boolean DEFAULT false NOT NULL,
    merged_into_id bigint,
    destination_type text,
    partner_id bigint,
    allocation_id bigint,
    allocated_at timestamp with time zone,
    allocation_reason text,
    partner_record_id text,
    partner_stage_raw text,
    partner_sub_stage_raw text,
    partner_synced_at timestamp with time zone,
    duplicate_claim_count integer DEFAULT 0 NOT NULL,
    application_id text,
    application_status text,
    applied_at timestamp with time zone,
    fee_amount_inr numeric(12,2),
    fee_paid_inr numeric(12,2),
    enrollment_status text,
    enrollment_verified_at timestamp with time zone,
    expected_net_revenue_inr numeric(12,2),
    realised_net_revenue_inr numeric(12,2),
    active_journey_id bigint,
    last_campaign_id bigint,
    last_marketing_message_at timestamp with time zone,
    first_agent_channel text,
    chatwoot_conversation_id bigint,
    web_session_id text,
    is_bot_paused boolean DEFAULT false NOT NULL,
    last_agent_message_at timestamp with time zone,
    portal_user_id uuid,
    open_ticket_count integer DEFAULT 0 NOT NULL,
    custom_fields jsonb DEFAULT '{}'::jsonb NOT NULL,
    zoho_lead_id text,
    is_test boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text,
    deleted_at timestamp with time zone,
    anonymised_at timestamp with time zone,
    sla_alerted_at timestamp with time zone,
    score_updated_at timestamp with time zone,
    partner_stale_at timestamp with time zone,
    CONSTRAINT student_leads_destination_chk CHECK ((destination_type = ANY (ARRAY['in_house'::text, 'partner'::text]))),
    CONSTRAINT student_leads_score_chk CHECK (((academic_score_pct >= (0)::numeric) AND (academic_score_pct <= (100)::numeric))),
    CONSTRAINT student_leads_temperature_chk CHECK ((temperature = ANY (ARRAY['hot'::text, 'warm'::text, 'cold'::text])))
);
ALTER TABLE b2b.allocations ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME b2b.allocations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.catalog_programs (
    id bigint NOT NULL,
    university_id bigint NOT NULL,
    level text,
    level_raw text,
    course text,
    course_key text,
    dual boolean DEFAULT false NOT NULL,
    specialization text,
    program_name text NOT NULL,
    mode text,
    fee_yearly numeric,
    fee_semester numeric,
    fee_total numeric,
    fee_exam numeric,
    fee_registration numeric,
    fee_other jsonb,
    min_qualification text,
    min_pct_general numeric,
    min_pct_reserved numeric,
    eligibility_text text,
    brochure_url text,
    source_row integer,
    flags text[],
    active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    program_key text,
    search_doc tsvector GENERATED ALWAYS AS (to_tsvector('simple'::regconfig, ((((COALESCE(program_name, ''::text) || ' '::text) || COALESCE(specialization, ''::text)) || ' '::text) || COALESCE(course, ''::text)))) STORED,
    source_file text
);
CREATE TABLE public.catalog_universities (
    id bigint NOT NULL,
    name text NOT NULL,
    short_name text,
    institution_type text,
    recognitions text[],
    accreditation_text text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.catalog_synonyms (
    alias text NOT NULL,
    course_key text NOT NULL
);
CREATE SEQUENCE public.catalog_programs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.catalog_programs_id_seq OWNED BY public.catalog_programs.id;
CREATE SEQUENCE public.catalog_universities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.catalog_universities_id_seq OWNED BY public.catalog_universities.id;
ALTER TABLE public.student_leads ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.student_leads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE TABLE public.touchpoints (
    id bigint NOT NULL,
    lead_id bigint NOT NULL,
    phone text NOT NULL,
    source_system text NOT NULL,
    event_type text NOT NULL,
    source text,
    campaign text,
    attribution jsonb DEFAULT '{}'::jsonb NOT NULL,
    idempotency_key text,
    payload jsonb,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE SEQUENCE public.touchpoints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.touchpoints_id_seq OWNED BY public.touchpoints.id;
CREATE TABLE public.w2_conversations (
    phone text NOT NULL,
    conversation_id bigint,
    account_id bigint,
    state jsonb DEFAULT '{}'::jsonb NOT NULL,
    classification text DEFAULT 'UNQUALIFIED'::text NOT NULL,
    readiness text DEFAULT 'EXPLORING'::text NOT NULL,
    eligibility text DEFAULT 'INSUFFICIENT_DATA'::text NOT NULL,
    pending_question text DEFAULT 'NONE'::text NOT NULL,
    bot_paused boolean DEFAULT false NOT NULL,
    opted_out boolean DEFAULT false NOT NULL,
    consent_at timestamp with time zone,
    escalated_at timestamp with time zone,
    lead_source text,
    activation_code text,
    crm_record_id text,
    version integer DEFAULT 0 NOT NULL,
    lock_id text,
    lock_until timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    access_code text,
    access_at timestamp with time zone,
    attribution jsonb,
    last_student_at timestamp with time zone,
    nurture_step integer DEFAULT 0 NOT NULL,
    nurture_next_at timestamp with time zone
);
CREATE TABLE public.w2_kb_chunks (
    id bigint NOT NULL,
    doc_id bigint NOT NULL,
    chunk_no integer NOT NULL,
    content text NOT NULL,
    embedding public.vector(768),
    search_doc tsvector GENERATED ALWAYS AS (to_tsvector('simple'::regconfig, content)) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE SEQUENCE public.w2_kb_chunks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.w2_kb_chunks_id_seq OWNED BY public.w2_kb_chunks.id;
CREATE TABLE public.w2_kb_docs (
    id bigint NOT NULL,
    source_file text NOT NULL,
    name text,
    mime text,
    modified_at timestamp with time zone,
    chunks integer DEFAULT 0 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE SEQUENCE public.w2_kb_docs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.w2_kb_docs_id_seq OWNED BY public.w2_kb_docs.id;
CREATE TABLE public.w2_messages (
    id bigint NOT NULL,
    phone text NOT NULL,
    direction text NOT NULL,
    kind text DEFAULT 'chat'::text NOT NULL,
    message_id text,
    run_id text,
    content text,
    answer_mode text,
    reply_source text,
    model text,
    prompt_tokens integer,
    cached_tokens integer,
    output_tokens integer,
    latency_ms integer,
    verify_errors jsonb,
    sent boolean,
    meta jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.w2_learnings (
    id bigint NOT NULL,
    report_id bigint,
    kind text NOT NULL,
    title text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    rationale text,
    evidence jsonb,
    confidence numeric,
    status text DEFAULT 'proposed'::text NOT NULL,
    auto boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    decided_at timestamp with time zone,
    decided_by text
);
CREATE SEQUENCE public.w2_learnings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.w2_learnings_id_seq OWNED BY public.w2_learnings.id;
CREATE SEQUENCE public.w2_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.w2_messages_id_seq OWNED BY public.w2_messages.id;
CREATE TABLE public.w2_meta (
    key text NOT NULL,
    value jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.w2_prompts (
    name text NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    body text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE public.w2_search_cache (
    key text NOT NULL,
    version integer NOT NULL,
    result jsonb NOT NULL,
    hits integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_hit_at timestamp with time zone
);
CREATE TABLE public.w2_trusted (
    phone text NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_test boolean DEFAULT false NOT NULL
);
ALTER TABLE ONLY public.catalog_programs ALTER COLUMN id SET DEFAULT nextval('public.catalog_programs_id_seq'::regclass);
ALTER TABLE ONLY public.catalog_universities ALTER COLUMN id SET DEFAULT nextval('public.catalog_universities_id_seq'::regclass);
ALTER TABLE ONLY public.touchpoints ALTER COLUMN id SET DEFAULT nextval('public.touchpoints_id_seq'::regclass);
ALTER TABLE ONLY public.w2_kb_chunks ALTER COLUMN id SET DEFAULT nextval('public.w2_kb_chunks_id_seq'::regclass);
ALTER TABLE ONLY public.w2_kb_docs ALTER COLUMN id SET DEFAULT nextval('public.w2_kb_docs_id_seq'::regclass);
ALTER TABLE ONLY public.w2_learnings ALTER COLUMN id SET DEFAULT nextval('public.w2_learnings_id_seq'::regclass);
ALTER TABLE ONLY public.w2_messages ALTER COLUMN id SET DEFAULT nextval('public.w2_messages_id_seq'::regclass);

CREATE OR REPLACE FUNCTION public.crm_norm_phone(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when d = '' then null
    when length(d) = 10 then '91' || d
    when length(d) = 11 and left(d, 1) = '0' then '91' || substr(d, 2)
    else d end
  from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_find_lead(p_phone text)
 RETURNS student_leads
 LANGUAGE sql
 STABLE
AS $function$
  select l from student_leads l
   where regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') = p_phone
     and l.deleted_at is null and l.merged_into_id is null
   order by l.created_at desc limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.w2_is_test(p_phone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(p_phone, '') similar to '910000[0-9]{6}' or exists (select 1 from w2_trusted t where t.phone = p_phone and t.is_test);
$function$
;

CREATE OR REPLACE FUNCTION public.w2_crm_owned(p_phone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce((
    select (l.owner_user_id is not null and l.destination_type is distinct from 'partner')         -- B2C counsellor assigned
        or exists (select 1 from b2b.allocations a                                                  -- a partner accepted it
                    where a.id = l.allocation_id and a.lead_id = l.id
                      and a.destination_type = 'partner' and a.status = 'accepted')
        or (l.destination_type = 'partner'                                                           -- legacy Eduwit CRM allocation
            and not exists (select 1 from b2b.allocations a where a.id = l.allocation_id and a.lead_id = l.id))
      from crm_find_lead(p_phone) l where l.id is not null), false);
$function$
;

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

CREATE OR REPLACE FUNCTION public.student_leads_touch()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin new.updated_at := now(); return new; end $function$
;

CREATE OR REPLACE FUNCTION public.student_leads_bulk_delete_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare n int;
begin
  if coalesce(current_setting('crm.allow_bulk_delete', true), '') = 'on' then return null; end if;
  if tg_op = 'TRUNCATE' then
    raise exception 'student_leads: TRUNCATE is blocked. If you really mean it: begin; set local crm.allow_bulk_delete = ''on''; truncate ...; commit;';
  end if;
  select count(*) into n from old_rows;
  if n > 5 then
    raise exception 'student_leads: refusing to delete % leads in one go (max 5). If you really mean it: begin; set local crm.allow_bulk_delete = ''on''; delete ...; commit;', n;
  end if;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION public.w2_fee_sanity(p_level text, p_dual boolean, p_y numeric, p_s numeric, p_t numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare
  -- allowed ratio of total to yearly fee, by programme length
  t_lo numeric; t_hi numeric;
  y numeric := nullif(p_y, 0); s numeric := nullif(p_s, 0); t numeric := nullif(p_t, 0);
  ys boolean; yt boolean; st boolean;          -- pair consistent? (null = pair not present)
  bad int;
  note text := null;
  k int;
  w numeric;                                   -- extra tolerance when only two fees exist (one-time charges blur them)
begin
  if coalesce(p_dual, false) then t_lo := 1.0; t_hi := 6.0;           -- dual degrees: 4-5 years
  elsif upper(coalesce(p_level, '')) = 'PG' then t_lo := 1.7; t_hi := 2.8;   -- 2-year masters (+ one-time fees)
  elsif upper(coalesce(p_level, '')) = 'UG' then t_lo := 2.6; t_hi := 4.6;   -- 3- or 4-year bachelors
  else t_lo := 0.9; t_hi := 2.6;                                      -- diploma, certificate: 1-2 years
  end if;

  -- A "yearly" fee that is exactly the semester fee times the whole programme's semesters is really the total.
  if y is not null and s is not null and t is null then
    foreach k in array array[4, 6, 8] loop
      if abs(y - s * k) <= y * 0.02 and (y / s) > 2.7 then
        return jsonb_build_object('y', null, 's', s, 't', y, 'note', 'fee check: yearly fee was the total for ' || k || ' semesters; moved to total');
      end if;
    end loop;
  end if;

  w := case when (y is null)::int + (s is null)::int + (t is null)::int = 1 then 0.15 else 0 end;
  ys := case when y is null or s is null then null else (2 * s / y) between 0.75 * (1 - w) and 1.35 * (1 + w) end;
  yt := case when y is null or t is null then null else (t / y) between t_lo * (1 - w) and t_hi * (1 + w) end;
  st := case when s is null or t is null then null else (t / s) between 2 * t_lo * (1 - w) and 2 * t_hi * (1 + w) end;
  bad := (case when ys = false then 1 else 0 end) + (case when yt = false then 1 else 0 end) + (case when st = false then 1 else 0 end);

  if bad = 0 then
    return jsonb_build_object('y', y, 's', s, 't', t, 'note', null);
  end if;

  if y is not null and s is not null and t is not null then
    if bad = 1 then          -- one pair slightly off (e.g. first semester includes registration): keep all, flag for review
      return jsonb_build_object('y', y, 's', s, 't', t, 'note', 'fee check: yearly, semester and total do not fully agree; review the sheet');
    end if;
    if bad = 3 then
      return jsonb_build_object('y', null, 's', null, 't', null, 'note', 'fee check: yearly, semester and total all contradict each other; all dropped');
    end if;
    -- bad = 2: the field in both failing pairs is the odd one out
    if st then return jsonb_build_object('y', null, 's', s, 't', t, 'note', 'fee check: yearly fee contradicted semester and total; yearly dropped'); end if;
    if yt then return jsonb_build_object('y', y, 's', null, 't', t, 'note', 'fee check: semester fee contradicted yearly and total; semester dropped'); end if;
    return jsonb_build_object('y', y, 's', s, 't', null, 'note', 'fee check: total fee contradicted yearly and semester; total dropped');
  end if;

  -- only two fees and they disagree: no way to tell which is right
  return jsonb_build_object('y', null, 's', null, 't', null,
    'note', 'fee check: ' || concat_ws(' and ', case when y is not null then 'yearly' end, case when s is not null then 'semester' end,
                                       case when t is not null then 'total' end) || ' fees contradict each other; both dropped');
end $function$
;

CREATE OR REPLACE FUNCTION public.catalog_programs_fee_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare r jsonb; v_orig jsonb;
begin
  -- fee_other is normally an object; keep any other JSON value under "value"
  if new.fee_other is not null and jsonb_typeof(new.fee_other) <> 'object' then
    new.fee_other := case when jsonb_typeof(new.fee_other) = 'null' then '{}'::jsonb else jsonb_build_object('value', new.fee_other) end;
  end if;
  -- an update that re-saves an already-cleaned row keeps its original import values
  v_orig := coalesce(new.fee_other->'as_imported',
                     jsonb_build_object('fee_yearly', new.fee_yearly, 'fee_semester', new.fee_semester, 'fee_total', new.fee_total));
  if tg_op = 'UPDATE' and new.fee_other ? 'as_imported'
     and (new.fee_yearly, new.fee_semester, new.fee_total) is not distinct from (old.fee_yearly, old.fee_semester, old.fee_total) then
    r := w2_fee_sanity(new.level, new.dual, (v_orig->>'fee_yearly')::numeric, (v_orig->>'fee_semester')::numeric, (v_orig->>'fee_total')::numeric);
  else
    v_orig := jsonb_build_object('fee_yearly', new.fee_yearly, 'fee_semester', new.fee_semester, 'fee_total', new.fee_total);
    r := w2_fee_sanity(new.level, new.dual, new.fee_yearly, new.fee_semester, new.fee_total);
  end if;
  new.flags := array(select f from unnest(coalesce(new.flags, '{}')) f where f not like 'fee check:%');
  new.fee_other := coalesce(new.fee_other, '{}'::jsonb) - 'as_imported';
  new.fee_yearly := (r->>'y')::numeric;
  new.fee_semester := (r->>'s')::numeric;
  new.fee_total := (r->>'t')::numeric;
  if r->>'note' is not null then
    new.flags := new.flags || (r->>'note');
    new.fee_other := new.fee_other || jsonb_build_object('as_imported', v_orig);
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.w2_bump(p_key text)
 RETURNS integer
 LANGUAGE sql
AS $function$
insert into w2_meta (key, value) values (p_key, '1'::jsonb)
on conflict (key) do update set value = to_jsonb(coalesce((w2_meta.value #>> '{}')::int, 0) + 1), updated_at = now()
returning (value #>> '{}')::int;
$function$
;

CREATE OR REPLACE FUNCTION public.w2_build_prompt(p_name text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
v_base    text := (select body from w2_prompts where name = p_name);
v_lessons text;
v_kinds   text[] := case p_name when 'extractor' then array['extractor_rule', 'extractor_example', 'intent_phrase']
else array['counselor_guideline', 'counselor_example'] end;
begin
if v_base is null then return null; end if;
select string_agg('- ' || coalesce(payload->>'text', title), E'\n' order by id) into v_lessons
from (select id, payload, title from w2_learnings
where status in ('approved', 'applied') and kind = any(v_kinds)
order by id limit 40) l;
return v_base
|| case when p_name = 'extractor' then E'\n\n' || w2_catalog_index() else '' end
|| case when v_lessons is not null then E'\n\nLESSONS FROM REVIEWED CONVERSATIONS (follow them):\n' || v_lessons else '' end;
end $function$
;

CREATE OR REPLACE FUNCTION public.w2_catalog_index()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
select coalesce('CATALOG INDEX (course: common specializations | modes | levels). Use it only to recognise and spell course and specialization names; never add a course or specialization the student did not state.' || E'\n' ||
string_agg(line, E'\n' order by n desc, line), '')
from (
select count(*) as n,
min(p.course) || ': ' ||
coalesce((select string_agg(s.specialization, ', ') from (
select specialization from catalog_programs p2
where p2.active and p2.course_key = p.course_key and p2.specialization <> 'General'
group by specialization order by count(*) desc, specialization limit 6) s), 'general') ||
' | ' || string_agg(distinct p.mode, '/') || ' | ' || string_agg(distinct coalesce(p.level, '?'), '/') as line
from catalog_programs p
where p.active and p.course_key is not null and p.course_key <> ''
group by p.course_key
order by count(*) desc
limit 80
) x;
$function$
;

CREATE OR REPLACE FUNCTION public.w2_search_programs(q jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_course text := nullif(q->>'course', '');
  v_spec   text := nullif(q->>'specialization', '');
  v_level  text := nullif(q->>'level', '');
  v_mode   text := nullif(q->>'mode', '');
  v_field  text := nullif(q->>'field', '');
  v_uni    text := nullif(q->>'university', '');
  v_key    text;
  v_total  int := 0;
  v_spec_ok boolean := true;
  v_mode_ok boolean := true;
  v_rows   jsonb := '[]'::jsonb;
  v_specs  jsonb := '[]'::jsonb;
  v_modes  jsonb := '[]'::jsonb;
  v_unis   jsonb := '[]'::jsonb;
  v_match  jsonb := '{}'::jsonb;
  v_names  text[] := '{}';
  v_uni_ids bigint[] := '{}';
  v_tsq    tsquery;
begin
  if v_spec is not null then
    v_spec := coalesce((select a.full_name from (values ('ai','Artificial Intelligence'),('ml','Machine Learning'),('aiml','Artificial Intelligence & Machine Learning'),
      ('hr','Human Resource'),('hrm','Human Resource Management'),('it','Information Technology'),('ba','Business Analytics'),('scm','Supply Chain'),
      ('ds','Data Science'),('ib','International Business'),('om','Operations Management'),('pm','Project Management'),('dm','Digital Marketing'),
      ('fin','Finance'),('mkt','Marketing'),('ops','Operations')) as a(abbr, full_name) where a.abbr = lower(regexp_replace(v_spec, '[^a-zA-Z]', '', 'g'))), v_spec);
  end if;
  if v_course is not null then
    select coalesce((select course_key from catalog_synonyms where alias = v_course limit 1), v_course) into v_key;

    select coalesce(jsonb_agg(s.specialization order by s.n desc), '[]'::jsonb) into v_specs
      from (select specialization, count(*) n from catalog_programs where active and course_key = v_key and specialization <> 'General'
             group by specialization order by 2 desc limit 8) s;
    select coalesce(jsonb_agg(distinct mode), '[]'::jsonb) into v_modes from catalog_programs where active and course_key = v_key;

    if v_spec is not null then
      select coalesce(jsonb_object_agg(x.s, x.sc), '{}'::jsonb) into v_match
        from (select d.s, greatest(similarity(d.s, v_spec),
                                   case when length(v_spec) >= 4 and (d.s ilike '%' || v_spec || '%' or v_spec ilike '%' || d.s || '%') then 1
                                        when length(v_spec) < 4 and d.s ~* ('\m' || v_spec || '\M') then 1 else 0 end) as sc
                from (select distinct specialization as s from catalog_programs where active and course_key = v_key and specialization is not null) d) x
       where x.sc > 0.35;
      v_spec_ok := v_match <> '{}'::jsonb;
      v_names := array(select jsonb_object_keys(v_match));
    end if;
    if v_mode is not null and not exists (select 1 from catalog_programs where active and course_key = v_key and mode = v_mode) then
      v_mode_ok := false;
    end if;
    if v_uni is not null and length(v_uni) >= 3 then
      v_uni_ids := array(select u.id from catalog_universities u
                          where u.name ilike '%' || v_uni || '%' or u.short_name ilike '%' || v_uni || '%' or v_uni ilike '%' || u.short_name || '%'
                             -- 5 Oct 2026: "DY Patil" must match "D. Y. Patil University" (ignore dots, spaces, case)
                             or regexp_replace(lower(u.name), '[^a-z0-9]', '', 'g') like '%' || regexp_replace(lower(v_uni), '[^a-z0-9]', '', 'g') || '%');
    end if;

    select count(*) into v_total from catalog_programs p
     where p.active and p.course_key = v_key
       and (v_spec is null or not v_spec_ok or p.specialization = any(v_names))
       and (v_mode is null or not v_mode_ok or p.mode = v_mode);

    select coalesce(jsonb_agg(r order by r.uni_match desc, r.match desc, r.fee_yearly nulls last), '[]'::jsonb) into v_rows from (
      select p.id, u.name as university, u.short_name as university_short, p.level, p.course, p.specialization, p.program_name, p.mode,
             p.fee_yearly, p.fee_semester, p.fee_total, p.fee_exam, p.fee_registration,
             p.min_qualification, p.min_pct_general, p.min_pct_reserved, p.brochure_url, p.dual,
             nullif(regexp_replace(coalesce(p.fee_other->>'Emi', ''), '[^0-9.]', '', 'g'), '')::numeric as fee_emi,
             (p.fee_other ?| array['Pay After Placement Fees', 'Fees After Placement Fees', 'Program Fees (after Placement Fees)', 'Pay After Placemnet Fees']) as pay_after_placement,
             (coalesce(p.eligibility_text, '') ~* 'loan') as loan_available,
             (case when v_spec is null or not v_spec_ok then 0.5 else coalesce((v_match->>p.specialization)::float8, 0) end) as match,
             (p.university_id = any(v_uni_ids)) as uni_match
        from catalog_programs p join catalog_universities u on u.id = p.university_id
       where p.active and p.course_key = v_key
         and (v_spec is null or not v_spec_ok or p.specialization = any(v_names))
         and (v_mode is null or not v_mode_ok or p.mode = v_mode)
       order by uni_match desc, match desc, fee_yearly nulls last
       limit 30
    ) r;
    select coalesce(jsonb_agg(jsonb_build_object('name', u.name, 'short_name', u.short_name)), '[]'::jsonb) into v_unis
      from catalog_universities u
     where u.id in (select p.university_id from catalog_programs p where p.active and p.course_key = v_key);
  elsif v_field is not null then
    v_tsq := websearch_to_tsquery('simple', v_field);
    select coalesce(jsonb_agg(r order by r.match desc), '[]'::jsonb) into v_rows from (
      select p.id, u.name as university, u.short_name as university_short, p.level, p.course, p.specialization, p.program_name, p.mode,
             p.fee_yearly, p.fee_semester, p.fee_total, p.fee_exam, p.fee_registration,
             p.min_qualification, p.min_pct_general, p.min_pct_reserved, p.brochure_url, p.dual,
             nullif(regexp_replace(coalesce(p.fee_other->>'Emi', ''), '[^0-9.]', '', 'g'), '')::numeric as fee_emi,
             (p.fee_other ?| array['Pay After Placement Fees', 'Fees After Placement Fees', 'Program Fees (after Placement Fees)', 'Pay After Placemnet Fees']) as pay_after_placement,
             (coalesce(p.eligibility_text, '') ~* 'loan') as loan_available,
             greatest(ts_rank(p.search_doc, v_tsq), word_similarity(v_field, p.program_name), word_similarity(v_field, p.specialization)) as match
        from catalog_programs p join catalog_universities u on u.id = p.university_id
       where p.active and (v_level is null or p.level = v_level)
         and (p.search_doc @@ v_tsq or p.specialization ilike '%' || v_field || '%' or p.program_name ilike '%' || v_field || '%')
       order by match desc
       limit 15
    ) r;
    v_total := jsonb_array_length(v_rows);
    select coalesce(jsonb_agg(distinct jsonb_build_object('name', u.name, 'short_name', u.short_name)), '[]'::jsonb) into v_unis
      from catalog_universities u where u.name in (select x->>'university' from jsonb_array_elements(v_rows) x);
  end if;

  return jsonb_build_object('rows', v_rows, 'total_for_course', v_total, 'course_key', v_key, 'specializations', v_specs,
                            'modes', v_modes, 'spec_matched', v_spec_ok, 'mode_matched', v_mode_ok, 'universities', v_unis);
end $function$
;

CREATE OR REPLACE FUNCTION public.w2_search_programs_cached(q jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_key  text := md5(lower(coalesce(q, '{}'::jsonb)::text));
  v_ver  int := coalesce((select (value #>> '{}')::int from w2_meta where key = 'catalog_version'), 1);
  v_res  jsonb;
begin
  if q is null or q = '{}'::jsonb then return w2_search_programs('{}'::jsonb); end if;
  select result into v_res from w2_search_cache where key = v_key and version = v_ver;
  if v_res is not null then
    update w2_search_cache set hits = hits + 1, last_hit_at = now()
     where key = v_key and (last_hit_at is null or last_hit_at < now() - interval '30 seconds');
    return v_res || jsonb_build_object('cached', true);
  end if;
  v_res := w2_search_programs(q);
  insert into w2_search_cache (key, version, result) values (v_key, v_ver, v_res)
  on conflict (key) do update set version = excluded.version, result = excluded.result, hits = 0, created_at = now();
  return v_res || jsonb_build_object('cached', false);
end $function$
;

CREATE OR REPLACE FUNCTION public.w2_kb_search(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
v_text  text := left(coalesce(p->>'text', ''), 500);
v_emb   vector(768) := case when jsonb_typeof(p->'embedding') = 'array' then (p->>'embedding')::vector else null end;
v_limit int := least(coalesce((p->>'limit')::int, 3), 6);
v_tsq   tsquery := websearch_to_tsquery('simple', v_text);
begin
return coalesce((
with vec as (
select c.id, row_number() over (order by c.embedding <=> v_emb) as rk, 1 - (c.embedding <=> v_emb) as sim
from w2_kb_chunks c join w2_kb_docs d on d.id = c.doc_id and d.active
where v_emb is not null and c.embedding is not null
order by c.embedding <=> v_emb limit 12
), fts as (
select c.id, row_number() over (order by ts_rank(c.search_doc, v_tsq) desc, word_similarity(v_text, c.content) desc) as rk
from w2_kb_chunks c join w2_kb_docs d on d.id = c.doc_id and d.active
where v_text <> '' and (c.search_doc @@ v_tsq or word_similarity(v_text, c.content) > 0.35)
order by ts_rank(c.search_doc, v_tsq) desc, word_similarity(v_text, c.content) desc limit 12
), fused as (
select id, sum(1.0 / (60 + rk)) as score, max(sim) as sim, bool_or(src = 'fts') as in_fts from (
select id, rk, sim, 'vec' as src from vec union all select id, rk, null::float8, 'fts' from fts) u
group by id
)
select jsonb_agg(jsonb_build_object('ref', 'K' || rn, 'doc', d.name, 'text', c.content, 'score', round(f.score::numeric, 4),
'similarity', round(f.sim::numeric, 3)) order by rn)
from (select *, row_number() over (order by score desc) rn from fused where in_fts or sim >= 0.55) f
join w2_kb_chunks c on c.id = f.id join w2_kb_docs d on d.id = c.doc_id
where rn <= v_limit
), '[]'::jsonb);
end $function$
;

ALTER TABLE ONLY b2b.allocations
    ADD CONSTRAINT allocations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY b2b.allocations
    ADD CONSTRAINT allocations_reference_key UNIQUE (reference);

ALTER TABLE ONLY public.catalog_programs
    ADD CONSTRAINT catalog_programs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.catalog_synonyms
    ADD CONSTRAINT catalog_synonyms_pkey PRIMARY KEY (alias);

ALTER TABLE ONLY public.catalog_universities
    ADD CONSTRAINT catalog_universities_name_key UNIQUE (name);

ALTER TABLE ONLY public.catalog_universities
    ADD CONSTRAINT catalog_universities_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.student_leads
    ADD CONSTRAINT student_leads_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.touchpoints
    ADD CONSTRAINT touchpoints_idempotency_key_key UNIQUE (idempotency_key);

ALTER TABLE ONLY public.touchpoints
    ADD CONSTRAINT touchpoints_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.w2_conversations
    ADD CONSTRAINT w2_conversations_pkey PRIMARY KEY (phone);

ALTER TABLE ONLY public.w2_kb_chunks
    ADD CONSTRAINT w2_kb_chunks_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.w2_kb_docs
    ADD CONSTRAINT w2_kb_docs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.w2_kb_docs
    ADD CONSTRAINT w2_kb_docs_source_file_key UNIQUE (source_file);

ALTER TABLE ONLY public.w2_learnings
    ADD CONSTRAINT w2_learnings_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.w2_messages
    ADD CONSTRAINT w2_messages_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.w2_meta
    ADD CONSTRAINT w2_meta_pkey PRIMARY KEY (key);

ALTER TABLE ONLY public.w2_prompts
    ADD CONSTRAINT w2_prompts_pkey PRIMARY KEY (name);

ALTER TABLE ONLY public.w2_search_cache
    ADD CONSTRAINT w2_search_cache_pkey PRIMARY KEY (key);

ALTER TABLE ONLY public.w2_trusted
    ADD CONSTRAINT w2_trusted_pkey PRIMARY KEY (phone);

CREATE INDEX allocations_hold_idx ON b2b.allocations USING btree (hold_until) WHERE (status = 'pushed'::text);

CREATE INDEX allocations_lead_in_house_idx ON b2b.allocations USING btree (lead_id, created_at DESC) WHERE (destination_type = 'in_house'::text);

CREATE INDEX allocations_lead_status_idx ON b2b.allocations USING btree (lead_id, status);

CREATE INDEX allocations_lost_grace_idx ON b2b.allocations USING btree (lost_grace_until) WHERE ((lost_at IS NOT NULL) AND (lost_revived_at IS NULL));

CREATE UNIQUE INDEX allocations_one_open_per_cycle ON b2b.allocations USING btree (lead_id, cycle_no) WHERE (status = ANY (ARRAY['queued'::text, 'pushing'::text, 'pushed'::text, 'accepted'::text, 'handed_off'::text]));

CREATE INDEX allocations_partner_created_idx ON b2b.allocations USING btree (partner_id, created_at DESC) WHERE (partner_id IS NOT NULL);

CREATE INDEX allocations_push_due_idx ON b2b.allocations USING btree (next_push_at) WHERE (status = ANY (ARRAY['queued'::text, 'pushing'::text]));

CREATE INDEX allocations_segment_exact_idx ON b2b.allocations USING btree (segment_exact, partner_id) WHERE (segment_exact IS NOT NULL);

CREATE INDEX allocations_segment_idx ON b2b.allocations USING btree (segment, partner_id);

CREATE INDEX catalog_programs_course_idx ON public.catalog_programs USING btree (course_key, level, mode) WHERE active;

CREATE INDEX catalog_programs_course_spec_idx ON public.catalog_programs USING btree (course_key, specialization) WHERE active;

CREATE INDEX catalog_programs_course_trgm ON public.catalog_programs USING gin (course public.gin_trgm_ops);

CREATE UNIQUE INDEX catalog_programs_key_idx ON public.catalog_programs USING btree (program_key);

CREATE INDEX catalog_programs_name_trgm ON public.catalog_programs USING gin (program_name public.gin_trgm_ops);

CREATE INDEX catalog_programs_search_idx ON public.catalog_programs USING gin (search_doc);

CREATE INDEX catalog_programs_source_idx ON public.catalog_programs USING btree (source_file);

CREATE INDEX catalog_programs_spec_trgm ON public.catalog_programs USING gin (specialization public.gin_trgm_ops);

CREATE INDEX catalog_programs_uni_idx ON public.catalog_programs USING btree (university_id);

CREATE INDEX student_leads_channel_idx ON public.student_leads USING btree (channel, created_at DESC);

CREATE INDEX student_leads_created_idx ON public.student_leads USING btree (created_at DESC);

CREATE INDEX student_leads_owner_idx ON public.student_leads USING btree (owner_user_id, next_task_due_at);

CREATE INDEX student_leads_partner_idx ON public.student_leads USING btree (partner_id, allocated_at DESC);

CREATE INDEX student_leads_phone_digits_idx ON public.student_leads USING btree (regexp_replace(COALESCE(whatsapp_number, ''::text), '\D'::text, ''::text, 'g'::text)) WHERE ((deleted_at IS NULL) AND (merged_into_id IS NULL));

CREATE INDEX student_leads_phone_idx ON public.student_leads USING btree (whatsapp_number);

CREATE INDEX student_leads_referral_idx ON public.student_leads USING btree (referral_code, created_at DESC);

CREATE INDEX student_leads_segment_idx ON public.student_leads USING btree (programme_segment);

CREATE INDEX student_leads_stage_idx ON public.student_leads USING btree (stage, stage_changed_at DESC);

CREATE INDEX student_leads_test_idx ON public.student_leads USING btree (is_test) WHERE is_test;

CREATE INDEX student_leads_updated_at_idx ON public.student_leads USING btree (updated_at);

CREATE INDEX touchpoints_lead_idx ON public.touchpoints USING btree (lead_id, occurred_at DESC);

CREATE INDEX w2_conversations_class_idx ON public.w2_conversations USING btree (classification);

CREATE INDEX w2_conversations_conv_idx ON public.w2_conversations USING btree (conversation_id);

CREATE INDEX w2_conversations_nurture_idx ON public.w2_conversations USING btree (nurture_next_at) WHERE (nurture_next_at IS NOT NULL);

CREATE INDEX w2_conversations_source_idx ON public.w2_conversations USING btree (lead_source);

CREATE INDEX w2_kb_chunks_doc_idx ON public.w2_kb_chunks USING btree (doc_id, chunk_no);

CREATE INDEX w2_kb_chunks_fts_idx ON public.w2_kb_chunks USING gin (search_doc);

CREATE INDEX w2_kb_chunks_trgm_idx ON public.w2_kb_chunks USING gin (content public.gin_trgm_ops);

CREATE INDEX w2_kb_chunks_vec_idx ON public.w2_kb_chunks USING hnsw (embedding public.vector_cosine_ops);

CREATE INDEX w2_learnings_status_idx ON public.w2_learnings USING btree (status, kind);

CREATE INDEX w2_messages_created_idx ON public.w2_messages USING btree (created_at);

CREATE UNIQUE INDEX w2_messages_in_uidx ON public.w2_messages USING btree (message_id) WHERE (direction = 'in'::text);

CREATE INDEX w2_messages_phone_idx ON public.w2_messages USING btree (phone, created_at);

CREATE TRIGGER catalog_programs_fee_check_trg BEFORE INSERT OR UPDATE ON public.catalog_programs FOR EACH ROW EXECUTE FUNCTION public.catalog_programs_fee_check();

CREATE TRIGGER student_leads_bulk_delete_guard AFTER DELETE ON public.student_leads REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.student_leads_bulk_delete_guard();

CREATE TRIGGER student_leads_touch_trg BEFORE UPDATE ON public.student_leads FOR EACH ROW EXECUTE FUNCTION public.student_leads_touch();

CREATE TRIGGER student_leads_truncate_guard BEFORE TRUNCATE ON public.student_leads FOR EACH STATEMENT EXECUTE FUNCTION public.student_leads_bulk_delete_guard();

ALTER TABLE ONLY public.catalog_programs
    ADD CONSTRAINT catalog_programs_university_id_fkey FOREIGN KEY (university_id) REFERENCES public.catalog_universities(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.touchpoints
    ADD CONSTRAINT touchpoints_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES public.student_leads(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.w2_kb_chunks
    ADD CONSTRAINT w2_kb_chunks_doc_id_fkey FOREIGN KEY (doc_id) REFERENCES public.w2_kb_docs(id) ON DELETE CASCADE;

ALTER TABLE b2b.allocations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.catalog_programs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.catalog_synonyms ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.catalog_universities ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.student_leads ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.touchpoints ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.w2_conversations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.w2_kb_chunks ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.w2_kb_docs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.w2_learnings ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.w2_messages ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.w2_meta ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.w2_prompts ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.w2_search_cache ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.w2_trusted ENABLE ROW LEVEL SECURITY;


-- Production grants on lead_intake (service_role only).
revoke all on function public.lead_intake(jsonb) from public, anon, authenticated;
grant execute on function public.lead_intake(jsonb) to service_role;
