-- =====================================================================================================================
-- Snapshot of production schema taken 2026-10-17, read-only, for local dev.
-- Source: Supabase project xlseqwgyjuqhktrguhyc, reconstructed with SELECT-only catalog queries. NOTHING here was run
-- against production.
--
-- Scope: Witty 2.0's shared agent-conversation store ("the shared messages table" of the spec).
--   public.w2_messages        every inbound + outbound agent message (168 rows; backups hold ~2,300 more)
--   public.w2_conversations   one row per phone: agent state machine + qualification profile (16 rows)
--   public.w2_inbox           raw inbound queue (Chatwoot webhook), dedup on message_id (84 rows)
--   public.w2_events, w2_fact_log, w2_outbox   written in the same transaction as each outbound reply
--   public.w2_feedback        thumbs/ratings per run (0 rows)
--   Writer functions: w2_inbox_add (inbound), w2_commit_turn (outbound reply + state + CRM sync), w2_nurture_done
--   (nurture sends), w2_crm_payload (state -> lead_intake payload), w2_add_feedback; helpers w2_pv, crm_num.
--
-- KEY FACTS
--   * Everything is keyed by `phone` (digits, country code, no '+', e.g. 9198xxxxxxxx). There is NO lead_id, NO session
--     id and NO channel column on w2_messages or w2_conversations. Correlation per turn is `run_id`; Chatwoot
--     conversation id lives in w2_conversations.conversation_id and in w2_messages.meta->>'conversation_id' (inbound).
--   * direction: 'in' | 'out'. kind: 'chat' (inbound), 'reply', 'gate', 'nurture'.
--     answer_mode (out): DIRECTIONAL, PROGRAMS, ACK, ANSWER, NO_MATCH, GATE, GREETING, HANDOFF, CLOSE.
--     reply_source (out): counselor, fixed, fallback, template.  model e.g. 'gemini-3.6-flash + gemini-3.6-flash'.
--     meta keys seen: conversation_id, content_type, has_attachment, referral (in); prompt_source, knowledge,
--     catalog_cached (out); step, template (nurture).
--   * No CHECK constraints on direction/kind; no FK to student_leads. A web channel can be recorded today only through
--     meta (e.g. meta->>'channel' = 'web') — adding a real column needs approval (see db.md §4).
--   * Grants: anon/authenticated/service_role hold full table grants, RLS is ON with NO policies => service_role only.
--     The w2_* functions are SECURITY INVOKER and EXECUTE-able by PUBLIC/anon (RLS still blocks anon).
--   * Readers: b2c.witty_messages / b2c.witty_transcript (B2C CRM), b2b.lead_detail, crm_timeline__impl, health/learning
--     digests, w2_try_claim (history window for the next turn).
-- =====================================================================================================================

create sequence if not exists public.w2_messages_id_seq;
create sequence if not exists public.w2_events_id_seq;
create sequence if not exists public.w2_fact_log_id_seq;
create sequence if not exists public.w2_outbox_id_seq;
create sequence if not exists public.w2_feedback_id_seq;

CREATE TABLE IF NOT EXISTS public.w2_messages (
  id bigint DEFAULT nextval('w2_messages_id_seq'::regclass) NOT NULL,
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
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT w2_messages_pkey PRIMARY KEY (id)
);
alter sequence public.w2_messages_id_seq owned by public.w2_messages.id;
CREATE INDEX IF NOT EXISTS w2_messages_phone_idx ON public.w2_messages USING btree (phone, created_at);
CREATE INDEX IF NOT EXISTS w2_messages_created_idx ON public.w2_messages USING btree (created_at);
CREATE UNIQUE INDEX IF NOT EXISTS w2_messages_in_uidx ON public.w2_messages USING btree (message_id) WHERE (direction = 'in'::text);
alter table public.w2_messages enable row level security;

-- state jsonb keys seen: phone, phase, profile{<field>:{value,status,...}}, classification, readiness, eligibility,
-- pending_question, pending_value, flags{shown_rows,...}, recent_turns, turn_count, asks, last_ask_text, language,
-- enquirer{relation,name}, consent_at, consent_text_version, consent_partner_share_at, access, attribution, lead_source,
-- activation_code, crm_fingerprint, bot_paused, opted_out, escalated_at, revisits, fallback_streak, gate_count,
-- feedback_asked_at, feedback_asked_mode.
-- classification values: UNQUALIFIED, WARM, HOT, COLD, PROGRAM_MISMATCH (JUNK on leads). readiness: EXPLORING, PLANNING,
-- READY_NOW. eligibility default INSUFFICIENT_DATA. lead_source seen: test_harness, whatsapp_direct.
CREATE TABLE IF NOT EXISTS public.w2_conversations (
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
  nurture_next_at timestamp with time zone,
  CONSTRAINT w2_conversations_pkey PRIMARY KEY (phone)
);
CREATE INDEX IF NOT EXISTS w2_conversations_class_idx ON public.w2_conversations USING btree (classification);
CREATE INDEX IF NOT EXISTS w2_conversations_conv_idx ON public.w2_conversations USING btree (conversation_id);
CREATE INDEX IF NOT EXISTS w2_conversations_nurture_idx ON public.w2_conversations USING btree (nurture_next_at) WHERE (nurture_next_at IS NOT NULL);
CREATE INDEX IF NOT EXISTS w2_conversations_source_idx ON public.w2_conversations USING btree (lead_source);
alter table public.w2_conversations enable row level security;

CREATE TABLE IF NOT EXISTS public.w2_inbox (
  message_id text NOT NULL,
  phone text NOT NULL,
  conversation_id bigint,
  account_id bigint,
  content text,
  content_type text,
  has_attachment boolean DEFAULT false NOT NULL,
  labels jsonb,
  received_at timestamp with time zone DEFAULT now() NOT NULL,
  claimed_by text,
  processed_at timestamp with time zone,
  referral jsonb,
  CONSTRAINT w2_inbox_pkey PRIMARY KEY (message_id)
);
CREATE INDEX IF NOT EXISTS w2_inbox_pending_idx ON public.w2_inbox USING btree (phone, received_at) WHERE (processed_at IS NULL);
CREATE INDEX IF NOT EXISTS w2_inbox_phone_idx ON public.w2_inbox USING btree (phone, received_at);
alter table public.w2_inbox enable row level security;

CREATE TABLE IF NOT EXISTS public.w2_events (
  id bigint DEFAULT nextval('w2_events_id_seq'::regclass) NOT NULL,
  phone text,
  type text NOT NULL,
  run_id text,
  payload jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT w2_events_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS w2_events_phone_idx ON public.w2_events USING btree (phone, created_at);
CREATE INDEX IF NOT EXISTS w2_events_type_idx ON public.w2_events USING btree (type, created_at);
alter table public.w2_events enable row level security;

CREATE TABLE IF NOT EXISTS public.w2_fact_log (
  id bigint DEFAULT nextval('w2_fact_log_id_seq'::regclass) NOT NULL,
  phone text NOT NULL,
  turn_run text,
  field text,
  value text,
  evidence text,
  op text,
  subject text,
  accepted boolean NOT NULL,
  reject_reason text,
  model text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT w2_fact_log_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS w2_fact_log_phone_idx ON public.w2_fact_log USING btree (phone, created_at);
alter table public.w2_fact_log enable row level security;

CREATE TABLE IF NOT EXISTS public.w2_outbox (
  id bigint DEFAULT nextval('w2_outbox_id_seq'::regclass) NOT NULL,
  phone text NOT NULL,
  target text DEFAULT 'crm'::text NOT NULL,
  event_type text NOT NULL,
  idempotency_key text NOT NULL,
  payload jsonb NOT NULL,
  status text DEFAULT 'pending'::text NOT NULL,
  attempts integer DEFAULT 0 NOT NULL,
  next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
  locked_by text,
  last_error text,
  crm_record_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  sent_at timestamp with time zone,
  CONSTRAINT w2_outbox_idempotency_key_key UNIQUE (idempotency_key),
  CONSTRAINT w2_outbox_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS w2_outbox_due_idx ON public.w2_outbox USING btree (status, next_attempt_at);
alter table public.w2_outbox enable row level security;

CREATE TABLE IF NOT EXISTS public.w2_feedback (
  id bigint DEFAULT nextval('w2_feedback_id_seq'::regclass) NOT NULL,
  phone text,
  run_id text,
  source text NOT NULL,
  rating smallint,
  label text,
  comment text,
  author text,
  meta jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  reviewed_at timestamp with time zone,
  CONSTRAINT w2_feedback_pkey PRIMARY KEY (id)
);
CREATE INDEX IF NOT EXISTS w2_feedback_created_idx ON public.w2_feedback USING btree (created_at);
CREATE INDEX IF NOT EXISTS w2_feedback_phone_idx ON public.w2_feedback USING btree (phone, created_at);
alter table public.w2_feedback enable row level security;

-- =====================================================================================================================
-- Helpers
-- =====================================================================================================================
CREATE OR REPLACE FUNCTION public.w2_pv(pr jsonb, f text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when pr->f->>'status' = 'declined' then null else nullif(pr->f->>'value', '') end;
$function$;

CREATE OR REPLACE FUNCTION public.crm_num(p text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p ~ ('^\s*\d+(\.\d+)?\s*' || chr(36)) then trim(p)::numeric else null end;
$function$;

-- =====================================================================================================================
-- Writers (verbatim). Called by n8n (n8n.eduwit.in) with the service role.
-- =====================================================================================================================

-- Inbound: Chatwoot webhook -> w2_inbox (dedup on message_id) -> mirrored into w2_messages (direction 'in', kind 'chat').
CREATE OR REPLACE FUNCTION public.w2_inbox_add(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_id text;
begin
insert into w2_inbox (message_id, phone, conversation_id, account_id, content, content_type, has_attachment, labels, referral)
values (p->>'message_id', p->>'phone', (p->>'conversation_id')::bigint, (p->>'account_id')::bigint, p->>'content',
p->>'content_type', coalesce((p->>'has_attachment')::boolean, false), p->'labels',
case when jsonb_typeof(p->'referral') = 'object' then p->'referral' end)
on conflict (message_id) do nothing
returning message_id into v_id;
if v_id is not null then
insert into w2_messages (phone, direction, kind, message_id, content, meta)
values (p->>'phone', 'in', 'chat', v_id, p->>'content',
jsonb_build_object('conversation_id', p->>'conversation_id', 'content_type', p->>'content_type', 'has_attachment', coalesce((p->>'has_attachment')::boolean, false),
'referral', case when jsonb_typeof(p->'referral') = 'object' then p->'referral' end))
on conflict do nothing;
end if;
return jsonb_build_object('inserted', v_id is not null, 'phone', p->>'phone');
end $function$;

-- State -> lead_intake payload (source_system 'witty', channel 'whatsapp'). The template for a web equivalent.
-- NOTE: final_program_id / final_program_name / final_program_confirmed_at / programs_shown /
-- consent_partner_share_declined_at are emitted but are NOT in lead_intake's allow-list (kept only in touchpoints.payload).
CREATE OR REPLACE FUNCTION public.w2_crm_payload(p_phone text, p_event text, p_key text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
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
    'university_preference', w2_pv(pr, 'university_preference'),
    'interested_university', case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'university' end,
    'final_program_id',     case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'id' end,
    'final_program_name',   case when pr->'final_program'->>'status' = 'confirmed' then pr->'final_program'->>'program_name' end,
    'final_program_confirmed_at', case when pr->'final_program'->>'status' = 'confirmed' and pr->'final_program'->>'at' ~ '^\d{4}-\d{2}-\d{2}' then (pr->'final_program'->>'at')::timestamptz end,
    'programs_shown',       case when jsonb_typeof(s->'flags'->'shown_rows') = 'array' then s->'flags'->'shown_rows' end,
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
    'referred_by_code',     case when a->>'via' in ('direct', 'ctwa') then null else a->>'via' end,
    'access_code',          case when c.access_code in ('LEGACY', 'DIRECT') then null else c.access_code end,
    'ip_address',           a->>'ip',
    'device_type',          a->>'device_type',
    'device_fingerprint',   a->>'fingerprint',
    'consent_sales_at',     c.consent_at,
    'consent_partner_share_at', case when s->>'consent_partner_share_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_partner_share_at')::timestamptz end,
    'consent_marketing_at', case when s->>'consent_marketing_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_marketing_at')::timestamptz end,
    'consent_text_version', s->>'consent_text_version',
    'consent_partner_share_declined_at', case when s->>'consent_partner_share_declined_at' ~ '^\d{4}-\d{2}-\d{2}' then (s->>'consent_partner_share_declined_at')::timestamptz end,
    'is_opted_out',         c.opted_out,
    'first_agent_channel',  'whatsapp',
    'chatwoot_conversation_id', c.conversation_id,
    'is_bot_paused',        c.bot_paused,
    'last_agent_message_at', case when coalesce(p->'log'->>'content', '') <> '' then now() end
  ));
  return jsonb_build_object('source_system', 'witty', 'event_type', p_event, 'idempotency_key', p_key, 'phone', p_phone,
                            'lead', v_lead, 'attribution', a, 'occurred_at', coalesce((a->>'first_click_at')::timestamptz, (a->>'first_message_at')::timestamptz, c.created_at),
                            'is_test', w2_is_test(p_phone));
end $function$;

-- Outbound: one call per agent turn. Updates conversation state, marks inbox rows processed, logs facts + event, inserts
-- the reply into w2_messages (direction 'out'), and — for gated chats (access_code not null) — syncs the lead via
-- w2_crm_payload -> lead_intake in the same transaction (failures queue into w2_outbox; w2_outbox_retry re-delivers).
CREATE OR REPLACE FUNCTION public.w2_commit_turn(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
end $function$;

-- Nurture sends (follow-up templates): logs to w2_nurture_log (not snapshotted) and mirrors into w2_messages (kind 'nurture').
CREATE OR REPLACE FUNCTION public.w2_nurture_done(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
v_phone text := p->>'phone';
v_step  int := (p->>'step')::int;
v_next  timestamptz;
begin
insert into w2_nurture_log (phone, step, kind, template, content, status, error)
values (v_phone, v_step, coalesce(p->>'kind', 'text'), p->>'template', left(p->>'content', 2000), p->>'status', left(p->>'error', 1000));
if p->>'status' in ('sent', 'dry_run') then
insert into w2_messages (phone, direction, kind, content, reply_source, sent, meta)
values (v_phone, 'out', 'nurture', p->>'content', case when p->>'kind' = 'template' then 'template' else 'fixed' end,
p->>'status' = 'sent', jsonb_build_object('step', v_step, 'template', p->>'template'));
end if;
if coalesce((p->>'stop')::boolean, false) or v_step >= 6 then
v_next := null;
else
select greatest(last_student_at + w2_nurture_offset(v_step + 1), now() + interval '1 hour') into v_next from w2_conversations where phone = v_phone;
end if;
update w2_conversations set nurture_step = v_step, nurture_next_at = v_next where phone = v_phone;
return jsonb_build_object('phone', v_phone, 'step', v_step, 'next_at', v_next);
end $function$;

-- Feedback (counsellor '#witty 👍/👎' notes today; a web thumbs up/down could use source 'web').
CREATE OR REPLACE FUNCTION public.w2_add_feedback(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
v_text   text := btrim(regexp_replace(coalesce(p->>'comment', ''), '^\s*#witty\s*', '', 'i'));
v_rating smallint := (p->>'rating')::smallint;
v_id     bigint;
begin
if v_rating is null then
v_rating := case when v_text ~* '^(👍|\+|good|great|correct|right)' then 1
when v_text ~* '^(👎|-|bad|wrong|incorrect|poor)' then -1 else 0 end;
end if;
insert into w2_feedback (phone, run_id, source, rating, label, comment, author, meta)
values (regexp_replace(coalesce(p->>'phone', ''), '\D', '', 'g'), p->>'run_id', coalesce(p->>'source', 'counselor'), v_rating,
p->>'label', left(v_text, 2000), left(p->>'author', 120), p->'meta')
returning id into v_id;
return jsonb_build_object('id', v_id, 'rating', v_rating);
end $function$;

-- Not snapshotted (large, Witty-internal): w2_try_claim (10.5 KB: lease + history + soft gate; also calls lead_intake),
-- w2_outbox_retry, w2_bot_check, w2_redeem_code, w2_issue_code, w2_register_lead (website/landing "get a WhatsApp code":
-- writes w2_clicks + w2_access_codes, source slug from w2_sources incl. 'website'), w2_search_programs (catalogue search
-- used as Witty's tool), w2_catalog_index, w2_kb_search, w2_build_prompt / w2_turn_prompts (prompts in w2_prompts).
