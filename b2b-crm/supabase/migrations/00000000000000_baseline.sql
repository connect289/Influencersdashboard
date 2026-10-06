-- Baseline: schema of Supabase project xlseqwgyjuqhktrguhyc (public schema), generated from the catalog.
-- Excludes: n8n's internal tables, *_backup_* tables, extension-owned objects. Schema only, no data.
-- Generated 6 Oct 2026 after the two hotfix migrations, so it already contains their objects; trigger enabled/disabled
-- state is not captured (re-run 20261006095337_disable_crm_auto_assign.sql after it). Never applied to production.
set check_function_bodies = off;
set client_min_messages = warning;
create extension if not exists pg_trgm with schema public;
create extension if not exists vector with schema public;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;


create sequence if not exists public.allocations_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.calls_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.campaign_sends_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.campaigns_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.catalog_programs_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.catalog_universities_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.course_directory_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.crm_activities_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.crm_alerts_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.crm_api_keys_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.crm_notifications_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.crm_saved_views_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.crm_tasks_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.crm_teams_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.earning_rates_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.earnings_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.eduwit_knowledge_base_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.engine_decisions_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.enrollments_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.influencer_auth_id_seq as integer increment 1 minvalue 1 maxvalue 2147483647 start 1 cache 1;
create sequence if not exists public.influencer_login_attempts_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.invoices_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.journey_runs_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.journeys_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.message_templates_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.n8n_chat_histories_id_seq as integer increment 1 minvalue 1 maxvalue 2147483647 start 1 cache 1;
create sequence if not exists public.partner_events_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.partner_mapping_profiles_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.partners_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.payout_rates_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.payout_runs_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.payouts_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.routing_rules_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.segments_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.touchpoints_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.verifications_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_clicks_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_events_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_fact_log_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_feedback_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_kb_chunks_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_kb_docs_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_learning_reports_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_learnings_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_messages_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_nurture_log_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_outbox_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_security_log_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;
create sequence if not exists public.w2_test_runs_id_seq as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;

create table public.allocations (
  id bigint default nextval('allocations_id_seq'::regclass) not null,
  lead_id bigint not null,
  cycle_no integer default 1 not null,
  segment text,
  destination_type text not null,
  partner_id bigint,
  user_id uuid,
  reference text,
  status text default 'pending'::text not null,
  attempts integer default 0 not null,
  next_attempt_at timestamp with time zone default now() not null,
  last_error text,
  pushed_at timestamp with time zone,
  partner_record_id text,
  first_contact_at timestamp with time zone,
  partner_stage_raw text,
  partner_sub_stage_raw text,
  last_event_at timestamp with time zone,
  duplicate_claim jsonb,
  override boolean default false not null,
  reason text,
  engine_decision_id bigint,
  outcome text,
  outcome_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.calls (
  id bigint default nextval('calls_id_seq'::regclass) not null,
  lead_id bigint,
  user_id uuid,
  provider text default 'manual'::text not null,
  provider_call_id text,
  direction text default 'outbound'::text not null,
  from_number text,
  to_number text,
  status text default 'initiated'::text not null,
  started_at timestamp with time zone default now() not null,
  answered_at timestamp with time zone,
  ended_at timestamp with time zone,
  duration_sec integer,
  recording_url text,
  outcome text,
  notes text,
  activity_id bigint,
  raw jsonb,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.campaign_sends (
  id bigint default nextval('campaign_sends_id_seq'::regclass) not null,
  campaign_id bigint not null,
  lead_id bigint not null,
  status text default 'queued'::text not null,
  reason text,
  next_at timestamp with time zone default now() not null,
  sent_at timestamp with time zone,
  provider_message_id text,
  error text,
  created_at timestamp with time zone default now() not null
);

create table public.campaigns (
  id bigint default nextval('campaigns_id_seq'::regclass) not null,
  name text not null,
  channel text not null,
  template_id bigint,
  segment_id bigint,
  status text default 'draft'::text not null,
  scheduled_at timestamp with time zone,
  stats jsonb default '{}'::jsonb not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.catalog_programs (
  id bigint default nextval('catalog_programs_id_seq'::regclass) not null,
  university_id bigint not null,
  level text,
  level_raw text,
  course text,
  course_key text,
  dual boolean default false not null,
  specialization text,
  program_name text not null,
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
  active boolean default true not null,
  updated_at timestamp with time zone default now() not null,
  program_key text,
  search_doc tsvector generated always as (to_tsvector('simple'::regconfig, ((((COALESCE(program_name, ''::text) || ' '::text) || COALESCE(specialization, ''::text)) || ' '::text) || COALESCE(course, ''::text)))) stored,
  source_file text
);

create table public.catalog_stage (
  batch text not null,
  kind text not null,
  "row" jsonb not null,
  created_at timestamp with time zone default now() not null
);

create table public.catalog_synonyms (
  alias text not null,
  course_key text not null
);

create table public.catalog_universities (
  id bigint default nextval('catalog_universities_id_seq'::regclass) not null,
  name text not null,
  short_name text,
  institution_type text,
  recognitions text[],
  accreditation_text text,
  updated_at timestamp with time zone default now() not null
);

create table public.conversation_locks (
  phone_number text not null,
  locked_at timestamp with time zone not null
);

create table public.course_directory (
  id bigint default nextval('course_directory_id_seq'::regclass) not null,
  content text not null,
  metadata jsonb,
  embedding vector(3072)
);

create table public.crm_activities (
  id bigint default nextval('crm_activities_id_seq'::regclass) not null,
  lead_id bigint not null,
  kind text not null,
  content text,
  outcome text,
  meta jsonb default '{}'::jsonb not null,
  actor_id uuid,
  actor_name text,
  created_at timestamp with time zone default now() not null
);

create table public.crm_alerts (
  id bigint default nextval('crm_alerts_id_seq'::regclass) not null,
  kind text not null,
  partner_id bigint,
  lead_id bigint,
  message text not null,
  created_at timestamp with time zone default now() not null,
  resolved_at timestamp with time zone,
  resolved_by uuid
);

create table public.crm_api_keys (
  id bigint default nextval('crm_api_keys_id_seq'::regclass) not null,
  name text not null,
  key_hash text not null,
  source_system text default 'api'::text not null,
  scopes text[] default '{intake}'::text[] not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  revoked_at timestamp with time zone,
  last_used_at timestamp with time zone
);

create table public.crm_notifications (
  id bigint default nextval('crm_notifications_id_seq'::regclass) not null,
  user_id uuid not null,
  kind text not null,
  title text not null,
  body text,
  link text,
  lead_id bigint,
  created_at timestamp with time zone default now() not null,
  read_at timestamp with time zone,
  emailed_at timestamp with time zone
);

create table public.crm_saved_views (
  id bigint default nextval('crm_saved_views_id_seq'::regclass) not null,
  user_id uuid not null,
  name text not null,
  filters jsonb default '{}'::jsonb not null,
  is_shared boolean default false not null,
  created_at timestamp with time zone default now() not null
);

create table public.crm_settings (
  key text not null,
  value jsonb not null,
  updated_at timestamp with time zone default now() not null
);

create table public.crm_tasks (
  id bigint default nextval('crm_tasks_id_seq'::regclass) not null,
  lead_id bigint not null,
  title text not null,
  kind text default 'followup'::text not null,
  due_at timestamp with time zone not null,
  done_at timestamp with time zone,
  assignee_id uuid,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  reminded_at timestamp with time zone,
  overdue_alerted_at timestamp with time zone,
  escalated_at timestamp with time zone
);

create table public.crm_teams (
  id bigint default nextval('crm_teams_id_seq'::regclass) not null,
  name text not null,
  head_user_id uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.crm_university_settings (
  university_id bigint not null,
  refund_window_days integer,
  gstin text,
  contact text,
  notes text,
  updated_at timestamp with time zone default now() not null
);

create table public.crm_users (
  id uuid not null,
  email text not null,
  full_name text,
  role text default 'viewer'::text not null,
  team_id bigint,
  is_active boolean default false not null,
  on_shift boolean default true not null,
  monthly_cap integer default 200 not null,
  languages text[] default '{}'::text[] not null,
  skills text[] default '{}'::text[] not null,
  phone text,
  last_assigned_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  monthly_target integer default 0 not null
);

create table public.earning_rates (
  id bigint default nextval('earning_rates_id_seq'::regclass) not null,
  scope text not null,
  university_id bigint,
  programme_id bigint,
  partner_id bigint,
  rate_type text not null,
  fee_base text default 'recorded'::text not null,
  value numeric,
  tiers jsonb,
  gst_inclusive boolean default true not null,
  valid_from date default CURRENT_DATE not null,
  valid_to date,
  note text,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);

create table public.earnings (
  id bigint default nextval('earnings_id_seq'::regclass) not null,
  enrollment_id bigint not null,
  rate_id bigint,
  rate_snapshot jsonb,
  period text not null,
  base_inr numeric,
  pct numeric,
  gross_inr numeric not null,
  gst_inr numeric not null,
  net_inr numeric not null,
  status text default 'expected'::text not null,
  tier_provisional boolean default false not null,
  reverses_id bigint,
  invoice_id bigint,
  received_inr numeric,
  tds_inr numeric,
  bank_ref text,
  received_at timestamp with time zone,
  note text,
  created_at timestamp with time zone default now() not null
);

create table public.eduwit_knowledge_base (
  id bigint default nextval('eduwit_knowledge_base_id_seq'::regclass) not null,
  content text,
  metadata jsonb,
  embedding vector(3072)
);

create table public.engine_decisions (
  id bigint default nextval('engine_decisions_id_seq'::regclass) not null,
  lead_id bigint not null,
  segment text,
  mode text not null,
  candidates jsonb default '[]'::jsonb not null,
  winner_type text,
  winner_id bigint,
  seed double precision,
  settings jsonb,
  note text,
  created_at timestamp with time zone default now() not null
);

create table public.enrollments (
  id bigint default nextval('enrollments_id_seq'::regclass) not null,
  lead_id bigint not null,
  cycle_no integer default 1 not null,
  university_id bigint,
  university_name text,
  programme_id bigint,
  programme_name text,
  fee_amount_inr numeric,
  fee_paid_inr numeric,
  enrolled_on date default CURRENT_DATE not null,
  destination_type text,
  owner_user_id uuid,
  partner_id bigint,
  status text default 'reported'::text not null,
  proof_url text,
  proof_ref text,
  reported_by uuid,
  verified_by uuid,
  verified_at timestamp with time zone,
  refund_window_ends_on date,
  refunded_at timestamp with time zone,
  refund_reason text,
  expected_net_revenue_inr numeric,
  realised_net_revenue_inr numeric,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.influencer_auth (
  id integer default nextval('influencer_auth_id_seq'::regclass) not null,
  referral_code text not null,
  secret_password text not null
);

create table public.influencer_login_attempts (
  id bigint default nextval('influencer_login_attempts_id_seq'::regclass) not null,
  referral_code text not null,
  ok boolean not null,
  at timestamp with time zone default now() not null
);

create table public.influencers (
  id uuid default gen_random_uuid() not null,
  auth_uid uuid not null,
  referral_code text not null,
  email text,
  name text,
  created_at timestamp with time zone default now() not null,
  status text default 'active'::text not null
);

create table public.invoices (
  id bigint default nextval('invoices_id_seq'::regclass) not null,
  number text,
  counterparty_type text default 'university'::text not null,
  counterparty_id bigint,
  counterparty_name text,
  period text not null,
  gross_inr numeric default 0 not null,
  gst_inr numeric default 0 not null,
  net_inr numeric default 0 not null,
  line_count integer default 0 not null,
  status text default 'draft'::text not null,
  created_by uuid,
  sent_at timestamp with time zone,
  paid_at timestamp with time zone,
  created_at timestamp with time zone default now() not null
);

create table public.journey_runs (
  id bigint default nextval('journey_runs_id_seq'::regclass) not null,
  journey_id bigint not null,
  lead_id bigint not null,
  step_index integer default 0 not null,
  status text default 'active'::text not null,
  next_at timestamp with time zone default now() not null,
  started_at timestamp with time zone default now() not null,
  finished_at timestamp with time zone,
  exit_reason text,
  log jsonb default '[]'::jsonb not null,
  last_send_at timestamp with time zone,
  updated_at timestamp with time zone default now() not null
);

create table public.journeys (
  id bigint default nextval('journeys_id_seq'::regclass) not null,
  name text not null,
  status text default 'draft'::text not null,
  trigger jsonb default '{"type": "manual"}'::jsonb not null,
  steps jsonb default '[]'::jsonb not null,
  description text,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.message_templates (
  id bigint default nextval('message_templates_id_seq'::regclass) not null,
  channel text not null,
  name text not null,
  subject text,
  body text not null,
  wa_template_name text,
  wa_language text default 'en'::text,
  wa_params jsonb default '[]'::jsonb not null,
  active boolean default true not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.n8n_chat_histories (
  id integer default nextval('n8n_chat_histories_id_seq'::regclass) not null,
  session_id character varying(255) not null,
  message jsonb not null
);

create table public.partner_events (
  id bigint default nextval('partner_events_id_seq'::regclass) not null,
  partner_id bigint not null,
  allocation_id bigint,
  event_id text not null,
  event_type text not null,
  raw jsonb not null,
  mapped jsonb,
  processed boolean default false not null,
  error text,
  received_at timestamp with time zone default now() not null
);

create table public.partner_mapping_profiles (
  id bigint default nextval('partner_mapping_profiles_id_seq'::regclass) not null,
  partner_id bigint not null,
  version integer default 1 not null,
  is_active boolean default true not null,
  status_map jsonb default '[]'::jsonb not null,
  field_map jsonb default '{}'::jsonb not null,
  value_maps jsonb default '{}'::jsonb not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);

create table public.partners (
  id bigint default nextval('partners_id_seq'::regclass) not null,
  slug text not null,
  name text not null,
  status text default 'onboarding'::text not null,
  adapter_type text default 'webhook'::text not null,
  api_base_url text,
  outbound_auth jsonb default '{}'::jsonb not null,
  inbound_secret text,
  daily_cap integer,
  monthly_cap integer,
  lead_criteria jsonb default '{}'::jsonb not null,
  sla jsonb default '{"proof_days": 7, "duplicate_hours": 24, "status_update_days": 7, "first_contact_hours": 2}'::jsonb not null,
  contract_min_monthly integer,
  paused_reason text,
  auto_paused_at timestamp with time zone,
  notes text,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.payout_rates (
  id bigint default nextval('payout_rates_id_seq'::regclass) not null,
  scope text not null,
  university_id bigint,
  programme_id bigint,
  user_id uuid,
  rate_type text not null,
  value numeric not null,
  accelerators jsonb,
  valid_from date default CURRENT_DATE not null,
  valid_to date,
  note text,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);

create table public.payout_runs (
  id bigint default nextval('payout_runs_id_seq'::regclass) not null,
  period text not null,
  status text default 'draft'::text not null,
  total_inr numeric default 0 not null,
  line_count integer default 0 not null,
  created_by uuid,
  approved_by uuid,
  approved_at timestamp with time zone,
  paid_at timestamp with time zone,
  created_at timestamp with time zone default now() not null
);

create table public.payouts (
  id bigint default nextval('payouts_id_seq'::regclass) not null,
  enrollment_id bigint not null,
  user_id uuid not null,
  rate_id bigint,
  rate_snapshot jsonb,
  period text not null,
  amount_inr numeric not null,
  status text default 'provisional'::text not null,
  payable_on date,
  paid_at timestamp with time zone,
  payout_run_id bigint,
  is_clawback boolean default false not null,
  reverses_id bigint,
  note text,
  created_at timestamp with time zone default now() not null
);

create table public.processed_whatsapp_messages (
  message_id bigint not null,
  phone_number text not null,
  created_at timestamp with time zone default now()
);

create table public.routing_rules (
  id bigint default nextval('routing_rules_id_seq'::regclass) not null,
  priority integer default 100 not null,
  name text not null,
  conditions jsonb default '{}'::jsonb not null,
  action jsonb default '{}'::jsonb not null,
  active boolean default true not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null
);

create table public.segment_members (
  segment_id bigint not null,
  lead_id bigint not null,
  added_at timestamp with time zone default now() not null
);

create table public.segments (
  id bigint default nextval('segments_id_seq'::regclass) not null,
  name text not null,
  kind text default 'dynamic'::text not null,
  rules jsonb default '[]'::jsonb not null,
  description text,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table public.student_leads (
  id bigint generated by default as identity not null,
  created_at timestamp with time zone default now() not null,
  whatsapp_number text,
  student_name text,
  interested_course text,
  highest_qualification text,
  lead_status text default 'UNQUALIFIED'::text,
  is_hot_sent_to_crm boolean default false,
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
  country text default 'India'::text,
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
  is_opted_out boolean default false not null,
  opted_out_at timestamp with time zone,
  opted_out_channels text[],
  email_bounced_at timestamp with time zone,
  stage text,
  sub_stage text,
  stage_changed_at timestamp with time zone,
  temperature text,
  lead_score integer,
  is_sales_ready boolean default false not null,
  sales_ready_at timestamp with time zone,
  owner_user_id uuid,
  team_id bigint,
  assigned_at timestamp with time zone,
  first_contacted_at timestamp with time zone,
  last_contacted_at timestamp with time zone,
  last_activity_at timestamp with time zone,
  contact_attempts integer default 0 not null,
  next_task_due_at timestamp with time zone,
  lost_reason text,
  lost_at timestamp with time zone,
  cycle_no integer default 1 not null,
  reopened_at timestamp with time zone,
  is_duplicate_suspect boolean default false not null,
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
  duplicate_claim_count integer default 0 not null,
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
  is_bot_paused boolean default false not null,
  last_agent_message_at timestamp with time zone,
  portal_user_id uuid,
  open_ticket_count integer default 0 not null,
  custom_fields jsonb default '{}'::jsonb not null,
  zoho_lead_id text,
  is_test boolean default false not null,
  updated_at timestamp with time zone default now() not null,
  updated_by text,
  deleted_at timestamp with time zone,
  anonymised_at timestamp with time zone,
  sla_alerted_at timestamp with time zone,
  score_updated_at timestamp with time zone
);

create table public.touchpoints (
  id bigint default nextval('touchpoints_id_seq'::regclass) not null,
  lead_id bigint not null,
  phone text not null,
  source_system text not null,
  event_type text not null,
  source text,
  campaign text,
  attribution jsonb default '{}'::jsonb not null,
  idempotency_key text,
  payload jsonb,
  occurred_at timestamp with time zone default now() not null,
  created_at timestamp with time zone default now() not null
);

create table public.verifications (
  id bigint default nextval('verifications_id_seq'::regclass) not null,
  kind text not null,
  target text not null,
  code_hash text not null,
  expires_at timestamp with time zone not null,
  attempts integer default 0 not null,
  max_attempts integer default 3 not null,
  resend_after timestamp with time zone not null,
  verified_at timestamp with time zone,
  ip text,
  lead_id bigint,
  context jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default now() not null
);

create table public.w2_access_codes (
  code text not null,
  kind text default 'personal'::text not null,
  source text not null,
  campaign text,
  click_id bigint,
  attribution jsonb default '{}'::jsonb not null,
  parent_code text,
  created_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone,
  phone text,
  bound_at timestamp with time zone,
  redeem_count integer default 0 not null,
  last_redeemed_at timestamp with time zone
);

create table public.w2_blocks (
  phone text not null,
  level integer default 1 not null,
  reason text,
  score integer,
  evidence jsonb,
  blocked_at timestamp with time zone default now() not null,
  blocked_until timestamp with time zone,
  unblocked_at timestamp with time zone,
  unblocked_by text,
  note text
);

create table public.w2_clicks (
  id bigint default nextval('w2_clicks_id_seq'::regclass) not null,
  created_at timestamp with time zone default now() not null,
  source text not null,
  source_known boolean default false not null,
  campaign text,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  utm_term text,
  click_ids jsonb,
  referrer text,
  landing_url text,
  via_code text,
  ip text,
  country text,
  user_agent text,
  device_type text,
  os text,
  browser text,
  in_app text,
  language text,
  fingerprint text,
  is_bot boolean default false not null,
  code text
);

create table public.w2_conversations (
  phone text not null,
  conversation_id bigint,
  account_id bigint,
  state jsonb default '{}'::jsonb not null,
  classification text default 'UNQUALIFIED'::text not null,
  readiness text default 'EXPLORING'::text not null,
  eligibility text default 'INSUFFICIENT_DATA'::text not null,
  pending_question text default 'NONE'::text not null,
  bot_paused boolean default false not null,
  opted_out boolean default false not null,
  consent_at timestamp with time zone,
  escalated_at timestamp with time zone,
  lead_source text,
  activation_code text,
  crm_record_id text,
  version integer default 0 not null,
  lock_id text,
  lock_until timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  access_code text,
  access_at timestamp with time zone,
  attribution jsonb,
  last_student_at timestamp with time zone,
  nurture_step integer default 0 not null,
  nurture_next_at timestamp with time zone
);

create table public.w2_drive_files (
  file_id text not null,
  name text,
  mime text,
  kind text,
  modified_at timestamp with time zone,
  status text default 'pending'::text not null,
  seen_at timestamp with time zone,
  synced_at timestamp with time zone,
  result jsonb,
  error text
);

create table public.w2_events (
  id bigint default nextval('w2_events_id_seq'::regclass) not null,
  phone text,
  type text not null,
  run_id text,
  payload jsonb,
  created_at timestamp with time zone default now() not null
);

create table public.w2_fact_log (
  id bigint default nextval('w2_fact_log_id_seq'::regclass) not null,
  phone text not null,
  turn_run text,
  field text,
  value text,
  evidence text,
  op text,
  subject text,
  accepted boolean not null,
  reject_reason text,
  model text,
  created_at timestamp with time zone default now() not null
);

create table public.w2_feedback (
  id bigint default nextval('w2_feedback_id_seq'::regclass) not null,
  phone text,
  run_id text,
  source text not null,
  rating smallint,
  label text,
  comment text,
  author text,
  meta jsonb,
  created_at timestamp with time zone default now() not null,
  reviewed_at timestamp with time zone
);

create table public.w2_gemini_caches (
  name text not null,
  cache_name text,
  model text,
  prompt_hash text,
  prompt_text text,
  tokens integer,
  expire_at timestamp with time zone,
  error text,
  updated_at timestamp with time zone default now() not null
);

create table public.w2_inbox (
  message_id text not null,
  phone text not null,
  conversation_id bigint,
  account_id bigint,
  content text,
  content_type text,
  has_attachment boolean default false not null,
  labels jsonb,
  received_at timestamp with time zone default now() not null,
  claimed_by text,
  processed_at timestamp with time zone
);

create table public.w2_kb_chunks (
  id bigint default nextval('w2_kb_chunks_id_seq'::regclass) not null,
  doc_id bigint not null,
  chunk_no integer not null,
  content text not null,
  embedding vector(768),
  search_doc tsvector generated always as (to_tsvector('simple'::regconfig, content)) stored,
  created_at timestamp with time zone default now() not null
);

create table public.w2_kb_docs (
  id bigint default nextval('w2_kb_docs_id_seq'::regclass) not null,
  source_file text not null,
  name text,
  mime text,
  modified_at timestamp with time zone,
  chunks integer default 0 not null,
  active boolean default true not null,
  updated_at timestamp with time zone default now() not null
);

create table public.w2_kb_stage (
  batch text not null,
  "row" jsonb not null,
  created_at timestamp with time zone default now() not null
);

create table public.w2_learning_reports (
  id bigint default nextval('w2_learning_reports_id_seq'::regclass) not null,
  window_start timestamp with time zone,
  window_end timestamp with time zone,
  stats jsonb,
  summary text,
  model text,
  usage jsonb,
  created_at timestamp with time zone default now() not null
);

create table public.w2_learnings (
  id bigint default nextval('w2_learnings_id_seq'::regclass) not null,
  report_id bigint,
  kind text not null,
  title text,
  payload jsonb default '{}'::jsonb not null,
  rationale text,
  evidence jsonb,
  confidence numeric,
  status text default 'proposed'::text not null,
  auto boolean default false not null,
  created_at timestamp with time zone default now() not null,
  decided_at timestamp with time zone,
  decided_by text
);

create table public.w2_messages (
  id bigint default nextval('w2_messages_id_seq'::regclass) not null,
  phone text not null,
  direction text not null,
  kind text default 'chat'::text not null,
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
  created_at timestamp with time zone default now() not null
);

create table public.w2_meta (
  key text not null,
  value jsonb not null,
  updated_at timestamp with time zone default now() not null
);

create table public.w2_nurture_log (
  id bigint default nextval('w2_nurture_log_id_seq'::regclass) not null,
  phone text not null,
  step integer not null,
  kind text not null,
  template text,
  content text,
  status text not null,
  error text,
  created_at timestamp with time zone default now() not null
);

create table public.w2_outbox (
  id bigint default nextval('w2_outbox_id_seq'::regclass) not null,
  phone text not null,
  target text default 'crm'::text not null,
  event_type text not null,
  idempotency_key text not null,
  payload jsonb not null,
  status text default 'pending'::text not null,
  attempts integer default 0 not null,
  next_attempt_at timestamp with time zone default now() not null,
  locked_by text,
  last_error text,
  crm_record_id text,
  created_at timestamp with time zone default now() not null,
  sent_at timestamp with time zone
);

create table public.w2_prompts (
  name text not null,
  version integer default 1 not null,
  body text not null,
  updated_at timestamp with time zone default now() not null
);

create table public.w2_search_cache (
  key text not null,
  version integer not null,
  result jsonb not null,
  hits integer default 0 not null,
  created_at timestamp with time zone default now() not null,
  last_hit_at timestamp with time zone
);

create table public.w2_security_log (
  id bigint default nextval('w2_security_log_id_seq'::regclass) not null,
  phone text not null,
  kind text not null,
  detail jsonb,
  created_at timestamp with time zone default now() not null
);

create table public.w2_sources (
  slug text not null,
  name text not null,
  channel text default 'other'::text not null,
  owner text,
  allow_reuse boolean default false not null,
  reuse_code text,
  active boolean default true not null,
  notes text,
  created_at timestamp with time zone default now() not null
);

create table public.w2_test_runs (
  id bigint default nextval('w2_test_runs_id_seq'::regclass) not null,
  run_tag text,
  summary jsonb,
  results jsonb,
  created_at timestamp with time zone default now() not null
);

create table public.w2_trusted (
  phone text not null,
  note text,
  created_at timestamp with time zone default now() not null,
  is_test boolean default false not null
);

alter sequence public.allocations_id_seq owned by public.allocations.id;
alter sequence public.calls_id_seq owned by public.calls.id;
alter sequence public.campaign_sends_id_seq owned by public.campaign_sends.id;
alter sequence public.campaigns_id_seq owned by public.campaigns.id;
alter sequence public.catalog_programs_id_seq owned by public.catalog_programs.id;
alter sequence public.catalog_universities_id_seq owned by public.catalog_universities.id;
alter sequence public.course_directory_id_seq owned by public.course_directory.id;
alter sequence public.crm_activities_id_seq owned by public.crm_activities.id;
alter sequence public.crm_alerts_id_seq owned by public.crm_alerts.id;
alter sequence public.crm_api_keys_id_seq owned by public.crm_api_keys.id;
alter sequence public.crm_notifications_id_seq owned by public.crm_notifications.id;
alter sequence public.crm_saved_views_id_seq owned by public.crm_saved_views.id;
alter sequence public.crm_tasks_id_seq owned by public.crm_tasks.id;
alter sequence public.crm_teams_id_seq owned by public.crm_teams.id;
alter sequence public.earning_rates_id_seq owned by public.earning_rates.id;
alter sequence public.earnings_id_seq owned by public.earnings.id;
alter sequence public.eduwit_knowledge_base_id_seq owned by public.eduwit_knowledge_base.id;
alter sequence public.engine_decisions_id_seq owned by public.engine_decisions.id;
alter sequence public.enrollments_id_seq owned by public.enrollments.id;
alter sequence public.influencer_auth_id_seq owned by public.influencer_auth.id;
alter sequence public.influencer_login_attempts_id_seq owned by public.influencer_login_attempts.id;
alter sequence public.invoices_id_seq owned by public.invoices.id;
alter sequence public.journey_runs_id_seq owned by public.journey_runs.id;
alter sequence public.journeys_id_seq owned by public.journeys.id;
alter sequence public.message_templates_id_seq owned by public.message_templates.id;
alter sequence public.n8n_chat_histories_id_seq owned by public.n8n_chat_histories.id;
alter sequence public.partner_events_id_seq owned by public.partner_events.id;
alter sequence public.partner_mapping_profiles_id_seq owned by public.partner_mapping_profiles.id;
alter sequence public.partners_id_seq owned by public.partners.id;
alter sequence public.payout_rates_id_seq owned by public.payout_rates.id;
alter sequence public.payout_runs_id_seq owned by public.payout_runs.id;
alter sequence public.payouts_id_seq owned by public.payouts.id;
alter sequence public.routing_rules_id_seq owned by public.routing_rules.id;
alter sequence public.segments_id_seq owned by public.segments.id;
alter sequence public.touchpoints_id_seq owned by public.touchpoints.id;
alter sequence public.verifications_id_seq owned by public.verifications.id;
alter sequence public.w2_clicks_id_seq owned by public.w2_clicks.id;
alter sequence public.w2_events_id_seq owned by public.w2_events.id;
alter sequence public.w2_fact_log_id_seq owned by public.w2_fact_log.id;
alter sequence public.w2_feedback_id_seq owned by public.w2_feedback.id;
alter sequence public.w2_kb_chunks_id_seq owned by public.w2_kb_chunks.id;
alter sequence public.w2_kb_docs_id_seq owned by public.w2_kb_docs.id;
alter sequence public.w2_learning_reports_id_seq owned by public.w2_learning_reports.id;
alter sequence public.w2_learnings_id_seq owned by public.w2_learnings.id;
alter sequence public.w2_messages_id_seq owned by public.w2_messages.id;
alter sequence public.w2_nurture_log_id_seq owned by public.w2_nurture_log.id;
alter sequence public.w2_outbox_id_seq owned by public.w2_outbox.id;
alter sequence public.w2_security_log_id_seq owned by public.w2_security_log.id;
alter sequence public.w2_test_runs_id_seq owned by public.w2_test_runs.id;

alter table only public.allocations add constraint allocations_pkey PRIMARY KEY (id);
alter table only public.calls add constraint calls_pkey PRIMARY KEY (id);
alter table only public.campaign_sends add constraint campaign_sends_pkey PRIMARY KEY (id);
alter table only public.campaigns add constraint campaigns_pkey PRIMARY KEY (id);
alter table only public.catalog_programs add constraint catalog_programs_pkey PRIMARY KEY (id);
alter table only public.catalog_synonyms add constraint catalog_synonyms_pkey PRIMARY KEY (alias);
alter table only public.catalog_universities add constraint catalog_universities_pkey PRIMARY KEY (id);
alter table only public.conversation_locks add constraint conversation_locks_pkey PRIMARY KEY (phone_number);
alter table only public.course_directory add constraint course_directory_pkey PRIMARY KEY (id);
alter table only public.crm_activities add constraint crm_activities_pkey PRIMARY KEY (id);
alter table only public.crm_alerts add constraint crm_alerts_pkey PRIMARY KEY (id);
alter table only public.crm_api_keys add constraint crm_api_keys_pkey PRIMARY KEY (id);
alter table only public.crm_notifications add constraint crm_notifications_pkey PRIMARY KEY (id);
alter table only public.crm_saved_views add constraint crm_saved_views_pkey PRIMARY KEY (id);
alter table only public.crm_settings add constraint crm_settings_pkey PRIMARY KEY (key);
alter table only public.crm_tasks add constraint crm_tasks_pkey PRIMARY KEY (id);
alter table only public.crm_teams add constraint crm_teams_pkey PRIMARY KEY (id);
alter table only public.crm_university_settings add constraint crm_university_settings_pkey PRIMARY KEY (university_id);
alter table only public.crm_users add constraint crm_users_pkey PRIMARY KEY (id);
alter table only public.earning_rates add constraint earning_rates_pkey PRIMARY KEY (id);
alter table only public.earnings add constraint earnings_pkey PRIMARY KEY (id);
alter table only public.eduwit_knowledge_base add constraint eduwit_knowledge_base_pkey PRIMARY KEY (id);
alter table only public.engine_decisions add constraint engine_decisions_pkey PRIMARY KEY (id);
alter table only public.enrollments add constraint enrollments_pkey PRIMARY KEY (id);
alter table only public.influencer_auth add constraint influencer_auth_pkey PRIMARY KEY (id);
alter table only public.influencer_login_attempts add constraint influencer_login_attempts_pkey PRIMARY KEY (id);
alter table only public.influencers add constraint influencers_pkey PRIMARY KEY (id);
alter table only public.invoices add constraint invoices_pkey PRIMARY KEY (id);
alter table only public.journey_runs add constraint journey_runs_pkey PRIMARY KEY (id);
alter table only public.journeys add constraint journeys_pkey PRIMARY KEY (id);
alter table only public.message_templates add constraint message_templates_pkey PRIMARY KEY (id);
alter table only public.n8n_chat_histories add constraint n8n_chat_histories_pkey PRIMARY KEY (id);
alter table only public.partner_events add constraint partner_events_pkey PRIMARY KEY (id);
alter table only public.partner_mapping_profiles add constraint partner_mapping_profiles_pkey PRIMARY KEY (id);
alter table only public.partners add constraint partners_pkey PRIMARY KEY (id);
alter table only public.payout_rates add constraint payout_rates_pkey PRIMARY KEY (id);
alter table only public.payout_runs add constraint payout_runs_pkey PRIMARY KEY (id);
alter table only public.payouts add constraint payouts_pkey PRIMARY KEY (id);
alter table only public.processed_whatsapp_messages add constraint processed_whatsapp_messages_pkey PRIMARY KEY (message_id, phone_number);
alter table only public.routing_rules add constraint routing_rules_pkey PRIMARY KEY (id);
alter table only public.segment_members add constraint segment_members_pkey PRIMARY KEY (segment_id, lead_id);
alter table only public.segments add constraint segments_pkey PRIMARY KEY (id);
alter table only public.student_leads add constraint student_leads_pkey PRIMARY KEY (id);
alter table only public.touchpoints add constraint touchpoints_pkey PRIMARY KEY (id);
alter table only public.verifications add constraint verifications_pkey PRIMARY KEY (id);
alter table only public.w2_access_codes add constraint w2_access_codes_pkey PRIMARY KEY (code);
alter table only public.w2_blocks add constraint w2_blocks_pkey PRIMARY KEY (phone);
alter table only public.w2_clicks add constraint w2_clicks_pkey PRIMARY KEY (id);
alter table only public.w2_conversations add constraint w2_conversations_pkey PRIMARY KEY (phone);
alter table only public.w2_drive_files add constraint w2_drive_files_pkey PRIMARY KEY (file_id);
alter table only public.w2_events add constraint w2_events_pkey PRIMARY KEY (id);
alter table only public.w2_fact_log add constraint w2_fact_log_pkey PRIMARY KEY (id);
alter table only public.w2_feedback add constraint w2_feedback_pkey PRIMARY KEY (id);
alter table only public.w2_gemini_caches add constraint w2_gemini_caches_pkey PRIMARY KEY (name);
alter table only public.w2_inbox add constraint w2_inbox_pkey PRIMARY KEY (message_id);
alter table only public.w2_kb_chunks add constraint w2_kb_chunks_pkey PRIMARY KEY (id);
alter table only public.w2_kb_docs add constraint w2_kb_docs_pkey PRIMARY KEY (id);
alter table only public.w2_learning_reports add constraint w2_learning_reports_pkey PRIMARY KEY (id);
alter table only public.w2_learnings add constraint w2_learnings_pkey PRIMARY KEY (id);
alter table only public.w2_messages add constraint w2_messages_pkey PRIMARY KEY (id);
alter table only public.w2_meta add constraint w2_meta_pkey PRIMARY KEY (key);
alter table only public.w2_nurture_log add constraint w2_nurture_log_pkey PRIMARY KEY (id);
alter table only public.w2_outbox add constraint w2_outbox_pkey PRIMARY KEY (id);
alter table only public.w2_prompts add constraint w2_prompts_pkey PRIMARY KEY (name);
alter table only public.w2_search_cache add constraint w2_search_cache_pkey PRIMARY KEY (key);
alter table only public.w2_security_log add constraint w2_security_log_pkey PRIMARY KEY (id);
alter table only public.w2_sources add constraint w2_sources_pkey PRIMARY KEY (slug);
alter table only public.w2_test_runs add constraint w2_test_runs_pkey PRIMARY KEY (id);
alter table only public.w2_trusted add constraint w2_trusted_pkey PRIMARY KEY (phone);
alter table only public.allocations add constraint allocations_reference_key UNIQUE (reference);
alter table only public.campaign_sends add constraint campaign_sends_campaign_id_lead_id_key UNIQUE (campaign_id, lead_id);
alter table only public.catalog_universities add constraint catalog_universities_name_key UNIQUE (name);
alter table only public.crm_api_keys add constraint crm_api_keys_key_hash_key UNIQUE (key_hash);
alter table only public.crm_teams add constraint crm_teams_name_key UNIQUE (name);
alter table only public.influencer_auth add constraint influencer_auth_referral_code_key UNIQUE (referral_code);
alter table only public.influencers add constraint influencers_auth_uid_key UNIQUE (auth_uid);
alter table only public.influencers add constraint influencers_referral_code_key UNIQUE (referral_code);
alter table only public.invoices add constraint invoices_number_key UNIQUE (number);
alter table only public.partners add constraint partners_slug_key UNIQUE (slug);
alter table only public.touchpoints add constraint touchpoints_idempotency_key_key UNIQUE (idempotency_key);
alter table only public.w2_kb_docs add constraint w2_kb_docs_source_file_key UNIQUE (source_file);
alter table only public.w2_outbox add constraint w2_outbox_idempotency_key_key UNIQUE (idempotency_key);
alter table only public.w2_sources add constraint w2_sources_reuse_code_key UNIQUE (reuse_code);
alter table only public.allocations add constraint allocations_destination_type_check CHECK ((destination_type = ANY (ARRAY['in_house'::text, 'partner'::text])));
alter table only public.allocations add constraint allocations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'pushing'::text, 'pushed'::text, 'failed'::text, 'duplicate'::text, 'recalled'::text, 'closed'::text, 'assigned'::text])));
alter table only public.calls add constraint calls_direction_check CHECK ((direction = ANY (ARRAY['outbound'::text, 'inbound'::text])));
alter table only public.calls add constraint calls_status_check CHECK ((status = ANY (ARRAY['initiated'::text, 'ringing'::text, 'in_progress'::text, 'completed'::text, 'no_answer'::text, 'busy'::text, 'failed'::text, 'cancelled'::text, 'missed'::text])));
alter table only public.campaign_sends add constraint campaign_sends_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'sending'::text, 'sent'::text, 'failed'::text, 'skipped'::text])));
alter table only public.campaigns add constraint campaigns_channel_check CHECK ((channel = ANY (ARRAY['email'::text, 'whatsapp'::text])));
alter table only public.campaigns add constraint campaigns_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'scheduled'::text, 'sending'::text, 'sent'::text, 'cancelled'::text])));
alter table only public.crm_activities add constraint crm_activities_kind_check CHECK ((kind = ANY (ARRAY['note'::text, 'call'::text, 'whatsapp'::text, 'email'::text, 'sms'::text, 'meeting'::text, 'stage'::text, 'assign'::text, 'task'::text, 'system'::text])));
alter table only public.crm_users add constraint crm_users_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'sales_head'::text, 'sales_manager'::text, 'marketing'::text, 'revenue'::text, 'finance'::text, 'viewer'::text])));
alter table only public.earning_rates add constraint earning_rates_fee_base_check CHECK ((fee_base = ANY (ARRAY['first_year'::text, 'total'::text, 'paid'::text, 'recorded'::text])));
alter table only public.earning_rates add constraint earning_rates_rate_type_check CHECK ((rate_type = ANY (ARRAY['percent'::text, 'fixed'::text, 'tiered'::text])));
alter table only public.earning_rates add constraint earning_rates_scope_check CHECK ((scope = ANY (ARRAY['university'::text, 'programme'::text, 'partner'::text])));
alter table only public.earnings add constraint earnings_status_check CHECK ((status = ANY (ARRAY['expected'::text, 'realised'::text, 'invoiced'::text, 'received'::text, 'reversed'::text])));
alter table only public.enrollments add constraint enrollments_status_check CHECK ((status = ANY (ARRAY['reported'::text, 'verified'::text, 'refunded'::text, 'cancelled'::text])));
alter table only public.influencers add constraint influencers_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
alter table only public.invoices add constraint invoices_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'sent'::text, 'paid'::text])));
alter table only public.journey_runs add constraint journey_runs_status_check CHECK ((status = ANY (ARRAY['active'::text, 'waiting_send'::text, 'done'::text, 'exited'::text])));
alter table only public.journeys add constraint journeys_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'paused'::text])));
alter table only public.message_templates add constraint message_templates_channel_check CHECK ((channel = ANY (ARRAY['email'::text, 'whatsapp'::text])));
alter table only public.partners add constraint partners_adapter_type_check CHECK ((adapter_type = ANY (ARRAY['webhook'::text, 'portal'::text, 'none'::text])));
alter table only public.partners add constraint partners_status_check CHECK ((status = ANY (ARRAY['onboarding'::text, 'active'::text, 'paused'::text, 'closed'::text])));
alter table only public.payout_rates add constraint payout_rates_rate_type_check CHECK ((rate_type = ANY (ARRAY['pct_of_fee'::text, 'pct_of_earning'::text, 'fixed'::text])));
alter table only public.payout_rates add constraint payout_rates_scope_check CHECK ((scope = ANY (ARRAY['university'::text, 'programme'::text, 'user'::text])));
alter table only public.payout_runs add constraint payout_runs_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'paid'::text])));
alter table only public.payouts add constraint payouts_status_check CHECK ((status = ANY (ARRAY['provisional'::text, 'confirmed'::text, 'payable'::text, 'paid'::text, 'clawback'::text, 'held'::text])));
alter table only public.segments add constraint segments_kind_check CHECK ((kind = ANY (ARRAY['dynamic'::text, 'static'::text])));
alter table only public.student_leads add constraint student_leads_destination_chk CHECK ((destination_type = ANY (ARRAY['in_house'::text, 'partner'::text])));
alter table only public.student_leads add constraint student_leads_score_chk CHECK (((academic_score_pct >= (0)::numeric) AND (academic_score_pct <= (100)::numeric)));
alter table only public.student_leads add constraint student_leads_temperature_chk CHECK ((temperature = ANY (ARRAY['hot'::text, 'warm'::text, 'cold'::text])));
alter table only public.verifications add constraint verifications_kind_check CHECK ((kind = ANY (ARRAY['phone'::text, 'email'::text])));

alter table only public.allocations add constraint allocations_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES student_leads(id) ON DELETE CASCADE;
alter table only public.allocations add constraint allocations_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES partners(id);
alter table only public.calls add constraint calls_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES student_leads(id) ON DELETE CASCADE;
alter table only public.campaign_sends add constraint campaign_sends_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES campaigns(id) ON DELETE CASCADE;
alter table only public.campaign_sends add constraint campaign_sends_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES student_leads(id) ON DELETE CASCADE;
alter table only public.campaigns add constraint campaigns_segment_id_fkey FOREIGN KEY (segment_id) REFERENCES segments(id);
alter table only public.campaigns add constraint campaigns_template_id_fkey FOREIGN KEY (template_id) REFERENCES message_templates(id);
alter table only public.catalog_programs add constraint catalog_programs_university_id_fkey FOREIGN KEY (university_id) REFERENCES catalog_universities(id) ON DELETE CASCADE;
alter table only public.crm_activities add constraint crm_activities_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES student_leads(id) ON DELETE CASCADE;
alter table only public.crm_alerts add constraint crm_alerts_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE CASCADE;
alter table only public.crm_tasks add constraint crm_tasks_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES student_leads(id) ON DELETE CASCADE;
alter table only public.crm_university_settings add constraint crm_university_settings_university_id_fkey FOREIGN KEY (university_id) REFERENCES catalog_universities(id);
alter table only public.crm_users add constraint crm_users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table only public.crm_users add constraint crm_users_team_id_fkey FOREIGN KEY (team_id) REFERENCES crm_teams(id);
alter table only public.earning_rates add constraint earning_rates_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES catalog_programs(id);
alter table only public.earning_rates add constraint earning_rates_university_id_fkey FOREIGN KEY (university_id) REFERENCES catalog_universities(id);
alter table only public.earnings add constraint earnings_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES enrollments(id);
alter table only public.engine_decisions add constraint engine_decisions_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES student_leads(id) ON DELETE CASCADE;
alter table only public.enrollments add constraint enrollments_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES student_leads(id);
alter table only public.enrollments add constraint enrollments_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES catalog_programs(id);
alter table only public.enrollments add constraint enrollments_university_id_fkey FOREIGN KEY (university_id) REFERENCES catalog_universities(id);
alter table only public.influencers add constraint influencers_auth_uid_fkey FOREIGN KEY (auth_uid) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table only public.journey_runs add constraint journey_runs_journey_id_fkey FOREIGN KEY (journey_id) REFERENCES journeys(id) ON DELETE CASCADE;
alter table only public.journey_runs add constraint journey_runs_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES student_leads(id) ON DELETE CASCADE;
alter table only public.partner_events add constraint partner_events_allocation_id_fkey FOREIGN KEY (allocation_id) REFERENCES allocations(id) ON DELETE SET NULL;
alter table only public.partner_events add constraint partner_events_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE CASCADE;
alter table only public.partner_mapping_profiles add constraint partner_mapping_profiles_partner_id_fkey FOREIGN KEY (partner_id) REFERENCES partners(id) ON DELETE CASCADE;
alter table only public.payout_rates add constraint payout_rates_programme_id_fkey FOREIGN KEY (programme_id) REFERENCES catalog_programs(id);
alter table only public.payout_rates add constraint payout_rates_university_id_fkey FOREIGN KEY (university_id) REFERENCES catalog_universities(id);
alter table only public.payouts add constraint payouts_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES enrollments(id);
alter table only public.segment_members add constraint segment_members_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES student_leads(id) ON DELETE CASCADE;
alter table only public.segment_members add constraint segment_members_segment_id_fkey FOREIGN KEY (segment_id) REFERENCES segments(id) ON DELETE CASCADE;
alter table only public.touchpoints add constraint touchpoints_lead_id_fkey FOREIGN KEY (lead_id) REFERENCES student_leads(id) ON DELETE CASCADE;
alter table only public.w2_kb_chunks add constraint w2_kb_chunks_doc_id_fkey FOREIGN KEY (doc_id) REFERENCES w2_kb_docs(id) ON DELETE CASCADE;
alter table only public.w2_learnings add constraint w2_learnings_report_id_fkey FOREIGN KEY (report_id) REFERENCES w2_learning_reports(id) ON DELETE SET NULL;

CREATE INDEX allocations_dest_idx ON public.allocations USING btree (destination_type, partner_id, segment, created_at DESC);
CREATE UNIQUE INDEX allocations_open_uidx ON public.allocations USING btree (lead_id) WHERE (status = ANY (ARRAY['pending'::text, 'pushing'::text, 'pushed'::text, 'assigned'::text]));
CREATE INDEX calls_lead_idx ON public.calls USING btree (lead_id, started_at DESC);
CREATE UNIQUE INDEX calls_provider_uidx ON public.calls USING btree (provider, provider_call_id) WHERE (provider_call_id IS NOT NULL);
CREATE INDEX campaign_sends_due_idx ON public.campaign_sends USING btree (next_at) WHERE (status = 'queued'::text);
CREATE INDEX catalog_programs_course_idx ON public.catalog_programs USING btree (course_key, level, mode) WHERE active;
CREATE INDEX catalog_programs_course_spec_idx ON public.catalog_programs USING btree (course_key, specialization) WHERE active;
CREATE INDEX catalog_programs_course_trgm ON public.catalog_programs USING gin (course gin_trgm_ops);
CREATE UNIQUE INDEX catalog_programs_key_idx ON public.catalog_programs USING btree (program_key);
CREATE INDEX catalog_programs_name_trgm ON public.catalog_programs USING gin (program_name gin_trgm_ops);
CREATE INDEX catalog_programs_search_idx ON public.catalog_programs USING gin (search_doc);
CREATE INDEX catalog_programs_source_idx ON public.catalog_programs USING btree (source_file);
CREATE INDEX catalog_programs_spec_trgm ON public.catalog_programs USING gin (specialization gin_trgm_ops);
CREATE INDEX catalog_programs_uni_idx ON public.catalog_programs USING btree (university_id);
CREATE INDEX catalog_stage_batch_idx ON public.catalog_stage USING btree (batch, kind);
CREATE INDEX crm_activities_lead_idx ON public.crm_activities USING btree (lead_id, created_at DESC);
CREATE INDEX crm_alerts_open_idx ON public.crm_alerts USING btree (resolved_at, created_at DESC);
CREATE INDEX crm_notifications_user_idx ON public.crm_notifications USING btree (user_id, read_at, created_at DESC);
CREATE INDEX crm_tasks_assignee_idx ON public.crm_tasks USING btree (assignee_id, done_at, due_at);
CREATE INDEX crm_tasks_lead_idx ON public.crm_tasks USING btree (lead_id, due_at);
CREATE UNIQUE INDEX crm_users_email_uidx ON public.crm_users USING btree (lower(email));
CREATE INDEX earning_rates_lookup_idx ON public.earning_rates USING btree (scope, university_id, programme_id, partner_id, valid_from DESC);
CREATE INDEX earnings_period_idx ON public.earnings USING btree (period, status);
CREATE INDEX engine_decisions_lead_idx ON public.engine_decisions USING btree (lead_id, created_at DESC);
CREATE UNIQUE INDEX enrollments_open_uidx ON public.enrollments USING btree (lead_id, cycle_no) WHERE (status = ANY (ARRAY['reported'::text, 'verified'::text]));
CREATE INDEX enrollments_owner_idx ON public.enrollments USING btree (owner_user_id, enrolled_on DESC);
CREATE INDEX influencer_login_attempts_code_idx ON public.influencer_login_attempts USING btree (referral_code, at DESC);
CREATE UNIQUE INDEX journey_runs_active_uidx ON public.journey_runs USING btree (lead_id) WHERE (status = ANY (ARRAY['active'::text, 'waiting_send'::text]));
CREATE INDEX journey_runs_due_idx ON public.journey_runs USING btree (next_at) WHERE (status = 'active'::text);
CREATE INDEX journey_runs_journey_idx ON public.journey_runs USING btree (journey_id, status);
CREATE UNIQUE INDEX partner_events_uidx ON public.partner_events USING btree (partner_id, event_id);
CREATE INDEX partner_mapping_active_idx ON public.partner_mapping_profiles USING btree (partner_id, is_active, version DESC);
CREATE INDEX payout_rates_lookup_idx ON public.payout_rates USING btree (scope, university_id, programme_id, user_id, valid_from DESC);
CREATE INDEX payouts_user_idx ON public.payouts USING btree (user_id, period, status);
CREATE INDEX student_leads_channel_idx ON public.student_leads USING btree (channel, created_at DESC);
CREATE INDEX student_leads_created_idx ON public.student_leads USING btree (created_at DESC);
CREATE INDEX student_leads_owner_idx ON public.student_leads USING btree (owner_user_id, next_task_due_at);
CREATE INDEX student_leads_partner_idx ON public.student_leads USING btree (partner_id, allocated_at DESC);
CREATE INDEX student_leads_phone_idx ON public.student_leads USING btree (whatsapp_number);
CREATE INDEX student_leads_referral_idx ON public.student_leads USING btree (referral_code, created_at DESC);
CREATE INDEX student_leads_segment_idx ON public.student_leads USING btree (programme_segment);
CREATE INDEX student_leads_stage_idx ON public.student_leads USING btree (stage, stage_changed_at DESC);
CREATE INDEX student_leads_test_idx ON public.student_leads USING btree (is_test) WHERE is_test;
CREATE INDEX touchpoints_lead_idx ON public.touchpoints USING btree (lead_id, occurred_at DESC);
CREATE INDEX verifications_ip_idx ON public.verifications USING btree (ip, created_at DESC);
CREATE INDEX verifications_target_idx ON public.verifications USING btree (kind, target, created_at DESC);
CREATE INDEX w2_access_codes_fp_idx ON public.w2_access_codes USING btree (((attribution ->> 'fingerprint'::text)), created_at) WHERE (phone IS NULL);
CREATE INDEX w2_access_codes_phone_idx ON public.w2_access_codes USING btree (phone);
CREATE INDEX w2_access_codes_source_idx ON public.w2_access_codes USING btree (source, created_at);
CREATE INDEX w2_clicks_created_idx ON public.w2_clicks USING btree (created_at);
CREATE INDEX w2_clicks_fp_idx ON public.w2_clicks USING btree (fingerprint, created_at);
CREATE INDEX w2_clicks_source_idx ON public.w2_clicks USING btree (source, created_at);
CREATE INDEX w2_conversations_class_idx ON public.w2_conversations USING btree (classification);
CREATE INDEX w2_conversations_conv_idx ON public.w2_conversations USING btree (conversation_id);
CREATE INDEX w2_conversations_nurture_idx ON public.w2_conversations USING btree (nurture_next_at) WHERE (nurture_next_at IS NOT NULL);
CREATE INDEX w2_conversations_source_idx ON public.w2_conversations USING btree (lead_source);
CREATE INDEX w2_events_phone_idx ON public.w2_events USING btree (phone, created_at);
CREATE INDEX w2_events_type_idx ON public.w2_events USING btree (type, created_at);
CREATE INDEX w2_fact_log_phone_idx ON public.w2_fact_log USING btree (phone, created_at);
CREATE INDEX w2_feedback_created_idx ON public.w2_feedback USING btree (created_at);
CREATE INDEX w2_feedback_phone_idx ON public.w2_feedback USING btree (phone, created_at);
CREATE INDEX w2_inbox_pending_idx ON public.w2_inbox USING btree (phone, received_at) WHERE (processed_at IS NULL);
CREATE INDEX w2_inbox_phone_idx ON public.w2_inbox USING btree (phone, received_at);
CREATE INDEX w2_kb_chunks_doc_idx ON public.w2_kb_chunks USING btree (doc_id, chunk_no);
CREATE INDEX w2_kb_chunks_fts_idx ON public.w2_kb_chunks USING gin (search_doc);
CREATE INDEX w2_kb_chunks_trgm_idx ON public.w2_kb_chunks USING gin (content gin_trgm_ops);
CREATE INDEX w2_kb_chunks_vec_idx ON public.w2_kb_chunks USING hnsw (embedding vector_cosine_ops);
CREATE INDEX w2_kb_stage_idx ON public.w2_kb_stage USING btree (batch);
CREATE INDEX w2_learnings_status_idx ON public.w2_learnings USING btree (status, kind);
CREATE INDEX w2_messages_created_idx ON public.w2_messages USING btree (created_at);
CREATE UNIQUE INDEX w2_messages_in_uidx ON public.w2_messages USING btree (message_id) WHERE (direction = 'in'::text);
CREATE INDEX w2_messages_phone_idx ON public.w2_messages USING btree (phone, created_at);
CREATE INDEX w2_nurture_log_phone_idx ON public.w2_nurture_log USING btree (phone, created_at);
CREATE INDEX w2_outbox_due_idx ON public.w2_outbox USING btree (status, next_attempt_at);
CREATE INDEX w2_security_log_idx ON public.w2_security_log USING btree (phone, kind, created_at);

CREATE OR REPLACE FUNCTION public.catalog_commit(p_batch text, p_deactivate_missing boolean DEFAULT true, p_source_file text DEFAULT 'master'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_unis int; v_progs int; v_off int := 0; v_staged int;
begin
select count(*) into v_staged from catalog_stage where batch = p_batch and kind = 'program';
if v_staged = 0 then
return jsonb_build_object('error', 'nothing staged for batch ' || p_batch);
end if;
insert into catalog_universities (name, short_name, institution_type, recognitions, accreditation_text, updated_at)
select distinct on (u->>'name') u->>'name', u->>'short_name', u->>'institution_type',
array(select jsonb_array_elements_text(coalesce(u->'recognitions', '[]'::jsonb))), u->>'accreditation_text', now()
from catalog_stage s, lateral (select s.row as u) x
where s.batch = p_batch and s.kind = 'university' and coalesce(u->>'name', '') <> ''
on conflict (name) do update set short_name = coalesce(excluded.short_name, catalog_universities.short_name),
institution_type = coalesce(excluded.institution_type, catalog_universities.institution_type),
recognitions = case when cardinality(excluded.recognitions) > 0 then excluded.recognitions else catalog_universities.recognitions end,
accreditation_text = coalesce(nullif(excluded.accreditation_text, ''), catalog_universities.accreditation_text), updated_at = now();
get diagnostics v_unis = row_count;
insert into catalog_universities (name, updated_at)
select distinct s.row->>'university_name', now() from catalog_stage s
where s.batch = p_batch and s.kind = 'program' and coalesce(s.row->>'university_name', '') <> ''
on conflict (name) do nothing;
create temporary table if not exists _cat_keys (program_key text primary key) on commit drop;
truncate _cat_keys;
with src as (
select distinct on (k.key) k.key, x, u.id as university_id
from catalog_stage s
cross join lateral (select s.row as x) r
join catalog_universities u on u.name = x->>'university_name'
cross join lateral (select md5(lower(u.name) || '|' || lower(x->>'program_name') || '|' || lower(coalesce(x->>'mode', ''))) as key) k
where s.batch = p_batch and s.kind = 'program' and coalesce(x->>'program_name', '') <> ''
order by k.key, (x->>'source_row')::int
), ins as (
insert into catalog_programs (program_key, university_id, level, level_raw, course, course_key, dual, specialization, program_name, mode,
fee_yearly, fee_semester, fee_total, fee_exam, fee_registration, fee_other, min_qualification, min_pct_general, min_pct_reserved,
eligibility_text, brochure_url, source_row, flags, active, source_file, updated_at)
select key, university_id, x->>'level', x->>'level_raw', x->>'course', x->>'course_key', coalesce((x->>'dual')::boolean, false), x->>'specialization',
x->>'program_name', x->>'mode', (x->>'fee_yearly')::numeric, (x->>'fee_semester')::numeric, (x->>'fee_total')::numeric,
(x->>'fee_exam')::numeric, (x->>'fee_registration')::numeric, x->'fee_other', x->>'min_qualification',
(x->>'min_pct_general')::numeric, (x->>'min_pct_reserved')::numeric, x->>'eligibility_text', x->>'brochure_url',
(x->>'source_row')::int, array(select jsonb_array_elements_text(coalesce(x->'flags', '[]'::jsonb))), true, p_source_file, now()
from src
on conflict (program_key) do update set university_id = excluded.university_id, level = excluded.level, level_raw = excluded.level_raw,
course = excluded.course, course_key = excluded.course_key, dual = excluded.dual, specialization = excluded.specialization,
program_name = excluded.program_name, mode = excluded.mode, fee_yearly = excluded.fee_yearly, fee_semester = excluded.fee_semester,
fee_total = excluded.fee_total, fee_exam = excluded.fee_exam, fee_registration = excluded.fee_registration, fee_other = excluded.fee_other,
min_qualification = excluded.min_qualification, min_pct_general = excluded.min_pct_general, min_pct_reserved = excluded.min_pct_reserved,
eligibility_text = excluded.eligibility_text, brochure_url = excluded.brochure_url, source_row = excluded.source_row, flags = excluded.flags,
active = true, source_file = excluded.source_file, updated_at = now()
returning program_key
)
insert into _cat_keys select program_key from ins;
get diagnostics v_progs = row_count;
if p_deactivate_missing then
update catalog_programs p set active = false, updated_at = now()
where p.active and p.source_file = p_source_file and not exists (select 1 from _cat_keys k where k.program_key = p.program_key);
get diagnostics v_off = row_count;
end if;
delete from catalog_stage where batch = p_batch or created_at < now() - interval '1 day';
perform w2_bump('catalog_version');
delete from w2_search_cache;
return jsonb_build_object('batch', p_batch, 'source_file', p_source_file, 'universities', v_unis, 'programs', v_progs, 'deactivated', v_off);
end $function$;

CREATE OR REPLACE FUNCTION public.catalog_load(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_batch text := 'single-' || md5(random()::text || clock_timestamp()::text);
begin
perform catalog_stage_add(v_batch, p);
return catalog_commit(v_batch, true);
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.catalog_remove_source(p_source_file text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare n int;
begin
update catalog_programs set active = false, updated_at = now() where active and source_file = p_source_file;
get diagnostics n = row_count;
if n > 0 then perform w2_bump('catalog_version'); delete from w2_search_cache; end if;
return jsonb_build_object('source_file', p_source_file, 'deactivated', n);
end $function$;

CREATE OR REPLACE FUNCTION public.catalog_stage_add(p_batch text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_u int; v_p int;
begin
insert into catalog_stage (batch, kind, row) select p_batch, 'university', u from jsonb_array_elements(coalesce(p->'universities', '[]'::jsonb)) u;
get diagnostics v_u = row_count;
insert into catalog_stage (batch, kind, row) select p_batch, 'program', x from jsonb_array_elements(coalesce(p->'programs', '[]'::jsonb)) x;
get diagnostics v_p = row_count;
return jsonb_build_object('batch', p_batch, 'universities', v_u, 'programs', v_p);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_add_earning_rate(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_from date := coalesce((p->>'valid_from')::date, current_date); r earning_rates;
begin
  perform crm_require(array['admin','finance']);
  update earning_rates set valid_to = v_from - 1
   where valid_to is null and valid_from < v_from and scope = p->>'scope'
     and coalesce(university_id, 0) = coalesce((p->>'university_id')::bigint, 0)
     and coalesce(programme_id, 0) = coalesce((p->>'programme_id')::bigint, 0)
     and coalesce(partner_id, 0) = coalesce((p->>'partner_id')::bigint, 0);
  insert into earning_rates (scope, university_id, programme_id, partner_id, rate_type, fee_base, value, tiers, gst_inclusive, valid_from, note, created_by)
  values (p->>'scope', (p->>'university_id')::bigint, (p->>'programme_id')::bigint, (p->>'partner_id')::bigint, p->>'rate_type',
          coalesce(p->>'fee_base', 'recorded'), (p->>'value')::numeric, p->'tiers', coalesce((p->>'gst_inclusive')::boolean, true), v_from, p->>'note', auth.uid())
  returning * into r;
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_add_note(p_id bigint, p_content text, p_kind text DEFAULT 'note'::text, p_outcome text DEFAULT NULL::text, p_meta jsonb DEFAULT '{}'::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint;
begin
  perform crm_require(array['admin','sales_head','sales_manager','marketing','revenue','finance']);
  if not exists (select 1 from student_leads l where l.id = p_id and crm_can_see(l.owner_user_id, l.is_test, l.is_sales_ready)) then raise exception 'lead % not visible', p_id using errcode = '42501'; end if;
  insert into crm_activities (lead_id, kind, content, outcome, meta, actor_id, actor_name)
  values (p_id, p_kind, p_content, p_outcome, coalesce(p_meta, '{}'::jsonb), auth.uid(), crm_me()->>'full_name') returning id into v_id;
  update student_leads set last_activity_at = now(),
         contact_attempts = case when p_kind in ('call','whatsapp','email','sms') then coalesce(contact_attempts, 0) + 1 else contact_attempts end,
         last_contacted_at = case when p_outcome in ('connected','replied') then now() else last_contacted_at end,
         first_contacted_at = case when p_outcome in ('connected','replied') then coalesce(first_contacted_at, now()) else first_contacted_at end
   where id = p_id;
  if p_kind = 'call' and not coalesce(p_meta ? 'call_id', false) then
    insert into calls (lead_id, user_id, provider, direction, status, ended_at, outcome, notes, activity_id)
    values (p_id, auth.uid(), 'manual', 'outbound', case when p_outcome = 'connected' then 'completed' when p_outcome in ('no answer', 'switched off') then 'no_answer' when p_outcome = 'busy' then 'busy' else 'completed' end, now(), p_outcome, p_content, v_id);
    perform crm_call_outcome_task(p_id, p_outcome, auth.uid());
  end if;
  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_add_payout_rate(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_from date := coalesce((p->>'valid_from')::date, current_date); r payout_rates;
begin
  perform crm_require(array['admin','finance']);
  update payout_rates set valid_to = v_from - 1
   where valid_to is null and valid_from < v_from and scope = p->>'scope'
     and coalesce(university_id, 0) = coalesce((p->>'university_id')::bigint, 0)
     and coalesce(programme_id, 0) = coalesce((p->>'programme_id')::bigint, 0)
     and coalesce(user_id::text, '') = coalesce(p->>'user_id', '');
  insert into payout_rates (scope, university_id, programme_id, user_id, rate_type, value, accelerators, valid_from, note, created_by)
  values (p->>'scope', (p->>'university_id')::bigint, (p->>'programme_id')::bigint, (p->>'user_id')::uuid, p->>'rate_type', (p->>'value')::numeric,
          p->'accelerators', v_from, p->>'note', auth.uid())
  returning * into r;
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_agenda()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role text := crm_role(); v_tz text; v_sod timestamptz; v_eod timestamptz;
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  select coalesce(value->>'timezone', 'Asia/Kolkata') into v_tz from crm_settings where key = 'followup';
  v_sod := date_trunc('day', now() at time zone v_tz) at time zone v_tz; v_eod := v_sod + interval '1 day';
  return (
    with mine as (
      select t.id, t.lead_id, t.title, t.kind, t.due_at, t.assignee_id, v.full_name, v.phone_masked, v.stage, v.temperature, u.full_name as assignee_name
        from crm_tasks t join crm_leads_v v on v.id = t.lead_id left join crm_users u on u.id = t.assignee_id
       where t.done_at is null and (v_role in ('admin', 'sales_head') or t.assignee_id = auth.uid())
    )
    select jsonb_build_object(
      'overdue', coalesce((select jsonb_agg(to_jsonb(m) order by m.due_at) from mine m where m.due_at < now()), '[]'::jsonb),
      'today', coalesce((select jsonb_agg(to_jsonb(m) order by m.due_at) from mine m where m.due_at >= now() and m.due_at < v_eod), '[]'::jsonb),
      'upcoming', coalesce((select jsonb_agg(to_jsonb(m) order by m.due_at) from (select * from mine m where m.due_at >= v_eod order by m.due_at limit 100) m), '[]'::jsonb),
      'untouched', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'full_name', v.full_name, 'stage', v.stage, 'temperature', v.temperature, 'assigned_at', v.assigned_at) order by v.assigned_at)
                              from crm_leads_v v where v.owner_user_id is not null and (v_role in ('admin', 'sales_head') or v.owner_user_id = auth.uid())
                                 and v.first_contacted_at is null and v.stage in ('assigned') and v.assigned_at < now() - interval '48 hours'), '[]'::jsonb)
    )
  );
end $function$;

CREATE OR REPLACE FUNCTION public.crm_allocate_lead(p_lead bigint, p_exclude bigint[] DEFAULT '{}'::bigint[], p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  l student_leads; s jsonb; v_seg text; v_consent boolean; c jsonb := '[]'::jsonb; cand jsonb; pt partners; rr routing_rules; v_force text; v_force_partner bigint;
  v_mode text := 'engine'; v_seed double precision; v_stats jsonb; v_draw numeric; v_sd numeric; v_score numeric; v_nr_neutral boolean := false; v_best jsonb; v_best_score numeric := -1;
  v_floor numeric; v_cap numeric; v_min int; v_winner_type text; v_winner_id bigint; v_dec bigint; a allocations; r jsonb; v_in_house_ok boolean; v_assign jsonb; v_excl bigint[] := coalesce(p_exclude, '{}');
begin
  if auth.uid() is not null then perform crm_require(array['admin','revenue','sales_head']); end if;
  select * into l from student_leads where id = p_lead;
  if l.id is null then raise exception 'lead % not found', p_lead; end if;
  if exists (select 1 from allocations where lead_id = p_lead and status in ('pending','pushing','pushed','assigned')) then
    return jsonb_build_object('allocated', false, 'reason', 'lead already has an open allocation');
  end if;
  select value into s from crm_settings where key = 'engine';
  v_seg := crm_segment_of(l);
  v_consent := l.consent_partner_share_at is not null or not coalesce((s->>'require_partner_consent')::boolean, true);
  v_floor := coalesce((s->>'exploration_floor')::numeric, 0.10); v_cap := coalesce((s->>'share_cap')::numeric, 0.70); v_min := coalesce((s->>'new_destination_min_leads')::int, 30);
  v_in_house_ok := exists (select 1 from crm_users cu where cu.is_active and cu.on_shift and cu.role = 'sales_manager'
                             and (select count(*) from student_leads x where x.owner_user_id = cu.id and x.assigned_at >= date_trunc('month', now())) < cu.monthly_cap);
  for rr in select * from routing_rules where active order by priority, id loop
    if crm_criteria_match(rr.conditions, l) then
      if rr.action ? 'exclude_partners' then v_excl := v_excl || array(select (x)::bigint from jsonb_array_elements_text(rr.action->'exclude_partners') x); end if;
      if rr.action->>'destination' = 'in_house' then v_force := 'in_house'; v_mode := 'rule'; exit; end if;
      if rr.action->>'destination' = 'partner' then v_force := 'partner'; v_force_partner := (rr.action->>'partner_id')::bigint; v_mode := 'rule'; exit; end if;
    end if;
  end loop;
  c := c || jsonb_build_object('type', 'in_house', 'id', null, 'name', 'In-house team', 'eligible', v_in_house_ok or coalesce(v_force = 'in_house', false), 'reason', case when v_in_house_ok then null else 'no sales manager with capacity' end);
  for pt in select * from partners where status = 'active' and not (id = any(v_excl)) and coalesce(l.duplicate_claim_count, 0) < 2 loop
    cand := jsonb_build_object('type', 'partner', 'id', pt.id, 'name', pt.name, 'eligible', true, 'reason', null);
    if not v_consent then cand := cand || jsonb_build_object('eligible', false, 'reason', 'no partner-sharing consent');
    elsif not crm_criteria_match(pt.lead_criteria, l) then cand := cand || jsonb_build_object('eligible', false, 'reason', 'outside partner lead criteria');
    elsif coalesce((s->>'require_partner_rate')::boolean, true) and crm_earning_rate(null, null, pt.id, current_date) is null then cand := cand || jsonb_build_object('eligible', false, 'reason', 'no active partner rate');
    elsif pt.daily_cap is not null and (select count(*) from allocations where partner_id = pt.id and created_at > now() - interval '1 day' and status not in ('duplicate','recalled')) >= pt.daily_cap then cand := cand || jsonb_build_object('eligible', false, 'reason', 'daily cap reached');
    elsif pt.monthly_cap is not null and (select count(*) from allocations where partner_id = pt.id and created_at >= date_trunc('month', now()) and status not in ('duplicate','recalled')) >= pt.monthly_cap then cand := cand || jsonb_build_object('eligible', false, 'reason', 'monthly cap reached');
    elsif exists (select 1 from allocations where lead_id = p_lead and partner_id = pt.id and status = 'duplicate') then cand := cand || jsonb_build_object('eligible', false, 'reason', 'partner reported this student as a duplicate');
    end if;
    c := c || cand;
  end loop;
  v_seed := random();
  perform setseed(v_seed);
  for cand in select * from jsonb_array_elements(c) loop
    if (cand->>'eligible')::boolean then
      v_stats := crm_dest_stats(cand->>'type', (cand->>'id')::bigint, v_seg, s);
      v_sd := sqrt(greatest((v_stats->>'p_hat')::numeric * (1 - (v_stats->>'p_hat')::numeric), 0.0001) / ((v_stats->>'n_weighted')::numeric + coalesce((s->>'prior_weight')::numeric, 20)));
      v_draw := greatest(0.0001, least(1, (v_stats->>'p_hat')::numeric + v_sd * (random() + random() + random() + random() + random() + random() - 3)));
      if (v_stats->>'nr_estimated')::boolean then v_nr_neutral := true; end if;
      c := (select jsonb_agg(case when x->>'type' = cand->>'type' and coalesce(x->>'id', '') = coalesce(cand->>'id', '') then x || jsonb_build_object('stats', v_stats, 'draw', round(v_draw, 4)) else x end) from jsonb_array_elements(c) x);
    end if;
  end loop;
  c := (select jsonb_agg(case when (x->>'eligible')::boolean then x || jsonb_build_object('score', round((x->>'draw')::numeric * (case when v_nr_neutral then 1 else (x->'stats'->>'nr')::numeric end) * (x->'stats'->>'speed')::numeric * (x->'stats'->>'reliability')::numeric, 4)) else x end) from jsonb_array_elements(c) x);
  if coalesce((s->>'kill_switch')::boolean, false) then
    v_mode := 'kill_switch';
    select x into v_best from (select x, random() * coalesce((s->'fixed_split'->>coalesce(x->>'id', 'in_house'))::numeric, case when x->>'type' = 'in_house' then coalesce((s->'fixed_split'->>'in_house')::numeric, 100) else 0 end) rnd
                                 from jsonb_array_elements(c) x where (x->>'eligible')::boolean order by rnd desc limit 1) q;
  elsif v_force = 'in_house' then
    select x into v_best from jsonb_array_elements(c) x where x->>'type' = 'in_house';
  elsif v_force = 'partner' then
    select x into v_best from jsonb_array_elements(c) x where x->>'type' = 'partner' and (x->>'id')::bigint = v_force_partner and (x->>'eligible')::boolean;
    if v_best is null then v_mode := 'engine'; end if;
  end if;
  if v_best is null then
    select x into v_best from jsonb_array_elements(c) x
     where (x->>'eligible')::boolean and (x->'stats'->>'n')::int < v_min and (x->'stats'->>'share_30d')::numeric < v_floor and (x->'stats'->>'segment_total_30d')::int >= 5
     order by (x->'stats'->>'share_30d')::numeric limit 1;
    if v_best is not null then v_mode := 'engine_floor'; end if;
  end if;
  if v_best is null then
    select x into v_best from jsonb_array_elements(c) x where (x->>'eligible')::boolean order by (x->>'score')::numeric desc nulls last limit 1;
    if v_best is not null and (v_best->'stats'->>'share_30d')::numeric > v_cap then
      select x into cand from jsonb_array_elements(c) x where (x->>'eligible')::boolean and not (x->>'type' = v_best->>'type' and coalesce(x->>'id', '') = coalesce(v_best->>'id', '')) order by (x->>'score')::numeric desc nulls last limit 1;
      if cand is not null then v_best := cand; v_mode := v_mode || '_cap'; end if;
    end if;
  end if;
  if v_best is null then
    insert into engine_decisions (lead_id, segment, mode, candidates, seed, settings, note) values (p_lead, v_seg, 'none', c, v_seed, s, coalesce(p_note, 'no eligible destination')) returning id into v_dec;
    return jsonb_build_object('allocated', false, 'reason', 'no eligible destination', 'decision_id', v_dec, 'candidates', c);
  end if;
  v_winner_type := v_best->>'type'; v_winner_id := (v_best->>'id')::bigint;
  insert into engine_decisions (lead_id, segment, mode, candidates, winner_type, winner_id, seed, settings, note) values (p_lead, v_seg, v_mode, c, v_winner_type, v_winner_id, v_seed, s, p_note) returning id into v_dec;
  update student_leads set programme_segment = v_seg where id = p_lead;
  if v_winner_type = 'in_house' then
    v_assign := crm_assign_lead(p_lead);
    if not coalesce((v_assign->>'assigned')::boolean, false) then return jsonb_build_object('allocated', false, 'reason', v_assign->>'reason', 'decision_id', v_dec); end if;
    insert into allocations (lead_id, cycle_no, segment, destination_type, user_id, status, pushed_at, engine_decision_id, reason, override)
    values (p_lead, coalesce(l.cycle_no, 1), v_seg, 'in_house', (v_assign->>'user_id')::uuid, 'assigned', now(), v_dec, v_mode, false) returning * into a;
    update allocations set reference = 'EDW-' || a.id where id = a.id;
    update student_leads set allocation_id = a.id, allocation_reason = v_mode where id = p_lead;
    return jsonb_build_object('allocated', true, 'destination', 'in_house', 'user_id', v_assign->>'user_id', 'allocation_id', a.id, 'decision_id', v_dec, 'mode', v_mode);
  else
    insert into allocations (lead_id, cycle_no, segment, destination_type, partner_id, status, engine_decision_id, reason, override)
    values (p_lead, coalesce(l.cycle_no, 1), v_seg, 'partner', v_winner_id, 'pending', v_dec, v_mode, false) returning * into a;
    update allocations set reference = 'EDW-' || a.id where id = a.id;
    update student_leads set destination_type = 'partner', partner_id = v_winner_id, allocation_id = a.id, allocated_at = now(), allocation_reason = v_mode,
           owner_user_id = null, stage = case when stage in ('new','qualifying','allocated','assigned') then 'sent_to_partner' else stage end, stage_changed_at = now(), last_activity_at = now()
     where id = p_lead;
    insert into crm_activities (lead_id, kind, content, meta, actor_id, actor_name)
    values (p_lead, 'assign', 'Allocated to partner ' || (select name from partners where id = v_winner_id) || ' (' || v_mode || ')', jsonb_build_object('allocation_id', a.id, 'decision_id', v_dec), auth.uid(), coalesce(crm_me()->>'full_name', 'Allocation engine'));
    return jsonb_build_object('allocated', true, 'destination', 'partner', 'partner_id', v_winner_id, 'allocation_id', a.id, 'reference', 'EDW-' || a.id, 'decision_id', v_dec, 'mode', v_mode);
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_api_key_check(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k crm_api_keys;
begin
  select * into k from crm_api_keys where key_hash = encode(extensions.digest(coalesce(p_key, ''), 'sha256'), 'hex') and revoked_at is null;
  if k.id is null then return null; end if;
  update crm_api_keys set last_used_at = now() where id = k.id;
  return jsonb_build_object('id', k.id, 'name', k.name, 'source_system', k.source_system, 'scopes', to_jsonb(k.scopes));
end $function$;

CREATE OR REPLACE FUNCTION public.crm_apply_stage_system(p_id bigint, p_stage text, p_sub_stage text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_fields jsonb DEFAULT '{}'::jsonb, p_actor text DEFAULT 'system'::text, p_allow_back boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l student_leads; v_stages jsonb; v_subs jsonb; v_lost jsonb; v_req jsonb; f text; v_set text; v_from int; v_to int;
begin
  select * into l from student_leads where id = p_id;
  if l.id is null then raise exception 'lead % not found', p_id; end if;
  select value into v_stages from crm_settings where key = 'stages';
  select value into v_subs from crm_settings where key = 'sub_stages';
  select value into v_lost from crm_settings where key = 'lost_reasons';
  select value into v_req from crm_settings where key = 'required_fields';
  if not v_stages ? p_stage then raise exception 'unknown stage %', p_stage; end if;
  if p_sub_stage is not null and not coalesce(v_subs->p_stage, '[]'::jsonb) ? p_sub_stage then p_sub_stage := null; end if;
  if p_stage = 'lost' and not v_lost ? coalesce(p_reason, '') then p_reason := 'cannot be served'; end if;
  select t.ord - 1 into v_from from jsonb_array_elements_text(v_stages) with ordinality as t(x, ord) where t.x = l.stage;
  select t.ord - 1 into v_to from jsonb_array_elements_text(v_stages) with ordinality as t(x, ord) where t.x = p_stage;
  if not p_allow_back and v_from is not null and v_to is not null and v_to < v_from and p_stage not in ('lost','nurture') then
    return jsonb_build_object('skipped', true, 'reason', 'backwards move ' || l.stage || ' -> ' || p_stage);
  end if;
  select string_agg(format('%I = %L', case k when 'enrolled_programme' then 'enrolled_program' when 'enrolled_on' then 'enrollment_date' else k end, v), ', ')
    into v_set from jsonb_each_text(p_fields) as e(k, v)
   where k in ('application_id','application_status','fee_amount_inr','fee_paid_inr','enrolled_university','enrolled_programme','enrolled_on','enrollment_status');
  if v_set is not null then execute format('update student_leads set %s where id = %s', v_set, p_id); end if;
  select * into l from student_leads where id = p_id;
  for f in select jsonb_array_elements_text(coalesce(v_req->p_stage, '[]'::jsonb)) loop
    if (to_jsonb(l)->>f) is null or (to_jsonb(l)->>f) = '' then raise exception 'stage % needs %', p_stage, f; end if;
  end loop;
  update student_leads set
    stage = p_stage, sub_stage = p_sub_stage, stage_changed_at = now(),
    lost_reason = case when p_stage = 'lost' then p_reason else null end,
    lost_at = case when p_stage = 'lost' then now() else null end,
    applied_at = case when p_stage = 'applied' then coalesce(applied_at, now()) else applied_at end,
    enrollment_date = case when p_stage = 'enrolled' then coalesce(enrollment_date, current_date) else enrollment_date end,
    first_contacted_at = case when p_stage in ('contacted','counselled','applied','enrolled') then coalesce(first_contacted_at, now()) else first_contacted_at end,
    last_contacted_at = case when p_stage in ('contacted','counselled') then now() else last_contacted_at end,
    last_activity_at = now(), updated_by = p_actor
  where id = p_id;
  insert into crm_activities (lead_id, kind, content, outcome, meta, actor_id, actor_name)
  values (p_id, 'stage', l.stage || ' → ' || p_stage || coalesce(' (' || p_sub_stage || ')', ''), p_reason,
          jsonb_build_object('from', l.stage, 'to', p_stage, 'sub_stage', p_sub_stage, 'fields', p_fields), auth.uid(), coalesce(crm_me()->>'full_name', p_actor));
  if p_stage = 'enrolled' then perform crm_report_enrollment(p_id, p_fields); end if;
  if p_stage in ('enrolled','lost') then update allocations set outcome = p_stage, outcome_at = now(), updated_at = now() where lead_id = p_id and status in ('pushed','assigned') and outcome is null; end if;
  return jsonb_build_object('stage', p_stage, 'sub_stage', p_sub_stage);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_assign_lead(p_id bigint, p_user uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l student_leads; u crm_users; v_due timestamptz; v_reason text; v_actor text;
begin
  select * into l from student_leads where id = p_id;
  if l.id is null then raise exception 'lead % not found', p_id; end if;
  if auth.uid() is not null then
    if p_user is null then perform crm_require(array['admin','sales_head','revenue']);
    elsif p_user = auth.uid() then perform crm_require(array['admin','sales_head','sales_manager','revenue']);
    else perform crm_require(array['admin','sales_head','revenue']); end if;
    if not crm_can_see(l.owner_user_id, l.is_test, l.is_sales_ready) then raise exception 'lead % not visible', p_id using errcode = '42501'; end if;
  end if;
  if p_user is not null then
    select * into u from crm_users where id = p_user and is_active and role in ('sales_manager','sales_head','admin');
    if u.id is null then raise exception 'user % is not an active sales user', p_user; end if;
    v_reason := 'manual';
  else
    select * into u from crm_users c
     where c.is_active and c.on_shift and c.role = 'sales_manager'
       and (select count(*) from student_leads s where s.owner_user_id = c.id and s.assigned_at >= date_trunc('month', now())) < c.monthly_cap
     order by c.last_assigned_at nulls first, c.id limit 1;
    if u.id is null then return jsonb_build_object('assigned', false, 'reason', 'no eligible sales manager'); end if;
    v_reason := 'round_robin';
  end if;
  v_due := now() + make_interval(mins => crm_sla_minutes(l.temperature));
  update student_leads set
    owner_user_id = u.id, team_id = u.team_id, assigned_at = now(), destination_type = 'in_house', partner_id = null, allocation_reason = v_reason, allocated_at = coalesce(allocated_at, now()),
    stage = case when stage in ('new','qualifying','allocated','sent_to_partner') then 'assigned' else stage end,
    stage_changed_at = case when stage in ('new','qualifying','allocated','sent_to_partner') then now() else stage_changed_at end,
    next_task_due_at = v_due, last_activity_at = now()
  where id = p_id;
  update crm_users set last_assigned_at = now() where id = u.id;
  update crm_tasks set done_at = now() where lead_id = p_id and done_at is null and kind = 'first_contact';
  insert into crm_tasks (lead_id, title, kind, due_at, assignee_id, created_by)
  values (p_id, 'First contact (' || coalesce(l.temperature, 'lead') || ')', 'first_contact', v_due, u.id, auth.uid());
  v_actor := coalesce(crm_me()->>'full_name', case when auth.uid() is null then 'Allocation engine' else null end);
  insert into crm_activities (lead_id, kind, content, meta, actor_id, actor_name)
  values (p_id, 'assign', 'Assigned to ' || coalesce(u.full_name, u.email) || ' (' || v_reason || ')' || coalesce(': ' || p_note, ''),
          jsonb_build_object('user_id', u.id, 'reason', v_reason, 'due_at', v_due), auth.uid(), v_actor);
  return jsonb_build_object('assigned', true, 'user_id', u.id, 'user_name', coalesce(u.full_name, u.email), 'due_at', v_due, 'reason', v_reason);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_auto_assign_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s jsonb;
begin
  select value into s from crm_settings where key = 'engine';
  if coalesce((s->>'enabled')::boolean, true) then perform crm_allocate_lead(new.id, '{}', 'auto on sales-ready');
  else perform crm_assign_lead(new.id); end if;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_b2b_reader()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(crm_role(), '') in ('admin','revenue','sales_head','finance','viewer','marketing');
$function$;

CREATE OR REPLACE FUNCTION public.crm_call_event(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c calls; l student_leads; v_status text := lower(coalesce(p->>'status', '')); v_outcome text; v_content text; v_act bigint; v_task bigint; v_dur int;
begin
  if auth.uid() is not null then perform crm_require(array['admin','sales_head','sales_manager']); end if;
  if p ? 'call_id' then select * into c from calls where id = (p->>'call_id')::bigint; end if;
  if c.id is null and p->>'provider_call_id' is not null then select * into c from calls where provider = coalesce(p->>'provider', 'exotel') and provider_call_id = p->>'provider_call_id'; end if;
  if c.id is null then
    l := crm_find_lead(crm_norm_phone(coalesce(p->>'from', '')));
    insert into calls (lead_id, user_id, provider, provider_call_id, direction, from_number, to_number, status, raw)
    values (l.id, l.owner_user_id, coalesce(p->>'provider', 'exotel'), p->>'provider_call_id', coalesce(p->>'direction', 'inbound'), p->>'from', p->>'to', 'initiated', p->'raw') returning * into c;
  else
    select * into l from student_leads where id = c.lead_id;
  end if;
  if v_status not in ('initiated', 'ringing', 'in_progress', 'completed', 'no_answer', 'busy', 'failed', 'cancelled', 'missed') then v_status := c.status; end if;
  v_dur := coalesce((p->>'duration_sec')::int, c.duration_sec);
  update calls set
    provider_call_id = coalesce(p->>'provider_call_id', provider_call_id), status = v_status,
    answered_at = coalesce((p->>'answered_at')::timestamptz, answered_at, case when v_status = 'in_progress' then now() end),
    ended_at = coalesce((p->>'ended_at')::timestamptz, ended_at, case when v_status in ('completed', 'no_answer', 'busy', 'failed', 'cancelled', 'missed') then now() end),
    duration_sec = v_dur, recording_url = coalesce(p->>'recording_url', recording_url), notes = coalesce(p->>'error', notes),
    raw = coalesce(p->'raw', raw), updated_at = now()
  where id = c.id returning * into c;
  if v_status not in ('completed', 'no_answer', 'busy', 'failed', 'cancelled', 'missed') or c.activity_id is not null or c.lead_id is null then
    return jsonb_build_object('call_id', c.id, 'status', v_status, 'lead_id', c.lead_id);
  end if;
  if c.direction = 'inbound' then
    v_outcome := case when v_status = 'completed' and coalesce(v_dur, 0) > 0 then 'connected' else 'missed' end;
    v_content := case when v_outcome = 'connected' then 'Inbound call answered' else 'Missed inbound call' end || coalesce(' · ' || v_dur || ' s', '');
  else
    v_outcome := case when v_status = 'completed' and coalesce(v_dur, 0) > 0 then 'connected' when v_status = 'busy' then 'busy' when v_status in ('no_answer', 'completed') then 'no answer' else 'failed' end;
    v_content := 'Call · ' || v_status || coalesce(' · ' || v_dur || ' s', '') || coalesce(' · ' || (p->>'error'), '');
  end if;
  insert into crm_activities (lead_id, kind, content, outcome, meta, actor_id, actor_name)
  values (c.lead_id, 'call', v_content, v_outcome, jsonb_build_object('call_id', c.id, 'provider', c.provider, 'recording_url', c.recording_url, 'duration_sec', v_dur, 'direction', c.direction),
          c.user_id, coalesce((select full_name from crm_users where id = c.user_id), 'Telephony')) returning id into v_act;
  update calls set activity_id = v_act, outcome = v_outcome where id = c.id;
  update student_leads set last_activity_at = now(),
         contact_attempts = case when c.direction = 'outbound' and v_outcome <> 'failed' then coalesce(contact_attempts, 0) + 1 else contact_attempts end,
         last_contacted_at = case when v_outcome = 'connected' then now() else last_contacted_at end,
         first_contacted_at = case when v_outcome = 'connected' then coalesce(first_contacted_at, now()) else first_contacted_at end
   where id = c.lead_id;
  if c.direction = 'inbound' and v_outcome = 'missed' then
    if not exists (select 1 from crm_tasks where lead_id = c.lead_id and done_at is null and kind = 'callback') then
      insert into crm_tasks (lead_id, title, kind, due_at, assignee_id) values (c.lead_id, 'Call back — missed call from the student', 'callback', now() + interval '30 minutes', l.owner_user_id) returning id into v_task;
      update student_leads set next_task_due_at = least(coalesce(next_task_due_at, now() + interval '30 minutes'), now() + interval '30 minutes') where id = c.lead_id;
    end if;
  elsif c.direction = 'outbound' then
    v_task := crm_call_outcome_task(c.lead_id, v_outcome, c.user_id);
  end if;
  return jsonb_build_object('call_id', c.id, 'status', v_status, 'lead_id', c.lead_id, 'outcome', v_outcome, 'activity_id', v_act, 'task_id', v_task);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_call_outcome_task(p_lead bigint, p_outcome text, p_assignee uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_title text; v_due timestamptz; v_misses int; v_id bigint; v_owner uuid;
begin
  select owner_user_id into v_owner from student_leads where id = p_lead;
  case lower(coalesce(p_outcome, ''))
    when 'connected' then v_title := 'Follow-up call'; v_due := now() + interval '1 day';
    when 'call back' then v_title := 'Call back as agreed'; v_due := now() + interval '2 hours';
    when 'no answer', 'busy', 'switched off' then
      select count(*) into v_misses from crm_activities where lead_id = p_lead and kind = 'call' and lower(coalesce(outcome, '')) in ('no answer', 'busy', 'switched off') and created_at > now() - interval '48 hours';
      if v_misses >= 3 then v_title := 'Send a WhatsApp template (3 no-answers in 48 h)'; v_due := now() + interval '1 hour';
      else v_title := 'Retry call'; v_due := now() + interval '3 hours'; end if;
    when 'wrong number' then v_title := 'Verify the phone number'; v_due := now() + interval '1 day';
    else return null;
  end case;
  select id into v_id from crm_tasks where lead_id = p_lead and done_at is null and kind = 'suggested' order by id limit 1;
  if v_id is not null then
    update crm_tasks set title = v_title, due_at = v_due, assignee_id = coalesce(p_assignee, v_owner, assignee_id) where id = v_id;
  else
    insert into crm_tasks (lead_id, title, kind, due_at, assignee_id, created_by)
    values (p_lead, v_title, 'suggested', v_due, coalesce(p_assignee, v_owner), auth.uid()) returning id into v_id;
  end if;
  update student_leads set next_task_due_at = (select min(due_at) from crm_tasks where lead_id = p_lead and done_at is null) where id = p_lead;
  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_call_start(p_lead bigint, p_provider text, p_from text, p_to text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint;
begin
  perform crm_require(array['admin','sales_head','sales_manager']);
  if not exists (select 1 from student_leads l where l.id = p_lead and crm_can_see(l.owner_user_id, l.is_test, l.is_sales_ready)) then raise exception 'lead % not visible', p_lead using errcode = '42501'; end if;
  insert into calls (lead_id, user_id, provider, direction, from_number, to_number, status) values (p_lead, auth.uid(), p_provider, 'outbound', p_from, p_to, 'initiated') returning id into v_id;
  return jsonb_build_object('call_id', v_id);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_campaign_cancel(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  perform crm_require(array['admin', 'marketing', 'sales_head']);
  update campaign_sends set status = 'skipped', reason = 'cancelled' where campaign_id = p_id and status = 'queued'; get diagnostics n = row_count;
  update campaigns set status = 'cancelled', updated_at = now() where id = p_id and status in ('draft', 'scheduled', 'sending');
  return jsonb_build_object('cancelled', n);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_campaign_claim(p_limit integer DEFAULT 50, p_base_url text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cs campaign_sends; c campaigns; g jsonb; jobs jsonb := '[]'::jsonb; job jsonb;
begin
  if auth.uid() is not null then perform crm_require(array['admin']); end if;
  for cs in select s.* from campaign_sends s join campaigns ca on ca.id = s.campaign_id
             where ca.status in ('scheduled', 'sending') and ca.scheduled_at <= now() and s.status = 'queued' and s.next_at <= now()
             order by s.next_at, s.id limit p_limit for update of s skip locked loop
    select * into c from campaigns where id = cs.campaign_id;
    g := crm_marketing_allowed(cs.lead_id, c.channel);
    if not (g->>'ok')::boolean then
      if g ? 'defer_until' and (g->>'defer_until')::timestamptz < c.scheduled_at + interval '7 days' then
        update campaign_sends set next_at = (g->>'defer_until')::timestamptz, reason = g->>'reason' where id = cs.id;
      else
        update campaign_sends set status = 'skipped', reason = g->>'reason' where id = cs.id;
        update campaigns set stats = stats || jsonb_build_object('skipped', coalesce((stats->>'skipped')::int, 0) + 1) where id = c.id;
      end if;
      continue;
    end if;
    begin
      job := crm_send_job(cs.lead_id, c.template_id, p_base_url, jsonb_build_object('campaign_name', c.name)) || jsonb_build_object('send_id', cs.id, 'campaign_id', c.id);
    exception when others then
      update campaign_sends set status = 'failed', error = sqlerrm where id = cs.id;
      update campaigns set stats = stats || jsonb_build_object('failed', coalesce((stats->>'failed')::int, 0) + 1) where id = c.id;
      continue;
    end;
    update campaign_sends set status = 'sending' where id = cs.id;
    update campaigns set status = 'sending', updated_at = now() where id = c.id and status = 'scheduled';
    jobs := jobs || job;
  end loop;
  return jobs;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_campaign_result(p_send bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cs campaign_sends; c campaigns; v_ok boolean := coalesce((p->>'ok')::boolean, false);
begin
  if auth.uid() is not null then perform crm_require(array['admin']); end if;
  select * into cs from campaign_sends where id = p_send;
  if cs.id is null then return jsonb_build_object('error', 'send not found'); end if;
  select * into c from campaigns where id = cs.campaign_id;
  if v_ok then
    update campaign_sends set status = 'sent', sent_at = now(), provider_message_id = p->>'message_id', error = null where id = cs.id;
    insert into crm_activities (lead_id, kind, content, meta, actor_name)
    values (cs.lead_id, c.channel, left(coalesce(p->>'content', c.name), 2000), jsonb_build_object('marketing', true, 'campaign_id', c.id, 'campaign', c.name, 'message_id', p->>'message_id', 'dry_run', coalesce((p->>'dry_run')::boolean, false)), 'Campaign');
    update student_leads set last_campaign_id = c.id, last_marketing_message_at = now() where id = cs.lead_id;
    update campaigns set stats = stats || jsonb_build_object('sent', coalesce((stats->>'sent')::int, 0) + 1) where id = c.id;
  else
    update campaign_sends set status = 'failed', error = left(p->>'error', 2000) where id = cs.id;
    update campaigns set stats = stats || jsonb_build_object('failed', coalesce((stats->>'failed')::int, 0) + 1) where id = c.id;
  end if;
  if not exists (select 1 from campaign_sends where campaign_id = c.id and status in ('queued', 'sending')) then update campaigns set status = 'sent', updated_at = now() where id = c.id and status = 'sending'; end if;
  return jsonb_build_object('status', case when v_ok then 'sent' else 'failed' end);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_campaign_schedule(p_id bigint, p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c campaigns; n int; tpl message_templates;
begin
  perform crm_require(array['admin', 'marketing', 'sales_head']);
  select * into c from campaigns where id = p_id;
  if c.id is null then raise exception 'campaign % not found', p_id; end if;
  if c.status not in ('draft', 'scheduled', 'cancelled') then raise exception 'campaign is %', c.status; end if;
  select * into tpl from message_templates where id = c.template_id and active;
  if tpl.id is null or tpl.channel <> c.channel then raise exception 'pick an active % template first', c.channel; end if;
  if c.channel = 'whatsapp' and coalesce(tpl.wa_template_name, '') = '' then raise exception 'a WhatsApp campaign needs an approved template (Meta template name)'; end if;
  delete from campaign_sends where campaign_id = p_id and status = 'queued';
  insert into campaign_sends (campaign_id, lead_id, next_at) select p_id, x, coalesce(p_at, now()) from crm_segment_resolve(c.segment_id) x on conflict (campaign_id, lead_id) do nothing;
  select count(*) into n from campaign_sends where campaign_id = p_id and status = 'queued';
  update campaigns set status = 'scheduled', scheduled_at = coalesce(p_at, now()), stats = jsonb_build_object('queued', n, 'sent', 0, 'failed', 0, 'skipped', 0), updated_at = now() where id = p_id;
  return jsonb_build_object('campaign_id', p_id, 'queued', n, 'scheduled_at', coalesce(p_at, now()));
end $function$;

CREATE OR REPLACE FUNCTION public.crm_can_see(p_owner uuid, p_is_test boolean, p_ready boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case coalesce(crm_role(), '')
           when '' then false
           when 'sales_manager' then (p_owner = auth.uid() or (p_owner is null and coalesce(p_ready, false))) and not coalesce(p_is_test, false)
           when 'admin' then true
           else not coalesce(p_is_test, false) end;
$function$;

CREATE OR REPLACE FUNCTION public.crm_compute_earning(e enrollments, r earning_rates, p_period text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p catalog_programs; v_base numeric; v_pct numeric; v_amt numeric; v_gst numeric := coalesce((crm_money_setting('gst_rate'))::text::numeric, 0.18);
        v_gross numeric; v_net numeric; v_tax numeric; v_prov boolean := false;
begin
  if r.id is null then return null; end if;
  if e.programme_id is not null then select * into p from catalog_programs where id = e.programme_id; end if;
  v_base := case r.fee_base when 'first_year' then coalesce(p.fee_yearly, e.fee_amount_inr) when 'total' then coalesce(p.fee_total, e.fee_amount_inr)
                            when 'paid' then coalesce(e.fee_paid_inr, e.fee_amount_inr) else coalesce(e.fee_amount_inr, p.fee_yearly) end;
  if r.rate_type = 'tiered' then v_pct := crm_tier_pct(r.tiers, crm_conversion(p_period, r.university_id)); v_prov := true;
  elsif r.rate_type = 'percent' then v_pct := r.value; end if;
  v_amt := case r.rate_type when 'fixed' then r.value else round(coalesce(v_base, 0) * coalesce(v_pct, 0) / 100, 2) end;
  if r.gst_inclusive then v_gross := v_amt; v_net := round(v_amt / (1 + v_gst), 2); v_tax := v_gross - v_net;
  else v_net := v_amt; v_tax := round(v_amt * v_gst, 2); v_gross := v_net + v_tax; end if;
  return jsonb_build_object('base', v_base, 'pct', v_pct, 'gross', v_gross, 'gst', v_tax, 'net', v_net, 'tier_provisional', v_prov);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_compute_payout(e enrollments, r payout_rates, p_earning_net numeric, p_period text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p catalog_programs; v_base numeric; v_pct numeric := r.value; v_n int; v_extra numeric := 0; a jsonb; v_amt numeric;
begin
  if r.id is null then return null; end if;
  if e.programme_id is not null then select * into p from catalog_programs where id = e.programme_id; end if;
  v_base := coalesce(e.fee_amount_inr, p.fee_yearly, 0);
  select count(*) + 1 into v_n from payouts x where x.user_id = e.owner_user_id and x.period = p_period and not x.is_clawback and x.status <> 'clawback' and x.enrollment_id <> e.id;
  for a in select * from jsonb_array_elements(coalesce(r.accelerators, '[]'::jsonb)) loop
    if v_n >= (a->>'from_count')::int then v_extra := greatest(v_extra, (a->>'extra_pct')::numeric); end if;
  end loop;
  v_amt := case r.rate_type when 'pct_of_fee' then round(v_base * (v_pct + v_extra) / 100, 2)
                            when 'pct_of_earning' then round(coalesce(p_earning_net, 0) * (v_pct + v_extra) / 100, 2)
                            else r.value + round(v_base * v_extra / 100, 2) end;
  return jsonb_build_object('base', v_base, 'pct', v_pct, 'extra_pct', v_extra, 'nth', v_n, 'amount', v_amt);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_conversion(p_period text, p_university bigint DEFAULT NULL::bigint)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when d = 0 then null else round(n * 100.0 / d, 2) end from (
    select (select count(*) from enrollments e where e.status = 'verified' and to_char(e.enrolled_on, 'YYYY-MM') = p_period and (p_university is null or e.university_id = p_university)) as n,
           (select count(*) from student_leads l where to_char(l.assigned_at, 'YYYY-MM') = p_period and not l.is_test) as d) x;
$function$;

CREATE OR REPLACE FUNCTION public.crm_create_api_key(p_name text, p_source_system text DEFAULT 'api'::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_key text;
begin
  perform crm_require(array['admin']);
  v_key := 'edw_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into crm_api_keys (name, key_hash, source_system, created_by) values (p_name, encode(extensions.digest(v_key, 'sha256'), 'hex'), p_source_system, auth.uid());
  return v_key;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_criteria_match(p_criteria jsonb, l student_leads)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select (not (p_criteria ? 'course_keys') or p_criteria->'course_keys' ? regexp_replace(lower(coalesce(l.interested_course, '')), '[^a-z0-9]', '', 'g'))
     and (not (p_criteria ? 'levels') or p_criteria->'levels' ? coalesce(l.program_level, ''))
     and (not (p_criteria ? 'modes') or p_criteria->'modes' ? coalesce(l.study_mode_preference, ''))
     and (not (p_criteria ? 'cities') or exists (select 1 from jsonb_array_elements_text(p_criteria->'cities') c where lower(c) = lower(coalesce(l.city, l.current_city_country, ''))))
     and (not (p_criteria ? 'sources') or p_criteria->'sources' ? coalesce(l.lead_source, ''))
     and (not (p_criteria ? 'universities') or exists (select 1 from jsonb_array_elements_text(p_criteria->'universities') u where lower(u) = lower(coalesce(l.interested_university, l.university_preference, ''))));
$function$;

CREATE OR REPLACE FUNCTION public.crm_daily_digest()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tz text; v_day date; v_from timestamptz; v_to timestamptz; r jsonb;
begin
  if auth.uid() is not null then perform crm_require(array['admin']); end if;
  select coalesce(value->>'timezone', 'Asia/Kolkata') into v_tz from crm_settings where key = 'followup';
  v_day := (now() at time zone v_tz)::date - 1; v_from := v_day::timestamp at time zone v_tz; v_to := (v_day + 1)::timestamp at time zone v_tz;
  select jsonb_build_object(
    'day', v_day,
    'new_leads', (select count(*) from student_leads where created_at >= v_from and created_at < v_to and deleted_at is null and not coalesce(is_test, false)),
    'sales_ready', (select count(*) from student_leads where sales_ready_at >= v_from and sales_ready_at < v_to and not coalesce(is_test, false)),
    'assigned', (select count(*) from student_leads where assigned_at >= v_from and assigned_at < v_to and not coalesce(is_test, false)),
    'contacted', (select count(*) from student_leads where first_contacted_at >= v_from and first_contacted_at < v_to and not coalesce(is_test, false)),
    'enrolled', (select count(*) from student_leads where enrollment_date = v_day and not coalesce(is_test, false)),
    'calls', (select count(*) from calls where started_at >= v_from and started_at < v_to),
    'overdue_tasks', (select count(*) from crm_tasks where done_at is null and due_at < now()),
    'untouched_48h', (select count(*) from student_leads where owner_user_id is not null and first_contacted_at is null and stage = 'assigned' and assigned_at < now() - interval '48 hours' and deleted_at is null),
    'top_sources', (select coalesce(jsonb_agg(jsonb_build_object('source', source, 'leads', n) order by n desc), '[]'::jsonb) from (select coalesce(lead_source, 'unknown') source, count(*) n from student_leads where created_at >= v_from and created_at < v_to and deleted_at is null and not coalesce(is_test, false) group by 1 order by 2 desc limit 5) s),
    'recipients', (select coalesce(jsonb_agg(jsonb_build_object('email', email, 'name', full_name)), '[]'::jsonb) from crm_users where is_active and role in ('admin', 'sales_head'))
  ) into r;
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_dest_stats(p_type text, p_partner bigint, p_segment text, s jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_hl numeric := coalesce((s->>'half_life_days')::numeric, 30);
  v_prior numeric := coalesce((s->>'prior_weight')::numeric, 20);
  v_default numeric := coalesce((s->>'default_p_enroll')::numeric, 0.05);
  v_n_w numeric; v_enr_w numeric; v_n int; v_avg numeric; v_p numeric; v_nr numeric; v_nr_est boolean := false;
  v_contact_med numeric; v_seg_contact_med numeric; v_speed numeric := 1; v_rel numeric := 1; v_breach numeric; v_stale numeric; v_share numeric; v_seg_total int;
  v_seg_prefix text := split_part(p_segment, '|', 1) || '|' || split_part(p_segment, '|', 2) || '|';
begin
  with a as (
    select al.*, power(0.5, extract(epoch from now() - al.created_at) / 86400 / v_hl) w,
           exists (select 1 from enrollments e where e.lead_id = al.lead_id and e.created_at >= al.created_at and e.status in ('reported','verified')) enrolled
      from allocations al
     where al.destination_type = p_type and (p_type = 'in_house' or al.partner_id = p_partner) and al.status in ('pushed','assigned','closed')
       and (al.segment = p_segment or (al.segment like v_seg_prefix || '%' and (select count(*) from allocations x where x.destination_type = p_type and (p_type = 'in_house' or x.partner_id = p_partner) and x.segment = p_segment) < v_prior))
  )
  select coalesce(sum(w), 0), coalesce(sum(w) filter (where enrolled), 0), count(*) into v_n_w, v_enr_w, v_n from a;
  select coalesce(sum(case when e.lead_id is not null then 1 else 0 end)::numeric / nullif(count(*), 0), v_default) into v_avg
    from allocations al left join lateral (select lead_id from enrollments e where e.lead_id = al.lead_id and e.created_at >= al.created_at and e.status in ('reported','verified') limit 1) e on true
   where al.status in ('pushed','assigned','closed') and al.segment like v_seg_prefix || '%';
  v_avg := coalesce(v_avg, v_default);
  v_p := (v_enr_w + v_prior * v_avg) / (v_n_w + v_prior);
  select avg(e.realised_net_revenue_inr) into v_nr from enrollments e join allocations al on al.lead_id = e.lead_id and al.destination_type = p_type and (p_type = 'in_house' or al.partner_id = p_partner)
   where e.status = 'verified' and al.segment = p_segment;
  if v_nr is null then
    select avg(e.realised_net_revenue_inr) into v_nr from enrollments e where e.status = 'verified' and coalesce(e.destination_type, 'in_house') = p_type and (p_type = 'in_house' or e.partner_id = p_partner);
  end if;
  if v_nr is null then v_nr_est := true; end if;
  select percentile_cont(0.5) within group (order by extract(epoch from first_contact_at - coalesce(pushed_at, created_at)) / 3600) into v_contact_med
    from allocations where destination_type = p_type and (p_type = 'in_house' or partner_id = p_partner) and first_contact_at is not null and created_at > now() - interval '90 days';
  select percentile_cont(0.5) within group (order by extract(epoch from first_contact_at - coalesce(pushed_at, created_at)) / 3600) into v_seg_contact_med
    from allocations where first_contact_at is not null and created_at > now() - interval '90 days';
  if v_contact_med is not null and v_seg_contact_med is not null and v_contact_med > 0 then
    v_speed := greatest((s->'speed_bounds'->>0)::numeric, least((s->'speed_bounds'->>1)::numeric, v_seg_contact_med / v_contact_med));
  end if;
  if p_type = 'partner' then
    select coalesce(avg(case when al.first_contact_at is null and al.pushed_at < now() - make_interval(hours => coalesce((pt.sla->>'first_contact_hours')::int, 2)) then 1 else 0 end), 0),
           coalesce(avg(case when al.outcome is null and coalesce(al.last_event_at, al.pushed_at) < now() - make_interval(days => coalesce((pt.sla->>'status_update_days')::int, 7)) then 1 else 0 end), 0)
      into v_breach, v_stale
      from allocations al join partners pt on pt.id = al.partner_id where al.partner_id = p_partner and al.status = 'pushed' and al.pushed_at > now() - interval '7 days';
    v_rel := greatest((s->'reliability_bounds'->>0)::numeric, least((s->'reliability_bounds'->>1)::numeric, 1 - 0.5 * coalesce(v_breach, 0) - 0.3 * coalesce(v_stale, 0)));
  end if;
  select count(*) into v_seg_total from allocations where segment = p_segment and created_at > now() - interval '30 days' and status not in ('duplicate','recalled');
  select case when v_seg_total = 0 then 0 else count(*)::numeric / v_seg_total end into v_share from allocations
   where segment = p_segment and created_at > now() - interval '30 days' and status not in ('duplicate','recalled') and destination_type = p_type and (p_type = 'in_house' or partner_id = p_partner);
  return jsonb_build_object('n', v_n, 'n_weighted', round(v_n_w, 2), 'enrolled_weighted', round(v_enr_w, 2), 'p_hat', round(v_p, 4), 'prior_avg', round(v_avg, 4),
                            'nr', round(coalesce(v_nr, 0), 2), 'nr_estimated', v_nr_est, 'speed', round(v_speed, 3), 'reliability', round(v_rel, 3),
                            'contact_median_h', round(coalesce(v_contact_med, 0), 1), 'share_30d', round(coalesce(v_share, 0), 3), 'segment_total_30d', v_seg_total);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_duplicate_candidates(p_lead bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l student_leads; v_phone text;
begin
  select * into l from student_leads where id = p_lead and crm_can_see(owner_user_id, is_test, is_sales_ready);
  if l.id is null then return '[]'::jsonb; end if;
  v_phone := regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g');
  return coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'full_name', v.full_name, 'phone_masked', v.phone_masked, 'stage', v.stage, 'owner_name', v.owner_name, 'created_at', v.created_at, 'reason', d.reason) order by v.created_at)
    from (
      select o.id, 'same email' as reason from student_leads o where o.id <> p_lead and o.deleted_at is null and o.merged_into_id is null and coalesce(l.email_id, '') <> '' and lower(o.email_id) = lower(l.email_id)
      union
      select o.id, 'same alternate phone' from student_leads o where o.id <> p_lead and o.deleted_at is null and o.merged_into_id is null
       and ((coalesce(l.alternate_phone, '') <> '' and regexp_replace(o.whatsapp_number, '\D', '', 'g') = regexp_replace(l.alternate_phone, '\D', '', 'g'))
         or (coalesce(o.alternate_phone, '') <> '' and regexp_replace(o.alternate_phone, '\D', '', 'g') = v_phone))
      union
      select o.id, 'same name and city' from student_leads o where o.id <> p_lead and o.deleted_at is null and o.merged_into_id is null and coalesce(l.student_name, '') <> '' and coalesce(l.city, '') <> ''
       and lower(o.student_name) = lower(l.student_name) and lower(o.city) = lower(l.city)
    ) d join crm_leads_v v on v.id = d.id limit 5), '[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_earning_rate(p_university bigint, p_programme bigint, p_partner bigint, p_on date)
 RETURNS earning_rates
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r from earning_rates r
   where r.valid_from <= p_on and (r.valid_to is null or r.valid_to >= p_on)
     and ((r.scope = 'programme' and r.programme_id = p_programme)
       or (r.scope = 'partner' and r.partner_id = p_partner)
       or (r.scope = 'university' and r.university_id = p_university and (p_partner is null or r.partner_id is null)))
   order by case r.scope when 'programme' then 1 when 'partner' then 2 else 3 end, r.valid_from desc, r.id desc
   limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.crm_engine_flow(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('segment', segment, 'total', total, 'shares', shares) order by total desc), '[]'::jsonb) from (
    select segment, count(*) total,
           (select jsonb_object_agg(coalesce(x.name, 'In-house team'), x.n) from (select coalesce(p.name, 'In-house team') name, count(*) n from allocations b left join partners p on p.id = b.partner_id where b.segment = a.segment and b.created_at > now() - make_interval(days => p_days) and b.status not in ('duplicate','recalled') group by 1) x) shares
      from allocations a where created_at > now() - make_interval(days => p_days) and status not in ('duplicate','recalled') group by segment) s;
$function$;

CREATE OR REPLACE FUNCTION public.crm_find_lead(p_phone text)
 RETURNS student_leads
 LANGUAGE sql
 STABLE
AS $function$
  select l from student_leads l
   where regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') = p_phone
     and l.deleted_at is null and l.merged_into_id is null
   order by l.created_at desc limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.crm_followup_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s jsonb; v_remind int; v_escalate int; v_heads uuid[]; h uuid; t record; ld record; n_remind int := 0; n_overdue int := 0; n_esc int := 0; n_sla int := 0;
begin
  if auth.uid() is not null then perform crm_require(array['admin']); end if;
  select value into s from crm_settings where key = 'followup';
  v_remind := coalesce((s->>'remind_before_minutes')::int, 10); v_escalate := coalesce((s->>'escalate_after_minutes')::int, 120);
  select array_agg(id) into v_heads from crm_users where is_active and role = 'sales_head';
  if v_heads is null then select array_agg(id) into v_heads from crm_users where is_active and role = 'admin'; end if;
  for t in select tk.id, tk.lead_id, tk.title, tk.assignee_id, tk.due_at, l.student_name from crm_tasks tk join student_leads l on l.id = tk.lead_id
            where tk.done_at is null and tk.reminded_at is null and tk.assignee_id is not null and tk.due_at between now() and now() + make_interval(mins => v_remind) loop
    perform crm_notify(t.assignee_id, 'reminder', 'Due in ' || v_remind || ' min: ' || t.title, coalesce(t.student_name, 'Lead ' || t.lead_id), '/leads/' || t.lead_id, t.lead_id, 0);
    update crm_tasks set reminded_at = now() where id = t.id; n_remind := n_remind + 1;
  end loop;
  for t in select tk.id, tk.lead_id, tk.title, tk.assignee_id, tk.due_at, l.student_name from crm_tasks tk join student_leads l on l.id = tk.lead_id
            where tk.done_at is null and tk.overdue_alerted_at is null and tk.assignee_id is not null and tk.due_at < now() loop
    perform crm_notify(t.assignee_id, 'overdue', 'Overdue: ' || t.title, coalesce(t.student_name, 'Lead ' || t.lead_id) || ' · was due ' || to_char(t.due_at at time zone coalesce(s->>'timezone', 'Asia/Kolkata'), 'DD Mon HH24:MI'), '/leads/' || t.lead_id, t.lead_id, 0);
    update crm_tasks set overdue_alerted_at = now() where id = t.id; n_overdue := n_overdue + 1;
  end loop;
  for t in select tk.id, tk.lead_id, tk.title, tk.assignee_id, tk.due_at, l.student_name, u.full_name as owner_name from crm_tasks tk join student_leads l on l.id = tk.lead_id left join crm_users u on u.id = tk.assignee_id
            where tk.done_at is null and tk.escalated_at is null and tk.due_at < now() - make_interval(mins => v_escalate) loop
    foreach h in array coalesce(v_heads, '{}'::uuid[]) loop
      perform crm_notify(h, 'escalation', 'Task overdue ' || v_escalate || '+ min: ' || t.title, coalesce(t.student_name, 'Lead ' || t.lead_id) || ' · ' || coalesce(t.owner_name, 'unassigned'), '/leads/' || t.lead_id, t.lead_id, 0);
    end loop;
    update crm_tasks set escalated_at = now() where id = t.id; n_esc := n_esc + 1;
  end loop;
  for ld in select l.id, l.student_name, l.owner_user_id, l.temperature, l.assigned_at, u.full_name as owner_name from student_leads l left join crm_users u on u.id = l.owner_user_id
             where l.owner_user_id is not null and l.first_contacted_at is null and l.sla_alerted_at is null and l.deleted_at is null and l.assigned_at is not null
               and l.stage in ('assigned', 'allocated') and l.assigned_at + make_interval(mins => crm_sla_minutes(l.temperature)) < now() loop
    perform crm_notify(ld.owner_user_id, 'sla_breach', 'First-contact SLA missed: ' || coalesce(ld.student_name, 'Lead ' || ld.id), coalesce(ld.temperature, 'lead') || ' · assigned ' || to_char(ld.assigned_at at time zone coalesce(s->>'timezone', 'Asia/Kolkata'), 'DD Mon HH24:MI'), '/leads/' || ld.id, ld.id, 24);
    foreach h in array coalesce(v_heads, '{}'::uuid[]) loop
      if h <> ld.owner_user_id then perform crm_notify(h, 'sla_breach', 'SLA missed by ' || coalesce(ld.owner_name, 'owner') || ': ' || coalesce(ld.student_name, 'Lead ' || ld.id), null, '/leads/' || ld.id, ld.id, 24); end if;
    end loop;
    update student_leads set sla_alerted_at = now() where id = ld.id; n_sla := n_sla + 1;
  end loop;
  return jsonb_build_object('reminders', n_remind, 'overdue', n_overdue, 'escalations', n_esc, 'sla_breaches', n_sla);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_handle_new_auth_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into crm_users (id, email, full_name)
  values (new.id, coalesce(new.email, new.id::text), coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'))
  on conflict (id) do nothing;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_invoice_set_status(p_invoice bigint, p_status text, p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare inv invoices;
begin
  perform crm_require(array['admin','finance']);
  update invoices set status = p_status, sent_at = case when p_status = 'sent' then now() else sent_at end, paid_at = case when p_status = 'paid' then now() else paid_at end
   where id = p_invoice returning * into inv;
  if inv.id is null then raise exception 'invoice % not found', p_invoice; end if;
  if p_status = 'paid' then
    update earnings set status = 'received', received_at = now(), received_inr = (p->>'amount_inr')::numeric, tds_inr = (p->>'tds_inr')::numeric, bank_ref = p->>'bank_ref'
     where invoice_id = p_invoice and status = 'invoiced';
  end if;
  return to_jsonb(inv);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_journey_enroll(p_journey bigint, p_lead bigint, p_reason text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j journeys; l student_leads; v_id bigint;
begin
  if auth.uid() is not null then perform crm_require(array['admin', 'marketing', 'sales_head', 'sales_manager']); end if;
  select * into j from journeys where id = p_journey;
  select * into l from student_leads where id = p_lead;
  if j.id is null or l.id is null then return jsonb_build_object('enrolled', false, 'reason', 'not found'); end if;
  if j.status <> 'active' then return jsonb_build_object('enrolled', false, 'reason', 'journey is ' || j.status); end if;
  if coalesce(l.is_test, false) then return jsonb_build_object('enrolled', false, 'reason', 'test lead'); end if;
  if l.deleted_at is not null or l.merged_into_id is not null then return jsonb_build_object('enrolled', false, 'reason', 'lead deleted or merged'); end if;
  if coalesce(l.is_opted_out, false) then return jsonb_build_object('enrolled', false, 'reason', 'opted out'); end if;
  if l.destination_type = 'partner' then return jsonb_build_object('enrolled', false, 'reason', 'allocated to a partner'); end if;
  if l.is_sales_ready and not coalesce((j.trigger->>'allow_sales_ready')::boolean, false) then return jsonb_build_object('enrolled', false, 'reason', 'already sales-ready'); end if;
  if l.stage = 'lost' and not coalesce((j.trigger->>'allow_lost')::boolean, false) then return jsonb_build_object('enrolled', false, 'reason', 'lead is lost'); end if;
  if l.stage in ('enrolled', 'verified', 'commission_booked', 'paid') then return jsonb_build_object('enrolled', false, 'reason', 'already enrolled'); end if;
  if exists (select 1 from journey_runs where lead_id = p_lead and status in ('active', 'waiting_send')) then return jsonb_build_object('enrolled', false, 'reason', 'already in a journey'); end if;
  insert into journey_runs (journey_id, lead_id, log) values (p_journey, p_lead, jsonb_build_array(jsonb_build_object('at', now(), 'event', 'enrolled', 'reason', p_reason))) returning id into v_id;
  update student_leads set active_journey_id = p_journey where id = p_lead;
  insert into crm_activities (lead_id, kind, content, meta, actor_id, actor_name) values (p_lead, 'system', 'Entered journey "' || j.name || '" (' || p_reason || ')', jsonb_build_object('journey_id', j.id, 'run_id', v_id), auth.uid(), coalesce(crm_me()->>'full_name', 'Journeys'));
  return jsonb_build_object('enrolled', true, 'run_id', v_id);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_journey_enroll_due(p_limit integer DEFAULT 100)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j journeys; v_lead bigint; n int := 0; v_type text; r jsonb;
begin
  if auth.uid() is not null then perform crm_require(array['admin']); end if;
  for j in select * from journeys where status = 'active' and coalesce(trigger->>'type', 'manual') in ('segment', 'source', 'inactive_days') loop
    v_type := j.trigger->>'type';
    for v_lead in
      select x.id from (
        select s.crm_segment_resolve as id from crm_segment_resolve((j.trigger->>'segment_id')::bigint) s where v_type = 'segment'
        union
        select l.id from student_leads l where v_type = 'source' and l.lead_source = any(array(select jsonb_array_elements_text(j.trigger->'sources'))) and l.created_at > now() - interval '30 days' and l.deleted_at is null
        union
        select l.id from student_leads l where v_type = 'inactive_days' and coalesce(l.last_activity_at, l.created_at) < now() - make_interval(days => coalesce((j.trigger->>'days')::int, 7))
           and l.deleted_at is null and l.merged_into_id is null and not coalesce(l.is_test, false) and crm_rules_match(coalesce(j.trigger->'rules', '[]'::jsonb), l.id)
      ) x
      where not exists (select 1 from journey_runs jr where jr.journey_id = j.id and jr.lead_id = x.id)
        and not exists (select 1 from journey_runs jr where jr.lead_id = x.id and jr.status in ('active', 'waiting_send'))
      limit p_limit
    loop
      r := crm_journey_enroll(j.id, v_lead, 'trigger:' || v_type);
      if (r->>'enrolled')::boolean then n := n + 1; end if;
    end loop;
  end loop;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_journey_send_result(p_run bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare run journey_runs; j journeys; v_ok boolean := coalesce((p->>'ok')::boolean, false);
begin
  if auth.uid() is not null then perform crm_require(array['admin']); end if;
  select * into run from journey_runs where id = p_run;
  if run.id is null then return jsonb_build_object('error', 'run not found'); end if;
  select * into j from journeys where id = run.journey_id;
  if v_ok then
    insert into crm_activities (lead_id, kind, content, meta, actor_name)
    values (run.lead_id, coalesce(p->>'channel', 'email'), left(coalesce(p->>'content', j.name), 2000), jsonb_build_object('marketing', true, 'journey_id', j.id, 'journey', j.name, 'run_id', run.id, 'message_id', p->>'message_id', 'dry_run', coalesce((p->>'dry_run')::boolean, false)), 'Journey');
    update student_leads set last_marketing_message_at = now() where id = run.lead_id;
  end if;
  update journey_runs set status = 'active', step_index = run.step_index + 1, next_at = now(), last_send_at = case when v_ok then now() else last_send_at end, updated_at = now(),
         log = log || jsonb_build_object('at', now(), 'step', run.step_index, 'type', 'send', 'ok', v_ok, 'error', p->>'error', 'dry_run', coalesce((p->>'dry_run')::boolean, false))
   where id = run.id;
  return jsonb_build_object('status', case when v_ok then 'sent' else 'failed' end);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_journey_set_status(p_id bigint, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r journeys;
begin
  perform crm_require(array['admin', 'marketing', 'sales_head']);
  if p_status not in ('draft', 'active', 'paused') then raise exception 'bad status'; end if;
  update journeys set status = p_status, updated_at = now() where id = p_id returning * into r;
  insert into crm_alerts (kind, message) values ('journey_status', 'Journey "' || r.name || '" set to ' || p_status || ' by ' || coalesce(crm_me()->>'email', 'admin'));
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_journey_tick(p_limit integer DEFAULT 50, p_base_url text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare run journey_runs; j journeys; l student_leads; v_phone text; v_exit text; v_i int; v_guard int; step jsonb; v_type text; v_next timestamptz; tpl message_templates; g jsonb; job jsonb; jobs jsonb := '[]'::jsonb;
        v_tz text; v_loops int; v_log jsonb;
begin
  if auth.uid() is not null then perform crm_require(array['admin']); end if;
  select coalesce(value->>'timezone', 'Asia/Kolkata') into v_tz from crm_settings where key = 'marketing';
  update journey_runs set status = 'active', next_at = now(), updated_at = now(), log = log || jsonb_build_object('at', now(), 'event', 'send_retry') where status = 'waiting_send' and updated_at < now() - interval '30 minutes';
  for run in select * from journey_runs where status = 'active' and next_at <= now() order by next_at, id limit p_limit for update skip locked loop
    select * into j from journeys where id = run.journey_id;
    select * into l from student_leads where id = run.lead_id;
    v_log := run.log;
    if j.status <> 'active' then update journey_runs set next_at = now() + interval '1 hour', updated_at = now() where id = run.id; continue; end if;
    v_phone := regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g');
    v_exit := case when l.id is null or l.deleted_at is not null or l.merged_into_id is not null then 'deleted'
                   when coalesce(l.is_opted_out, false) then 'opted_out'
                   when l.destination_type = 'partner' then 'partner'
                   when l.stage in ('enrolled', 'verified', 'commission_booked', 'paid') then 'enrolled'
                   when l.stage = 'lost' and not coalesce((j.trigger->>'allow_lost')::boolean, false) then 'lost'
                   when l.is_sales_ready and not coalesce((j.trigger->>'allow_sales_ready')::boolean, false) then 'sales_ready'
                   when exists (select 1 from w2_messages m where m.phone = v_phone and m.direction = 'in' and m.created_at > coalesce(run.last_send_at, run.started_at)) then 'replied'
                   when exists (select 1 from crm_activities a where a.lead_id = l.id and a.kind in ('whatsapp', 'email', 'call') and a.outcome in ('replied', 'connected') and a.created_at > run.started_at) then 'replied'
                   else null end;
    if v_exit is not null then
      update journey_runs set status = 'exited', exit_reason = v_exit, finished_at = now(), updated_at = now(), log = v_log || jsonb_build_object('at', now(), 'event', 'exit', 'reason', v_exit) where id = run.id;
      update student_leads set active_journey_id = null where id = l.id and active_journey_id = j.id;
      continue;
    end if;
    v_i := run.step_index; v_guard := 0;
    loop
      v_guard := v_guard + 1;
      if v_guard > 25 then update journey_runs set status = 'exited', exit_reason = 'step_loop', finished_at = now(), updated_at = now(), log = v_log where id = run.id; exit; end if;
      step := j.steps -> v_i;
      if step is null then
        update journey_runs set status = 'done', finished_at = now(), step_index = v_i, updated_at = now(), log = v_log || jsonb_build_object('at', now(), 'event', 'done') where id = run.id;
        update student_leads set active_journey_id = null where id = l.id and active_journey_id = j.id;
        exit;
      end if;
      v_type := lower(coalesce(step->>'type', ''));
      if v_type = 'wait' then
        if step ? 'until_hour' then
          v_next := (date_trunc('day', now() at time zone v_tz) + make_interval(hours => (step->>'until_hour')::int)) at time zone v_tz;
          if v_next <= now() then v_next := v_next + interval '1 day'; end if;
        else
          v_next := now() + (coalesce((step->>'hours')::numeric, 0) * interval '1 hour') + (coalesce((step->>'days')::numeric, 0) * interval '1 day');
          if v_next <= now() then v_next := now() + interval '1 hour'; end if;
        end if;
        update journey_runs set step_index = v_i + 1, next_at = v_next, updated_at = now(), log = v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'wait', 'until', v_next) where id = run.id;
        exit;
      elsif v_type = 'task' then
        insert into crm_tasks (lead_id, title, kind, due_at, assignee_id) values (l.id, coalesce(step->>'title', 'Follow up (journey)'), 'journey', now() + (coalesce((step->>'due_hours')::numeric, 24) * interval '1 hour'), l.owner_user_id);
        update student_leads set next_task_due_at = (select min(due_at) from crm_tasks where lead_id = l.id and done_at is null) where id = l.id;
        v_log := v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'task'); v_i := v_i + 1;
      elsif v_type = 'update' then
        perform lead_intake(jsonb_build_object('source_system', 'crm', 'event_type', 'journey.update', 'phone', l.whatsapp_number, 'lead', coalesce(step->'fields', '{}'::jsonb)));
        v_log := v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'update'); v_i := v_i + 1;
      elsif v_type = 'mark_sales_ready' then
        update student_leads set is_sales_ready = true, sales_ready_at = coalesce(sales_ready_at, now()), last_activity_at = now() where id = l.id and not is_sales_ready;
        update journey_runs set status = 'exited', exit_reason = 'sales_ready', finished_at = now(), step_index = v_i, updated_at = now(), log = v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'mark_sales_ready') where id = run.id;
        update student_leads set active_journey_id = null where id = l.id and active_journey_id = j.id;
        exit;
      elsif v_type = 'branch' then
        if crm_rules_match(coalesce(step->'rules', '[]'::jsonb), l.id) then v_i := coalesce((step->>'then')::int, v_i + 1); else v_i := coalesce((step->>'else')::int, v_i + 1); end if;
        v_log := v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'branch');
      elsif v_type = 'goto' then
        select count(*) into v_loops from jsonb_array_elements(v_log) e where e->>'type' = 'goto';
        if v_loops >= coalesce((step->>'max_loops')::int, 12) then
          update journey_runs set status = 'done', finished_at = now(), step_index = v_i, updated_at = now(), log = v_log || jsonb_build_object('at', now(), 'event', 'done', 'reason', 'max_loops') where id = run.id;
          update student_leads set active_journey_id = null where id = l.id and active_journey_id = j.id;
          exit;
        end if;
        v_log := v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'goto'); v_i := coalesce((step->>'index')::int, 0);
      elsif v_type = 'exit' then
        update journey_runs set status = 'exited', exit_reason = coalesce(step->>'reason', 'exit'), finished_at = now(), step_index = v_i, updated_at = now(), log = v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'exit') where id = run.id;
        update student_leads set active_journey_id = null where id = l.id and active_journey_id = j.id;
        exit;
      elsif v_type = 'send' then
        select * into tpl from message_templates where active and (id = (step->>'template_id')::bigint or (step->>'template_name' is not null and name = step->>'template_name')) order by (id = (step->>'template_id')::bigint) desc limit 1;
        if tpl.id is null then
          v_log := v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'send', 'skipped', 'template missing'); v_i := v_i + 1; continue;
        end if;
        g := crm_marketing_allowed(l.id, tpl.channel);
        if not (g->>'ok')::boolean then
          if g ? 'defer_until' then
            update journey_runs set step_index = v_i, next_at = (g->>'defer_until')::timestamptz, updated_at = now(), log = v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'send', 'deferred', g->>'reason') where id = run.id;
            exit;
          end if;
          v_log := v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'send', 'skipped', g->>'reason'); v_i := v_i + 1; continue;
        end if;
        begin
          job := crm_send_job(l.id, tpl.id, p_base_url, jsonb_build_object('journey_name', j.name)) || jsonb_build_object('run_id', run.id, 'journey_id', j.id, 'step', v_i);
        exception when others then
          v_log := v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', 'send', 'error', sqlerrm); v_i := v_i + 1; continue;
        end;
        update journey_runs set status = 'waiting_send', step_index = v_i, updated_at = now(), log = v_log where id = run.id;
        jobs := jobs || job;
        exit;
      else
        v_log := v_log || jsonb_build_object('at', now(), 'step', v_i, 'type', v_type, 'skipped', 'unknown step'); v_i := v_i + 1;
      end if;
    end loop;
  end loop;
  return jobs;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_marketing_allowed(p_lead bigint, p_channel text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l student_leads; s jsonb; v_phone text; v_tz text; v_local timestamp; v_hour int; v_qs int; v_qe int; v_next timestamptz; n int; cv w2_conversations;
begin
  select * into l from student_leads where id = p_lead;
  if l.id is null then return jsonb_build_object('ok', false, 'reason', 'lead not found'); end if;
  select value into s from crm_settings where key = 'marketing';
  v_tz := coalesce(s->>'timezone', 'Asia/Kolkata'); v_qs := coalesce((s->>'quiet_start_hour')::int, 9); v_qe := coalesce((s->>'quiet_end_hour')::int, 20);
  if l.deleted_at is not null or l.merged_into_id is not null then return jsonb_build_object('ok', false, 'reason', 'lead deleted or merged'); end if;
  if coalesce(l.is_test, false) then return jsonb_build_object('ok', false, 'reason', 'test lead'); end if;
  if coalesce(l.is_opted_out, false) then return jsonb_build_object('ok', false, 'reason', 'opted out'); end if;
  if l.opted_out_channels is not null and p_channel = any(l.opted_out_channels) then return jsonb_build_object('ok', false, 'reason', 'opted out of ' || p_channel); end if;
  if l.destination_type = 'partner' then return jsonb_build_object('ok', false, 'reason', 'allocated to a partner'); end if;
  if l.stage in ('enrolled', 'verified', 'commission_booked', 'paid') then return jsonb_build_object('ok', false, 'reason', 'already enrolled'); end if;
  v_phone := regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g');
  if p_channel = 'email' then
    if coalesce(l.email_id, '') = '' then return jsonb_build_object('ok', false, 'reason', 'no email'); end if;
    if l.email_bounced_at is not null then return jsonb_build_object('ok', false, 'reason', 'email bounced'); end if;
    select count(*) into n from crm_activities where lead_id = p_lead and kind = 'email' and coalesce((meta->>'marketing')::boolean, false) and created_at > now() - interval '1 day';
    if n >= coalesce((s->>'email_per_day')::int, 2) then return jsonb_build_object('ok', false, 'defer_until', now() + interval '1 day', 'reason', 'email daily limit'); end if;
  else
    if v_phone = '' then return jsonb_build_object('ok', false, 'reason', 'no phone'); end if;
    select * into cv from w2_conversations where phone = v_phone;
    if coalesce(cv.opted_out, false) then return jsonb_build_object('ok', false, 'reason', 'opted out (WhatsApp)'); end if;
    if exists (select 1 from w2_messages where phone = v_phone and created_at > now() - make_interval(mins => coalesce((s->>'active_chat_minutes')::int, 30))) then
      return jsonb_build_object('ok', false, 'defer_until', now() + make_interval(mins => coalesce((s->>'active_chat_minutes')::int, 30)), 'reason', 'active chat');
    end if;
    select count(*) into n from crm_activities where lead_id = p_lead and kind = 'whatsapp' and coalesce((meta->>'marketing')::boolean, false) and created_at > now() - interval '30 days';
    if n >= coalesce((s->>'wa_per_30d')::int, 6) then return jsonb_build_object('ok', false, 'reason', 'WhatsApp monthly limit'); end if;
    select count(*) into n from crm_activities where lead_id = p_lead and kind = 'whatsapp' and coalesce((meta->>'marketing')::boolean, false) and created_at > now() - interval '1 day';
    if n >= coalesce((s->>'wa_per_day')::int, 1) then return jsonb_build_object('ok', false, 'defer_until', now() + interval '1 day', 'reason', 'WhatsApp daily limit'); end if;
  end if;
  v_local := now() at time zone v_tz; v_hour := extract(hour from v_local);
  if v_hour < v_qs or v_hour >= v_qe then
    v_next := (date_trunc('day', v_local) + make_interval(hours => v_qs) + case when v_hour >= v_qe then interval '1 day' else interval '0' end) at time zone v_tz;
    return jsonb_build_object('ok', false, 'defer_until', v_next, 'reason', 'quiet hours');
  end if;
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_marketing_stats()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'journeys', coalesce((select jsonb_object_agg(journey_id::text, s) from (
        select journey_id, jsonb_build_object('active', count(*) filter (where status in ('active', 'waiting_send')), 'done', count(*) filter (where status = 'done'), 'exited', count(*) filter (where status = 'exited'),
               'sales_ready', count(*) filter (where exit_reason = 'sales_ready'), 'replied', count(*) filter (where exit_reason = 'replied'), 'total', count(*)) s
          from journey_runs group by journey_id) x), '{}'::jsonb),
    'campaigns', coalesce((select jsonb_object_agg(campaign_id::text, s) from (
        select campaign_id, jsonb_build_object('queued', count(*) filter (where status = 'queued'), 'sent', count(*) filter (where status = 'sent'), 'failed', count(*) filter (where status = 'failed'), 'skipped', count(*) filter (where status = 'skipped')) s
          from campaign_sends group by campaign_id) x), '{}'::jsonb));
$function$;

CREATE OR REPLACE FUNCTION public.crm_mask_email(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p is null or position('@' in p) < 2 then p else left(p, 2) || '***' || substr(p, position('@' in p)) end;
$function$;

CREATE OR REPLACE FUNCTION public.crm_mask_phone(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p is null or length(p) < 6 then p else left(p, 4) || repeat('*', greatest(length(p) - 6, 1)) || right(p, 2) end;
$function$;

CREATE OR REPLACE FUNCTION public.crm_masks()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(crm_role(), 'viewer') in ('marketing', 'finance', 'viewer');
$function$;

CREATE OR REPLACE FUNCTION public.crm_me()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select to_jsonb(u) - 'phone' from crm_users u where u.id = auth.uid();
$function$;

CREATE OR REPLACE FUNCTION public.crm_merge_leads(p_keep bigint, p_merge bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k student_leads; m student_leads; col text; n int := 0;
begin
  perform crm_require(array['admin', 'sales_head']);
  if p_keep = p_merge then raise exception 'pick two different leads'; end if;
  select * into k from student_leads where id = p_keep and deleted_at is null and merged_into_id is null;
  select * into m from student_leads where id = p_merge and deleted_at is null and merged_into_id is null;
  if k.id is null or m.id is null then raise exception 'lead not found or already merged'; end if;
  for col in select column_name from information_schema.columns where table_schema = 'public' and table_name = 'student_leads'
              and column_name not in ('id', 'created_at', 'updated_at', 'updated_by', 'whatsapp_number', 'stage', 'sub_stage', 'stage_changed_at', 'owner_user_id', 'team_id', 'assigned_at',
                                      'is_test', 'deleted_at', 'merged_into_id', 'cycle_no', 'lead_score', 'score_updated_at', 'temperature', 'is_sales_ready', 'sales_ready_at', 'destination_type', 'partner_id',
                                      'allocation_id', 'allocated_at', 'allocation_reason', 'contact_attempts', 'next_task_due_at', 'custom_fields', 'active_journey_id', 'is_duplicate_suspect', 'sla_alerted_at') loop
    execute format('update student_leads k set %I = coalesce(k.%I, m.%I) from student_leads m where k.id = %s and m.id = %s', col, col, col, p_keep, p_merge);
  end loop;
  update student_leads set custom_fields = coalesce(m.custom_fields, '{}'::jsonb) || coalesce(custom_fields, '{}'::jsonb), contact_attempts = coalesce(contact_attempts, 0) + coalesce(m.contact_attempts, 0) where id = p_keep;
  update crm_activities set lead_id = p_keep where lead_id = p_merge; get diagnostics n = row_count;
  update crm_tasks set lead_id = p_keep where lead_id = p_merge;
  update calls set lead_id = p_keep where lead_id = p_merge;
  update touchpoints set lead_id = p_keep where lead_id = p_merge;
  update engine_decisions set lead_id = p_keep where lead_id = p_merge;
  update enrollments set lead_id = p_keep where lead_id = p_merge and not exists (select 1 from enrollments e2 where e2.lead_id = p_keep and e2.cycle_no = enrollments.cycle_no and e2.status in ('reported', 'verified'));
  if exists (select 1 from allocations where lead_id = p_keep and status in ('pending', 'pushing', 'pushed', 'assigned')) then
    update allocations set status = 'recalled', reason = 'merged into lead ' || p_keep, updated_at = now() where lead_id = p_merge and status in ('pending', 'pushing', 'pushed', 'assigned');
  end if;
  update allocations set lead_id = p_keep where lead_id = p_merge;
  if to_regclass('public.journey_runs') is not null then
    update journey_runs set status = 'exited', exit_reason = 'merged', finished_at = now() where lead_id = p_merge and status in ('active', 'waiting_send');
    update journey_runs set lead_id = p_keep where lead_id = p_merge;
  end if;
  if to_regclass('public.campaign_sends') is not null then
    update campaign_sends cs set lead_id = p_keep where lead_id = p_merge and not exists (select 1 from campaign_sends c2 where c2.campaign_id = cs.campaign_id and c2.lead_id = p_keep);
    delete from campaign_sends where lead_id = p_merge;
  end if;
  update student_leads set merged_into_id = p_keep, deleted_at = now(), is_duplicate_suspect = false, updated_by = coalesce(crm_me()->>'email', 'crm') where id = p_merge;
  update student_leads set is_duplicate_suspect = false, last_activity_at = now() where id = p_keep;
  insert into crm_activities (lead_id, kind, content, meta, actor_id, actor_name)
  values (p_keep, 'system', 'Merged lead #' || p_merge || ' (' || coalesce(m.student_name, '?') || ', ' || coalesce(m.whatsapp_number, '?') || ') into this lead', jsonb_build_object('merged_id', p_merge, 'activities_moved', n), auth.uid(), crm_me()->>'full_name');
  return jsonb_build_object('kept', p_keep, 'merged', p_merge, 'activities_moved', n);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_money_reader()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(crm_role(), '') in ('admin','finance','sales_head','revenue','viewer','marketing');
$function$;

CREATE OR REPLACE FUNCTION public.crm_money_setting(p_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select value->p_key from crm_settings where key = 'money';
$function$;

CREATE OR REPLACE FUNCTION public.crm_money_summary(p_period text DEFAULT to_char(now(), 'YYYY-MM'::text))
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role text := crm_role(); v_uid uuid := auth.uid(); v_mgr jsonb; v_mgmt jsonb; v_hist jsonb; v_uni jsonb; v_by_mgr jsonb; v_recv jsonb; v_pay jsonb; v_tier jsonb; v_enr jsonb;
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  select jsonb_build_object(
    'tiles', (select jsonb_build_object('provisional', coalesce(sum(amount_inr) filter (where status = 'provisional'), 0), 'confirmed', coalesce(sum(amount_inr) filter (where status = 'confirmed'), 0),
                                        'payable', coalesce(sum(amount_inr) filter (where status = 'payable'), 0), 'paid', coalesce(sum(amount_inr) filter (where status = 'paid'), 0))
                from payouts where user_id = v_uid and period = p_period),
    'by_university', (select coalesce(jsonb_agg(jsonb_build_object('university', u.university_name, 'enrollments', u.n, 'fees', u.fees, 'payout', u.payout, 'rate', u.rate)), '[]'::jsonb)
                        from (select e.university_name, count(*) n, sum(e.fee_amount_inr) fees, sum(p.amount_inr) payout, max(p.rate_snapshot->>'value') rate
                                from payouts p join enrollments e on e.id = p.enrollment_id where p.user_id = v_uid and p.period = p_period and p.status <> 'clawback' group by e.university_name) u),
    'enrollments', (select coalesce(jsonb_agg(jsonb_build_object('enrollment_id', e.id, 'lead_id', e.lead_id, 'student', l.student_name, 'programme', e.programme_name, 'university', e.university_name,
                                   'enrolled_on', e.enrolled_on, 'status', e.status, 'payout', p.amount_inr, 'payout_status', p.status, 'payable_on', p.payable_on) order by e.enrolled_on desc), '[]'::jsonb)
                      from enrollments e join student_leads l on l.id = e.lead_id left join payouts p on p.enrollment_id = e.id and not p.is_clawback
                     where e.owner_user_id = v_uid and to_char(e.enrolled_on, 'YYYY-MM') = p_period),
    'accelerator', (select jsonb_build_object('count', (select count(*) from payouts where user_id = v_uid and period = p_period and not is_clawback and status <> 'clawback'),
                                              'next_threshold', (select min((a->>'from_count')::int) from payout_rates r, jsonb_array_elements(coalesce(r.accelerators, '[]'::jsonb)) a
                                                                   where (r.scope = 'user' and r.user_id = v_uid or r.scope <> 'user') and r.valid_to is null
                                                                     and (a->>'from_count')::int > (select count(*) from payouts where user_id = v_uid and period = p_period and not is_clawback)))),
    'clawbacks', (select coalesce(jsonb_agg(jsonb_build_object('enrollment_id', enrollment_id, 'amount', amount_inr, 'note', note, 'at', created_at)), '[]'::jsonb) from payouts where user_id = v_uid and (is_clawback or status = 'clawback') and created_at > now() - interval '12 months'),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('period', period, 'paid', paid, 'confirmed', confirmed) order by period), '[]'::jsonb)
                  from (select period, sum(amount_inr) filter (where status = 'paid') paid, sum(amount_inr) filter (where status in ('confirmed','payable')) confirmed
                          from payouts where user_id = v_uid and period >= to_char(now() - interval '12 months', 'YYYY-MM') group by period) h))
  into v_mgr;
  if v_role = 'sales_manager' then return jsonb_build_object('lens', 'manager', 'period', p_period, 'manager', v_mgr); end if;
  select coalesce(jsonb_agg(jsonb_build_object('period', period, 'gross', gross, 'gst', gst, 'net', net, 'realised_net', realised, 'expected_net', expected) order by period), '[]'::jsonb) into v_hist
    from (select period, sum(gross_inr) gross, sum(gst_inr) gst, sum(net_inr) net, sum(net_inr) filter (where status in ('realised','invoiced','received')) realised, sum(net_inr) filter (where status = 'expected') expected
            from earnings where period >= to_char(now() - interval '12 months', 'YYYY-MM') group by period) h;
  select coalesce(jsonb_agg(jsonb_build_object('university', university_name, 'enrollments', n, 'fees', fees, 'earning_net', earning, 'payouts', payouts, 'margin', earning - payouts,
                                               'margin_pct', case when earning > 0 then round((earning - payouts) * 100 / earning, 1) end, 'rate', rate) order by earning desc nulls last), '[]'::jsonb) into v_uni
    from (select e.university_name, count(*) n, sum(e.fee_amount_inr) fees, sum(ge.s) earning, sum(pp.s) payouts,
                 (select coalesce(r.value::text, r.rate_type) from earning_rates r where r.university_id = e.university_id and r.valid_to is null order by r.valid_from desc limit 1) rate
            from enrollments e
            left join lateral (select coalesce(sum(net_inr), 0) s from earnings g where g.enrollment_id = e.id and g.status <> 'reversed') ge on true
            left join lateral (select coalesce(sum(amount_inr), 0) s from payouts p where p.enrollment_id = e.id and p.status in ('confirmed','payable','paid')) pp on true
           where to_char(e.enrolled_on, 'YYYY-MM') = p_period and e.status in ('reported','verified') group by e.university_id, e.university_name) u;
  select coalesce(jsonb_agg(jsonb_build_object('user', coalesce(u.full_name, u.email), 'enrollments', m.n, 'earning_net', m.earning, 'payout', m.payout, 'margin', m.earning - m.payout) order by m.earning desc), '[]'::jsonb) into v_by_mgr
    from (select e.owner_user_id, count(*) n, sum(ge.s) earning, sum(pp.s) payout
            from enrollments e
            left join lateral (select coalesce(sum(net_inr), 0) s from earnings g where g.enrollment_id = e.id and g.status <> 'reversed') ge on true
            left join lateral (select coalesce(sum(amount_inr), 0) s from payouts p where p.enrollment_id = e.id and p.status in ('confirmed','payable','paid')) pp on true
           where to_char(e.enrolled_on, 'YYYY-MM') = p_period and e.status in ('reported','verified') and e.owner_user_id is not null group by e.owner_user_id) m
    join crm_users u on u.id = m.owner_user_id;
  select jsonb_build_object('uninvoiced', coalesce(sum(net_inr) filter (where status = 'realised'), 0), 'invoiced', coalesce(sum(net_inr) filter (where status = 'invoiced'), 0),
                            'ageing', jsonb_build_object('0_30', coalesce(sum(net_inr) filter (where status in ('realised','invoiced') and age <= 30), 0), '31_60', coalesce(sum(net_inr) filter (where status in ('realised','invoiced') and age between 31 and 60), 0),
                                                         '61_90', coalesce(sum(net_inr) filter (where status in ('realised','invoiced') and age between 61 and 90), 0), '90_plus', coalesce(sum(net_inr) filter (where status in ('realised','invoiced') and age > 90), 0)))
    into v_recv from (select g.*, (current_date - e.verified_at::date) age from earnings g join enrollments e on e.id = g.enrollment_id where g.reverses_id is null) x;
  select jsonb_build_object('confirmed', coalesce(sum(amount_inr) filter (where status = 'confirmed'), 0), 'payable', coalesce(sum(amount_inr) filter (where status = 'payable'), 0),
                            'paid_this_period', coalesce(sum(amount_inr) filter (where status = 'paid' and period = p_period), 0), 'held', coalesce(sum(amount_inr) filter (where status = 'held'), 0),
                            'clawbacks_pending', coalesce(sum(amount_inr) filter (where is_clawback and status = 'payable'), 0))
    into v_pay from payouts;
  select coalesce(jsonb_agg(jsonb_build_object('university', cu.name, 'tiers', r.tiers, 'conversion', crm_conversion(p_period, r.university_id), 'current_pct', crm_tier_pct(r.tiers, crm_conversion(p_period, r.university_id)))), '[]'::jsonb) into v_tier
    from earning_rates r left join catalog_universities cu on cu.id = r.university_id where r.rate_type = 'tiered' and r.valid_to is null;
  select jsonb_build_object('pending_verification', count(*) filter (where status = 'reported'), 'verified', count(*) filter (where status = 'verified'), 'refunded', count(*) filter (where status in ('refunded','cancelled')))
    into v_enr from enrollments where to_char(enrolled_on, 'YYYY-MM') = p_period;
  v_mgmt := jsonb_build_object('earnings_by_month', v_hist, 'by_university', v_uni, 'by_manager', v_by_mgr, 'receivables', v_recv, 'payables', v_pay, 'tier_watch', v_tier, 'enrollments', v_enr, 'conversion', crm_conversion(p_period));
  return jsonb_build_object('lens', 'management', 'period', p_period, 'management', v_mgmt, 'manager', v_mgr);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_my_notifications(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'unread', (select count(*) from crm_notifications where user_id = auth.uid() and read_at is null),
    'items', coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc) from (select * from crm_notifications where user_id = auth.uid() order by created_at desc limit p_limit) n), '[]'::jsonb));
$function$;

CREATE OR REPLACE FUNCTION public.crm_new_lead(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform crm_require(array['admin','sales_head','sales_manager','marketing']);
  r := lead_intake(jsonb_build_object('source_system', coalesce(p->>'source_system', 'manual'), 'event_type', 'lead.created',
                                      'idempotency_key', p->>'idempotency_key', 'phone', p->>'phone', 'lead', coalesce(p->'lead', '{}'::jsonb),
                                      'attribution', coalesce(p->'attribution', '{}'::jsonb)));
  insert into crm_activities (lead_id, kind, content, meta, actor_id, actor_name)
  values ((r->>'lead_id')::bigint, 'system', 'Lead ' || (r->>'action') || ' by ' || coalesce(p->>'source_system', 'manual'), p - 'lead', auth.uid(), crm_me()->>'full_name');
  if coalesce((p->>'assign_to_me')::boolean, false) then r := r || jsonb_build_object('assignment', crm_assign_lead((r->>'lead_id')::bigint, auth.uid())); end if;
  return r;
end $function$;

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
$function$;

CREATE OR REPLACE FUNCTION public.crm_notifications_emailed(p_ids bigint[])
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with u as (update crm_notifications set emailed_at = now() where id = any(p_ids) returning 1) select count(*)::int from u;
$function$;

CREATE OR REPLACE FUNCTION public.crm_notifications_read()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update crm_notifications set read_at = now() where user_id = auth.uid() and read_at is null;
$function$;

CREATE OR REPLACE FUNCTION public.crm_notify(p_user uuid, p_kind text, p_title text, p_body text DEFAULT NULL::text, p_link text DEFAULT NULL::text, p_lead bigint DEFAULT NULL::bigint, p_dedupe_hours integer DEFAULT 24)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint;
begin
  if p_user is null then return null; end if;
  if p_dedupe_hours > 0 and exists (select 1 from crm_notifications where user_id = p_user and kind = p_kind and coalesce(lead_id, 0) = coalesce(p_lead, 0) and created_at > now() - make_interval(hours => p_dedupe_hours)) then return null; end if;
  insert into crm_notifications (user_id, kind, title, body, link, lead_id) values (p_user, p_kind, p_title, p_body, p_link, p_lead) returning id into v_id;
  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_num(p text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p ~ ('^\s*\d+(\.\d+)?\s*' || chr(36)) then trim(p)::numeric else null end;
$function$;

CREATE OR REPLACE FUNCTION public.crm_partner_duplicate(p_allocation bigint, p_record_id text, p_record_created timestamp with time zone, p_via text DEFAULT 'api'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a allocations; pt partners; l student_leads; r jsonb; v_hours int;
begin
  select * into a from allocations where id = p_allocation;
  select * into pt from partners where id = a.partner_id;
  v_hours := coalesce((pt.sla->>'duplicate_hours')::int, 24);
  if a.pushed_at is not null and a.pushed_at < now() - make_interval(hours => v_hours) then
    return jsonb_build_object('accepted', false, 'reason', 'duplicate claims are accepted within ' || v_hours || ' hours of the push');
  end if;
  update allocations set status = 'duplicate', duplicate_claim = jsonb_build_object('record_id', p_record_id, 'record_created_at', p_record_created, 'via', p_via, 'at', now()), updated_at = now() where id = a.id;
  update student_leads set duplicate_claim_count = coalesce(duplicate_claim_count, 0) + 1, destination_type = null, partner_id = null, allocation_id = null, stage = case when stage = 'sent_to_partner' then 'qualifying' else stage end where id = a.lead_id returning * into l;
  insert into crm_activities (lead_id, kind, content, meta, actor_name) values (a.lead_id, 'system', 'Partner ' || pt.name || ' reported a duplicate (their record ' || coalesce(p_record_id, '?') || ')', jsonb_build_object('allocation_id', a.id), 'Partner sync');
  if l.duplicate_claim_count >= 2 then
    r := crm_assign_lead(a.lead_id);
    if coalesce((r->>'assigned')::boolean, false) then
      insert into allocations (lead_id, segment, destination_type, user_id, status, pushed_at, reason, reference) values (a.lead_id, a.segment, 'in_house', (r->>'user_id')::uuid, 'assigned', now(), 'second duplicate: in-house', null);
      update allocations set reference = 'EDW-' || id where lead_id = a.lead_id and reference is null;
    end if;
    return jsonb_build_object('accepted', true, 'next', 'in_house', 'assignment', r);
  end if;
  r := crm_allocate_lead(a.lead_id, array[a.partner_id], 'after duplicate at ' || pt.name);
  if not coalesce((r->>'allocated')::boolean, false) then r := r || jsonb_build_object('fallback', crm_assign_lead(a.lead_id)); end if;
  return jsonb_build_object('accepted', true, 'next', r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_partner_event(p_partner bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a allocations; ev partner_events; prof partner_mapping_profiles; m jsonb; v_stage text; v_sub text; v_reason text; v_reopen boolean := false; v_type text := lower(coalesce(p->>'type', ''));
        v_fields jsonb := '{}'::jsonb; r jsonb; pt partners;
begin
  select * into pt from partners where id = p_partner;
  if pt.id is null then raise exception 'partner % not found', p_partner; end if;
  select * into a from allocations where partner_id = p_partner and reference = p->>'reference' limit 1;
  if a.id is null and p->>'record_id' is not null then select * into a from allocations where partner_id = p_partner and partner_record_id = p->>'record_id' order by id desc limit 1; end if;
  if a.id is null and p->>'phone' is not null then
    select al.* into a from allocations al join student_leads l on l.id = al.lead_id where al.partner_id = p_partner and regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g') = crm_norm_phone(p->>'phone') order by al.id desc limit 1;
  end if;
  insert into partner_events (partner_id, allocation_id, event_id, event_type, raw) values (p_partner, a.id, coalesce(p->>'event_id', md5(p::text)), v_type, p)
  on conflict (partner_id, event_id) do nothing returning * into ev;
  if ev.id is null then return jsonb_build_object('accepted', true, 'duplicate_event', true); end if;
  if a.id is null then
    update partner_events set error = 'no allocation found for this partner and reference/record/phone' where id = ev.id;
    return jsonb_build_object('accepted', false, 'reason', 'unknown lead for this partner');
  end if;
  update allocations set last_event_at = now(), partner_record_id = coalesce(p->>'record_id', partner_record_id), partner_stage_raw = coalesce(p->>'partner_stage', partner_stage_raw), partner_sub_stage_raw = coalesce(p->>'partner_sub_stage', partner_sub_stage_raw), updated_at = now() where id = a.id;
  update student_leads set partner_stage_raw = coalesce(p->>'partner_stage', partner_stage_raw), partner_sub_stage_raw = coalesce(p->>'partner_sub_stage', partner_sub_stage_raw), partner_synced_at = now(), partner_record_id = coalesce(p->>'record_id', partner_record_id) where id = a.lead_id;
  if v_type = 'duplicate' then
    r := crm_partner_duplicate(a.id, p->>'record_id', (p->>'record_created_at')::timestamptz, 'api');
    update partner_events set processed = true, mapped = r where id = ev.id;
    return r;
  end if;
  select * into prof from partner_mapping_profiles where partner_id = p_partner and is_active order by version desc limit 1;
  if prof.id is not null and p->>'partner_stage' is not null then
    select x into m from jsonb_array_elements(prof.status_map) x
     where lower(x->>'partner_stage') = lower(p->>'partner_stage') and (coalesce(x->>'partner_sub', '*') = '*' or lower(x->>'partner_sub') = lower(coalesce(p->>'partner_sub_stage', '')))
     order by case when coalesce(x->>'partner_sub', '*') = '*' then 1 else 0 end limit 1;
    if m is null then
      update partner_events set error = 'unmapped partner status: ' || (p->>'partner_stage') || coalesce(' / ' || (p->>'partner_sub_stage'), '') where id = ev.id;
      insert into crm_alerts (kind, partner_id, lead_id, message) values ('unmapped_status', p_partner, a.lead_id, pt.name || ' sent an unmapped status "' || (p->>'partner_stage') || coalesce(' / ' || (p->>'partner_sub_stage'), '') || '" for ' || a.reference);
      return jsonb_build_object('accepted', true, 'mapped', false);
    end if;
    v_stage := m->>'stage'; v_sub := m->>'sub_stage'; v_reason := coalesce(m->>'lost_reason', p->>'reason'); v_reopen := coalesce((m->>'reopen')::boolean, false);
  else
    v_stage := case v_type when 'contact_attempted' then 'contacted' when 'contact_connected' then 'contacted' when 'counselled' then 'counselled' when 'applied' then 'applied'
                           when 'enrolled' then 'enrolled' when 'lost' then 'lost' when 'refund' then null else null end;
    v_sub := case v_type when 'contact_attempted' then 'no answer' when 'contact_connected' then 'connected, interested' else null end;
    v_reason := p->>'reason';
  end if;
  if prof.id is not null and v_reason is not null and prof.value_maps ? 'lost_reason' then v_reason := coalesce(prof.value_maps->'lost_reason'->>v_reason, v_reason); end if;
  if v_type in ('contact_attempted','contact_connected','counselled') or v_stage in ('contacted','counselled') then
    update allocations set first_contact_at = coalesce(first_contact_at, now()) where id = a.id;
  end if;
  if v_type = 'refund' then
    r := (select crm_refund_enrollment(e.id, coalesce(p->>'reason', 'partner reported refund')) from enrollments e where e.lead_id = a.lead_id and e.status in ('reported','verified') order by e.id desc limit 1);
    update partner_events set processed = true, mapped = jsonb_build_object('refund', r) where id = ev.id;
    return jsonb_build_object('accepted', true, 'refund', r);
  end if;
  if v_stage is null then
    update partner_events set processed = true, mapped = jsonb_build_object('note', 'no stage change') where id = ev.id;
    return jsonb_build_object('accepted', true, 'mapped', true, 'stage', null);
  end if;
  if v_stage = 'enrolled' then
    v_fields := jsonb_strip_nulls(jsonb_build_object('fee_amount_inr', (p->>'fee_amount_inr')::numeric, 'enrolled_on', p->>'enrolled_on', 'application_id', p->>'application_id',
                                                     'enrolled_university', p->>'university', 'enrolled_programme', p->>'programme'));
    if not (v_fields ? 'fee_amount_inr') then v_fields := v_fields || jsonb_build_object('fee_amount_inr', 0); end if;
  elsif v_stage = 'applied' and p->>'application_id' is not null then
    v_fields := jsonb_build_object('application_id', p->>'application_id');
  elsif v_stage = 'applied' then
    v_fields := jsonb_build_object('application_id', 'partner:' || coalesce(p->>'record_id', a.reference));
  end if;
  r := crm_apply_stage_system(a.lead_id, v_stage, v_sub, v_reason, v_fields, 'partner:' || pt.slug, v_reopen);
  if v_stage = 'enrolled' and p->>'proof_url' is not null then update enrollments set proof_url = p->>'proof_url' where lead_id = a.lead_id and status = 'reported'; end if;
  update partner_events set processed = true, mapped = jsonb_build_object('stage', v_stage, 'sub_stage', v_sub, 'reason', v_reason, 'result', r) where id = ev.id;
  return jsonb_build_object('accepted', true, 'mapped', true, 'stage', v_stage, 'result', r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_partner_health_check()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pt partners; v_paused int := 0; v_alerts int := 0; v_last5 int; v_breached5 int; v_fail int; v_ok int; v_dup numeric;
begin
  for pt in select * from partners where status = 'active' loop
    select count(*), count(*) filter (where first_contact_at is null and pushed_at < now() - make_interval(hours => coalesce((pt.sla->>'first_contact_hours')::int, 2))) into v_last5, v_breached5
      from (select * from allocations where partner_id = pt.id and status = 'pushed' order by pushed_at desc limit 5) x;
    if v_last5 = 5 and v_breached5 = 5 then
      update partners set status = 'paused', auto_paused_at = now(), paused_reason = 'missed the first-contact SLA on 5 leads in a row' where id = pt.id;
      insert into crm_alerts (kind, partner_id, message) values ('auto_paused', pt.id, pt.name || ' paused automatically: missed the first-contact SLA on 5 leads in a row');
      v_paused := v_paused + 1; continue;
    end if;
    select count(*) filter (where status in ('pending','failed') and last_error is not null and updated_at > now() - interval '30 minutes'), count(*) filter (where status = 'pushed' and pushed_at > now() - interval '30 minutes') into v_fail, v_ok
      from allocations where partner_id = pt.id;
    if v_fail >= 3 and v_ok = 0 then
      update partners set status = 'paused', auto_paused_at = now(), paused_reason = 'sync failing for 30 minutes' where id = pt.id;
      insert into crm_alerts (kind, partner_id, message) values ('auto_paused', pt.id, pt.name || ' paused automatically: pushes have failed for 30 minutes');
      v_paused := v_paused + 1; continue;
    end if;
    select count(*) filter (where status = 'duplicate')::numeric / nullif(count(*), 0) into v_dup from allocations where partner_id = pt.id and created_at > now() - interval '7 days';
    if coalesce(v_dup, 0) > 0.15 and not exists (select 1 from crm_alerts where partner_id = pt.id and kind = 'duplicate_rate' and created_at > now() - interval '1 day') then
      insert into crm_alerts (kind, partner_id, message) values ('duplicate_rate', pt.id, pt.name || ' duplicate rate this week is ' || round(v_dup * 100) || '%'); v_alerts := v_alerts + 1;
    end if;
    if pt.adapter_type = 'webhook' and exists (select 1 from allocations where partner_id = pt.id and status = 'pushed' and outcome is null and pushed_at < now() - interval '2 hours')
       and not exists (select 1 from partner_events where partner_id = pt.id and received_at > now() - interval '2 hours')
       and not exists (select 1 from crm_alerts where partner_id = pt.id and kind = 'silent' and created_at > now() - interval '1 day')
       and extract(hour from now() at time zone 'Asia/Kolkata') between 9 and 20 then
      insert into crm_alerts (kind, partner_id, message) values ('silent', pt.id, pt.name || ' has sent no status events for 2 hours while holding open leads'); v_alerts := v_alerts + 1;
    end if;
  end loop;
  return jsonb_build_object('paused', v_paused, 'alerts', v_alerts);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_partner_rotate_secret(p_partner bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text;
begin
  perform crm_require(array['admin','revenue']);
  v := 'pk_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  update partners set inbound_secret = v, updated_at = now() where id = p_partner;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_partner_verify(p_partner bigint, p_body text, p_signature text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from partners where id = p_partner and status in ('active','onboarding','paused') and inbound_secret is not null
                   and encode(extensions.hmac(p_body, inbound_secret, 'sha256'), 'hex') = lower(coalesce(p_signature, '')));
$function$;

CREATE OR REPLACE FUNCTION public.crm_payout_rate(p_university bigint, p_programme bigint, p_user uuid, p_on date)
 RETURNS payout_rates
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r from payout_rates r
   where r.valid_from <= p_on and (r.valid_to is null or r.valid_to >= p_on)
     and ((r.scope = 'user' and r.user_id = p_user and (r.university_id is null or r.university_id = p_university))
       or (r.scope = 'programme' and r.programme_id = p_programme)
       or (r.scope = 'university' and r.university_id = p_university))
   order by case r.scope when 'user' then 1 when 'programme' then 2 else 3 end, r.valid_from desc, r.id desc
   limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.crm_payout_run_create(p_period text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r payout_runs; v_total numeric; v_n int;
begin
  perform crm_require(array['admin','finance']);
  update payouts set status = 'payable' where status = 'confirmed' and payable_on <= current_date;
  insert into payout_runs (period, created_by) values (p_period, auth.uid()) returning * into r;
  update payouts set payout_run_id = r.id where status = 'payable' and payout_run_id is null;
  select coalesce(sum(amount_inr), 0), count(*) into v_total, v_n from payouts where payout_run_id = r.id;
  update payout_runs set total_inr = v_total, line_count = v_n where id = r.id returning * into r;
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_payout_run_set_status(p_run bigint, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r payout_runs;
begin
  perform crm_require(array['admin','finance']);
  select * into r from payout_runs where id = p_run;
  if r.id is null then raise exception 'run % not found', p_run; end if;
  if p_status = 'approved' and r.status = 'draft' then
    update payout_runs set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_run returning * into r;
  elsif p_status = 'paid' and r.status = 'approved' then
    update payout_runs set status = 'paid', paid_at = now() where id = p_run returning * into r;
    update payouts set status = 'paid', paid_at = now() where payout_run_id = p_run and status = 'payable';
    update student_leads l set stage = 'paid', stage_changed_at = now() from enrollments e join payouts p on p.enrollment_id = e.id
     where p.payout_run_id = p_run and e.lead_id = l.id and l.stage = 'commission_booked';
  elsif p_status = 'draft' and r.status = 'draft' then
    update payouts set payout_run_id = null where payout_run_id = p_run; delete from payout_runs where id = p_run; return jsonb_build_object('deleted', p_run);
  else raise exception 'cannot move run % from % to %', p_run, r.status, p_status; end if;
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_pending_notification_emails(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'email', u.email, 'name', u.full_name, 'kind', n.kind, 'title', n.title, 'body', n.body, 'link', n.link) order by n.id), '[]'::jsonb)
    from (select * from crm_notifications where emailed_at is null and created_at > now() - interval '1 day' order by id limit p_limit) n
    join crm_users u on u.id = n.user_id and u.is_active;
$function$;

CREATE OR REPLACE FUNCTION public.crm_period_close(p_period text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare x record; v_adj int := 0; v_inv int := 0; v_e jsonb; e enrollments; er earning_rates; inv invoices; v_seq int;
begin
  perform crm_require(array['admin','finance']);
  for x in select g.* from earnings g where g.period = p_period and g.tier_provisional and g.status in ('realised','expected') and g.reverses_id is null loop
    select * into e from enrollments where id = x.enrollment_id;
    select * into er from earning_rates where id = x.rate_id;
    v_e := crm_compute_earning(e, er, p_period);
    if v_e is not null and (v_e->>'net')::numeric <> x.net_inr then
      insert into earnings (enrollment_id, rate_id, rate_snapshot, period, base_inr, pct, gross_inr, gst_inr, net_inr, status, note)
      values (x.enrollment_id, x.rate_id, x.rate_snapshot, p_period, (v_e->>'base')::numeric, (v_e->>'pct')::numeric,
              (v_e->>'gross')::numeric - x.gross_inr, (v_e->>'gst')::numeric - x.gst_inr, (v_e->>'net')::numeric - x.net_inr, x.status, 'tier adjustment at period close');
      v_adj := v_adj + 1;
    end if;
    update earnings set tier_provisional = false where id = x.id;
  end loop;
  for x in select en.university_id, en.university_name, sum(g.gross_inr) gross, sum(g.gst_inr) gst, sum(g.net_inr) net, count(*) n
             from earnings g join enrollments en on en.id = g.enrollment_id
            where g.period = p_period and g.status = 'realised' and g.invoice_id is null
            group by en.university_id, en.university_name loop
    select coalesce(max(id), 0) + 1 into v_seq from invoices;
    insert into invoices (number, counterparty_type, counterparty_id, counterparty_name, period, gross_inr, gst_inr, net_inr, line_count, created_by)
    values ('EDW-' || replace(p_period, '-', '') || '-' || lpad(v_seq::text, 4, '0'), 'university', x.university_id, x.university_name, p_period, x.gross, x.gst, x.net, x.n, auth.uid())
    returning * into inv;
    update earnings g set status = 'invoiced', invoice_id = inv.id from enrollments en
     where en.id = g.enrollment_id and g.period = p_period and g.status = 'realised' and g.invoice_id is null and coalesce(en.university_id, 0) = coalesce(x.university_id, 0);
    v_inv := v_inv + 1;
  end loop;
  return jsonb_build_object('period', p_period, 'tier_adjustments', v_adj, 'invoices_created', v_inv, 'conversion', crm_conversion(p_period));
end $function$;

CREATE OR REPLACE FUNCTION public.crm_programme_fit(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l student_leads; q jsonb;
begin
  select * into l from student_leads where id = p_id and crm_can_see(owner_user_id, is_test, is_sales_ready);
  if l.id is null then raise exception 'lead % not visible', p_id using errcode = '42501'; end if;
  if coalesce(l.interested_course, '') = '' then return jsonb_build_object('rows', '[]'::jsonb, 'total_for_course', 0); end if;
  q := jsonb_strip_nulls(jsonb_build_object(
    'course', regexp_replace(lower(regexp_replace(l.interested_course, '\(.*?\)', ' ', 'g')), '[^a-z0-9]', '', 'g'),
    'course_label', l.interested_course, 'specialization', l.interested_specialization, 'level', l.program_level,
    'mode', l.study_mode_preference, 'university', l.university_preference));
  return w2_search_programs(q) || jsonb_build_object('query', q);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_reallocate(p_lead bigint, p_dest_type text, p_partner bigint DEFAULT NULL::bigint, p_user uuid DEFAULT NULL::uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a allocations; pt partners; v_breached boolean := false; r jsonb; n allocations;
begin
  perform crm_require(array['admin','revenue']);
  if coalesce(p_reason, '') = '' then raise exception 'a reason is required'; end if;
  select * into a from allocations where lead_id = p_lead and status in ('pending','pushing','pushed','assigned') order by id desc limit 1;
  if a.id is not null then
    if a.destination_type = 'partner' then
      select * into pt from partners where id = a.partner_id;
      v_breached := a.first_contact_at is null and a.pushed_at < now() - make_interval(hours => coalesce((pt.sla->>'first_contact_hours')::int, 2));
      if a.first_contact_at is not null and not v_breached then raise exception 'partner has already contacted this student; re-allocation is only allowed before first contact or after an SLA breach'; end if;
    end if;
    update allocations set status = 'recalled', override = true, reason = p_reason, updated_at = now() where id = a.id;
  end if;
  update student_leads set destination_type = null, partner_id = null, allocation_id = null, owner_user_id = null, allocation_reason = 'manual override' where id = p_lead;
  if p_dest_type = 'in_house' then
    r := crm_assign_lead(p_lead, p_user, p_reason);
    if coalesce((r->>'assigned')::boolean, false) then
      insert into allocations (lead_id, segment, destination_type, user_id, status, pushed_at, reason, override, reference)
      values (p_lead, (select crm_segment_of(l) from student_leads l where l.id = p_lead), 'in_house', (r->>'user_id')::uuid, 'assigned', now(), p_reason, true, null) returning * into n;
      update allocations set reference = 'EDW-' || n.id where id = n.id;
      update student_leads set allocation_id = n.id where id = p_lead;
    end if;
  else
    insert into allocations (lead_id, segment, destination_type, partner_id, status, reason, override)
    values (p_lead, (select crm_segment_of(l) from student_leads l where l.id = p_lead), 'partner', p_partner, 'pending', p_reason, true) returning * into n;
    update allocations set reference = 'EDW-' || n.id where id = n.id;
    update student_leads set destination_type = 'partner', partner_id = p_partner, allocation_id = n.id, allocated_at = now(), stage = case when stage in ('new','qualifying','allocated','assigned') then 'sent_to_partner' else stage end, stage_changed_at = now() where id = p_lead;
    r := jsonb_build_object('allocated', true, 'allocation_id', n.id, 'reference', 'EDW-' || n.id);
  end if;
  insert into engine_decisions (lead_id, segment, mode, winner_type, winner_id, note) values (p_lead, (select crm_segment_of(l) from student_leads l where l.id = p_lead), 'manual', p_dest_type, p_partner, p_reason);
  insert into crm_activities (lead_id, kind, content, meta, actor_id, actor_name) values (p_lead, 'assign', 'Re-allocated to ' || p_dest_type || ' by override: ' || p_reason, jsonb_build_object('recalled', a.id, 'breached', v_breached), auth.uid(), crm_me()->>'full_name');
  return coalesce(r, '{}'::jsonb) || jsonb_build_object('recalled_allocation', a.id);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_refund_enrollment(p_id bigint, p_reason text, p_kind text DEFAULT 'refunded'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e enrollments; x record; v_rev int := 0; v_claw int := 0;
begin
  perform crm_require(array['admin','finance']);
  select * into e from enrollments where id = p_id;
  if e.id is null or e.status in ('refunded','cancelled') then raise exception 'enrollment % cannot be refunded (%)', p_id, coalesce(e.status, 'missing'); end if;
  for x in select * from earnings where enrollment_id = p_id and reverses_id is null and status <> 'reversed' loop
    insert into earnings (enrollment_id, rate_id, rate_snapshot, period, base_inr, pct, gross_inr, gst_inr, net_inr, status, reverses_id, note)
    values (p_id, x.rate_id, x.rate_snapshot, x.period, x.base_inr, x.pct, -x.gross_inr, -x.gst_inr, -x.net_inr, case when x.status = 'expected' then 'expected' else 'realised' end, x.id, p_kind || ': ' || p_reason);
    v_rev := v_rev + 1;
  end loop;
  for x in select * from payouts where enrollment_id = p_id and not is_clawback loop
    if x.status = 'paid' then
      insert into payouts (enrollment_id, user_id, rate_id, rate_snapshot, period, amount_inr, status, payable_on, is_clawback, reverses_id, note)
      values (p_id, x.user_id, x.rate_id, x.rate_snapshot, to_char(now(), 'YYYY-MM'), -x.amount_inr, 'payable', current_date, true, x.id, p_kind || ': ' || p_reason);
      v_claw := v_claw + 1;
    else
      update payouts set status = 'clawback', note = p_kind || ': ' || p_reason where id = x.id;
    end if;
  end loop;
  update enrollments set status = p_kind, refunded_at = now(), refund_reason = p_reason, realised_net_revenue_inr = 0, expected_net_revenue_inr = 0, updated_at = now() where id = p_id;
  update student_leads set enrollment_status = p_kind, realised_net_revenue_inr = 0, expected_net_revenue_inr = 0, last_activity_at = now() where id = e.lead_id;
  insert into crm_activities (lead_id, kind, content, meta, actor_id, actor_name)
  values (e.lead_id, 'system', 'Enrollment ' || p_kind || ': ' || p_reason, jsonb_build_object('enrollment_id', p_id, 'reversals', v_rev, 'clawbacks', v_claw), auth.uid(), crm_me()->>'full_name');
  return jsonb_build_object('enrollment_id', p_id, 'reversals', v_rev, 'clawbacks', v_claw);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_render_template(p_template bigint, p_lead bigint, p_extra jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tpl message_templates; v jsonb; k text; val text; v_subject text; v_body text; v_params jsonb := '[]'::jsonb; prm text;
begin
  select * into tpl from message_templates where id = p_template;
  if tpl.id is null then raise exception 'template % not found', p_template; end if;
  select to_jsonb(x) into v from (select sv.*, u.full_name as owner_name, u.phone as owner_phone, u.email as owner_email, split_part(coalesce(sv.full_name, ''), ' ', 1) as first_name, to_char(current_date, 'DD Mon YYYY') as today
                                    from student_leads_v sv left join crm_users u on u.id = sv.owner_user_id where sv.id = p_lead) x;
  if v is null then raise exception 'lead % not visible', p_lead using errcode = '42501'; end if;
  v := v || coalesce(p_extra, '{}'::jsonb);
  v_subject := coalesce(tpl.subject, ''); v_body := tpl.body;
  for k, val in select key, value from jsonb_each_text(v) loop
    v_subject := replace(v_subject, '{{' || k || '}}', coalesce(val, ''));
    v_body := replace(v_body, '{{' || k || '}}', coalesce(val, ''));
  end loop;
  v_subject := regexp_replace(v_subject, '\{\{[a-z_]+\}\}', '', 'g');
  v_body := regexp_replace(v_body, '\{\{[a-z_]+\}\}', '', 'g');
  for prm in select jsonb_array_elements_text(tpl.wa_params) loop
    v_params := v_params || to_jsonb(coalesce(v->>prm, ''));
  end loop;
  return jsonb_build_object('channel', tpl.channel, 'subject', v_subject, 'body', v_body, 'wa_template_name', tpl.wa_template_name, 'wa_language', tpl.wa_language, 'wa_params', v_params);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_report(p_kind text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role text := crm_role(); v_me uuid := auth.uid(); v_from timestamptz; v_to timestamptz; r jsonb;
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  v_from := coalesce(p_from, (current_date - 29))::timestamptz; v_to := (coalesce(p_to, current_date) + 1)::timestamptz;
  if p_kind = 'funnel' then
    select jsonb_build_object(
      'created', count(*),
      'by_stage', (select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) from (select l2.stage, count(*) n from student_leads l2 where l2.created_at >= v_from and l2.created_at < v_to and l2.deleted_at is null and not coalesce(l2.is_test, false) and (v_role <> 'sales_manager' or l2.owner_user_id = v_me) group by l2.stage) s),
      'sales_ready', count(*) filter (where is_sales_ready),
      'contacted', count(*) filter (where first_contacted_at is not null),
      'applied', count(*) filter (where applied_at is not null or stage in ('applied', 'enrolled', 'verified', 'commission_booked', 'paid')),
      'enrolled', count(*) filter (where stage in ('enrolled', 'verified', 'commission_booked', 'paid')),
      'lost', count(*) filter (where stage = 'lost'),
      'lost_by_reason', (select coalesce(jsonb_object_agg(coalesce(lost_reason, 'unknown'), n), '{}'::jsonb) from (select l2.lost_reason, count(*) n from student_leads l2 where l2.created_at >= v_from and l2.created_at < v_to and l2.stage = 'lost' and l2.deleted_at is null and not coalesce(l2.is_test, false) and (v_role <> 'sales_manager' or l2.owner_user_id = v_me) group by l2.lost_reason) s),
      'median_days_to_enrol', (select percentile_cont(0.5) within group (order by extract(epoch from (l2.enrollment_date::timestamptz - l2.created_at)) / 86400) from student_leads l2 where l2.created_at >= v_from and l2.created_at < v_to and l2.enrollment_date is not null and l2.deleted_at is null and (v_role <> 'sales_manager' or l2.owner_user_id = v_me)),
      'by_temperature', (select coalesce(jsonb_object_agg(coalesce(temperature, 'none'), n), '{}'::jsonb) from (select l2.temperature, count(*) n from student_leads l2 where l2.created_at >= v_from and l2.created_at < v_to and l2.deleted_at is null and not coalesce(l2.is_test, false) and (v_role <> 'sales_manager' or l2.owner_user_id = v_me) group by l2.temperature) s)
    ) into r
    from student_leads l where l.created_at >= v_from and l.created_at < v_to and l.deleted_at is null and not coalesce(l.is_test, false) and (v_role <> 'sales_manager' or l.owner_user_id = v_me);
  elsif p_kind = 'sources' then
    select coalesce(jsonb_agg(jsonb_build_object('source', source, 'leads', leads, 'sales_ready', sales_ready, 'contacted', contacted, 'enrolled', enrolled, 'net_expected', net_expected, 'net_realised', net_realised) order by leads desc), '[]'::jsonb) into r
    from (select coalesce(l.lead_source, 'unknown') as source, count(*) leads, count(*) filter (where l.is_sales_ready) sales_ready, count(*) filter (where l.first_contacted_at is not null) contacted,
                 count(*) filter (where l.stage in ('enrolled', 'verified', 'commission_booked', 'paid')) enrolled, coalesce(sum(l.expected_net_revenue_inr), 0) net_expected, coalesce(sum(l.realised_net_revenue_inr), 0) net_realised
            from student_leads l where l.created_at >= v_from and l.created_at < v_to and l.deleted_at is null and not coalesce(l.is_test, false) and (v_role <> 'sales_manager' or l.owner_user_id = v_me) group by 1) s;
  elsif p_kind = 'activity' then
    select jsonb_build_object(
      'calls', (select count(*) from calls c join student_leads l on l.id = c.lead_id where c.started_at >= v_from and c.started_at < v_to and (v_role <> 'sales_manager' or c.user_id = v_me)),
      'calls_connected', (select count(*) from calls c where c.started_at >= v_from and c.started_at < v_to and c.outcome = 'connected' and (v_role <> 'sales_manager' or c.user_id = v_me)),
      'talk_time_min', (select coalesce(round(sum(c.duration_sec) / 60.0, 1), 0) from calls c where c.started_at >= v_from and c.started_at < v_to and (v_role <> 'sales_manager' or c.user_id = v_me)),
      'whatsapp_sent', (select count(*) from crm_activities a where a.created_at >= v_from and a.created_at < v_to and a.kind = 'whatsapp' and (v_role <> 'sales_manager' or a.actor_id = v_me)),
      'emails_sent', (select count(*) from crm_activities a where a.created_at >= v_from and a.created_at < v_to and a.kind = 'email' and (v_role <> 'sales_manager' or a.actor_id = v_me)),
      'tasks_created', (select count(*) from crm_tasks t where t.created_at >= v_from and t.created_at < v_to and (v_role <> 'sales_manager' or t.assignee_id = v_me)),
      'tasks_done', (select count(*) from crm_tasks t where t.done_at >= v_from and t.done_at < v_to and (v_role <> 'sales_manager' or t.assignee_id = v_me)),
      'tasks_overdue_now', (select count(*) from crm_tasks t where t.done_at is null and t.due_at < now() and (v_role <> 'sales_manager' or t.assignee_id = v_me)),
      'first_contact_median_min', (select round((percentile_cont(0.5) within group (order by extract(epoch from (l.first_contacted_at - l.assigned_at)) / 60))::numeric, 0) from student_leads l where l.assigned_at >= v_from and l.assigned_at < v_to and l.first_contacted_at is not null and (v_role <> 'sales_manager' or l.owner_user_id = v_me)),
      'sla_compliance', (select round(avg(case when l.first_contacted_at is not null and l.first_contacted_at <= l.assigned_at + make_interval(mins => crm_sla_minutes(l.temperature)) then 1 else 0 end)::numeric, 3) from student_leads l where l.assigned_at >= v_from and l.assigned_at < v_to and l.assigned_at < now() - interval '1 day' and (v_role <> 'sales_manager' or l.owner_user_id = v_me)),
      'untouched_48h', (select count(*) from student_leads l where l.owner_user_id is not null and l.first_contacted_at is null and l.stage = 'assigned' and l.assigned_at < now() - interval '48 hours' and l.deleted_at is null and (v_role <> 'sales_manager' or l.owner_user_id = v_me))
    ) into r;
  elsif p_kind = 'team' then
    select coalesce(jsonb_agg(jsonb_build_object('user_id', u.id, 'name', coalesce(u.full_name, u.email), 'role', u.role, 'on_shift', u.on_shift, 'cap', u.monthly_cap, 'target', u.monthly_target,
             'assigned', s.assigned, 'contacted', s.contacted, 'within_sla', s.within_sla, 'enrolled', s.enrolled, 'net_expected', s.net_expected, 'calls', s.calls, 'open_tasks', s.open_tasks, 'overdue_tasks', s.overdue_tasks) order by s.enrolled desc, s.assigned desc), '[]'::jsonb) into r
    from crm_users u
    join lateral (
      select count(*) filter (where l.assigned_at >= v_from and l.assigned_at < v_to) assigned,
             count(*) filter (where l.assigned_at >= v_from and l.assigned_at < v_to and l.first_contacted_at is not null) contacted,
             round(avg(case when l.first_contacted_at <= l.assigned_at + make_interval(mins => crm_sla_minutes(l.temperature)) then 1 else 0 end) filter (where l.assigned_at >= v_from and l.assigned_at < v_to and l.assigned_at < now() - interval '1 day')::numeric, 3) within_sla,
             count(*) filter (where l.enrollment_date >= v_from::date and l.enrollment_date < v_to::date) enrolled,
             coalesce(sum(l.expected_net_revenue_inr) filter (where l.enrollment_date >= v_from::date and l.enrollment_date < v_to::date), 0) net_expected,
             (select count(*) from calls c where c.user_id = u.id and c.started_at >= v_from and c.started_at < v_to) calls,
             (select count(*) from crm_tasks t where t.assignee_id = u.id and t.done_at is null) open_tasks,
             (select count(*) from crm_tasks t where t.assignee_id = u.id and t.done_at is null and t.due_at < now()) overdue_tasks
        from student_leads l where l.owner_user_id = u.id and l.deleted_at is null and not coalesce(l.is_test, false)
    ) s on true
    where u.is_active and u.role in ('sales_manager', 'sales_head') and (v_role <> 'sales_manager' or u.id = v_me);
  else
    raise exception 'unknown report %', p_kind;
  end if;
  if jsonb_typeof(coalesce(r, '{}'::jsonb)) = 'array' then return coalesce(r, '[]'::jsonb); end if;
  return coalesce(r, '{}'::jsonb) || jsonb_build_object('from', v_from::date, 'to', (v_to - interval '1 day')::date);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_report_enrollment(p_lead bigint, p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l student_leads; e enrollments; er earning_rates; pr payout_rates; v_e jsonb; v_p jsonb; v_period text; v_uni bigint; v_prog bigint; v_win int;
begin
  if auth.uid() is not null then perform crm_require(array['admin','finance','sales_head','sales_manager','revenue']); end if;
  select * into l from student_leads where id = p_lead;
  if l.id is null then raise exception 'lead % not found', p_lead; end if;
  v_prog := coalesce((p->>'programme_id')::bigint, (select cp.id from catalog_programs cp where cp.program_name = l.enrolled_program and cp.active order by cp.id limit 1));
  v_uni := coalesce((p->>'university_id')::bigint, (select university_id from catalog_programs where id = v_prog),
                    (select cu.id from catalog_universities cu where lower(cu.name) = lower(coalesce(p->>'university_name', l.enrolled_university)) or lower(cu.short_name) = lower(coalesce(p->>'university_name', l.enrolled_university)) limit 1));
  select refund_window_days into v_win from crm_university_settings where university_id = v_uni;
  v_win := coalesce(v_win, (crm_money_setting('refund_window_days'))::text::int, 30);
  insert into enrollments (lead_id, cycle_no, university_id, university_name, programme_id, programme_name, fee_amount_inr, fee_paid_inr, enrolled_on,
                           destination_type, owner_user_id, partner_id, reported_by, refund_window_ends_on, proof_url, proof_ref)
  values (p_lead, coalesce(l.cycle_no, 1), v_uni, coalesce(p->>'university_name', l.enrolled_university, (select name from catalog_universities where id = v_uni)),
          v_prog, coalesce(p->>'programme_name', l.enrolled_program, (select program_name from catalog_programs where id = v_prog)),
          coalesce((p->>'fee_amount_inr')::numeric, l.fee_amount_inr), coalesce((p->>'fee_paid_inr')::numeric, l.fee_paid_inr),
          coalesce((p->>'enrolled_on')::date, l.enrollment_date, current_date), coalesce(l.destination_type, 'in_house'), l.owner_user_id, l.partner_id, auth.uid(),
          coalesce((p->>'enrolled_on')::date, l.enrollment_date, current_date) + v_win, p->>'proof_url', p->>'proof_ref')
  on conflict (lead_id, cycle_no) where status in ('reported','verified') do update
     set fee_amount_inr = coalesce(excluded.fee_amount_inr, enrollments.fee_amount_inr), fee_paid_inr = coalesce(excluded.fee_paid_inr, enrollments.fee_paid_inr),
         programme_id = coalesce(excluded.programme_id, enrollments.programme_id), university_id = coalesce(excluded.university_id, enrollments.university_id),
         programme_name = coalesce(excluded.programme_name, enrollments.programme_name), university_name = coalesce(excluded.university_name, enrollments.university_name),
         proof_url = coalesce(excluded.proof_url, enrollments.proof_url), proof_ref = coalesce(excluded.proof_ref, enrollments.proof_ref), updated_at = now()
  returning * into e;
  if e.status <> 'reported' then return jsonb_build_object('enrollment', to_jsonb(e), 'note', 'already ' || e.status); end if;
  v_period := to_char(e.enrolled_on, 'YYYY-MM');
  delete from payouts where enrollment_id = e.id and status = 'provisional';
  delete from earnings where enrollment_id = e.id and status = 'expected';
  er := crm_earning_rate(e.university_id, e.programme_id, e.partner_id, e.enrolled_on);
  v_e := crm_compute_earning(e, er, v_period);
  if v_e is not null then
    insert into earnings (enrollment_id, rate_id, rate_snapshot, period, base_inr, pct, gross_inr, gst_inr, net_inr, status, tier_provisional)
    values (e.id, er.id, to_jsonb(er), v_period, (v_e->>'base')::numeric, (v_e->>'pct')::numeric, (v_e->>'gross')::numeric, (v_e->>'gst')::numeric, (v_e->>'net')::numeric, 'expected', (v_e->>'tier_provisional')::boolean);
  end if;
  if e.owner_user_id is not null and coalesce(e.destination_type, 'in_house') = 'in_house' then
    pr := crm_payout_rate(e.university_id, e.programme_id, e.owner_user_id, e.enrolled_on);
    v_p := crm_compute_payout(e, pr, (v_e->>'net')::numeric, v_period);
    if v_p is not null then
      insert into payouts (enrollment_id, user_id, rate_id, rate_snapshot, period, amount_inr, status, payable_on)
      values (e.id, e.owner_user_id, pr.id, to_jsonb(pr) || jsonb_build_object('computed', v_p), v_period, (v_p->>'amount')::numeric, 'provisional', e.refund_window_ends_on);
    end if;
  end if;
  update enrollments set expected_net_revenue_inr = coalesce((v_e->>'net')::numeric, 0) - coalesce((v_p->>'amount')::numeric, 0), updated_at = now() where id = e.id returning * into e;
  update student_leads set enrollment_status = coalesce(enrollment_status, 'reported'), enrollment_date = coalesce(enrollment_date, e.enrolled_on),
         fee_amount_inr = coalesce(fee_amount_inr, e.fee_amount_inr), enrolled_university = coalesce(enrolled_university, e.university_name), enrolled_program = coalesce(enrolled_program, e.programme_name),
         expected_net_revenue_inr = e.expected_net_revenue_inr where id = p_lead;
  return jsonb_build_object('enrollment', to_jsonb(e), 'earning', v_e, 'payout', v_p, 'earning_rate_found', er.id is not null, 'payout_rate_found', pr.id is not null);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_require(p_roles text[])
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
begin
  if coalesce(crm_role(), '') <> all (p_roles) then raise exception 'not allowed for role %', coalesce(crm_role(), 'none') using errcode = '42501'; end if;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_resolve_alert(p_alert bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform crm_require(array['admin','revenue','sales_head','finance']);
  update crm_alerts set resolved_at = now(), resolved_by = auth.uid() where id = p_alert;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select role from crm_users where id = auth.uid() and is_active;
$function$;

CREATE OR REPLACE FUNCTION public.crm_rules_match(p_rules jsonb, p_lead bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b boolean;
begin
  execute format('select exists (select 1 from student_leads_v where id = %s and (%s))', p_lead, crm_rules_where(p_rules)) into b;
  return coalesce(b, false);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_rules_where(p_rules jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; v_field text; v_op text; v_val jsonb; v_parts text[] := '{}'; v_type text; v_sql text; v_text text;
begin
  if p_rules is null or jsonb_typeof(p_rules) <> 'array' or jsonb_array_length(p_rules) = 0 then return 'true'; end if;
  for r in select * from jsonb_array_elements(p_rules) loop
    v_field := r->>'field'; v_op := lower(coalesce(r->>'op', 'eq')); v_val := r->'value'; v_text := v_val #>> '{}';
    select data_type into v_type from information_schema.columns where table_schema = 'public' and table_name = 'student_leads_v' and column_name = v_field;
    if v_type is null then raise exception 'unknown field %', v_field; end if;
    if v_op in ('in', 'not_in', 'contains_any') and jsonb_typeof(v_val) <> 'array' then v_val := jsonb_build_array(v_val); end if;
    v_sql := case v_op
      when 'eq' then format('%I::text = %L', v_field, v_text)
      when 'neq' then format('%I::text is distinct from %L', v_field, v_text)
      when 'gt' then format('%I > %L', v_field, v_text)
      when 'gte' then format('%I >= %L', v_field, v_text)
      when 'lt' then format('%I < %L', v_field, v_text)
      when 'lte' then format('%I <= %L', v_field, v_text)
      when 'in' then format('%I::text in (%s)', v_field, (select string_agg(format('%L', x), ',') from jsonb_array_elements_text(v_val) x))
      when 'not_in' then format('(%I is null or %I::text not in (%s))', v_field, v_field, (select string_agg(format('%L', x), ',') from jsonb_array_elements_text(v_val) x))
      when 'contains' then format('%I::text ilike %L', v_field, '%' || v_text || '%')
      when 'contains_any' then format('(%s)', (select string_agg(format('%I::text ilike %L', v_field, '%' || x || '%'), ' or ') from jsonb_array_elements_text(v_val) x))
      when 'is_null' then format('(%I is null or %I::text = %L)', v_field, v_field, '')
      when 'not_null' then format('(%I is not null and %I::text <> %L)', v_field, v_field, '')
      when 'true' then format('coalesce(%I::boolean, false)', v_field)
      when 'false' then format('not coalesce(%I::boolean, false)', v_field)
      when 'days_ago_gte' then format('%I <= now() - make_interval(days => %s)', v_field, (v_text)::int)
      when 'days_ago_lte' then format('%I >= now() - make_interval(days => %s)', v_field, (v_text)::int)
      else null end;
    if v_sql is null then raise exception 'unknown operator %', v_op; end if;
    v_parts := v_parts || v_sql;
  end loop;
  return coalesce(array_to_string(v_parts, ' and '), 'true');
end $function$;

CREATE OR REPLACE FUNCTION public.crm_save_campaign(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r campaigns;
begin
  perform crm_require(array['admin', 'marketing', 'sales_head']);
  if p ? 'id' then
    update campaigns set name = coalesce(p->>'name', name), channel = coalesce(p->>'channel', channel), template_id = coalesce((p->>'template_id')::bigint, template_id), segment_id = coalesce((p->>'segment_id')::bigint, segment_id), updated_at = now()
     where id = (p->>'id')::bigint and status in ('draft', 'cancelled') returning * into r;
    if r.id is null then raise exception 'only draft or cancelled campaigns can be edited'; end if;
  else
    insert into campaigns (name, channel, template_id, segment_id, created_by) values (p->>'name', p->>'channel', (p->>'template_id')::bigint, (p->>'segment_id')::bigint, auth.uid()) returning * into r;
  end if;
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_save_journey(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r journeys;
begin
  perform crm_require(array['admin', 'marketing', 'sales_head']);
  if p ? 'id' then
    update journeys set name = coalesce(p->>'name', name), trigger = coalesce(p->'trigger', trigger), steps = coalesce(p->'steps', steps), description = coalesce(p->>'description', description), updated_at = now()
     where id = (p->>'id')::bigint returning * into r;
  else
    insert into journeys (name, trigger, steps, description, created_by) values (p->>'name', coalesce(p->'trigger', '{"type":"manual"}'::jsonb), coalesce(p->'steps', '[]'::jsonb), p->>'description', auth.uid()) returning * into r;
  end if;
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_save_mapping_profile(p_partner bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r partner_mapping_profiles; v_ver int;
begin
  perform crm_require(array['admin','revenue']);
  select coalesce(max(version), 0) + 1 into v_ver from partner_mapping_profiles where partner_id = p_partner;
  update partner_mapping_profiles set is_active = false where partner_id = p_partner;
  insert into partner_mapping_profiles (partner_id, version, status_map, field_map, value_maps, created_by)
  values (p_partner, v_ver, coalesce(p->'status_map', '[]'::jsonb), coalesce(p->'field_map', '{}'::jsonb), coalesce(p->'value_maps', '{}'::jsonb), auth.uid())
  returning * into r;
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_save_routing_rule(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r routing_rules;
begin
  perform crm_require(array['admin','revenue']);
  if p ? 'id' then
    update routing_rules set priority = coalesce((p->>'priority')::int, priority), name = coalesce(p->>'name', name), conditions = coalesce(p->'conditions', conditions),
           action = coalesce(p->'action', action), active = coalesce((p->>'active')::boolean, active) where id = (p->>'id')::bigint returning * into r;
  else
    insert into routing_rules (priority, name, conditions, action, created_by) values (coalesce((p->>'priority')::int, 100), p->>'name', coalesce(p->'conditions', '{}'::jsonb), coalesce(p->'action', '{}'::jsonb), auth.uid()) returning * into r;
  end if;
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_save_segment(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r segments;
begin
  perform crm_require(array['admin', 'marketing', 'sales_head']);
  perform crm_rules_where(coalesce(p->'rules', '[]'::jsonb));
  if p ? 'id' then
    update segments set name = coalesce(p->>'name', name), rules = coalesce(p->'rules', rules), description = coalesce(p->>'description', description), updated_at = now() where id = (p->>'id')::bigint returning * into r;
  else
    insert into segments (name, kind, rules, description, created_by) values (p->>'name', coalesce(p->>'kind', 'dynamic'), coalesce(p->'rules', '[]'::jsonb), p->>'description', auth.uid()) returning * into r;
  end if;
  return to_jsonb(r) || jsonb_build_object('count', case when r.kind = 'dynamic' then crm_segment_count(r.rules) else (select count(*)::int from segment_members where segment_id = r.id) end);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_save_template(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r message_templates;
begin
  perform crm_require(array['admin','sales_head','marketing']);
  if p ? 'id' then
    update message_templates set name = coalesce(p->>'name', name), subject = case when p ? 'subject' then p->>'subject' else subject end, body = coalesce(p->>'body', body),
           wa_template_name = case when p ? 'wa_template_name' then p->>'wa_template_name' else wa_template_name end, wa_language = coalesce(p->>'wa_language', wa_language),
           wa_params = coalesce(p->'wa_params', wa_params), active = coalesce((p->>'active')::boolean, active), updated_at = now()
     where id = (p->>'id')::bigint returning * into r;
  else
    insert into message_templates (channel, name, subject, body, wa_template_name, wa_language, wa_params, created_by)
    values (p->>'channel', p->>'name', p->>'subject', p->>'body', p->>'wa_template_name', coalesce(p->>'wa_language', 'en'), coalesce(p->'wa_params', '[]'::jsonb), auth.uid()) returning * into r;
  end if;
  return to_jsonb(r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_score_lead(p_lead bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s jsonb; l student_leads; v_fit numeric := 0; v_eng numeric := 0; v_hl numeric; v_phone text; f jsonb; v_score int; v_temp text; v_witty text; v_rank int; v_ready boolean;
begin
  select value into s from crm_settings where key = 'scoring';
  select * into l from student_leads where id = p_lead;
  if l.id is null then return null; end if;
  v_hl := coalesce((s->>'decay_half_life_days')::numeric, 14);
  v_phone := regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g');
  for f in select * from jsonb_array_elements(coalesce(s->'fit', '[]'::jsonb)) loop
    if crm_rules_match(coalesce(f->'rules', '[]'::jsonb), p_lead) then v_fit := v_fit + coalesce((f->>'points')::numeric, 0); end if;
  end loop;
  select coalesce(sum(coalesce((s->'engagement'->>'call_connected')::numeric, 20) * power(0.5, extract(epoch from (now() - c.started_at)) / 86400 / v_hl)), 0) into v_eng from calls c where c.lead_id = p_lead and c.outcome = 'connected';
  v_eng := v_eng + coalesce((select sum(coalesce((s->'engagement'->>'whatsapp_reply')::numeric, 10) * power(0.5, extract(epoch from (now() - m.created_at)) / 86400 / v_hl)) from w2_messages m where m.phone = v_phone and m.direction = 'in' and v_phone <> ''), 0);
  v_eng := v_eng + coalesce((select sum(coalesce((s->'engagement'->>'email_reply')::numeric, 10) * power(0.5, extract(epoch from (now() - a.created_at)) / 86400 / v_hl)) from crm_activities a where a.lead_id = p_lead and a.kind in ('email', 'whatsapp') and a.outcome = 'replied'), 0);
  v_eng := v_eng + coalesce((select sum(coalesce((s->'engagement'->>'form_filled')::numeric, 10) * power(0.5, extract(epoch from (now() - t.occurred_at)) / 86400 / v_hl)) from touchpoints t where t.lead_id = p_lead and (t.source_system in ('web_agent', 'web', 'form') or t.event_type ilike 'form%')), 0);
  v_eng := least(v_eng, coalesce((s->>'engagement_cap')::numeric, 60));
  v_score := round(v_fit + v_eng);
  v_temp := case when v_score >= coalesce((s->>'hot_at')::int, 60) then 'hot' when v_score >= coalesce((s->>'warm_at')::int, 30) then 'warm' else 'cold' end;
  v_witty := case upper(coalesce(l.lead_status, '')) when 'HOT' then 'hot' when 'WARM' then 'warm' when 'COLD' then 'cold' else null end;
  v_rank := greatest(case v_temp when 'hot' then 3 when 'warm' then 2 else 1 end, case v_witty when 'hot' then 3 when 'warm' then 2 when 'cold' then 1 else 0 end);
  v_temp := case v_rank when 3 then 'hot' when 2 then 'warm' else 'cold' end;
  v_ready := v_score >= coalesce((s->>'sales_ready_at')::int, 70) and not coalesce(l.is_sales_ready, false) and l.owner_user_id is null and l.destination_type is null and l.stage in ('new', 'qualifying') and not coalesce(l.is_test, false);
  update student_leads set lead_score = v_score, temperature = v_temp, score_updated_at = now(),
         is_sales_ready = is_sales_ready or v_ready, sales_ready_at = case when v_ready then coalesce(sales_ready_at, now()) else sales_ready_at end
   where id = p_lead;
  return jsonb_build_object('lead_id', p_lead, 'score', v_score, 'fit', v_fit, 'engagement', round(v_eng, 1), 'temperature', v_temp, 'sales_ready_now', v_ready);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_score_tick(p_limit integer DEFAULT 200)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id bigint; n int := 0;
begin
  if auth.uid() is not null then perform crm_require(array['admin', 'marketing']); end if;
  for v_id in select id from student_leads where deleted_at is null and merged_into_id is null and not coalesce(is_test, false)
                and stage in ('new', 'qualifying', 'allocated', 'sent_to_partner', 'assigned', 'contacted', 'counselled', 'nurture')
                and (score_updated_at is null or score_updated_at < coalesce(last_activity_at, created_at) or score_updated_at < now() - interval '1 day')
              order by score_updated_at nulls first, id limit p_limit loop
    perform crm_score_lead(v_id); n := n + 1;
  end loop;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_scorecards(p_segment text DEFAULT NULL::text, p_days integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with d as (
    select 'in_house' dtype, null::bigint did, 'In-house team' name
    union all select 'partner', id, name from partners where status <> 'closed'
  ), a as (
    select al.*, e.id enrollment_id, e.status enrollment_status, e.realised_net_revenue_inr, e.expected_net_revenue_inr, pt.sla
      from allocations al
      left join partners pt on pt.id = al.partner_id
      left join lateral (select * from enrollments e where e.lead_id = al.lead_id and e.created_at >= al.created_at order by e.id desc limit 1) e on true
     where al.created_at > now() - make_interval(days => p_days) and (p_segment is null or al.segment = p_segment)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', d.dtype, 'id', d.did, 'name', d.name,
    'allocated', (select count(*) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and a.status not in ('recalled')),
    'duplicates', (select count(*) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and a.status = 'duplicate'),
    'kept', (select count(*) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and a.status in ('pushed','assigned','closed')),
    'contacted', (select count(*) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and a.first_contact_at is not null),
    'contact_median_h', (select round(percentile_cont(0.5) within group (order by extract(epoch from first_contact_at - coalesce(pushed_at, created_at)) / 3600)::numeric, 1) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and first_contact_at is not null),
    'contact_p90_h', (select round(percentile_cont(0.9) within group (order by extract(epoch from first_contact_at - coalesce(pushed_at, created_at)) / 3600)::numeric, 1) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and first_contact_at is not null),
    'within_sla', (select round(avg(case when first_contact_at is not null and first_contact_at <= coalesce(pushed_at, created_at) + make_interval(hours => coalesce((sla->>'first_contact_hours')::int, 2)) then 1 else 0 end)::numeric, 3) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and a.status in ('pushed','assigned','closed')),
    'enrolled', (select count(*) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and enrollment_status in ('reported','verified')),
    'verified', (select count(*) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and enrollment_status = 'verified'),
    'lost', (select count(*) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and outcome = 'lost'),
    'net_revenue_realised', (select coalesce(sum(realised_net_revenue_inr), 0) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and enrollment_status = 'verified'),
    'net_revenue_expected', (select coalesce(sum(coalesce(realised_net_revenue_inr, expected_net_revenue_inr)), 0) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and enrollment_status in ('reported','verified')),
    'stale_share', (select round(avg(case when outcome is null and status = 'pushed' and coalesce(last_event_at, pushed_at) < now() - interval '7 days' then 1 else 0 end)::numeric, 3) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and status = 'pushed'),
    'sync_errors', (select count(*) from a where a.destination_type = d.dtype and (d.dtype = 'in_house' or a.partner_id = d.did) and last_error is not null),
    'last_event_at', (select max(received_at) from partner_events where partner_id = d.did),
    'engine', case when p_segment is not null then crm_dest_stats(d.dtype, d.did, p_segment, (select value from crm_settings where key = 'engine')) end
  ) order by d.dtype desc, d.name), '[]'::jsonb) from d;
$function$;

CREATE OR REPLACE FUNCTION public.crm_segment_add_leads(p_segment bigint, p_lead_ids bigint[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  perform crm_require(array['admin', 'marketing', 'sales_head']);
  insert into segment_members (segment_id, lead_id) select p_segment, x from unnest(p_lead_ids) x on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_segment_count(p_rules jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  execute format('select count(*) from student_leads_v where deleted_at is null and merged_into_id is null and not coalesce(is_test, false) and (%s)', crm_rules_where(p_rules)) into n;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_segment_leads(p_rules jsonb, p_limit integer DEFAULT 100000)
 RETURNS SETOF bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return query execute format('select id from student_leads_v where deleted_at is null and merged_into_id is null and not coalesce(is_test, false) and (%s) order by id desc limit %s', crm_rules_where(p_rules), greatest(p_limit, 1));
end $function$;

CREATE OR REPLACE FUNCTION public.crm_segment_of(l student_leads)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select regexp_replace(lower(coalesce(l.interested_course, '')), '[^a-z0-9]', '', 'g') || '|' || coalesce(l.program_level, '') || '|' || coalesce(l.study_mode_preference, '');
$function$;

CREATE OR REPLACE FUNCTION public.crm_segment_preview(p_rules jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if crm_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('count', crm_segment_count(p_rules),
    'sample', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'full_name', v.full_name, 'stage', v.stage, 'temperature', v.temperature, 'source', v.source, 'city', v.city)) from (select * from crm_segment_leads(p_rules, 10)) x join crm_leads_v v on v.id = x.crm_segment_leads), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.crm_segment_resolve(p_segment bigint)
 RETURNS SETOF bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s segments;
begin
  select * into s from segments where id = p_segment;
  if s.id is null then return; end if;
  if s.kind = 'dynamic' then return query select * from crm_segment_leads(s.rules);
  else return query select m.lead_id from segment_members m join student_leads l on l.id = m.lead_id where m.segment_id = p_segment and l.deleted_at is null and l.merged_into_id is null and not coalesce(l.is_test, false); end if;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_send_job(p_lead bigint, p_template bigint, p_base_url text, p_extra jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l student_leads; r jsonb; v_phone text; cv w2_conversations;
begin
  select * into l from student_leads where id = p_lead;
  v_phone := regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g');
  select * into cv from w2_conversations where phone = v_phone;
  r := crm_render_template(p_template, p_lead, coalesce(p_extra, '{}'::jsonb) || jsonb_build_object('unsubscribe_url', coalesce(p_base_url, '') || '/api/v1/unsubscribe?l=' || p_lead || '&t=' || crm_unsubscribe_token(p_lead)));
  return r || jsonb_build_object('lead_id', p_lead, 'template_id', p_template, 'phone', v_phone, 'email', l.email_id, 'full_name', l.student_name,
                                 'conversation_id', coalesce(l.chatwoot_conversation_id::text, cv.conversation_id::text));
end $function$;

CREATE OR REPLACE FUNCTION public.crm_set_my_phone(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if crm_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  update crm_users set phone = nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), ''), updated_at = now() where id = auth.uid();
  return jsonb_build_object('phone', (select phone from crm_users where id = auth.uid()));
end $function$;

CREATE OR REPLACE FUNCTION public.crm_set_stage(p_id bigint, p_stage text, p_sub_stage text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_fields jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_fin jsonb; v_lost jsonb; v_subs jsonb;
begin
  perform crm_require(array['admin','sales_head','sales_manager','revenue','finance']);
  if not exists (select 1 from student_leads l where l.id = p_id and crm_can_see(l.owner_user_id, l.is_test, l.is_sales_ready)) then raise exception 'lead % not visible', p_id using errcode = '42501'; end if;
  select value into v_fin from crm_settings where key = 'finance_stages';
  select value into v_lost from crm_settings where key = 'lost_reasons';
  select value into v_subs from crm_settings where key = 'sub_stages';
  if v_fin ? p_stage then raise exception 'stage % is set by the enrollment workflow (Money → Enrollments)', p_stage using errcode = '42501'; end if;
  if p_sub_stage is not null and not coalesce(v_subs->p_stage, '[]'::jsonb) ? p_sub_stage then raise exception 'unknown sub-stage % for %', p_sub_stage, p_stage; end if;
  if p_stage = 'lost' and not v_lost ? coalesce(p_reason, '') then raise exception 'a lost reason from the list is required'; end if;
  perform crm_apply_stage_system(p_id, p_stage, p_sub_stage, p_reason, p_fields, coalesce(crm_me()->>'email', 'crm'), true);
  return (select to_jsonb(v) from crm_leads_v v where v.id = p_id);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_sla_minutes(p_temperature text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((value->>coalesce(p_temperature, 'default'))::int, (value->>'default')::int, 1440) from crm_settings where key = 'sla_minutes';
$function$;

CREATE OR REPLACE FUNCTION public.crm_sync_claim(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb;
begin
  with due as (
    select a.id from allocations a join partners p on p.id = a.partner_id
     where a.destination_type = 'partner' and p.adapter_type = 'webhook' and p.status = 'active'
       and ((a.status = 'pending' and a.next_attempt_at <= now()) or (a.status = 'pushing' and a.updated_at < now() - interval '5 minutes'))
     order by a.id limit p_limit for update of a skip locked
  ), upd as (
    update allocations a set status = 'pushing', attempts = a.attempts + 1, updated_at = now() from due where a.id = due.id returning a.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'allocation_id', u.id, 'reference', u.reference, 'attempt', u.attempts, 'partner_id', p.id, 'partner', p.name,
           'url', p.api_base_url, 'auth_header', p.outbound_auth->>'header', 'auth_value', p.outbound_auth->>'value',
           'payload', jsonb_strip_nulls(jsonb_build_object('reference', u.reference, 'name', l.student_name, 'phone', l.whatsapp_number, 'email', l.email_id,
                        'programme', coalesce(l.interested_course, ''), 'specialization', l.interested_specialization, 'level', l.program_level, 'mode', l.study_mode_preference,
                        'qualification', l.highest_qualification, 'score', l.academic_percentage_gpa, 'city', coalesce(l.city, l.current_city_country), 'timeline', l.enrollment_timeline,
                        'note', left(coalesce(l."Comments", ''), 500), 'source', 'Eduwit'))) order by u.id), '[]'::jsonb)
    into v from upd u join partners p on p.id = u.partner_id join student_leads l on l.id = u.lead_id;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_sync_result(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a allocations; v_delays int[] := array[10, 60, 300, 900, 3600];
begin
  select * into a from allocations where id = (p->>'allocation_id')::bigint;
  if a.id is null then return jsonb_build_object('error', 'allocation not found'); end if;
  if coalesce((p->>'duplicate')::boolean, false) then
    return crm_partner_duplicate(a.id, p->>'record_id', (p->>'record_created_at')::timestamptz, 'adapter');
  elsif coalesce((p->>'ok')::boolean, false) then
    update allocations set status = 'pushed', pushed_at = now(), partner_record_id = coalesce(p->>'record_id', partner_record_id), last_error = null, updated_at = now() where id = a.id;
    update student_leads set partner_record_id = coalesce(p->>'record_id', partner_record_id), partner_synced_at = now() where id = a.lead_id;
    insert into crm_activities (lead_id, kind, content, meta, actor_name) values (a.lead_id, 'system', 'Pushed to partner (' || coalesce(p->>'record_id', 'no record id') || ')', jsonb_build_object('allocation_id', a.id), 'Partner sync');
    return jsonb_build_object('status', 'pushed');
  elsif a.attempts < 5 then
    update allocations set status = 'pending', last_error = left(p->>'error', 2000), next_attempt_at = now() + make_interval(secs => v_delays[greatest(1, least(a.attempts, 5))]), updated_at = now() where id = a.id;
    return jsonb_build_object('status', 'retry', 'attempt', a.attempts);
  else
    update allocations set status = 'failed', last_error = left(p->>'error', 2000), updated_at = now() where id = a.id;
    insert into crm_alerts (kind, partner_id, lead_id, message) values ('sync_failed', a.partner_id, a.lead_id, 'Push of ' || a.reference || ' failed after 5 attempts: ' || left(coalesce(p->>'error', ''), 300));
    return jsonb_build_object('status', 'failed');
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_tier_pct(p_tiers jsonb, p_conv numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce(
    (select (t->>'pct')::numeric from jsonb_array_elements(p_tiers) t
      where p_conv is not null and (t->>'upto_conv' is null or p_conv < (t->>'upto_conv')::numeric)
      order by coalesce((t->>'upto_conv')::numeric, 1e9) limit 1),
    (p_tiers->0->>'pct')::numeric);
$function$;

CREATE OR REPLACE FUNCTION public.crm_timeline(p_id bigint, p_limit integer DEFAULT 300)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l student_leads; v_phone text;
begin
  select * into l from student_leads where id = p_id and crm_can_see(owner_user_id, is_test, is_sales_ready);
  if l.id is null then raise exception 'lead % not visible', p_id using errcode = '42501'; end if;
  v_phone := regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g');
  return coalesce((select jsonb_agg(x order by (x->>'at') desc) from (
    (select jsonb_build_object('type', 'activity', 'kind', a.kind, 'content', a.content, 'outcome', a.outcome, 'actor', a.actor_name, 'meta', a.meta, 'at', a.created_at) as x
       from crm_activities a where a.lead_id = p_id order by a.created_at desc limit p_limit)
    union all
    (select jsonb_build_object('type', 'task', 'kind', t.kind, 'content', t.title, 'done_at', t.done_at, 'due_at', t.due_at, 'at', coalesce(t.done_at, t.created_at))
       from crm_tasks t where t.lead_id = p_id order by t.created_at desc limit 100)
    union all
    (select jsonb_build_object('type', 'touchpoint', 'kind', tp.event_type, 'content', coalesce(tp.source, tp.source_system), 'source', tp.source, 'campaign', tp.campaign, 'system', tp.source_system, 'at', tp.occurred_at)
       from touchpoints tp where tp.lead_id = p_id order by tp.occurred_at desc limit 100)
    union all
    (select jsonb_build_object('type', 'message', 'kind', m.kind, 'direction', m.direction, 'content', m.content, 'answer_mode', m.answer_mode, 'reply_source', m.reply_source, 'sent', m.sent, 'at', m.created_at)
       from w2_messages m where m.phone = v_phone order by m.created_at desc limit p_limit)
  ) s), '[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_unsubscribe(p_lead bigint, p_token text, p_channel text DEFAULT 'email'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_token is distinct from crm_unsubscribe_token(p_lead) then return false; end if;
  update student_leads set opted_out_channels = (select array_agg(distinct x) from unnest(coalesce(opted_out_channels, '{}'::text[]) || p_channel) x), opted_out_at = coalesce(opted_out_at, now()), last_activity_at = now() where id = p_lead;
  insert into crm_activities (lead_id, kind, content, meta, actor_name) values (p_lead, 'system', 'Unsubscribed from ' || p_channel || ' marketing', jsonb_build_object('channel', p_channel), 'Student');
  return true;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_unsubscribe_token(p_lead bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select left(encode(extensions.hmac(p_lead::text, (select value->>'unsubscribe_secret' from crm_settings where key = 'marketing'), 'sha256'), 'hex'), 24);
$function$;

CREATE OR REPLACE FUNCTION public.crm_update_engine_settings(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform crm_require(array['admin']);
  update crm_settings set value = value || p, updated_at = now() where key = 'engine';
  insert into crm_alerts (kind, message) values ('engine_settings', 'Engine settings changed by ' || coalesce(crm_me()->>'email', 'admin') || ': ' || p::text);
  return (select value from crm_settings where key = 'engine');
end $function$;

CREATE OR REPLACE FUNCTION public.crm_update_lead(p_id bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l student_leads; r jsonb; v_keys text;
begin
  perform crm_require(array['admin','sales_head','sales_manager','marketing','revenue','finance']);
  select * into l from student_leads where id = p_id and crm_can_see(owner_user_id, is_test, is_sales_ready);
  if l.id is null then raise exception 'lead % not visible', p_id using errcode = '42501'; end if;
  r := lead_intake(jsonb_build_object('source_system', 'crm', 'event_type', 'lead.edited', 'phone', l.whatsapp_number, 'lead', p));
  select string_agg(key, ', ' order by key) into v_keys from jsonb_object_keys(p) key;
  insert into crm_activities (lead_id, kind, content, meta, actor_id, actor_name)
  values (p_id, 'system', 'Updated ' || coalesce(v_keys, 'fields'), p, auth.uid(), (crm_me()->>'full_name'));
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.crm_update_scoring(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f jsonb;
begin
  perform crm_require(array['admin', 'marketing']);
  for f in select * from jsonb_array_elements(coalesce(p->'fit', '[]'::jsonb)) loop perform crm_rules_where(coalesce(f->'rules', '[]'::jsonb)); end loop;
  update crm_settings set value = value || p, updated_at = now() where key = 'scoring';
  insert into crm_alerts (kind, message) values ('scoring_rules', 'Lead scoring rules changed by ' || coalesce(crm_me()->>'email', 'admin'));
  return (select value from crm_settings where key = 'scoring');
end $function$;

CREATE OR REPLACE FUNCTION public.crm_update_user(p_user uuid, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform crm_require(array['admin','sales_head']);
  if p ? 'role' and (p->>'role' = 'admin' or crm_role() <> 'admin') then perform crm_require(array['admin']); end if;
  update crm_users set
    full_name   = coalesce(p->>'full_name', full_name),
    role        = coalesce(p->>'role', role),
    is_active   = coalesce((p->>'is_active')::boolean, is_active),
    on_shift    = coalesce((p->>'on_shift')::boolean, on_shift),
    monthly_cap = coalesce((p->>'monthly_cap')::int, monthly_cap),
    monthly_target = coalesce((p->>'monthly_target')::int, monthly_target),
    team_id     = case when p ? 'team_id' then nullif(p->>'team_id', '')::bigint else team_id end,
    languages   = case when p ? 'languages' then array(select jsonb_array_elements_text(p->'languages')) else languages end,
    skills      = case when p ? 'skills' then array(select jsonb_array_elements_text(p->'skills')) else skills end,
    phone       = coalesce(p->>'phone', phone),
    updated_at  = now()
  where id = p_user;
  return (select to_jsonb(u) from crm_users u where u.id = p_user);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_upsert_partner(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r partners; v_id bigint := (p->>'id')::bigint;
begin
  perform crm_require(array['admin','revenue']);
  if v_id is null then
    insert into partners (slug, name, status, adapter_type, api_base_url, outbound_auth, daily_cap, monthly_cap, lead_criteria, sla, contract_min_monthly, notes, created_by)
    values (lower(regexp_replace(coalesce(p->>'slug', p->>'name'), '[^a-zA-Z0-9]+', '_', 'g')), p->>'name', coalesce(p->>'status', 'onboarding'), coalesce(p->>'adapter_type', 'webhook'),
            p->>'api_base_url', coalesce(p->'outbound_auth', '{}'::jsonb), (p->>'daily_cap')::int, (p->>'monthly_cap')::int, coalesce(p->'lead_criteria', '{}'::jsonb),
            coalesce(p->'sla', '{"duplicate_hours":24,"first_contact_hours":2,"status_update_days":7,"proof_days":7}'::jsonb), (p->>'contract_min_monthly')::int, p->>'notes', auth.uid())
    returning * into r;
  else
    update partners set
      name = coalesce(p->>'name', name), status = coalesce(p->>'status', status), adapter_type = coalesce(p->>'adapter_type', adapter_type),
      api_base_url = case when p ? 'api_base_url' then p->>'api_base_url' else api_base_url end,
      outbound_auth = case when p ? 'outbound_auth' then p->'outbound_auth' else outbound_auth end,
      daily_cap = case when p ? 'daily_cap' then (p->>'daily_cap')::int else daily_cap end,
      monthly_cap = case when p ? 'monthly_cap' then (p->>'monthly_cap')::int else monthly_cap end,
      lead_criteria = coalesce(p->'lead_criteria', lead_criteria), sla = coalesce(p->'sla', sla),
      contract_min_monthly = case when p ? 'contract_min_monthly' then (p->>'contract_min_monthly')::int else contract_min_monthly end,
      paused_reason = case when p->>'status' = 'paused' then coalesce(p->>'paused_reason', paused_reason) when p ? 'status' then null else paused_reason end,
      auto_paused_at = case when p->>'status' = 'active' then null else auto_paused_at end,
      notes = coalesce(p->>'notes', notes), updated_at = now()
    where id = v_id returning * into r;
  end if;
  return (select to_jsonb(v) from partners_v v where v.id = r.id);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_verify_check(p_id bigint, p_code text, p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ver verifications; ctx jsonb; r jsonb; l student_leads; v_lead bigint;
begin
  select * into ver from verifications where id = p_id;
  if ver.id is null then return jsonb_build_object('verified', false, 'reason', 'unknown verification'); end if;
  if ver.verified_at is not null then return jsonb_build_object('verified', true, 'lead_id', ver.lead_id, 'already', true); end if;
  if ver.expires_at < now() then return jsonb_build_object('verified', false, 'reason', 'code expired'); end if;
  if ver.attempts >= ver.max_attempts then return jsonb_build_object('verified', false, 'reason', 'too many attempts'); end if;
  update verifications set attempts = attempts + 1 where id = ver.id returning * into ver;
  if ver.code_hash <> encode(extensions.digest(ver.target || ':' || trim(coalesce(p_code, '')), 'sha256'), 'hex') then
    return jsonb_build_object('verified', false, 'reason', 'wrong code', 'attempts_left', ver.max_attempts - ver.attempts);
  end if;
  ctx := ver.context || coalesce(p->'context', '{}'::jsonb);
  if ver.kind = 'phone' then
    r := lead_intake(jsonb_build_object('source_system', 'web_agent', 'event_type', 'lead.verified', 'phone', ver.target,
           'lead', jsonb_strip_nulls(jsonb_build_object('full_name', ctx->>'name', 'email', ctx->>'email', 'city', ctx->>'city', 'interested_course', ctx->>'interested_course',
                     'source', coalesce(ctx->>'source', 'website'), 'campaign', ctx->>'campaign', 'utm_source', ctx->>'utm_source', 'utm_medium', ctx->>'utm_medium', 'utm_campaign', ctx->>'utm_campaign',
                     'landing_url', ctx->>'landing_url', 'referrer_url', ctx->>'referrer', 'consent_sales_at', case when ctx->>'consent_text' is not null then now() end, 'consent_text_version', left(ctx->>'consent_text', 200))),
           'attribution', coalesce(ctx->'attribution', '{}'::jsonb)));
    v_lead := (r->>'lead_id')::bigint;
    update student_leads set phone_verified_at = coalesce(phone_verified_at, now()), phone_verification_method = coalesce(phone_verification_method, coalesce(ctx->>'method', 'sms_otp')) where id = v_lead;
  else
    l := crm_find_lead(crm_norm_phone(coalesce(ctx->>'phone', '')));
    v_lead := coalesce(l.id, (ctx->>'lead_id')::bigint);
    if v_lead is not null then
      update student_leads set email_id = coalesce(nullif(email_id, ''), ver.target), email_verified_at = now(), email_confirmed = true where id = v_lead;
    end if;
  end if;
  update verifications set verified_at = now(), lead_id = v_lead where id = ver.id;
  return jsonb_build_object('verified', true, 'lead_id', v_lead, 'kind', ver.kind, 'intake', r);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_verify_enrollment(p_id bigint, p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e enrollments; v_net numeric; v_pay numeric;
begin
  perform crm_require(array['admin','finance']);
  select * into e from enrollments where id = p_id;
  if e.id is null then raise exception 'enrollment % not found', p_id; end if;
  if e.status <> 'reported' then raise exception 'enrollment % is %', p_id, e.status; end if;
  if p ? 'fee_amount_inr' or p ? 'programme_id' or p ? 'university_id' or p ? 'enrolled_on' or p ? 'fee_paid_inr' then
    perform crm_report_enrollment(e.lead_id, p);
    select * into e from enrollments where id = p_id;
  end if;
  update enrollments set status = 'verified', verified_by = auth.uid(), verified_at = now(), proof_url = coalesce(p->>'proof_url', proof_url), proof_ref = coalesce(p->>'proof_ref', proof_ref), updated_at = now()
   where id = p_id returning * into e;
  update earnings set status = 'realised' where enrollment_id = p_id and status = 'expected';
  update payouts set status = 'confirmed', payable_on = coalesce(payable_on, e.refund_window_ends_on) where enrollment_id = p_id and status = 'provisional';
  select coalesce(sum(net_inr), 0) into v_net from earnings where enrollment_id = p_id and status in ('realised','invoiced','received');
  select coalesce(sum(amount_inr), 0) into v_pay from payouts where enrollment_id = p_id and status in ('confirmed','payable','paid');
  update enrollments set realised_net_revenue_inr = v_net - v_pay, updated_at = now() where id = p_id;
  update student_leads set stage = 'commission_booked', stage_changed_at = now(), enrollment_status = 'verified', enrollment_verified_at = now(),
         realised_net_revenue_inr = v_net - v_pay, last_activity_at = now() where id = e.lead_id;
  insert into crm_activities (lead_id, kind, content, meta, actor_id, actor_name)
  values (e.lead_id, 'system', 'Enrollment verified: commission booked (net ₹' || v_net || ', payout ₹' || v_pay || ')', jsonb_build_object('enrollment_id', p_id, 'proof_ref', e.proof_ref), auth.uid(), crm_me()->>'full_name');
  return jsonb_build_object('enrollment_id', p_id, 'earning_net', v_net, 'payout', v_pay, 'net_revenue', v_net - v_pay);
end $function$;

CREATE OR REPLACE FUNCTION public.crm_verify_start(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s jsonb; v_kind text := lower(coalesce(p->>'kind', 'phone')); v_target text; v_code text; v_id bigint; v_ttl int; v_resend int; n int; v_last timestamptz;
begin
  select value->'otp' into s from crm_settings where key = 'comms';
  v_ttl := coalesce((s->>'ttl_minutes')::int, 10); v_resend := coalesce((s->>'resend_seconds')::int, 30);
  if v_kind = 'phone' then v_target := crm_norm_phone(p->>'target'); else v_target := lower(trim(coalesce(p->>'target', ''))); end if;
  if v_kind = 'phone' and (v_target is null or length(v_target) < 10) then return jsonb_build_object('ok', false, 'reason', 'invalid phone'); end if;
  if v_kind = 'email' and v_target !~ ('^[^@\s]+@[^@\s]+\.[^@\s]+' || chr(36)) then return jsonb_build_object('ok', false, 'reason', 'invalid email'); end if;
  select count(*), max(created_at) into n, v_last from verifications where kind = v_kind and target = v_target and created_at > now() - interval '1 hour';
  if n >= coalesce((s->>'per_target_hour')::int, 3) then return jsonb_build_object('ok', false, 'reason', 'too many codes for this ' || v_kind || ' — try again later', 'retry_after', v_last + interval '1 hour'); end if;
  if v_last is not null and v_last > now() - make_interval(secs => v_resend) then return jsonb_build_object('ok', false, 'reason', 'wait before requesting another code', 'retry_after', v_last + make_interval(secs => v_resend)); end if;
  if p->>'ip' is not null then
    select count(*) into n from verifications where ip = p->>'ip' and created_at > now() - interval '1 hour';
    if n >= coalesce((s->>'per_ip_hour')::int, 10) then return jsonb_build_object('ok', false, 'reason', 'too many requests from this network'); end if;
  end if;
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  insert into verifications (kind, target, code_hash, expires_at, max_attempts, resend_after, ip, context)
  values (v_kind, v_target, encode(extensions.digest(v_target || ':' || v_code, 'sha256'), 'hex'), now() + make_interval(mins => v_ttl), coalesce((s->>'max_attempts')::int, 3),
          now() + make_interval(secs => v_resend), p->>'ip', coalesce(p->'context', '{}'::jsonb)) returning id into v_id;
  return jsonb_build_object('ok', true, 'verification_id', v_id, 'kind', v_kind, 'target', v_target, 'code', v_code, 'expires_at', now() + make_interval(mins => v_ttl), 'resend_after', now() + make_interval(secs => v_resend));
end $function$;

CREATE OR REPLACE FUNCTION public.crm_whatsapp_window(p_lead bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l student_leads; v_phone text; v_last timestamptz; v_hours int; cv w2_conversations;
begin
  select * into l from student_leads where id = p_lead and crm_can_see(owner_user_id, is_test, is_sales_ready);
  if l.id is null then raise exception 'lead % not visible', p_lead using errcode = '42501'; end if;
  v_phone := regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g');
  select coalesce(((value->>'whatsapp_window_hours')::int), 24) into v_hours from crm_settings where key = 'comms';
  select max(created_at) into v_last from w2_messages where phone = v_phone and direction = 'in';
  select * into cv from w2_conversations where phone = v_phone;
  return jsonb_build_object('phone', v_phone, 'last_inbound_at', v_last, 'open', v_last is not null and v_last > now() - make_interval(hours => coalesce(v_hours, 24)),
                            'hours_left', case when v_last is null then 0 else greatest(0, round(extract(epoch from (v_last + make_interval(hours => coalesce(v_hours, 24)) - now())) / 3600, 1)) end,
                            'conversation_id', coalesce(l.chatwoot_conversation_id::text, cv.conversation_id::text), 'account_id', cv.account_id, 'bot_paused', cv.bot_paused, 'opted_out', coalesce(l.is_opted_out, false) or coalesce(cv.opted_out, false));
end $function$;

CREATE OR REPLACE FUNCTION public.current_referral_code()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select referral_code
  from public.influencers
  where auth_uid = auth.uid() and status = 'active'
$function$;

CREATE OR REPLACE FUNCTION public.influencer_dashboard_leads(p_referral_code text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_code  text := trim(coalesce(p_referral_code, ''));
  v_fails int;
  v_ok    boolean;
begin
  if v_code = '' or coalesce(p_password, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  select count(*) into v_fails
    from influencer_login_attempts
   where referral_code = v_code and not ok and at > now() - interval '15 minutes';
  if v_fails >= 5 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  select exists (select 1 from influencer_auth a
                  where a.referral_code = v_code and a.secret_password = p_password)
    into v_ok;
  insert into influencer_login_attempts (referral_code, ok) values (v_code, v_ok);
  if not v_ok then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  return jsonb_build_object('ok', true, 'leads', coalesce((
    select jsonb_agg(jsonb_build_object(
             'student_name',        l.student_name,
             'phone_masked',        case when l.whatsapp_number is null then null
                                         else '••••••' || right(regexp_replace(l.whatsapp_number, '\D', '', 'g'), 4) end,
             'email_masked',        case when l.email_id is null or position('@' in l.email_id) = 0 then null
                                         else left(l.email_id, 1) || '•••@' || split_part(l.email_id, '@', 2) end,
             'lead_status',         l.lead_status,
             'interested_course',   l.interested_course,
             'lead_stage',          l.lead_stage,
             'enrolled_program',    l.enrolled_program,
             'enrolled_university', l.enrolled_university,
             'enrollment_date',     l.enrollment_date,
             'created_at',          l.created_at)
           order by l.created_at desc)
      from student_leads l
     where l.referral_code = v_code
       and l.deleted_at is null and l.merged_into_id is null
       and not coalesce(l.is_test, false)), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(auth.jwt() ->> 'email', '') = 'connect@eduwit.in'
$function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.match_documents(query_embedding vector, match_count integer DEFAULT NULL::integer, filter jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(id bigint, content text, metadata jsonb, similarity double precision)
 LANGUAGE plpgsql
AS $function$
begin
  return query
  select
    course_directory.id,
    course_directory.content,
    course_directory.metadata,
    1 - (course_directory.embedding <=> query_embedding) as similarity
  from course_directory
  where course_directory.metadata @> filter
  order by course_directory.embedding <=> query_embedding
  limit match_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.match_eduwit_knowledge_base(query_embedding vector, match_count integer DEFAULT NULL::integer, filter jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(id bigint, content text, metadata jsonb, similarity double precision)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
begin
  return query
  select
    id,
    content,
    metadata,
    1 - (eduwit_knowledge_base.embedding <=> query_embedding) as similarity
  from eduwit_knowledge_base
  where metadata @> filter
  order by eduwit_knowledge_base.embedding <=> query_embedding
  limit match_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.student_leads_touch()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin new.updated_at := now(); return new; end $function$;

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

CREATE OR REPLACE FUNCTION public.w2_add_source(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_slug  text := lower(regexp_replace(coalesce(p->>'slug', ''), '[^a-zA-Z0-9_-]', '', 'g'));
  v_reuse boolean := coalesce((p->>'allow_reuse')::boolean, false);
  v_code  text;
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
begin
  if v_slug = '' then return jsonb_build_object('error', 'slug is required'); end if;
  insert into w2_sources (slug, name, channel, owner, allow_reuse, active, notes)
  values (v_slug, coalesce(nullif(p->>'name', ''), v_slug), coalesce(nullif(p->>'channel', ''), 'other'), p->>'owner', v_reuse,
          coalesce((p->>'active')::boolean, true), p->>'notes')
  on conflict (slug) do update set name = excluded.name, channel = excluded.channel, owner = coalesce(excluded.owner, w2_sources.owner),
    allow_reuse = excluded.allow_reuse, active = excluded.active, notes = coalesce(excluded.notes, w2_sources.notes);
  select reuse_code into v_code from w2_sources where slug = v_slug;
  if v_reuse and v_code is null then
    loop
      v_bytes := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
      v_code := '';
      for i in 0..5 loop v_code := v_code || substr(v_alpha, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
      begin
        insert into w2_access_codes (code, kind, source, campaign, attribution)
        values (v_code, 'campaign', v_slug, p->>'campaign',
                jsonb_build_object('source', v_slug, 'campaign', p->>'campaign', 'channel', coalesce(nullif(p->>'channel', ''), 'other'), 'kind', 'campaign'));
        exit;
      exception when unique_violation then
      end;
    end loop;
    update w2_sources set reuse_code = v_code where slug = v_slug;
  end if;
  return jsonb_build_object('slug', v_slug, 'campaign_code', case when v_reuse then v_code end);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_bot_check(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
r        jsonb := coalesce((select value from w2_meta where key = 'bot_rules'), '{}'::jsonb);
v_score  int := 0;
v_why    jsonb := '[]'::jsonb;
n        int;
v_level  int;
v_until  timestamptz;
v_inj    text := '(ignore|disregard|forget|override)\s+((all|any|the|your|my|of)\s+)*(previous|prior|above|earlier|system)?\s*(instructions|rules|prompts?|guidelines)|system\s+prompt|you\s+are\s+now\s|developer\s+mode|jailbreak|\[/?inst\]|<\|im_(start|end)\|>|act\s+as\s+(an?\s+)?(ai|assistant|chatgpt|gpt|llm|language model)';
begin
if exists (select 1 from w2_trusted where phone = p_phone) then
return jsonb_build_object('blocked', false, 'score', 0, 'trusted', true);
end if;
select count(*) into n from w2_inbox where phone = p_phone and received_at > now() - make_interval(secs => coalesce((r->>'burst_seconds')::int, 20));
if n >= coalesce((r->>'burst_count')::int, 8) then v_score := v_score + 100; v_why := v_why || jsonb_build_object('signal', 'burst', 'count', n); end if;
select count(*) into n from w2_inbox where phone = p_phone and received_at > now() - make_interval(mins => coalesce((r->>'rate_minutes')::int, 5));
if n >= coalesce((r->>'rate_count')::int, 25) then v_score := v_score + 100; v_why := v_why || jsonb_build_object('signal', 'rate', 'count', n); end if;
select coalesce(max(c), 0) into n from (
select count(*) c from w2_inbox
where phone = p_phone and received_at > now() - make_interval(mins => coalesce((r->>'repeat_minutes')::int, 30))
and length(btrim(coalesce(content, ''))) >= 4
and lower(btrim(content)) !~ '^(hi+|hello+|hey+|ok+|okay|yes|no|thanks?|thank you|hmm+)[\s.!?]*$'
group by lower(regexp_replace(btrim(content), '\s+', ' ', 'g'))) x;
if n >= coalesce((r->>'repeat_count')::int, 4) then v_score := v_score + 100; v_why := v_why || jsonb_build_object('signal', 'repeat', 'count', n); end if;
select count(*) into n from w2_inbox i
where i.phone = p_phone and i.received_at > now() - interval '30 minutes'
and length(coalesce(i.content, '')) >= coalesce((r->>'fast_chars')::int, 150)
and exists (select 1 from w2_messages o where o.phone = p_phone and o.direction = 'out'
and o.created_at between i.received_at - make_interval(secs => coalesce((r->>'fast_seconds')::int, 2)) and i.received_at);
if n >= coalesce((r->>'fast_count')::int, 2) then v_score := v_score + 60; v_why := v_why || jsonb_build_object('signal', 'inhuman_typing_speed', 'count', n); end if;
select count(*) into n from w2_security_log where phone = p_phone and kind = 'bad_code' and created_at > now() - interval '24 hours';
if n >= coalesce((r->>'bad_codes_per_day')::int, 6) then v_score := v_score + 100; v_why := v_why || jsonb_build_object('signal', 'code_guessing', 'count', n); end if;
select count(*) into n from w2_inbox where phone = p_phone and received_at > now() - interval '24 hours' and content ~* v_inj;
if n >= 2 then v_score := v_score + 100; v_why := v_why || jsonb_build_object('signal', 'prompt_injection', 'count', n);
elsif n = 1 then v_score := v_score + 40; v_why := v_why || jsonb_build_object('signal', 'prompt_injection', 'count', n); end if;
select count(*) into n from w2_inbox where phone = p_phone and received_at > now() - make_interval(mins => coalesce((r->>'links_minutes')::int, 10))
and content ~* '(https?://|www\.)';
if n >= coalesce((r->>'links_count')::int, 3) then v_score := v_score + 60; v_why := v_why || jsonb_build_object('signal', 'link_spam', 'count', n); end if;
select count(*) into n from w2_inbox where phone = p_phone and received_at > now() - interval '30 minutes'
and content ~ '^\s*[\{\[].*[\}\]]\s*$' and content ~ '"\s*:';
if n >= 2 then v_score := v_score + 60; v_why := v_why || jsonb_build_object('signal', 'machine_format', 'count', n); end if;
if v_score >= coalesce((r->>'block_score')::int, 100) then
select coalesce(max(level), 0) + 1 into v_level from w2_blocks where phone = p_phone;
v_until := case v_level when 1 then now() + make_interval(hours => coalesce((r->>'first_block_hours')::int, 24))
when 2 then now() + make_interval(hours => coalesce((r->>'second_block_hours')::int, 168))
else null end;
insert into w2_blocks (phone, level, reason, score, evidence, blocked_at, blocked_until, unblocked_at, unblocked_by, note)
values (p_phone, v_level, v_why->0->>'signal', v_score, v_why, now(), v_until, null, null, null)
on conflict (phone) do update set level = excluded.level, reason = excluded.reason, score = excluded.score, evidence = excluded.evidence,
blocked_at = now(), blocked_until = excluded.blocked_until, unblocked_at = null, unblocked_by = null;
insert into w2_security_log (phone, kind, detail) values (p_phone, 'blocked', jsonb_build_object('score', v_score, 'signals', v_why, 'level', v_level, 'until', v_until));
return jsonb_build_object('blocked', true, 'score', v_score, 'signals', v_why, 'level', v_level, 'until', v_until);
end if;
if v_score > 0 then
insert into w2_security_log (phone, kind, detail) values (p_phone, 'suspicious', jsonb_build_object('score', v_score, 'signals', v_why));
end if;
return jsonb_build_object('blocked', false, 'score', v_score, 'signals', v_why);
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.w2_bump(p_key text)
 RETURNS integer
 LANGUAGE sql
AS $function$
insert into w2_meta (key, value) values (p_key, '1'::jsonb)
on conflict (key) do update set value = to_jsonb(coalesce((w2_meta.value #>> '{}')::int, 0) + 1), updated_at = now()
returning (value #>> '{}')::int;
$function$;

CREATE OR REPLACE FUNCTION public.w2_cache_plan(p_model text, p_refresh_minutes integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
v_out jsonb := '[]'::jsonb;
v_name text;
v_text text;
v_hash text;
c w2_gemini_caches;
begin
foreach v_name in array array['extractor', 'counselor'] loop
v_text := w2_build_prompt(v_name);
continue when v_text is null;
v_hash := md5(v_text);
insert into w2_gemini_caches (name) values (v_name) on conflict (name) do nothing;
select * into c from w2_gemini_caches where name = v_name;
update w2_gemini_caches set prompt_text = v_text, updated_at = now() where name = v_name;
if c.cache_name is null or c.prompt_hash is distinct from v_hash or c.model is distinct from p_model
or c.expire_at is null or c.expire_at < now() + make_interval(mins => p_refresh_minutes) then
v_out := v_out || jsonb_build_object('name', v_name, 'hash', v_hash, 'text', v_text, 'old_cache', c.cache_name, 'model', p_model);
end if;
end loop;
return v_out;
end $function$;

CREATE OR REPLACE FUNCTION public.w2_cache_saved(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
begin
if coalesce(p->>'cache_name', '') <> '' then
update w2_gemini_caches set cache_name = p->>'cache_name', model = p->>'model', prompt_hash = p->>'hash',
tokens = (p->>'tokens')::int, expire_at = (p->>'expire_at')::timestamptz, error = null, updated_at = now()
where name = p->>'name';
else
update w2_gemini_caches set error = left(p->>'error', 1000), updated_at = now() where name = p->>'name';
end if;
return jsonb_build_object('name', p->>'name', 'ok', coalesce(p->>'cache_name', '') <> '');
end $function$;

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
$function$;

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
    v_evt := coalesce(p->'outbox'->>'event_type', 'chat.turn');
    v_key := coalesce(p->'outbox'->>'idempotency_key', v_phone || ':turn:' || coalesce(p->>'run_id', ''));
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

CREATE OR REPLACE FUNCTION public.w2_crm_owned(p_phone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce((select l.destination_type is not null or l.owner_user_id is not null
                     from crm_find_lead(p_phone) l where l.id is not null), false);
$function$;

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
    'is_opted_out',         c.opted_out,
    'first_agent_channel',  'whatsapp',
    'chatwoot_conversation_id', c.conversation_id,
    'is_bot_paused',        c.bot_paused,
    'last_agent_message_at', case when coalesce(p->'log'->>'content', '') <> '' then now() end
  ));
  return jsonb_build_object('source_system', 'witty', 'event_type', p_event, 'idempotency_key', p_key, 'phone', p_phone,
                            'lead', v_lead, 'attribution', a, 'occurred_at', coalesce((a->>'first_click_at')::timestamptz, c.created_at),
                            'is_test', w2_is_test(p_phone));
end $function$;

CREATE OR REPLACE FUNCTION public.w2_drive_done(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
begin
  update w2_drive_files set status = case when coalesce((p->>'ok')::boolean, false) then 'synced' else 'error' end,
         synced_at = now(), result = p->'result', error = left(p->>'error', 1000)
   where file_id = p->>'file_id';
  return jsonb_build_object('file_id', p->>'file_id', 'ok', coalesce((p->>'ok')::boolean, false),
    'pending', (select count(*) from w2_drive_files where status = 'pending'));
end $function$;

CREATE OR REPLACE FUNCTION public.w2_drive_kind(p_mime text, p_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when p_mime in ('application/vnd.google-apps.spreadsheet', 'text/csv') or lower(p_name) like '%.csv' then 'catalog'
    when p_mime in ('application/vnd.google-apps.document', 'text/plain', 'text/markdown') or lower(p_name) like '%.txt' or lower(p_name) like '%.md' then 'text'
    when p_mime = 'application/pdf' then 'pdf'
    else 'unsupported' end;
$function$;

CREATE OR REPLACE FUNCTION public.w2_drive_plan(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  f jsonb; v_kind text; r record; v_removed int := 0; v_next jsonb; v_pending int;
begin
  if coalesce((p->>'ok')::boolean, false) is not true or jsonb_typeof(p->'files') <> 'array' then
    return jsonb_build_object('next', null, 'pending', 0, 'removed', 0, 'error', 'folder listing failed');
  end if;
  for f in select * from jsonb_array_elements(p->'files') loop
    continue when f->>'mimeType' = 'application/vnd.google-apps.folder';
    v_kind := w2_drive_kind(f->>'mimeType', f->>'name');
    insert into w2_drive_files as d (file_id, name, mime, kind, modified_at, status, seen_at)
    values (f->>'id', f->>'name', f->>'mimeType', v_kind, (f->>'modifiedTime')::timestamptz,
            case when v_kind = 'unsupported' then 'skipped' else 'pending' end, now())
    on conflict (file_id) do update set name = excluded.name, mime = excluded.mime, kind = excluded.kind, seen_at = now(),
      modified_at = excluded.modified_at,
      status = case when excluded.kind = 'unsupported' then 'skipped'
                    when d.modified_at is distinct from excluded.modified_at or d.status = 'removed' then 'pending'
                    else d.status end;
  end loop;
  for r in select * from w2_drive_files d
            where d.status <> 'removed'
              and not exists (select 1 from jsonb_array_elements(p->'files') x where x->>'id' = d.file_id) loop
    if r.kind = 'catalog' then perform catalog_remove_source('drive:' || r.file_id);
    else perform w2_kb_remove('drive:' || r.file_id); end if;
    update w2_drive_files set status = 'removed', synced_at = now() where file_id = r.file_id;
    v_removed := v_removed + 1;
  end loop;
  select to_jsonb(d) into v_next from w2_drive_files d where status = 'pending' order by modified_at nulls first limit 1;
  select count(*) into v_pending from w2_drive_files where status = 'pending';
  return jsonb_build_object('next', v_next, 'pending', v_pending, 'removed', v_removed);
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.w2_inbox_add(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_id text;
begin
insert into w2_inbox (message_id, phone, conversation_id, account_id, content, content_type, has_attachment, labels)
values (p->>'message_id', p->>'phone', (p->>'conversation_id')::bigint, (p->>'account_id')::bigint, p->>'content',
p->>'content_type', coalesce((p->>'has_attachment')::boolean, false), p->'labels')
on conflict (message_id) do nothing
returning message_id into v_id;
if v_id is not null then
insert into w2_messages (phone, direction, kind, message_id, content, meta)
values (p->>'phone', 'in', 'chat', v_id, p->>'content',
jsonb_build_object('conversation_id', p->>'conversation_id', 'content_type', p->>'content_type', 'has_attachment', coalesce((p->>'has_attachment')::boolean, false)))
on conflict do nothing;
end if;
return jsonb_build_object('inserted', v_id is not null, 'phone', p->>'phone');
end $function$;

CREATE OR REPLACE FUNCTION public.w2_is_blocked(p_phone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
select exists (select 1 from w2_blocks b where b.phone = p_phone and b.unblocked_at is null
and (b.blocked_until is null or b.blocked_until > now()));
$function$;

CREATE OR REPLACE FUNCTION public.w2_is_test(p_phone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(p_phone, '') similar to '910000[0-9]{6}' or exists (select 1 from w2_trusted t where t.phone = p_phone and t.is_test);
$function$;

CREATE OR REPLACE FUNCTION public.w2_issue_code(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
v_src     text := lower(regexp_replace(coalesce(p->>'source', ''), '[^a-zA-Z0-9_-]', '', 'g'));
v_known   boolean := false;
v_reuse   text;
v_click   bigint;
v_code    text;
v_alpha   text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   -- no 0/O or 1/I, so codes survive being retyped
v_bytes   bytea;
v_bot     boolean := coalesce((p->>'is_bot')::boolean, false);
v_via     text := upper(nullif(regexp_replace(coalesce(p->>'via_code', ''), '[^a-zA-Z0-9]', '', 'g'), ''));
v_parent  w2_access_codes;
v_attr    jsonb;
v_reused  boolean := false;
begin
if v_src = '' then v_src := case when v_via is not null then 'shared' else 'organic' end; end if;
v_src := left(v_src, 64);
select true, case when allow_reuse and active then reuse_code end into v_known, v_reuse from w2_sources where slug = v_src;
v_known := coalesce(v_known, false);
insert into w2_clicks (source, source_known, campaign, utm_source, utm_medium, utm_campaign, utm_content, utm_term, click_ids,
referrer, landing_url, via_code, ip, country, user_agent, device_type, os, browser, in_app, language, fingerprint, is_bot)
values (v_src, v_known, left(p->>'campaign', 120), left(p->>'utm_source', 120), left(p->>'utm_medium', 120), left(p->>'utm_campaign', 200),
left(p->>'utm_content', 200), left(p->>'utm_term', 200), nullif(p->'click_ids', '{}'::jsonb), left(p->>'referrer', 500),
left(p->>'landing_url', 1000), v_via, left(p->>'ip', 64), left(p->>'country', 8), left(p->>'user_agent', 500),
p->>'device_type', p->>'os', p->>'browser', p->>'in_app', left(p->>'language', 64), left(p->>'fingerprint', 128), v_bot)
returning id into v_click;
if v_bot then
return jsonb_build_object('code', null, 'bot', true, 'click_id', v_click, 'source', v_src);
end if;
if v_reuse is not null then
v_code := v_reuse;
else
if coalesce(p->>'fingerprint', '') <> '' then
select code into v_code from w2_access_codes
where phone is null and kind = 'personal' and source = v_src and attribution->>'fingerprint' = p->>'fingerprint'
and created_at > now() - interval '24 hours'
order by created_at desc limit 1;
v_reused := v_code is not null;
end if;
if v_code is null then
if v_via is not null then select * into v_parent from w2_access_codes where code = v_via; end if;
v_attr := (p - 'is_bot') || jsonb_build_object('first_click_at', now(), 'click_id', v_click)
|| case when v_parent.code is not null then jsonb_build_object('parent_source', v_parent.source, 'parent_campaign', v_parent.campaign) else '{}'::jsonb end;
loop
v_bytes := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');   -- first 6 bytes of a v4 UUID are random
v_code := '';
for i in 0..5 loop v_code := v_code || substr(v_alpha, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
begin
insert into w2_access_codes (code, kind, source, campaign, click_id, attribution, parent_code, expires_at)
values (v_code, 'personal', v_src, left(coalesce(p->>'campaign', p->>'utm_campaign'), 200), v_click, v_attr, v_parent.code, now() + interval '30 days');
exit;
exception when unique_violation then
end;
end loop;
end if;
end if;
update w2_clicks set code = v_code where id = v_click;
return jsonb_build_object('code', v_code, 'source', v_src, 'known_source', v_known, 'click_id', v_click, 'reused', v_reused, 'campaign_code', v_reuse is not null);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_kb_commit(p_batch text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_doc bigint; n int;
begin
insert into w2_kb_docs (source_file, name, mime, modified_at, active, updated_at)
values (p->>'source_file', p->>'name', p->>'mime', (p->>'modified_at')::timestamptz, true, now())
on conflict (source_file) do update set name = excluded.name, mime = excluded.mime, modified_at = excluded.modified_at, active = true, updated_at = now()
returning id into v_doc;
delete from w2_kb_chunks where doc_id = v_doc;
insert into w2_kb_chunks (doc_id, chunk_no, content, embedding)
select v_doc, coalesce((s.row->>'chunk_no')::int, (row_number() over ())::int), s.row->>'content',
case when jsonb_typeof(s.row->'embedding') = 'array' then (s.row->>'embedding')::vector else null end
from w2_kb_stage s where s.batch = p_batch and coalesce(s.row->>'content', '') <> '';
get diagnostics n = row_count;
update w2_kb_docs set chunks = n where id = v_doc;
delete from w2_kb_stage where batch = p_batch or created_at < now() - interval '1 day';
return jsonb_build_object('doc_id', v_doc, 'source_file', p->>'source_file', 'chunks', n);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_kb_missing(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'content', c.content)), '[]'::jsonb)
from (select c.id, c.content from w2_kb_chunks c join w2_kb_docs d on d.id = c.doc_id and d.active
where c.embedding is null order by c.id limit p_limit) c;
$function$;

CREATE OR REPLACE FUNCTION public.w2_kb_remove(p_source_file text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare n int;
begin
update w2_kb_docs set active = false, updated_at = now() where source_file = p_source_file and active;
get diagnostics n = row_count;
return jsonb_build_object('source_file', p_source_file, 'removed', n);
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.w2_kb_set_embeddings(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare n int;
begin
update w2_kb_chunks c set embedding = (e->>'embedding')::vector
from jsonb_array_elements(coalesce(p->'items', '[]'::jsonb)) e
where c.id = (e->>'id')::bigint and jsonb_typeof(e->'embedding') = 'array';
get diagnostics n = row_count;
return jsonb_build_object('updated', n);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_kb_stage_add(p_batch text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare n int;
begin
insert into w2_kb_stage (batch, row) select p_batch, c from jsonb_array_elements(coalesce(p->'chunks', '[]'::jsonb)) c;
get diagnostics n = row_count;
return jsonb_build_object('batch', p_batch, 'chunks', n);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_learning_apply()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare v_doc bigint; v_alias text;
begin
if new.status = 'approved' and (tg_op = 'INSERT' or old.status is distinct from 'approved') then
new.decided_at := coalesce(new.decided_at, now());
if new.kind = 'synonym' then
v_alias := regexp_replace(lower(coalesce(new.payload->>'alias', '')), '[^a-z0-9]', '', 'g');
if v_alias <> '' and coalesce(new.payload->>'course_key', '') <> '' then
insert into catalog_synonyms (alias, course_key) values (v_alias, new.payload->>'course_key')
on conflict (alias) do update set course_key = excluded.course_key;
delete from w2_search_cache;
new.status := 'applied';
end if;
elsif new.kind = 'faq' and coalesce(new.payload->>'answer', '') <> '' then
insert into w2_kb_docs (source_file, name, mime, active, updated_at)
values ('learned:' || new.id, 'FAQ: ' || left(coalesce(new.payload->>'question', new.title, 'answer'), 200), 'text/faq', true, now())
on conflict (source_file) do update set name = excluded.name, active = true, updated_at = now()
returning id into v_doc;
delete from w2_kb_chunks where doc_id = v_doc;
insert into w2_kb_chunks (doc_id, chunk_no, content)
values (v_doc, 1, 'Q: ' || coalesce(new.payload->>'question', new.title, '') || E'\nA: ' || (new.payload->>'answer'));
update w2_kb_docs set chunks = 1 where id = v_doc;
new.status := 'applied';
elsif new.kind in ('extractor_rule', 'extractor_example', 'intent_phrase', 'counselor_guideline', 'counselor_example') then
perform w2_bump('lessons_version');
end if;
elsif tg_op = 'UPDATE' and new.status in ('rejected', 'retired') and old.status in ('approved', 'applied') then
new.decided_at := now();
if new.kind = 'faq' then update w2_kb_docs set active = false where source_file = 'learned:' || new.id; end if;
if new.kind in ('extractor_rule', 'extractor_example', 'intent_phrase', 'counselor_guideline', 'counselor_example') then perform w2_bump('lessons_version'); end if;
end if;
return new;
end $function$;

CREATE OR REPLACE FUNCTION public.w2_learning_digest(p_hours integer DEFAULT 24, p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_from timestamptz := now() - make_interval(hours => p_hours);
  v_stats jsonb;
  v_cases jsonb;
  v_fb jsonb;
  v_courses jsonb;
  v_questions jsonb;
begin
  select jsonb_build_object(
    'turns', count(*) filter (where type = 'turn'),
    'fallback_replies', count(*) filter (where payload->>'reply_source' = 'fallback'),
    'rewrites', count(*) filter (where payload->>'reply_source' = 'rewrite'),
    'extractor_errors', count(*) filter (where payload->>'extractor_error' is not null),
    'avg_ms', round(avg((payload->>'elapsed_ms')::numeric)),
    'p95_ms', percentile_cont(0.95) within group (order by (payload->>'elapsed_ms')::numeric),
    'modes', (select jsonb_object_agg(m, n) from (select payload->>'answer_mode' m, count(*) n from w2_events where created_at > v_from and type = 'turn' and not w2_is_test(phone) group by 1) x),
    'feedback_good', (select count(*) from w2_feedback where created_at > v_from and rating > 0 and not w2_is_test(phone)),
    'feedback_bad', (select count(*) from w2_feedback where created_at > v_from and rating < 0 and not w2_is_test(phone)),
    'blocked_numbers', (select count(*) from w2_blocks where blocked_at > v_from and not w2_is_test(phone)),
    'cached_token_share', (select round(sum(cached_tokens)::numeric / nullif(sum(prompt_tokens), 0), 3) from w2_messages where created_at > v_from and direction = 'out' and not w2_is_test(phone)))
    into v_stats from w2_events where created_at > v_from and not w2_is_test(phone);

  select coalesce(jsonb_agg(c order by c->>'at'), '[]'::jsonb) into v_cases from (
    select jsonb_build_object(
      'at', e.created_at, 'who', left(md5(e.phone), 8), 'mode', e.payload->>'answer_mode', 'ask', e.payload->>'ask',
      'language', e.payload->>'language', 'reply_source', e.payload->>'reply_source', 'verify_errors', e.payload->'verify_errors',
      'extractor_error', e.payload->>'extractor_error', 'intents', e.payload->'intents',
      'student', regexp_replace(e.payload->>'student_message', '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '<email>', 'g'),
      'witty', regexp_replace(e.payload->>'reply', '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '<email>', 'g'),
      'rejected_facts', (select jsonb_agg(jsonb_build_object('field', f.field, 'value', f.value, 'reason', f.reject_reason))
                           from w2_fact_log f where f.turn_run = e.run_id and not f.accepted),
      'feedback', (select jsonb_agg(jsonb_build_object('rating', fb.rating, 'comment', fb.comment, 'source', fb.source))
                     from w2_feedback fb where fb.phone = e.phone and fb.created_at between e.created_at and e.created_at + interval '2 days')
    ) as c
      from w2_events e
     where e.created_at > v_from and e.type = 'turn' and not w2_is_test(e.phone)
       and (e.payload->>'reply_source' in ('fallback', 'rewrite') or e.payload->>'extractor_error' is not null
            or e.payload->'intents' ?| array['complaint', 'not_interested', 'asks_human']
            or exists (select 1 from w2_fact_log f where f.turn_run = e.run_id and not f.accepted)
            or exists (select 1 from w2_feedback fb where fb.phone = e.phone and fb.rating < 0 and fb.created_at between e.created_at and e.created_at + interval '2 days'))
     order by e.created_at desc limit p_limit) x;

  select coalesce(jsonb_agg(jsonb_build_object('rating', rating, 'source', source, 'comment', comment, 'label', label)), '[]'::jsonb) into v_fb
    from (select * from w2_feedback where created_at > v_from and not w2_is_test(phone) order by created_at desc limit 40) f;

  select coalesce(jsonb_agg(jsonb_build_object('course', course, 'times', n)), '[]'::jsonb) into v_courses from (
    select state->'profile'->'interested_course'->>'value' as course, count(*) n from w2_conversations
     where updated_at > v_from and classification = 'PROGRAM_MISMATCH' and not w2_is_test(phone) group by 1 order by 2 desc limit 20) x;

  select coalesce(jsonb_agg(jsonb_build_object('question', q, 'times', n)), '[]'::jsonb) into v_questions from (
    select left(payload->>'student_message', 200) q, count(*) n from w2_events
     where created_at > v_from and type = 'turn' and payload->>'answer_mode' = 'ANSWER' and not w2_is_test(phone) group by 1 order by 2 desc limit 25) x;

  return jsonb_build_object('window_hours', p_hours, 'from', v_from, 'to', now(), 'stats', v_stats, 'cases', v_cases,
    'feedback', v_fb, 'unmatched_courses', v_courses, 'general_questions', v_questions,
    'known_course_keys', (select jsonb_agg(distinct course_key) from catalog_programs where active),
    'active_lessons', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'title', title)), '[]'::jsonb)
                         from w2_learnings where status in ('approved', 'applied')));
end $function$;

CREATE OR REPLACE FUNCTION public.w2_learning_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
v_report bigint;
x jsonb;
v_status text;
v_auto int := 0;
v_new int := 0;
v_alias text;
begin
insert into w2_learning_reports (window_start, window_end, stats, summary, model, usage)
values ((p->>'from')::timestamptz, (p->>'to')::timestamptz, p->'stats', p->>'summary', p->>'model', p->'usage')
returning id into v_report;
for x in select * from jsonb_array_elements(coalesce(p->'proposals', '[]'::jsonb)) loop
continue when coalesce(x->>'kind', '') = '';
continue when exists (select 1 from w2_learnings l where l.kind = x->>'kind' and l.payload = coalesce(x->'payload', '{}'::jsonb)
and l.status in ('proposed', 'approved', 'applied', 'rejected'));
v_status := 'proposed';
if x->>'kind' = 'synonym' then
v_alias := regexp_replace(lower(coalesce(x->'payload'->>'alias', '')), '[^a-z0-9]', '', 'g');
if v_alias <> '' and exists (select 1 from catalog_programs where active and course_key = x->'payload'->>'course_key')
and coalesce((x->>'confidence')::numeric, 0) >= 0.8 then
v_status := 'approved'; v_auto := v_auto + 1;
end if;
end if;
insert into w2_learnings (report_id, kind, title, payload, rationale, evidence, confidence, status, auto, decided_at, decided_by)
values (v_report, x->>'kind', left(x->>'title', 300), coalesce(x->'payload', '{}'::jsonb), x->>'rationale', x->'evidence',
(x->>'confidence')::numeric, v_status, v_status = 'approved',
case when v_status = 'approved' then now() end, case when v_status = 'approved' then 'auto' end);
v_new := v_new + 1;
end loop;
update w2_feedback set reviewed_at = now() where reviewed_at is null and created_at <= coalesce((p->>'to')::timestamptz, now());
return jsonb_build_object('report_id', v_report, 'proposals', v_new, 'auto_approved', v_auto);
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.w2_nurture_offset(p_step integer)
 RETURNS interval
 LANGUAGE sql
 IMMUTABLE
AS $function$
select case p_step when 1 then interval '3 hours' when 2 then interval '22 hours' when 3 then interval '3 days'
when 4 then interval '7 days' when 5 then interval '15 days' when 6 then interval '30 days' end;
$function$;

CREATE OR REPLACE FUNCTION public.w2_outbox_claim(p_worker text, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v jsonb;
begin
with due as (
select id from w2_outbox
where (status = 'pending' and next_attempt_at <= now())
or (status = 'sending' and next_attempt_at <= now() - interval '5 minutes')
order by id
limit p_limit
for update skip locked
), upd as (
update w2_outbox o set status = 'sending', attempts = o.attempts + 1, locked_by = p_worker, next_attempt_at = now()
from due where o.id = due.id
returning o.*
)
select coalesce(jsonb_agg(to_jsonb(upd) order by upd.id), '[]'::jsonb) into v from upd;
return v;
end $function$;

CREATE OR REPLACE FUNCTION public.w2_outbox_result(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
v_id bigint := (p->>'id')::bigint;
v_ok boolean := coalesce((p->>'ok')::boolean, false);
v_retry boolean := coalesce((p->>'retryable')::boolean, true);
v_attempts int;
v_delays int[] := array[1, 2, 5, 15, 60];
v_status text;
begin
select attempts into v_attempts from w2_outbox where id = v_id;
if v_ok then
update w2_outbox set status = case when p->>'dry_run' = 'true' then 'skipped' else 'sent' end, sent_at = now(),
crm_record_id = p->>'crm_record_id', last_error = null where id = v_id;
if p->>'crm_record_id' is not null then
update w2_conversations c set crm_record_id = p->>'crm_record_id' from w2_outbox o where o.id = v_id and c.phone = o.phone;
end if;
v_status := 'sent';
elsif v_retry and v_attempts < 5 then
update w2_outbox set status = 'pending', last_error = left(p->>'error', 2000),
next_attempt_at = now() + make_interval(mins => v_delays[greatest(1, least(v_attempts, 5))]) where id = v_id;
v_status := 'retry';
else
update w2_outbox set status = 'failed', last_error = left(p->>'error', 2000) where id = v_id;
v_status := 'failed';
end if;
return jsonb_build_object('id', v_id, 'status', v_status, 'attempts', v_attempts);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_outbox_retry(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  j jsonb; r jsonb; v_ok int := 0; v_fail int := 0;
begin
  for j in select * from jsonb_array_elements(w2_outbox_claim('retry-' || to_char(now(), 'YYYYMMDDHH24MISS'), p_limit)) loop
    if j->>'target' <> 'crm' then
      perform w2_outbox_result(jsonb_build_object('id', j->'id', 'ok', false, 'retryable', false, 'error', 'unknown target ' || (j->>'target')));
      v_fail := v_fail + 1; continue;
    end if;
    begin
      r := lead_intake(j->'payload');
      perform w2_outbox_result(jsonb_build_object('id', j->'id', 'ok', true, 'crm_record_id', r->>'lead_id'));
      v_ok := v_ok + 1;
    exception when others then
      perform w2_outbox_result(jsonb_build_object('id', j->'id', 'ok', false, 'retryable', true, 'error', sqlerrm));
      v_fail := v_fail + 1;
    end;
  end loop;
  return jsonb_build_object('delivered', v_ok, 'failed', v_fail);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_parse_rating(p_text text)
 RETURNS smallint
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare t text := lower(btrim(coalesce(p_text, '')));
begin
if length(t) = 0 or length(t) > 30 then return null; end if;
if t ~ '^(👍|🙂|😊|😀|❤|good|great|very good|helpful|very helpful|useful|nice|accha|achha|acha|badhiya|bahut accha|5|4)[\s.!]*$' or t ~ '^👍' then return 1; end if;
if t ~ '^(👎|🙁|😞|😠|bad|not good|not helpful|unhelpful|not useful|useless|bekar|bakwas|1|2)[\s.!]*$' or t ~ '^👎' then return -1; end if;
if t ~ '^(3|ok|okay|average|theek|thik)[\s.!]*$' then return 0; end if;
return null;
end $function$;

CREATE OR REPLACE FUNCTION public.w2_pv(pr jsonb, f text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when pr->f->>'status' = 'declined' then null else nullif(pr->f->>'value', '') end;
$function$;

CREATE OR REPLACE FUNCTION public.w2_redeem_code(p_phone text, p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
v_phone  text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
v_text   text := coalesce(p_text, '');
v_cands  text[] := '{}';
v_c      text;
r        w2_access_codes;
v_status text := 'none';
v_bad    text;
v_leg    record;
v_said   boolean := true;   -- the student said "access code ..." (a bare 6-letter word may just be a word)
begin
-- Hermes test agent (Chatwoot API contacts +91 90000 000NN, not on WhatsApp): no access code needed. Added 4 Oct 2026.
if v_phone ~ '^9190000000[0-9]{2}$' then
return jsonb_build_object('status', 'ok', 'via', 'test_hermes', 'code', 'HERMES', 'kind', 'test', 'source', 'test_hermes',
'attribution', jsonb_build_object('code', 'HERMES', 'kind', 'test', 'source', 'test_hermes'));
end if;
select coalesce(array_agg(distinct upper(m[1])), '{}') into v_cands
from regexp_matches(v_text, '(?:access|activation)\s*code\s*(?:is|:|-)?\s*\m([A-Za-z0-9]{6})\M', 'gi') m;
if cardinality(v_cands) = 0 then
v_said := false;
select coalesce(array_agg(distinct upper(m[1])), '{}') into v_cands
from regexp_matches(v_text, '(?:^|\n)\s*([A-Za-z0-9]{6})\s*[.!]?\s*(?:$|\n)', 'g') m;
end if;
foreach v_c in array v_cands loop
select * into r from w2_access_codes where code = v_c for update;
if found then
if r.kind = 'campaign' or r.phone = v_phone then
update w2_access_codes set redeem_count = redeem_count + 1, last_redeemed_at = now() where code = v_c;
return jsonb_build_object('status', 'ok', 'via', 'code', 'code', v_c, 'kind', r.kind, 'source', r.source, 'campaign', r.campaign,
'attribution', r.attribution || jsonb_build_object('code', v_c, 'kind', r.kind));
elsif r.phone is null and (r.expires_at is null or r.expires_at > now()) then
update w2_access_codes set phone = v_phone, bound_at = now(), redeem_count = redeem_count + 1, last_redeemed_at = now() where code = v_c;
return jsonb_build_object('status', 'ok', 'via', 'code', 'code', v_c, 'kind', r.kind, 'source', r.source, 'campaign', r.campaign,
'attribution', r.attribution || jsonb_build_object('code', v_c, 'kind', r.kind));
elsif r.phone is null then
v_status := 'expired'; v_bad := v_c;
else
v_status := 'taken'; v_bad := v_c;
end if;
else
begin
select referral_code into v_leg from student_leads where upper(activation_code) = v_c order by created_at desc limit 1;
if found then
return jsonb_build_object('status', 'ok', 'via', 'legacy_code', 'code', v_c, 'kind', 'legacy', 'source', coalesce(nullif(v_leg.referral_code, ''), 'legacy'),
'attribution', jsonb_build_object('code', v_c, 'kind', 'legacy', 'legacy_referral', v_leg.referral_code));
end if;
exception when others then null;
end;
if v_status = 'none' and v_said then v_status := 'invalid'; v_bad := v_c; end if;
end if;
end loop;
select * into r from w2_access_codes where phone = v_phone order by bound_at desc limit 1;
if found then
return jsonb_build_object('status', 'ok', 'via', 'returning', 'code', r.code, 'kind', r.kind, 'source', r.source, 'campaign', r.campaign,
'attribution', r.attribution || jsonb_build_object('code', r.code, 'kind', r.kind));
end if;
begin
select activation_code, referral_code into v_leg from student_leads
where regexp_replace(coalesce(whatsapp_number, ''), '\D', '', 'g') = v_phone order by created_at desc limit 1;
if found then
return jsonb_build_object('status', 'ok', 'via', 'legacy_phone', 'code', upper(v_leg.activation_code), 'kind', 'legacy',
'source', coalesce(nullif(v_leg.referral_code, ''), 'legacy'),
'attribution', jsonb_build_object('code', upper(v_leg.activation_code), 'kind', 'legacy', 'legacy_referral', v_leg.referral_code));
end if;
exception when others then null;
end;
return jsonb_build_object('status', v_status, 'code', v_bad);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_register_lead(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_phone text := regexp_replace(coalesce(p->>'phone', ''), '\D', '', 'g');
  v_src   text := lower(regexp_replace(coalesce(nullif(p->>'source', ''), 'organic'), '[^a-zA-Z0-9_-]', '', 'g'));
  v_old   w2_access_codes;
  v_click bigint;
  v_code  text;
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea;
  v_attr  jsonb;
begin
  if length(v_phone) = 10 then v_phone := '91' || v_phone; end if;   -- bare Indian mobile number
  if length(v_phone) < 11 then return jsonb_build_object('error', 'phone with country code is required'); end if;
  insert into w2_clicks (source, source_known, campaign, utm_source, utm_medium, utm_campaign, utm_content, utm_term, click_ids, referrer, landing_url, is_bot)
  values (v_src, exists (select 1 from w2_sources where slug = v_src), left(p->>'campaign', 120), left(p->>'utm_source', 120), left(p->>'utm_medium', 120),
          left(p->>'utm_campaign', 200), left(p->>'utm_content', 200), left(p->>'utm_term', 200), nullif(p->'click_ids', '{}'::jsonb),
          left(p->>'referrer', 500), left(p->>'landing_url', 1000), false)
  returning id into v_click;
  select * into v_old from w2_access_codes where phone = v_phone and kind = 'personal' order by bound_at limit 1;
  if found then
    update w2_clicks set code = v_old.code where id = v_click;
    return jsonb_build_object('code', v_old.code, 'phone', v_phone, 'source', v_old.source, 'already_registered', true, 'click_id', v_click);
  end if;
  v_attr := (p - 'phone' - 'name') || jsonb_build_object('source', v_src, 'first_click_at', now(), 'click_id', v_click, 'registered', true);
  loop
    v_bytes := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
    v_code := '';
    for i in 0..5 loop v_code := v_code || substr(v_alpha, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
    begin
      insert into w2_access_codes (code, kind, source, campaign, click_id, attribution, created_at, expires_at, phone, bound_at)
      values (v_code, 'personal', v_src, left(coalesce(p->>'campaign', p->>'utm_campaign'), 200), v_click, v_attr, now(), now() + interval '30 days', v_phone, now());
      exit;
    exception when unique_violation then
    end;
  end loop;
  update w2_clicks set code = v_code where id = v_click;
  return jsonb_build_object('code', v_code, 'phone', v_phone, 'source', v_src, 'already_registered', false, 'click_id', v_click);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_release(p_phone text, p_run text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare v_pending int;
begin
update w2_conversations set lock_id = null, lock_until = null where phone = p_phone and lock_id = p_run;
select count(*) into v_pending from w2_inbox where phone = p_phone and processed_at is null;
return v_pending;
end $function$;

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
end $function$;

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
end $function$;

CREATE OR REPLACE FUNCTION public.w2_source_report(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  with c as (
    select source, coalesce(campaign, utm_campaign) as campaign, count(*) filter (where not is_bot) as clicks,
           count(*) filter (where is_bot) as bot_clicks, count(code) filter (where not is_bot) as codes
      from w2_clicks where created_at > now() - make_interval(days => p_days) group by 1, 2
  ), v as (
    select lead_source as source, attribution->>'campaign' as campaign, count(*) as chats,
           count(*) filter (where classification in ('HOT', 'WARM', 'COLD')) as qualified,
           count(*) filter (where classification = 'HOT') as hot,
           count(*) filter (where classification in ('UNQUALIFIED', 'PROGRAM_MISMATCH')) as nurturing
      from w2_conversations where access_at > now() - make_interval(days => p_days) group by 1, 2
  )
  select coalesce(jsonb_agg(jsonb_build_object('source', coalesce(c.source, v.source), 'campaign', coalesce(c.campaign, v.campaign),
           'clicks', coalesce(c.clicks, 0), 'bot_clicks', coalesce(c.bot_clicks, 0), 'codes', coalesce(c.codes, 0), 'chats', coalesce(v.chats, 0),
           'qualified', coalesce(v.qualified, 0), 'hot', coalesce(v.hot, 0), 'nurturing', coalesce(v.nurturing, 0))
           order by coalesce(v.chats, 0) desc, coalesce(c.clicks, 0) desc), '[]'::jsonb)
    from c full join v on c.source = v.source and c.campaign is not distinct from v.campaign;
$function$;

CREATE OR REPLACE FUNCTION public.w2_stale_inbox(p_older_than_seconds integer DEFAULT 40)
 RETURNS TABLE(phone text)
 LANGUAGE sql
 STABLE
AS $function$
select distinct i.phone
from w2_inbox i join w2_conversations c on c.phone = i.phone
where i.processed_at is null
and i.received_at < now() - make_interval(secs => p_older_than_seconds)
and (c.lock_until is null or c.lock_until < now())
and not c.opted_out
limit 50;
$function$;

CREATE OR REPLACE FUNCTION public.w2_test_prepare(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  p_phone text := p->>'phone';
  v_reset jsonb;
  v_reg   jsonb;
begin
  v_reset := w2_test_reset(p_phone);
  if coalesce((p->>'trusted')::boolean, true) then
    insert into w2_trusted (phone, note, is_test) values (p_phone, 'test harness', true)
    on conflict (phone) do update set is_test = true, note = 'test harness';
  else
    delete from w2_trusted where phone = p_phone;
  end if;
  if coalesce((p->>'with_access')::boolean, true) then
    v_reg := w2_register_lead(jsonb_build_object('phone', p_phone, 'source', 'test_harness', 'campaign', coalesce(p->>'run_tag', 'test')));
  end if;
  return jsonb_build_object('phone', p_phone, 'reset', v_reset, 'access', v_reg);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_test_reset(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare n jsonb := '{}'::jsonb; c int;
begin
  if not (coalesce(p_phone, '') similar to '910000[0-9]{6}') then
    raise exception 'w2_test_reset: % is not a test phone (must be 910000 followed by 6 digits)', p_phone;
  end if;
  delete from w2_inbox where phone = p_phone;          get diagnostics c = row_count; n := n || jsonb_build_object('inbox', c);
  delete from w2_messages where phone = p_phone;       get diagnostics c = row_count; n := n || jsonb_build_object('messages', c);
  delete from w2_events where phone = p_phone;         get diagnostics c = row_count; n := n || jsonb_build_object('events', c);
  delete from w2_fact_log where phone = p_phone;
  delete from w2_outbox where phone = p_phone;
  delete from w2_feedback where phone = p_phone;
  delete from w2_nurture_log where phone = p_phone;
  delete from w2_security_log where phone = p_phone;
  delete from w2_blocks where phone = p_phone;
  delete from w2_access_codes where phone = p_phone;
  delete from w2_conversations where phone = p_phone;
  delete from student_leads where whatsapp_number = p_phone and is_test;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.w2_test_result(p_phone text, p_since timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select jsonb_build_object(
    'replies', coalesce((select jsonb_agg(jsonb_build_object('content', m.content, 'kind', m.kind, 'answer_mode', m.answer_mode,
                                'reply_source', m.reply_source, 'latency_ms', m.latency_ms, 'prompt_tokens', m.prompt_tokens,
                                'cached_tokens', m.cached_tokens, 'output_tokens', m.output_tokens, 'verify_errors', m.verify_errors,
                                'sent', m.sent) order by m.id)
                         from w2_messages m where m.phone = p_phone and m.direction = 'out' and m.created_at >= p_since), '[]'::jsonb),
    'event', (select e.payload from w2_events e where e.phone = p_phone and e.type = 'turn' and e.created_at >= p_since order by e.id desc limit 1),
    'handoff', exists (select 1 from w2_events e where e.phone = p_phone and e.type = 'handoff' and e.created_at >= p_since),
    'facts', coalesce((select jsonb_agg(jsonb_build_object('field', f.field, 'value', f.value, 'accepted', f.accepted, 'reason', f.reject_reason))
                       from w2_fact_log f where f.phone = p_phone and f.created_at >= p_since), '[]'::jsonb),
    'state', (select jsonb_build_object('classification', c.classification, 'readiness', c.readiness, 'eligibility', c.eligibility,
                                         'pending_question', c.pending_question, 'bot_paused', c.bot_paused, 'opted_out', c.opted_out,
                                         'profile', c.state->'profile')
                from w2_conversations c where c.phone = p_phone),
    'blocked', w2_is_blocked(p_phone),
    'pending_inbox', (select count(*) from w2_inbox i where i.phone = p_phone and i.processed_at is null));
$function$;

CREATE OR REPLACE FUNCTION public.w2_test_send(p_phone text, p_text text, p_tag text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_id text := 'test-' || coalesce(p_tag, 'run') || '-' || replace(gen_random_uuid()::text, '-', '');
        v_at timestamptz := clock_timestamp();
begin
  if not (coalesce(p_phone, '') similar to '910000[0-9]{6}') then raise exception 'w2_test_send: % is not a test phone', p_phone; end if;
  return w2_inbox_add(jsonb_build_object('message_id', v_id, 'phone', p_phone, 'content', p_text, 'content_type', 'text', 'has_attachment', false))
         || jsonb_build_object('message_id', v_id, 'sent_at', v_at);
end $function$;

CREATE OR REPLACE FUNCTION public.w2_test_step(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_prep jsonb; v_sent jsonb;
begin
  if coalesce((p->>'first')::boolean, false) then
    v_prep := w2_test_prepare(p);
  end if;
  v_sent := w2_test_send(p->>'phone', coalesce(p->>'text', ''), p->>'tag');
  return p || jsonb_build_object('prep', v_prep, 'message_id', v_sent->>'message_id', 'sent_at', v_sent->>'sent_at', 'inserted', v_sent->'inserted');
end $function$;

CREATE OR REPLACE FUNCTION public.w2_test_transcript(p_phone text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('role', case when direction = 'in' then 'student' else 'witty' end, 'text', content) order by id), '[]'::jsonb)
    from w2_messages where phone = p_phone and content is not null;
$function$;

CREATE OR REPLACE FUNCTION public.w2_try_claim(p_phone text, p_run text, p_lease_seconds integer DEFAULT 45)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_conv   w2_conversations;
  v_msgs   jsonb;
  v_text   text;
  v_access jsonb;
  v_bot    jsonb;
  v_rating smallint;
  v_ids    text[];
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
    return jsonb_build_object('acquired', true, 'crm_paused', true, 'conversation', to_jsonb(v_conv), 'messages', '[]'::jsonb);
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

  -- 3. Access code gate.
  if v_conv.access_code is not null then
    v_access := jsonb_build_object('status', 'verified', 'code', v_conv.access_code, 'source', v_conv.lead_source, 'attribution', v_conv.attribution);
  else
    v_access := w2_redeem_code(p_phone, v_text);
    if v_access->>'status' = 'ok' then
      update w2_conversations
         set access_code = coalesce(v_access->>'code', 'LEGACY'), access_at = now(), lead_source = v_access->>'source',
             attribution = v_access->'attribution'
       where phone = p_phone
      returning * into v_conv;
    elsif v_access->>'status' in ('invalid', 'taken', 'expired') then
      insert into w2_security_log (phone, kind, detail) values (p_phone, 'bad_code', jsonb_build_object('status', v_access->>'status', 'code', v_access->>'code'));
    end if;
  end if;

  return jsonb_build_object('acquired', true, 'conversation', to_jsonb(v_conv), 'messages', v_msgs, 'access', v_access,
                            'activation_code', v_access->>'code', 'lead_source', v_conv.lead_source, 'prompts', w2_turn_prompts(),
                            'kb_ready', exists (select 1 from w2_kb_docs d where d.active and d.chunks > 0));
end $function$;

CREATE OR REPLACE FUNCTION public.w2_turn_prompts()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$ select coalesce(jsonb_object_agg(name, jsonb_strip_nulls(jsonb_build_object('cache', case when cache_name is not null and expire_at > now() + interval '3 minutes' then cache_name end, 'model', case when cache_name is not null and expire_at > now() + interval '3 minutes' then model end, 'text', prompt_text))), '{}'::jsonb) from w2_gemini_caches; $function$;

CREATE OR REPLACE FUNCTION public.w2_unblock(p_phone text, p_by text DEFAULT 'staff'::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
update w2_blocks set unblocked_at = now(), unblocked_by = p_by, note = p_note where phone = v and unblocked_at is null;
insert into w2_security_log (phone, kind, detail) values (v, 'unblocked', jsonb_build_object('by', p_by, 'note', p_note));
return jsonb_build_object('phone', v, 'unblocked', found);
end $function$;

create or replace view public.influencer_leads_dashboard as
 SELECT l.student_name,
    l.whatsapp_number,
    l.email_id,
    l.ip_address,
    l.lead_status,
    l.interested_course,
    l.lead_stage,
    l.enrolled_program,
    l.enrolled_university,
    l.enrollment_date,
    l.referral_code,
    a.secret_password
   FROM student_leads l
     JOIN influencer_auth a ON l.referral_code = a.referral_code;

create or replace view public.w2_latency_daily as
 SELECT date_trunc('day'::text, created_at) AS day,
    count(*) AS replies,
    round(avg(latency_ms)) AS avg_ms,
    percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (latency_ms::double precision)) AS p50_ms,
    percentile_cont(0.95::double precision) WITHIN GROUP (ORDER BY (latency_ms::double precision)) AS p95_ms,
    round(sum(cached_tokens)::numeric / NULLIF(sum(prompt_tokens), 0)::numeric, 3) AS cached_share
   FROM w2_messages
  WHERE direction = 'out'::text AND kind = 'reply'::text AND latency_ms IS NOT NULL AND NOT w2_is_test(phone)
  GROUP BY (date_trunc('day'::text, created_at))
  ORDER BY (date_trunc('day'::text, created_at)) DESC;

create or replace view public.student_leads_v with (security_invoker=true) as
 SELECT id,
    created_at,
    whatsapp_number AS phone,
    alternate_phone,
    student_name AS full_name,
    email_id AS email,
    preferred_language,
    city,
    state,
    country,
    current_city_country AS location_raw,
    enquirer_relation,
    guardian_name,
    guardian_phone,
    phone_verified_at,
    phone_verification_method,
    email_verified_at,
    name_confirmed AS is_name_confirmed,
    email_confirmed AS is_email_confirmed,
    interested_course,
    interested_specialization,
    field_of_interest,
    interested_university,
    university_preference,
    program_level AS programme_level,
    study_mode_preference,
    highest_qualification,
    current_study,
    academic_percentage_gpa AS academic_score_raw,
    academic_score_pct,
    work_experience_years AS work_experience_raw,
    work_experience_years_num,
    current_job_role,
    annual_budget AS annual_budget_raw,
    annual_budget_inr,
    enrollment_timeline,
    primary_motivation,
    preferred_counseling_time AS preferred_call_time,
    programme_segment,
    lead_status AS classification,
    lead_classification AS classification_ai,
    admission_readiness AS readiness,
    eligibility_status AS eligibility,
    lead_stage AS conversation_phase,
    intent_type AS last_intent,
    extraction_confidence AS ai_extraction_confidence,
    lead_source AS source,
    channel,
    source_detail,
    campaign,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,
    click_ids,
    landing_url,
    referrer_url,
    referral_code,
    referred_by_code,
    publisher_id,
    activation_code AS access_code,
    first_touch_at,
    last_touch_at,
    last_touch_source,
    ip_address,
    device AS device_type,
    fingerprint AS device_fingerprint,
    consent_sales_at,
    consent_marketing_at,
    consent_partner_share_at,
    consent_text_version,
    is_opted_out,
    opted_out_at,
    opted_out_channels,
    email_bounced_at,
    stage,
    sub_stage,
    stage_changed_at,
    temperature,
    lead_score,
    is_sales_ready,
    sales_ready_at,
    owner_user_id,
    team_id,
    assigned_at,
    first_contacted_at,
    last_contacted_at,
    last_activity_at,
    contact_attempts,
    next_task_due_at,
    lost_reason,
    lost_at,
    cycle_no,
    reopened_at,
    is_duplicate_suspect,
    merged_into_id,
    "Comments" AS notes,
    destination_type,
    partner_id,
    allocation_id,
    allocated_at,
    allocation_reason,
    partner_record_id,
    partner_stage_raw,
    partner_sub_stage_raw,
    partner_synced_at,
    duplicate_claim_count,
    application_id,
    application_status,
    applied_at,
    fee_amount_inr,
    fee_paid_inr,
    enrolled_university,
    enrolled_program AS enrolled_programme,
    enrollment_date AS enrolled_on,
    enrollment_status,
    enrollment_verified_at,
    expected_net_revenue_inr,
    realised_net_revenue_inr,
    active_journey_id,
    last_campaign_id,
    last_marketing_message_at,
    first_agent_channel,
    chatwoot_conversation_id,
    web_session_id,
    is_bot_paused,
    last_agent_message_at,
    portal_user_id,
    open_ticket_count,
    custom_fields,
    zoho_lead_id,
    is_hot_sent_to_crm AS is_pushed_to_zoho,
    is_test,
    updated_at,
    updated_by,
    deleted_at,
    anonymised_at
   FROM student_leads;

create or replace view public.w2_fee_review as
 SELECT p.id,
    u.name AS university,
    p.program_name,
    p.mode,
    p.level,
    p.source_row,
    p.fee_other -> 'as_imported'::text AS as_imported,
    jsonb_build_object('fee_yearly', p.fee_yearly, 'fee_semester', p.fee_semester, 'fee_total', p.fee_total) AS now_used,
    ( SELECT string_agg(f.f, '; '::text) AS string_agg
           FROM unnest(p.flags) f(f)
          WHERE f.f ~~ 'fee check:%'::text) AS reason
   FROM catalog_programs p
     JOIN catalog_universities u ON u.id = p.university_id
  WHERE p.active AND (EXISTS ( SELECT 1
           FROM unnest(p.flags) f(f)
          WHERE f.f ~~ 'fee check:%'::text));

create or replace view public.crm_leads_v with (security_invoker=true) as
 SELECT v.id,
    v.created_at,
    v.phone,
    v.alternate_phone,
    v.full_name,
    v.email,
    v.preferred_language,
    v.city,
    v.state,
    v.country,
    v.location_raw,
    v.enquirer_relation,
    v.guardian_name,
    v.guardian_phone,
    v.phone_verified_at,
    v.phone_verification_method,
    v.email_verified_at,
    v.is_name_confirmed,
    v.is_email_confirmed,
    v.interested_course,
    v.interested_specialization,
    v.field_of_interest,
    v.interested_university,
    v.university_preference,
    v.programme_level,
    v.study_mode_preference,
    v.highest_qualification,
    v.current_study,
    v.academic_score_raw,
    v.academic_score_pct,
    v.work_experience_raw,
    v.work_experience_years_num,
    v.current_job_role,
    v.annual_budget_raw,
    v.annual_budget_inr,
    v.enrollment_timeline,
    v.primary_motivation,
    v.preferred_call_time,
    v.programme_segment,
    v.classification,
    v.classification_ai,
    v.readiness,
    v.eligibility,
    v.conversation_phase,
    v.last_intent,
    v.ai_extraction_confidence,
    v.source,
    v.channel,
    v.source_detail,
    v.campaign,
    v.utm_source,
    v.utm_medium,
    v.utm_campaign,
    v.utm_content,
    v.utm_term,
    v.click_ids,
    v.landing_url,
    v.referrer_url,
    v.referral_code,
    v.referred_by_code,
    v.publisher_id,
    v.access_code,
    v.first_touch_at,
    v.last_touch_at,
    v.last_touch_source,
    v.ip_address,
    v.device_type,
    v.device_fingerprint,
    v.consent_sales_at,
    v.consent_marketing_at,
    v.consent_partner_share_at,
    v.consent_text_version,
    v.is_opted_out,
    v.opted_out_at,
    v.opted_out_channels,
    v.email_bounced_at,
    v.stage,
    v.sub_stage,
    v.stage_changed_at,
    v.temperature,
    v.lead_score,
    v.is_sales_ready,
    v.sales_ready_at,
    v.owner_user_id,
    v.team_id,
    v.assigned_at,
    v.first_contacted_at,
    v.last_contacted_at,
    v.last_activity_at,
    v.contact_attempts,
    v.next_task_due_at,
    v.lost_reason,
    v.lost_at,
    v.cycle_no,
    v.reopened_at,
    v.is_duplicate_suspect,
    v.merged_into_id,
    v.notes,
    v.destination_type,
    v.partner_id,
    v.allocation_id,
    v.allocated_at,
    v.allocation_reason,
    v.partner_record_id,
    v.partner_stage_raw,
    v.partner_sub_stage_raw,
    v.partner_synced_at,
    v.duplicate_claim_count,
    v.application_id,
    v.application_status,
    v.applied_at,
    v.fee_amount_inr,
    v.fee_paid_inr,
    v.enrolled_university,
    v.enrolled_programme,
    v.enrolled_on,
    v.enrollment_status,
    v.enrollment_verified_at,
    v.expected_net_revenue_inr,
    v.realised_net_revenue_inr,
    v.active_journey_id,
    v.last_campaign_id,
    v.last_marketing_message_at,
    v.first_agent_channel,
    v.chatwoot_conversation_id,
    v.web_session_id,
    v.is_bot_paused,
    v.last_agent_message_at,
    v.portal_user_id,
    v.open_ticket_count,
    v.custom_fields,
    v.zoho_lead_id,
    v.is_pushed_to_zoho,
    v.is_test,
    v.updated_at,
    v.updated_by,
    v.deleted_at,
    v.anonymised_at,
        CASE
            WHEN crm_masks() THEN crm_mask_phone(v.phone)
            ELSE v.phone
        END AS phone_masked,
        CASE
            WHEN crm_masks() THEN crm_mask_email(v.email)
            ELSE v.email
        END AS email_masked,
    u.full_name AS owner_name,
    t.title AS next_task_title,
    ( SELECT count(*) AS count
           FROM crm_tasks x
          WHERE x.lead_id = v.id AND x.done_at IS NULL) AS open_tasks,
    v.next_task_due_at IS NOT NULL AND v.next_task_due_at < now() AND (v.stage <> ALL (ARRAY['enrolled'::text, 'verified'::text, 'commission_booked'::text, 'paid'::text, 'lost'::text])) AS is_overdue
   FROM student_leads_v v
     LEFT JOIN crm_users u ON u.id = v.owner_user_id
     LEFT JOIN LATERAL ( SELECT x.title
           FROM crm_tasks x
          WHERE x.lead_id = v.id AND x.done_at IS NULL
          ORDER BY x.due_at
         LIMIT 1) t ON true;

create or replace view public.partners_v with (security_invoker=true) as
 SELECT id,
    slug,
    name,
    status,
    adapter_type,
    api_base_url,
    outbound_auth ->> 'header'::text AS outbound_auth_header,
    inbound_secret IS NOT NULL AS has_inbound_secret,
    daily_cap,
    monthly_cap,
    lead_criteria,
    sla,
    contract_min_monthly,
    paused_reason,
    auto_paused_at,
    notes,
    created_at,
    updated_at
   FROM partners;

do $at$ begin
  CREATE TRIGGER crm_on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION crm_handle_new_auth_user();
exception when others then raise warning 'auth.users trigger not created: %', sqlerrm;
end $at$;
CREATE TRIGGER catalog_programs_fee_check_trg BEFORE INSERT OR UPDATE ON public.catalog_programs FOR EACH ROW EXECUTE FUNCTION catalog_programs_fee_check();
CREATE TRIGGER crm_auto_assign AFTER UPDATE OF is_sales_ready ON public.student_leads FOR EACH ROW WHEN ((new.is_sales_ready AND (NOT COALESCE(old.is_sales_ready, false)) AND (new.owner_user_id IS NULL) AND (new.destination_type IS NULL) AND (NOT new.is_test))) EXECUTE FUNCTION crm_auto_assign_trg();
CREATE TRIGGER student_leads_bulk_delete_guard AFTER DELETE ON public.student_leads REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION student_leads_bulk_delete_guard();
CREATE TRIGGER student_leads_touch_trg BEFORE UPDATE ON public.student_leads FOR EACH ROW EXECUTE FUNCTION student_leads_touch();
CREATE TRIGGER student_leads_truncate_guard BEFORE TRUNCATE ON public.student_leads FOR EACH STATEMENT EXECUTE FUNCTION student_leads_bulk_delete_guard();
CREATE TRIGGER w2_learning_apply_trg BEFORE INSERT OR UPDATE OF status ON public.w2_learnings FOR EACH ROW EXECUTE FUNCTION w2_learning_apply();

do $et$ begin
  create event trigger ensure_rls on ddl_command_end execute function rls_auto_enable();
exception when others then raise warning 'event trigger ensure_rls not created: %', sqlerrm;
end $et$;

alter table public.allocations enable row level security;
alter table public.calls enable row level security;
alter table public.campaign_sends enable row level security;
alter table public.campaigns enable row level security;
alter table public.catalog_programs enable row level security;
alter table public.catalog_stage enable row level security;
alter table public.catalog_synonyms enable row level security;
alter table public.catalog_universities enable row level security;
alter table public.conversation_locks enable row level security;
alter table public.course_directory enable row level security;
alter table public.crm_activities enable row level security;
alter table public.crm_alerts enable row level security;
alter table public.crm_api_keys enable row level security;
alter table public.crm_notifications enable row level security;
alter table public.crm_saved_views enable row level security;
alter table public.crm_settings enable row level security;
alter table public.crm_tasks enable row level security;
alter table public.crm_teams enable row level security;
alter table public.crm_university_settings enable row level security;
alter table public.crm_users enable row level security;
alter table public.earning_rates enable row level security;
alter table public.earnings enable row level security;
alter table public.eduwit_knowledge_base enable row level security;
alter table public.engine_decisions enable row level security;
alter table public.enrollments enable row level security;
alter table public.influencer_auth enable row level security;
alter table public.influencer_login_attempts enable row level security;
alter table public.influencers enable row level security;
alter table public.invoices enable row level security;
alter table public.journey_runs enable row level security;
alter table public.journeys enable row level security;
alter table public.message_templates enable row level security;
alter table public.n8n_chat_histories enable row level security;
alter table public.partner_events enable row level security;
alter table public.partner_mapping_profiles enable row level security;
alter table public.partners enable row level security;
alter table public.payout_rates enable row level security;
alter table public.payout_runs enable row level security;
alter table public.payouts enable row level security;
alter table public.processed_whatsapp_messages enable row level security;
alter table public.routing_rules enable row level security;
alter table public.segment_members enable row level security;
alter table public.segments enable row level security;
alter table public.student_leads enable row level security;
alter table public.touchpoints enable row level security;
alter table public.verifications enable row level security;
alter table public.w2_access_codes enable row level security;
alter table public.w2_blocks enable row level security;
alter table public.w2_clicks enable row level security;
alter table public.w2_conversations enable row level security;
alter table public.w2_drive_files enable row level security;
alter table public.w2_events enable row level security;
alter table public.w2_fact_log enable row level security;
alter table public.w2_feedback enable row level security;
alter table public.w2_gemini_caches enable row level security;
alter table public.w2_inbox enable row level security;
alter table public.w2_kb_chunks enable row level security;
alter table public.w2_kb_docs enable row level security;
alter table public.w2_kb_stage enable row level security;
alter table public.w2_learning_reports enable row level security;
alter table public.w2_learnings enable row level security;
alter table public.w2_messages enable row level security;
alter table public.w2_meta enable row level security;
alter table public.w2_nurture_log enable row level security;
alter table public.w2_outbox enable row level security;
alter table public.w2_prompts enable row level security;
alter table public.w2_search_cache enable row level security;
alter table public.w2_security_log enable row level security;
alter table public.w2_sources enable row level security;
alter table public.w2_test_runs enable row level security;
alter table public.w2_trusted enable row level security;

create policy crm_select on public.allocations as permissive for select to authenticated using ((crm_b2b_reader() OR (user_id = auth.uid())));
create policy crm_select on public.calls as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM student_leads l
  WHERE ((l.id = calls.lead_id) AND crm_can_see(l.owner_user_id, l.is_test, l.is_sales_ready)))));
create policy crm_select on public.campaign_sends as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_select on public.campaigns as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_staff_select on public.catalog_programs as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_staff_select on public.catalog_universities as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_activities_select on public.crm_activities as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM student_leads l
  WHERE ((l.id = crm_activities.lead_id) AND crm_can_see(l.owner_user_id, l.is_test, l.is_sales_ready)))));
create policy crm_select on public.crm_alerts as permissive for select to authenticated using (crm_b2b_reader());
create policy crm_select on public.crm_notifications as permissive for select to authenticated using ((user_id = auth.uid()));
create policy crm_saved_views_own on public.crm_saved_views as permissive for all to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy crm_saved_views_shared on public.crm_saved_views as permissive for select to authenticated using ((is_shared AND (crm_role() IS NOT NULL)));
create policy crm_settings_select on public.crm_settings as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_tasks_select on public.crm_tasks as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM student_leads l
  WHERE ((l.id = crm_tasks.lead_id) AND crm_can_see(l.owner_user_id, l.is_test, l.is_sales_ready)))));
create policy crm_tasks_write on public.crm_tasks as permissive for all to authenticated using (((COALESCE(crm_role(), 'viewer'::text) <> 'viewer'::text) AND (EXISTS ( SELECT 1
   FROM student_leads l
  WHERE ((l.id = crm_tasks.lead_id) AND crm_can_see(l.owner_user_id, l.is_test, l.is_sales_ready)))))) with check (((COALESCE(crm_role(), 'viewer'::text) <> 'viewer'::text) AND (EXISTS ( SELECT 1
   FROM student_leads l
  WHERE ((l.id = crm_tasks.lead_id) AND crm_can_see(l.owner_user_id, l.is_test, l.is_sales_ready))))));
create policy crm_teams_select on public.crm_teams as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_select on public.crm_university_settings as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_users_select on public.crm_users as permissive for select to authenticated using (((id = auth.uid()) OR (crm_role() IS NOT NULL)));
create policy crm_select on public.earning_rates as permissive for select to authenticated using (crm_money_reader());
create policy crm_select on public.earnings as permissive for select to authenticated using (crm_money_reader());
create policy crm_select on public.engine_decisions as permissive for select to authenticated using ((crm_b2b_reader() OR (EXISTS ( SELECT 1
   FROM student_leads l
  WHERE ((l.id = engine_decisions.lead_id) AND (l.owner_user_id = auth.uid()))))));
create policy crm_select on public.enrollments as permissive for select to authenticated using ((crm_money_reader() OR (owner_user_id = auth.uid())));
create policy "Influencers can view their own profile" on public.influencers as permissive for select to authenticated using (((auth_uid = auth.uid()) OR is_admin()));
create policy crm_select on public.invoices as permissive for select to authenticated using (crm_money_reader());
create policy crm_select on public.journey_runs as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_select on public.journeys as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_select on public.message_templates as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_select on public.partner_events as permissive for select to authenticated using (crm_b2b_reader());
create policy crm_select on public.partner_mapping_profiles as permissive for select to authenticated using (crm_b2b_reader());
create policy crm_select on public.partners as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_select on public.payout_rates as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_select on public.payout_runs as permissive for select to authenticated using (crm_money_reader());
create policy crm_select on public.payouts as permissive for select to authenticated using ((crm_money_reader() OR (user_id = auth.uid())));
create policy crm_select on public.routing_rules as permissive for select to authenticated using (crm_b2b_reader());
create policy crm_select on public.segment_members as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy crm_select on public.segments as permissive for select to authenticated using ((crm_role() IS NOT NULL));
create policy "Influencers can only view their own student leads" on public.student_leads as permissive for select to authenticated using (((referral_code = current_referral_code()) OR is_admin()));
create policy crm_staff_select on public.student_leads as permissive for select to authenticated using (crm_can_see(owner_user_id, is_test, is_sales_ready));
create policy crm_touchpoints_select on public.touchpoints as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM student_leads l
  WHERE ((l.id = touchpoints.lead_id) AND crm_can_see(l.owner_user_id, l.is_test, l.is_sales_ready)))));

revoke all on public.allocations from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.allocations to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.allocations to service_role;
revoke all on public.allocations_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.allocations_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.allocations_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.allocations_id_seq to service_role;
revoke all on public.calls from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.calls to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.calls to service_role;
revoke all on public.calls_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.calls_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.calls_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.calls_id_seq to service_role;
revoke all on public.campaign_sends from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.campaign_sends to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.campaign_sends to service_role;
revoke all on public.campaign_sends_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.campaign_sends_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.campaign_sends_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.campaign_sends_id_seq to service_role;
revoke all on public.campaigns from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.campaigns to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.campaigns to service_role;
revoke all on public.campaigns_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.campaigns_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.campaigns_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.campaigns_id_seq to service_role;
revoke all on public.catalog_programs from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_programs to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_programs to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_programs to service_role;
revoke all on public.catalog_programs_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.catalog_programs_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.catalog_programs_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.catalog_programs_id_seq to service_role;
revoke all on public.catalog_stage from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_stage to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_stage to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_stage to service_role;
revoke all on public.catalog_synonyms from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_synonyms to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_synonyms to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_synonyms to service_role;
revoke all on public.catalog_universities from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_universities to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_universities to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.catalog_universities to service_role;
revoke all on public.catalog_universities_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.catalog_universities_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.catalog_universities_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.catalog_universities_id_seq to service_role;
revoke all on public.conversation_locks from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.conversation_locks to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.conversation_locks to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.conversation_locks to service_role;
revoke all on public.course_directory from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.course_directory to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.course_directory to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.course_directory to service_role;
revoke all on public.course_directory_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.course_directory_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.course_directory_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.course_directory_id_seq to service_role;
revoke all on public.crm_activities from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_activities to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_activities to service_role;
revoke all on public.crm_activities_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.crm_activities_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.crm_activities_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.crm_activities_id_seq to service_role;
revoke all on public.crm_alerts from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_alerts to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_alerts to service_role;
revoke all on public.crm_alerts_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.crm_alerts_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.crm_alerts_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.crm_alerts_id_seq to service_role;
revoke all on public.crm_api_keys from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_api_keys to service_role;
revoke all on public.crm_api_keys_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.crm_api_keys_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.crm_api_keys_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.crm_api_keys_id_seq to service_role;
revoke all on public.crm_leads_v from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_leads_v to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_leads_v to service_role;
revoke all on public.crm_notifications from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_notifications to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_notifications to service_role;
revoke all on public.crm_notifications_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.crm_notifications_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.crm_notifications_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.crm_notifications_id_seq to service_role;
revoke all on public.crm_saved_views from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_saved_views to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_saved_views to service_role;
revoke all on public.crm_saved_views_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.crm_saved_views_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.crm_saved_views_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.crm_saved_views_id_seq to service_role;
revoke all on public.crm_settings from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_settings to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_settings to service_role;
revoke all on public.crm_tasks from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_tasks to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_tasks to service_role;
revoke all on public.crm_tasks_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.crm_tasks_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.crm_tasks_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.crm_tasks_id_seq to service_role;
revoke all on public.crm_teams from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_teams to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_teams to service_role;
revoke all on public.crm_teams_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.crm_teams_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.crm_teams_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.crm_teams_id_seq to service_role;
revoke all on public.crm_university_settings from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_university_settings to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_university_settings to service_role;
revoke all on public.crm_users from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_users to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.crm_users to service_role;
revoke all on public.earning_rates from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.earning_rates to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.earning_rates to service_role;
revoke all on public.earning_rates_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.earning_rates_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.earning_rates_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.earning_rates_id_seq to service_role;
revoke all on public.earnings from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.earnings to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.earnings to service_role;
revoke all on public.earnings_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.earnings_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.earnings_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.earnings_id_seq to service_role;
revoke all on public.eduwit_knowledge_base from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.eduwit_knowledge_base to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.eduwit_knowledge_base to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.eduwit_knowledge_base to service_role;
revoke all on public.eduwit_knowledge_base_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.eduwit_knowledge_base_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.eduwit_knowledge_base_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.eduwit_knowledge_base_id_seq to service_role;
revoke all on public.engine_decisions from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.engine_decisions to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.engine_decisions to service_role;
revoke all on public.engine_decisions_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.engine_decisions_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.engine_decisions_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.engine_decisions_id_seq to service_role;
revoke all on public.enrollments from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.enrollments to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.enrollments to service_role;
revoke all on public.enrollments_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.enrollments_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.enrollments_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.enrollments_id_seq to service_role;
revoke all on public.influencer_auth from anon, authenticated, service_role;
grant MAINTAIN, REFERENCES, SELECT, TRIGGER on public.influencer_auth to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.influencer_auth to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.influencer_auth to service_role;
revoke all on public.influencer_auth_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.influencer_auth_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.influencer_auth_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.influencer_auth_id_seq to service_role;
revoke all on public.influencer_leads_dashboard from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.influencer_leads_dashboard to service_role;
revoke all on public.influencer_login_attempts from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.influencer_login_attempts to service_role;
revoke all on public.influencer_login_attempts_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.influencer_login_attempts_id_seq to service_role;
revoke all on public.influencers from anon, authenticated, service_role;
grant MAINTAIN, REFERENCES, SELECT, TRIGGER on public.influencers to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.influencers to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.influencers to service_role;
revoke all on public.invoices from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.invoices to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.invoices to service_role;
revoke all on public.invoices_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.invoices_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.invoices_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.invoices_id_seq to service_role;
revoke all on public.journey_runs from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.journey_runs to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.journey_runs to service_role;
revoke all on public.journey_runs_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.journey_runs_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.journey_runs_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.journey_runs_id_seq to service_role;
revoke all on public.journeys from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.journeys to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.journeys to service_role;
revoke all on public.journeys_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.journeys_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.journeys_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.journeys_id_seq to service_role;
revoke all on public.message_templates from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.message_templates to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.message_templates to service_role;
revoke all on public.message_templates_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.message_templates_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.message_templates_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.message_templates_id_seq to service_role;
revoke all on public.n8n_chat_histories from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.n8n_chat_histories to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.n8n_chat_histories to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.n8n_chat_histories to service_role;
revoke all on public.n8n_chat_histories_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.n8n_chat_histories_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.n8n_chat_histories_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.n8n_chat_histories_id_seq to service_role;
revoke all on public.partner_events from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.partner_events to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.partner_events to service_role;
revoke all on public.partner_events_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.partner_events_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.partner_events_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.partner_events_id_seq to service_role;
revoke all on public.partner_mapping_profiles from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.partner_mapping_profiles to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.partner_mapping_profiles to service_role;
revoke all on public.partner_mapping_profiles_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.partner_mapping_profiles_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.partner_mapping_profiles_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.partner_mapping_profiles_id_seq to service_role;
revoke all on public.partners from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.partners to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.partners to service_role;
revoke all on public.partners_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.partners_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.partners_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.partners_id_seq to service_role;
revoke all on public.partners_v from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.partners_v to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.partners_v to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.partners_v to service_role;
revoke all on public.payout_rates from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.payout_rates to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.payout_rates to service_role;
revoke all on public.payout_rates_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.payout_rates_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.payout_rates_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.payout_rates_id_seq to service_role;
revoke all on public.payout_runs from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.payout_runs to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.payout_runs to service_role;
revoke all on public.payout_runs_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.payout_runs_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.payout_runs_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.payout_runs_id_seq to service_role;
revoke all on public.payouts from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.payouts to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.payouts to service_role;
revoke all on public.payouts_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.payouts_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.payouts_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.payouts_id_seq to service_role;
revoke all on public.processed_whatsapp_messages from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.processed_whatsapp_messages to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.processed_whatsapp_messages to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.processed_whatsapp_messages to service_role;
revoke all on public.routing_rules from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.routing_rules to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.routing_rules to service_role;
revoke all on public.routing_rules_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.routing_rules_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.routing_rules_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.routing_rules_id_seq to service_role;
revoke all on public.segment_members from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.segment_members to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.segment_members to service_role;
revoke all on public.segments from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.segments to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.segments to service_role;
revoke all on public.segments_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.segments_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.segments_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.segments_id_seq to service_role;
revoke all on public.student_leads from anon, authenticated, service_role;
grant MAINTAIN, REFERENCES, SELECT, TRIGGER on public.student_leads to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.student_leads to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.student_leads to service_role;
revoke all on public.student_leads_v from anon, authenticated, service_role;
grant SELECT on public.student_leads_v to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.student_leads_v to service_role;
revoke all on public.touchpoints from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.touchpoints to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.touchpoints to service_role;
revoke all on public.touchpoints_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.touchpoints_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.touchpoints_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.touchpoints_id_seq to service_role;
revoke all on public.verifications from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.verifications to service_role;
revoke all on public.verifications_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.verifications_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.verifications_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.verifications_id_seq to service_role;
revoke all on public.w2_access_codes from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_access_codes to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_access_codes to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_access_codes to service_role;
revoke all on public.w2_blocks from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_blocks to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_blocks to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_blocks to service_role;
revoke all on public.w2_clicks from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_clicks to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_clicks to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_clicks to service_role;
revoke all on public.w2_clicks_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_clicks_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_clicks_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_clicks_id_seq to service_role;
revoke all on public.w2_conversations from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_conversations to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_conversations to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_conversations to service_role;
revoke all on public.w2_drive_files from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_drive_files to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_drive_files to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_drive_files to service_role;
revoke all on public.w2_events from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_events to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_events to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_events to service_role;
revoke all on public.w2_events_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_events_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_events_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_events_id_seq to service_role;
revoke all on public.w2_fact_log from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_fact_log to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_fact_log to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_fact_log to service_role;
revoke all on public.w2_fact_log_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_fact_log_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_fact_log_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_fact_log_id_seq to service_role;
revoke all on public.w2_fee_review from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_fee_review to service_role;
revoke all on public.w2_feedback from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_feedback to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_feedback to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_feedback to service_role;
revoke all on public.w2_feedback_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_feedback_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_feedback_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_feedback_id_seq to service_role;
revoke all on public.w2_gemini_caches from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_gemini_caches to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_gemini_caches to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_gemini_caches to service_role;
revoke all on public.w2_inbox from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_inbox to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_inbox to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_inbox to service_role;
revoke all on public.w2_kb_chunks from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_kb_chunks to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_kb_chunks to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_kb_chunks to service_role;
revoke all on public.w2_kb_chunks_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_kb_chunks_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_kb_chunks_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_kb_chunks_id_seq to service_role;
revoke all on public.w2_kb_docs from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_kb_docs to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_kb_docs to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_kb_docs to service_role;
revoke all on public.w2_kb_docs_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_kb_docs_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_kb_docs_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_kb_docs_id_seq to service_role;
revoke all on public.w2_kb_stage from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_kb_stage to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_kb_stage to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_kb_stage to service_role;
revoke all on public.w2_latency_daily from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_latency_daily to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_latency_daily to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_latency_daily to service_role;
revoke all on public.w2_learning_reports from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_learning_reports to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_learning_reports to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_learning_reports to service_role;
revoke all on public.w2_learning_reports_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_learning_reports_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_learning_reports_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_learning_reports_id_seq to service_role;
revoke all on public.w2_learnings from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_learnings to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_learnings to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_learnings to service_role;
revoke all on public.w2_learnings_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_learnings_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_learnings_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_learnings_id_seq to service_role;
revoke all on public.w2_messages from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_messages to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_messages to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_messages to service_role;
revoke all on public.w2_messages_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_messages_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_messages_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_messages_id_seq to service_role;
revoke all on public.w2_meta from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_meta to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_meta to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_meta to service_role;
revoke all on public.w2_nurture_log from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_nurture_log to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_nurture_log to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_nurture_log to service_role;
revoke all on public.w2_nurture_log_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_nurture_log_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_nurture_log_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_nurture_log_id_seq to service_role;
revoke all on public.w2_outbox from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_outbox to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_outbox to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_outbox to service_role;
revoke all on public.w2_outbox_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_outbox_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_outbox_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_outbox_id_seq to service_role;
revoke all on public.w2_prompts from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_prompts to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_prompts to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_prompts to service_role;
revoke all on public.w2_search_cache from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_search_cache to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_search_cache to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_search_cache to service_role;
revoke all on public.w2_security_log from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_security_log to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_security_log to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_security_log to service_role;
revoke all on public.w2_security_log_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_security_log_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_security_log_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_security_log_id_seq to service_role;
revoke all on public.w2_sources from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_sources to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_sources to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_sources to service_role;
revoke all on public.w2_test_runs from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_test_runs to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_test_runs to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_test_runs to service_role;
revoke all on public.w2_test_runs_id_seq from anon, authenticated, service_role;
grant SELECT, UPDATE, USAGE on public.w2_test_runs_id_seq to anon;
grant SELECT, UPDATE, USAGE on public.w2_test_runs_id_seq to authenticated;
grant SELECT, UPDATE, USAGE on public.w2_test_runs_id_seq to service_role;
revoke all on public.w2_trusted from anon, authenticated, service_role;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_trusted to anon;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_trusted to authenticated;
grant DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE on public.w2_trusted to service_role;
revoke all on function public.catalog_commit(p_batch text, p_deactivate_missing boolean, p_source_file text) from public, anon, authenticated, service_role;
grant execute on function public.catalog_commit(p_batch text, p_deactivate_missing boolean, p_source_file text) to public;
grant execute on function public.catalog_commit(p_batch text, p_deactivate_missing boolean, p_source_file text) to anon;
grant execute on function public.catalog_commit(p_batch text, p_deactivate_missing boolean, p_source_file text) to authenticated;
grant execute on function public.catalog_commit(p_batch text, p_deactivate_missing boolean, p_source_file text) to service_role;
revoke all on function public.catalog_load(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.catalog_load(p jsonb) to public;
grant execute on function public.catalog_load(p jsonb) to anon;
grant execute on function public.catalog_load(p jsonb) to authenticated;
grant execute on function public.catalog_load(p jsonb) to service_role;
revoke all on function public.catalog_programs_fee_check() from public, anon, authenticated, service_role;
grant execute on function public.catalog_programs_fee_check() to public;
grant execute on function public.catalog_programs_fee_check() to anon;
grant execute on function public.catalog_programs_fee_check() to authenticated;
grant execute on function public.catalog_programs_fee_check() to service_role;
revoke all on function public.catalog_remove_source(p_source_file text) from public, anon, authenticated, service_role;
grant execute on function public.catalog_remove_source(p_source_file text) to public;
grant execute on function public.catalog_remove_source(p_source_file text) to anon;
grant execute on function public.catalog_remove_source(p_source_file text) to authenticated;
grant execute on function public.catalog_remove_source(p_source_file text) to service_role;
revoke all on function public.catalog_stage_add(p_batch text, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.catalog_stage_add(p_batch text, p jsonb) to public;
grant execute on function public.catalog_stage_add(p_batch text, p jsonb) to anon;
grant execute on function public.catalog_stage_add(p_batch text, p jsonb) to authenticated;
grant execute on function public.catalog_stage_add(p_batch text, p jsonb) to service_role;
revoke all on function public.crm_add_earning_rate(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_add_earning_rate(p jsonb) to authenticated;
grant execute on function public.crm_add_earning_rate(p jsonb) to service_role;
revoke all on function public.crm_add_note(p_id bigint, p_content text, p_kind text, p_outcome text, p_meta jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_add_note(p_id bigint, p_content text, p_kind text, p_outcome text, p_meta jsonb) to authenticated;
grant execute on function public.crm_add_note(p_id bigint, p_content text, p_kind text, p_outcome text, p_meta jsonb) to service_role;
revoke all on function public.crm_add_payout_rate(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_add_payout_rate(p jsonb) to authenticated;
grant execute on function public.crm_add_payout_rate(p jsonb) to service_role;
revoke all on function public.crm_agenda() from public, anon, authenticated, service_role;
grant execute on function public.crm_agenda() to authenticated;
grant execute on function public.crm_agenda() to service_role;
revoke all on function public.crm_allocate_lead(p_lead bigint, p_exclude bigint[], p_note text) from public, anon, authenticated, service_role;
grant execute on function public.crm_allocate_lead(p_lead bigint, p_exclude bigint[], p_note text) to authenticated;
grant execute on function public.crm_allocate_lead(p_lead bigint, p_exclude bigint[], p_note text) to service_role;
revoke all on function public.crm_api_key_check(p_key text) from public, anon, authenticated, service_role;
grant execute on function public.crm_api_key_check(p_key text) to authenticated;
grant execute on function public.crm_api_key_check(p_key text) to service_role;
revoke all on function public.crm_apply_stage_system(p_id bigint, p_stage text, p_sub_stage text, p_reason text, p_fields jsonb, p_actor text, p_allow_back boolean) from public, anon, authenticated, service_role;
grant execute on function public.crm_apply_stage_system(p_id bigint, p_stage text, p_sub_stage text, p_reason text, p_fields jsonb, p_actor text, p_allow_back boolean) to authenticated;
grant execute on function public.crm_apply_stage_system(p_id bigint, p_stage text, p_sub_stage text, p_reason text, p_fields jsonb, p_actor text, p_allow_back boolean) to service_role;
revoke all on function public.crm_assign_lead(p_id bigint, p_user uuid, p_note text) from public, anon, authenticated, service_role;
grant execute on function public.crm_assign_lead(p_id bigint, p_user uuid, p_note text) to authenticated;
grant execute on function public.crm_assign_lead(p_id bigint, p_user uuid, p_note text) to service_role;
revoke all on function public.crm_auto_assign_trg() from public, anon, authenticated, service_role;
grant execute on function public.crm_auto_assign_trg() to public;
grant execute on function public.crm_auto_assign_trg() to anon;
grant execute on function public.crm_auto_assign_trg() to authenticated;
grant execute on function public.crm_auto_assign_trg() to service_role;
revoke all on function public.crm_b2b_reader() from public, anon, authenticated, service_role;
grant execute on function public.crm_b2b_reader() to authenticated;
grant execute on function public.crm_b2b_reader() to service_role;
revoke all on function public.crm_call_event(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_call_event(p jsonb) to authenticated;
grant execute on function public.crm_call_event(p jsonb) to service_role;
revoke all on function public.crm_call_outcome_task(p_lead bigint, p_outcome text, p_assignee uuid) from public, anon, authenticated, service_role;
grant execute on function public.crm_call_outcome_task(p_lead bigint, p_outcome text, p_assignee uuid) to service_role;
revoke all on function public.crm_call_start(p_lead bigint, p_provider text, p_from text, p_to text) from public, anon, authenticated, service_role;
grant execute on function public.crm_call_start(p_lead bigint, p_provider text, p_from text, p_to text) to authenticated;
grant execute on function public.crm_call_start(p_lead bigint, p_provider text, p_from text, p_to text) to service_role;
revoke all on function public.crm_campaign_cancel(p_id bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_campaign_cancel(p_id bigint) to authenticated;
grant execute on function public.crm_campaign_cancel(p_id bigint) to service_role;
revoke all on function public.crm_campaign_claim(p_limit integer, p_base_url text) from public, anon, authenticated, service_role;
grant execute on function public.crm_campaign_claim(p_limit integer, p_base_url text) to authenticated;
grant execute on function public.crm_campaign_claim(p_limit integer, p_base_url text) to service_role;
revoke all on function public.crm_campaign_result(p_send bigint, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_campaign_result(p_send bigint, p jsonb) to authenticated;
grant execute on function public.crm_campaign_result(p_send bigint, p jsonb) to service_role;
revoke all on function public.crm_campaign_schedule(p_id bigint, p_at timestamp with time zone) from public, anon, authenticated, service_role;
grant execute on function public.crm_campaign_schedule(p_id bigint, p_at timestamp with time zone) to authenticated;
grant execute on function public.crm_campaign_schedule(p_id bigint, p_at timestamp with time zone) to service_role;
revoke all on function public.crm_can_see(p_owner uuid, p_is_test boolean, p_ready boolean) from public, anon, authenticated, service_role;
grant execute on function public.crm_can_see(p_owner uuid, p_is_test boolean, p_ready boolean) to authenticated;
grant execute on function public.crm_can_see(p_owner uuid, p_is_test boolean, p_ready boolean) to service_role;
revoke all on function public.crm_compute_earning(e enrollments, r earning_rates, p_period text) from public, anon, authenticated, service_role;
grant execute on function public.crm_compute_earning(e enrollments, r earning_rates, p_period text) to authenticated;
grant execute on function public.crm_compute_earning(e enrollments, r earning_rates, p_period text) to service_role;
revoke all on function public.crm_compute_payout(e enrollments, r payout_rates, p_earning_net numeric, p_period text) from public, anon, authenticated, service_role;
grant execute on function public.crm_compute_payout(e enrollments, r payout_rates, p_earning_net numeric, p_period text) to authenticated;
grant execute on function public.crm_compute_payout(e enrollments, r payout_rates, p_earning_net numeric, p_period text) to service_role;
revoke all on function public.crm_conversion(p_period text, p_university bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_conversion(p_period text, p_university bigint) to authenticated;
grant execute on function public.crm_conversion(p_period text, p_university bigint) to service_role;
revoke all on function public.crm_create_api_key(p_name text, p_source_system text) from public, anon, authenticated, service_role;
grant execute on function public.crm_create_api_key(p_name text, p_source_system text) to authenticated;
grant execute on function public.crm_create_api_key(p_name text, p_source_system text) to service_role;
revoke all on function public.crm_criteria_match(p_criteria jsonb, l student_leads) from public, anon, authenticated, service_role;
grant execute on function public.crm_criteria_match(p_criteria jsonb, l student_leads) to authenticated;
grant execute on function public.crm_criteria_match(p_criteria jsonb, l student_leads) to service_role;
revoke all on function public.crm_daily_digest() from public, anon, authenticated, service_role;
grant execute on function public.crm_daily_digest() to authenticated;
grant execute on function public.crm_daily_digest() to service_role;
revoke all on function public.crm_dest_stats(p_type text, p_partner bigint, p_segment text, s jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_dest_stats(p_type text, p_partner bigint, p_segment text, s jsonb) to authenticated;
grant execute on function public.crm_dest_stats(p_type text, p_partner bigint, p_segment text, s jsonb) to service_role;
revoke all on function public.crm_duplicate_candidates(p_lead bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_duplicate_candidates(p_lead bigint) to authenticated;
grant execute on function public.crm_duplicate_candidates(p_lead bigint) to service_role;
revoke all on function public.crm_earning_rate(p_university bigint, p_programme bigint, p_partner bigint, p_on date) from public, anon, authenticated, service_role;
grant execute on function public.crm_earning_rate(p_university bigint, p_programme bigint, p_partner bigint, p_on date) to authenticated;
grant execute on function public.crm_earning_rate(p_university bigint, p_programme bigint, p_partner bigint, p_on date) to service_role;
revoke all on function public.crm_engine_flow(p_days integer) from public, anon, authenticated, service_role;
grant execute on function public.crm_engine_flow(p_days integer) to authenticated;
grant execute on function public.crm_engine_flow(p_days integer) to service_role;
revoke all on function public.crm_find_lead(p_phone text) from public, anon, authenticated, service_role;
grant execute on function public.crm_find_lead(p_phone text) to authenticated;
grant execute on function public.crm_find_lead(p_phone text) to service_role;
revoke all on function public.crm_followup_tick() from public, anon, authenticated, service_role;
grant execute on function public.crm_followup_tick() to authenticated;
grant execute on function public.crm_followup_tick() to service_role;
revoke all on function public.crm_handle_new_auth_user() from public, anon, authenticated, service_role;
grant execute on function public.crm_handle_new_auth_user() to public;
grant execute on function public.crm_handle_new_auth_user() to anon;
grant execute on function public.crm_handle_new_auth_user() to authenticated;
grant execute on function public.crm_handle_new_auth_user() to service_role;
revoke all on function public.crm_invoice_set_status(p_invoice bigint, p_status text, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_invoice_set_status(p_invoice bigint, p_status text, p jsonb) to authenticated;
grant execute on function public.crm_invoice_set_status(p_invoice bigint, p_status text, p jsonb) to service_role;
revoke all on function public.crm_journey_enroll(p_journey bigint, p_lead bigint, p_reason text) from public, anon, authenticated, service_role;
grant execute on function public.crm_journey_enroll(p_journey bigint, p_lead bigint, p_reason text) to authenticated;
grant execute on function public.crm_journey_enroll(p_journey bigint, p_lead bigint, p_reason text) to service_role;
revoke all on function public.crm_journey_enroll_due(p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.crm_journey_enroll_due(p_limit integer) to authenticated;
grant execute on function public.crm_journey_enroll_due(p_limit integer) to service_role;
revoke all on function public.crm_journey_send_result(p_run bigint, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_journey_send_result(p_run bigint, p jsonb) to authenticated;
grant execute on function public.crm_journey_send_result(p_run bigint, p jsonb) to service_role;
revoke all on function public.crm_journey_set_status(p_id bigint, p_status text) from public, anon, authenticated, service_role;
grant execute on function public.crm_journey_set_status(p_id bigint, p_status text) to authenticated;
grant execute on function public.crm_journey_set_status(p_id bigint, p_status text) to service_role;
revoke all on function public.crm_journey_tick(p_limit integer, p_base_url text) from public, anon, authenticated, service_role;
grant execute on function public.crm_journey_tick(p_limit integer, p_base_url text) to authenticated;
grant execute on function public.crm_journey_tick(p_limit integer, p_base_url text) to service_role;
revoke all on function public.crm_marketing_allowed(p_lead bigint, p_channel text) from public, anon, authenticated, service_role;
grant execute on function public.crm_marketing_allowed(p_lead bigint, p_channel text) to authenticated;
grant execute on function public.crm_marketing_allowed(p_lead bigint, p_channel text) to service_role;
revoke all on function public.crm_marketing_stats() from public, anon, authenticated, service_role;
grant execute on function public.crm_marketing_stats() to authenticated;
grant execute on function public.crm_marketing_stats() to service_role;
revoke all on function public.crm_mask_email(p text) from public, anon, authenticated, service_role;
grant execute on function public.crm_mask_email(p text) to public;
grant execute on function public.crm_mask_email(p text) to anon;
grant execute on function public.crm_mask_email(p text) to authenticated;
grant execute on function public.crm_mask_email(p text) to service_role;
revoke all on function public.crm_mask_phone(p text) from public, anon, authenticated, service_role;
grant execute on function public.crm_mask_phone(p text) to public;
grant execute on function public.crm_mask_phone(p text) to anon;
grant execute on function public.crm_mask_phone(p text) to authenticated;
grant execute on function public.crm_mask_phone(p text) to service_role;
revoke all on function public.crm_masks() from public, anon, authenticated, service_role;
grant execute on function public.crm_masks() to authenticated;
grant execute on function public.crm_masks() to service_role;
revoke all on function public.crm_me() from public, anon, authenticated, service_role;
grant execute on function public.crm_me() to authenticated;
grant execute on function public.crm_me() to service_role;
revoke all on function public.crm_merge_leads(p_keep bigint, p_merge bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_merge_leads(p_keep bigint, p_merge bigint) to authenticated;
grant execute on function public.crm_merge_leads(p_keep bigint, p_merge bigint) to service_role;
revoke all on function public.crm_money_reader() from public, anon, authenticated, service_role;
grant execute on function public.crm_money_reader() to authenticated;
grant execute on function public.crm_money_reader() to service_role;
revoke all on function public.crm_money_setting(p_key text) from public, anon, authenticated, service_role;
grant execute on function public.crm_money_setting(p_key text) to authenticated;
grant execute on function public.crm_money_setting(p_key text) to service_role;
revoke all on function public.crm_money_summary(p_period text) from public, anon, authenticated, service_role;
grant execute on function public.crm_money_summary(p_period text) to authenticated;
grant execute on function public.crm_money_summary(p_period text) to service_role;
revoke all on function public.crm_my_notifications(p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.crm_my_notifications(p_limit integer) to authenticated;
grant execute on function public.crm_my_notifications(p_limit integer) to service_role;
revoke all on function public.crm_new_lead(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_new_lead(p jsonb) to authenticated;
grant execute on function public.crm_new_lead(p jsonb) to service_role;
revoke all on function public.crm_norm_phone(p text) from public, anon, authenticated, service_role;
grant execute on function public.crm_norm_phone(p text) to public;
grant execute on function public.crm_norm_phone(p text) to anon;
grant execute on function public.crm_norm_phone(p text) to authenticated;
grant execute on function public.crm_norm_phone(p text) to service_role;
revoke all on function public.crm_notifications_emailed(p_ids bigint[]) from public, anon, authenticated, service_role;
grant execute on function public.crm_notifications_emailed(p_ids bigint[]) to service_role;
revoke all on function public.crm_notifications_read() from public, anon, authenticated, service_role;
grant execute on function public.crm_notifications_read() to authenticated;
grant execute on function public.crm_notifications_read() to service_role;
revoke all on function public.crm_notify(p_user uuid, p_kind text, p_title text, p_body text, p_link text, p_lead bigint, p_dedupe_hours integer) from public, anon, authenticated, service_role;
grant execute on function public.crm_notify(p_user uuid, p_kind text, p_title text, p_body text, p_link text, p_lead bigint, p_dedupe_hours integer) to service_role;
revoke all on function public.crm_num(p text) from public, anon, authenticated, service_role;
grant execute on function public.crm_num(p text) to public;
grant execute on function public.crm_num(p text) to anon;
grant execute on function public.crm_num(p text) to authenticated;
grant execute on function public.crm_num(p text) to service_role;
revoke all on function public.crm_partner_duplicate(p_allocation bigint, p_record_id text, p_record_created timestamp with time zone, p_via text) from public, anon, authenticated, service_role;
grant execute on function public.crm_partner_duplicate(p_allocation bigint, p_record_id text, p_record_created timestamp with time zone, p_via text) to authenticated;
grant execute on function public.crm_partner_duplicate(p_allocation bigint, p_record_id text, p_record_created timestamp with time zone, p_via text) to service_role;
revoke all on function public.crm_partner_event(p_partner bigint, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_partner_event(p_partner bigint, p jsonb) to authenticated;
grant execute on function public.crm_partner_event(p_partner bigint, p jsonb) to service_role;
revoke all on function public.crm_partner_health_check() from public, anon, authenticated, service_role;
grant execute on function public.crm_partner_health_check() to authenticated;
grant execute on function public.crm_partner_health_check() to service_role;
revoke all on function public.crm_partner_rotate_secret(p_partner bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_partner_rotate_secret(p_partner bigint) to authenticated;
grant execute on function public.crm_partner_rotate_secret(p_partner bigint) to service_role;
revoke all on function public.crm_partner_verify(p_partner bigint, p_body text, p_signature text) from public, anon, authenticated, service_role;
grant execute on function public.crm_partner_verify(p_partner bigint, p_body text, p_signature text) to authenticated;
grant execute on function public.crm_partner_verify(p_partner bigint, p_body text, p_signature text) to service_role;
revoke all on function public.crm_payout_rate(p_university bigint, p_programme bigint, p_user uuid, p_on date) from public, anon, authenticated, service_role;
grant execute on function public.crm_payout_rate(p_university bigint, p_programme bigint, p_user uuid, p_on date) to authenticated;
grant execute on function public.crm_payout_rate(p_university bigint, p_programme bigint, p_user uuid, p_on date) to service_role;
revoke all on function public.crm_payout_run_create(p_period text) from public, anon, authenticated, service_role;
grant execute on function public.crm_payout_run_create(p_period text) to authenticated;
grant execute on function public.crm_payout_run_create(p_period text) to service_role;
revoke all on function public.crm_payout_run_set_status(p_run bigint, p_status text) from public, anon, authenticated, service_role;
grant execute on function public.crm_payout_run_set_status(p_run bigint, p_status text) to authenticated;
grant execute on function public.crm_payout_run_set_status(p_run bigint, p_status text) to service_role;
revoke all on function public.crm_pending_notification_emails(p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.crm_pending_notification_emails(p_limit integer) to service_role;
revoke all on function public.crm_period_close(p_period text) from public, anon, authenticated, service_role;
grant execute on function public.crm_period_close(p_period text) to authenticated;
grant execute on function public.crm_period_close(p_period text) to service_role;
revoke all on function public.crm_programme_fit(p_id bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_programme_fit(p_id bigint) to authenticated;
grant execute on function public.crm_programme_fit(p_id bigint) to service_role;
revoke all on function public.crm_reallocate(p_lead bigint, p_dest_type text, p_partner bigint, p_user uuid, p_reason text) from public, anon, authenticated, service_role;
grant execute on function public.crm_reallocate(p_lead bigint, p_dest_type text, p_partner bigint, p_user uuid, p_reason text) to authenticated;
grant execute on function public.crm_reallocate(p_lead bigint, p_dest_type text, p_partner bigint, p_user uuid, p_reason text) to service_role;
revoke all on function public.crm_refund_enrollment(p_id bigint, p_reason text, p_kind text) from public, anon, authenticated, service_role;
grant execute on function public.crm_refund_enrollment(p_id bigint, p_reason text, p_kind text) to authenticated;
grant execute on function public.crm_refund_enrollment(p_id bigint, p_reason text, p_kind text) to service_role;
revoke all on function public.crm_render_template(p_template bigint, p_lead bigint, p_extra jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_render_template(p_template bigint, p_lead bigint, p_extra jsonb) to authenticated;
grant execute on function public.crm_render_template(p_template bigint, p_lead bigint, p_extra jsonb) to service_role;
revoke all on function public.crm_report(p_kind text, p_from date, p_to date) from public, anon, authenticated, service_role;
grant execute on function public.crm_report(p_kind text, p_from date, p_to date) to authenticated;
grant execute on function public.crm_report(p_kind text, p_from date, p_to date) to service_role;
revoke all on function public.crm_report_enrollment(p_lead bigint, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_report_enrollment(p_lead bigint, p jsonb) to authenticated;
grant execute on function public.crm_report_enrollment(p_lead bigint, p jsonb) to service_role;
revoke all on function public.crm_require(p_roles text[]) from public, anon, authenticated, service_role;
grant execute on function public.crm_require(p_roles text[]) to public;
grant execute on function public.crm_require(p_roles text[]) to anon;
grant execute on function public.crm_require(p_roles text[]) to authenticated;
grant execute on function public.crm_require(p_roles text[]) to service_role;
revoke all on function public.crm_resolve_alert(p_alert bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_resolve_alert(p_alert bigint) to authenticated;
grant execute on function public.crm_resolve_alert(p_alert bigint) to service_role;
revoke all on function public.crm_role() from public, anon, authenticated, service_role;
grant execute on function public.crm_role() to authenticated;
grant execute on function public.crm_role() to service_role;
revoke all on function public.crm_rules_match(p_rules jsonb, p_lead bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_rules_match(p_rules jsonb, p_lead bigint) to authenticated;
grant execute on function public.crm_rules_match(p_rules jsonb, p_lead bigint) to service_role;
revoke all on function public.crm_rules_where(p_rules jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_rules_where(p_rules jsonb) to authenticated;
grant execute on function public.crm_rules_where(p_rules jsonb) to service_role;
revoke all on function public.crm_save_campaign(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_save_campaign(p jsonb) to authenticated;
grant execute on function public.crm_save_campaign(p jsonb) to service_role;
revoke all on function public.crm_save_journey(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_save_journey(p jsonb) to authenticated;
grant execute on function public.crm_save_journey(p jsonb) to service_role;
revoke all on function public.crm_save_mapping_profile(p_partner bigint, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_save_mapping_profile(p_partner bigint, p jsonb) to authenticated;
grant execute on function public.crm_save_mapping_profile(p_partner bigint, p jsonb) to service_role;
revoke all on function public.crm_save_routing_rule(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_save_routing_rule(p jsonb) to authenticated;
grant execute on function public.crm_save_routing_rule(p jsonb) to service_role;
revoke all on function public.crm_save_segment(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_save_segment(p jsonb) to authenticated;
grant execute on function public.crm_save_segment(p jsonb) to service_role;
revoke all on function public.crm_save_template(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_save_template(p jsonb) to authenticated;
grant execute on function public.crm_save_template(p jsonb) to service_role;
revoke all on function public.crm_score_lead(p_lead bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_score_lead(p_lead bigint) to authenticated;
grant execute on function public.crm_score_lead(p_lead bigint) to service_role;
revoke all on function public.crm_score_tick(p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.crm_score_tick(p_limit integer) to authenticated;
grant execute on function public.crm_score_tick(p_limit integer) to service_role;
revoke all on function public.crm_scorecards(p_segment text, p_days integer) from public, anon, authenticated, service_role;
grant execute on function public.crm_scorecards(p_segment text, p_days integer) to authenticated;
grant execute on function public.crm_scorecards(p_segment text, p_days integer) to service_role;
revoke all on function public.crm_segment_add_leads(p_segment bigint, p_lead_ids bigint[]) from public, anon, authenticated, service_role;
grant execute on function public.crm_segment_add_leads(p_segment bigint, p_lead_ids bigint[]) to authenticated;
grant execute on function public.crm_segment_add_leads(p_segment bigint, p_lead_ids bigint[]) to service_role;
revoke all on function public.crm_segment_count(p_rules jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_segment_count(p_rules jsonb) to authenticated;
grant execute on function public.crm_segment_count(p_rules jsonb) to service_role;
revoke all on function public.crm_segment_leads(p_rules jsonb, p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.crm_segment_leads(p_rules jsonb, p_limit integer) to authenticated;
grant execute on function public.crm_segment_leads(p_rules jsonb, p_limit integer) to service_role;
revoke all on function public.crm_segment_of(l student_leads) from public, anon, authenticated, service_role;
grant execute on function public.crm_segment_of(l student_leads) to authenticated;
grant execute on function public.crm_segment_of(l student_leads) to service_role;
revoke all on function public.crm_segment_preview(p_rules jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_segment_preview(p_rules jsonb) to authenticated;
grant execute on function public.crm_segment_preview(p_rules jsonb) to service_role;
revoke all on function public.crm_segment_resolve(p_segment bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_segment_resolve(p_segment bigint) to authenticated;
grant execute on function public.crm_segment_resolve(p_segment bigint) to service_role;
revoke all on function public.crm_send_job(p_lead bigint, p_template bigint, p_base_url text, p_extra jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_send_job(p_lead bigint, p_template bigint, p_base_url text, p_extra jsonb) to authenticated;
grant execute on function public.crm_send_job(p_lead bigint, p_template bigint, p_base_url text, p_extra jsonb) to service_role;
revoke all on function public.crm_set_my_phone(p_phone text) from public, anon, authenticated, service_role;
grant execute on function public.crm_set_my_phone(p_phone text) to authenticated;
grant execute on function public.crm_set_my_phone(p_phone text) to service_role;
revoke all on function public.crm_set_stage(p_id bigint, p_stage text, p_sub_stage text, p_reason text, p_fields jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_set_stage(p_id bigint, p_stage text, p_sub_stage text, p_reason text, p_fields jsonb) to authenticated;
grant execute on function public.crm_set_stage(p_id bigint, p_stage text, p_sub_stage text, p_reason text, p_fields jsonb) to service_role;
revoke all on function public.crm_sla_minutes(p_temperature text) from public, anon, authenticated, service_role;
grant execute on function public.crm_sla_minutes(p_temperature text) to authenticated;
grant execute on function public.crm_sla_minutes(p_temperature text) to service_role;
revoke all on function public.crm_sync_claim(p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.crm_sync_claim(p_limit integer) to authenticated;
grant execute on function public.crm_sync_claim(p_limit integer) to service_role;
revoke all on function public.crm_sync_result(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_sync_result(p jsonb) to authenticated;
grant execute on function public.crm_sync_result(p jsonb) to service_role;
revoke all on function public.crm_tier_pct(p_tiers jsonb, p_conv numeric) from public, anon, authenticated, service_role;
grant execute on function public.crm_tier_pct(p_tiers jsonb, p_conv numeric) to authenticated;
grant execute on function public.crm_tier_pct(p_tiers jsonb, p_conv numeric) to service_role;
revoke all on function public.crm_timeline(p_id bigint, p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.crm_timeline(p_id bigint, p_limit integer) to authenticated;
grant execute on function public.crm_timeline(p_id bigint, p_limit integer) to service_role;
revoke all on function public.crm_unsubscribe(p_lead bigint, p_token text, p_channel text) from public, anon, authenticated, service_role;
grant execute on function public.crm_unsubscribe(p_lead bigint, p_token text, p_channel text) to authenticated;
grant execute on function public.crm_unsubscribe(p_lead bigint, p_token text, p_channel text) to service_role;
revoke all on function public.crm_unsubscribe_token(p_lead bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_unsubscribe_token(p_lead bigint) to authenticated;
grant execute on function public.crm_unsubscribe_token(p_lead bigint) to service_role;
revoke all on function public.crm_update_engine_settings(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_update_engine_settings(p jsonb) to authenticated;
grant execute on function public.crm_update_engine_settings(p jsonb) to service_role;
revoke all on function public.crm_update_lead(p_id bigint, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_update_lead(p_id bigint, p jsonb) to authenticated;
grant execute on function public.crm_update_lead(p_id bigint, p jsonb) to service_role;
revoke all on function public.crm_update_scoring(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_update_scoring(p jsonb) to authenticated;
grant execute on function public.crm_update_scoring(p jsonb) to service_role;
revoke all on function public.crm_update_user(p_user uuid, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_update_user(p_user uuid, p jsonb) to authenticated;
grant execute on function public.crm_update_user(p_user uuid, p jsonb) to service_role;
revoke all on function public.crm_upsert_partner(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_upsert_partner(p jsonb) to authenticated;
grant execute on function public.crm_upsert_partner(p jsonb) to service_role;
revoke all on function public.crm_verify_check(p_id bigint, p_code text, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_verify_check(p_id bigint, p_code text, p jsonb) to service_role;
revoke all on function public.crm_verify_enrollment(p_id bigint, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_verify_enrollment(p_id bigint, p jsonb) to authenticated;
grant execute on function public.crm_verify_enrollment(p_id bigint, p jsonb) to service_role;
revoke all on function public.crm_verify_start(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.crm_verify_start(p jsonb) to service_role;
revoke all on function public.crm_whatsapp_window(p_lead bigint) from public, anon, authenticated, service_role;
grant execute on function public.crm_whatsapp_window(p_lead bigint) to authenticated;
grant execute on function public.crm_whatsapp_window(p_lead bigint) to service_role;
revoke all on function public.current_referral_code() from public, anon, authenticated, service_role;
grant execute on function public.current_referral_code() to anon;
grant execute on function public.current_referral_code() to authenticated;
grant execute on function public.current_referral_code() to service_role;
revoke all on function public.influencer_dashboard_leads(p_referral_code text, p_password text) from public, anon, authenticated, service_role;
grant execute on function public.influencer_dashboard_leads(p_referral_code text, p_password text) to anon;
grant execute on function public.influencer_dashboard_leads(p_referral_code text, p_password text) to authenticated;
grant execute on function public.influencer_dashboard_leads(p_referral_code text, p_password text) to service_role;
revoke all on function public.is_admin() from public, anon, authenticated, service_role;
grant execute on function public.is_admin() to anon;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_admin() to service_role;
revoke all on function public.lead_intake(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.lead_intake(p jsonb) to authenticated;
grant execute on function public.lead_intake(p jsonb) to service_role;
revoke all on function public.match_documents(query_embedding vector, match_count integer, filter jsonb) from public, anon, authenticated, service_role;
grant execute on function public.match_documents(query_embedding vector, match_count integer, filter jsonb) to public;
grant execute on function public.match_documents(query_embedding vector, match_count integer, filter jsonb) to anon;
grant execute on function public.match_documents(query_embedding vector, match_count integer, filter jsonb) to authenticated;
grant execute on function public.match_documents(query_embedding vector, match_count integer, filter jsonb) to service_role;
revoke all on function public.match_eduwit_knowledge_base(query_embedding vector, match_count integer, filter jsonb) from public, anon, authenticated, service_role;
grant execute on function public.match_eduwit_knowledge_base(query_embedding vector, match_count integer, filter jsonb) to public;
grant execute on function public.match_eduwit_knowledge_base(query_embedding vector, match_count integer, filter jsonb) to anon;
grant execute on function public.match_eduwit_knowledge_base(query_embedding vector, match_count integer, filter jsonb) to authenticated;
grant execute on function public.match_eduwit_knowledge_base(query_embedding vector, match_count integer, filter jsonb) to service_role;
revoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;
grant execute on function public.rls_auto_enable() to public;
grant execute on function public.rls_auto_enable() to anon;
grant execute on function public.rls_auto_enable() to authenticated;
grant execute on function public.rls_auto_enable() to service_role;
revoke all on function public.student_leads_bulk_delete_guard() from public, anon, authenticated, service_role;
grant execute on function public.student_leads_bulk_delete_guard() to public;
grant execute on function public.student_leads_bulk_delete_guard() to anon;
grant execute on function public.student_leads_bulk_delete_guard() to authenticated;
grant execute on function public.student_leads_bulk_delete_guard() to service_role;
revoke all on function public.student_leads_touch() from public, anon, authenticated, service_role;
grant execute on function public.student_leads_touch() to public;
grant execute on function public.student_leads_touch() to anon;
grant execute on function public.student_leads_touch() to authenticated;
grant execute on function public.student_leads_touch() to service_role;
revoke all on function public.w2_add_feedback(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_add_feedback(p jsonb) to public;
grant execute on function public.w2_add_feedback(p jsonb) to anon;
grant execute on function public.w2_add_feedback(p jsonb) to authenticated;
grant execute on function public.w2_add_feedback(p jsonb) to service_role;
revoke all on function public.w2_add_source(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_add_source(p jsonb) to public;
grant execute on function public.w2_add_source(p jsonb) to anon;
grant execute on function public.w2_add_source(p jsonb) to authenticated;
grant execute on function public.w2_add_source(p jsonb) to service_role;
revoke all on function public.w2_bot_check(p_phone text) from public, anon, authenticated, service_role;
grant execute on function public.w2_bot_check(p_phone text) to public;
grant execute on function public.w2_bot_check(p_phone text) to anon;
grant execute on function public.w2_bot_check(p_phone text) to authenticated;
grant execute on function public.w2_bot_check(p_phone text) to service_role;
revoke all on function public.w2_build_prompt(p_name text) from public, anon, authenticated, service_role;
grant execute on function public.w2_build_prompt(p_name text) to public;
grant execute on function public.w2_build_prompt(p_name text) to anon;
grant execute on function public.w2_build_prompt(p_name text) to authenticated;
grant execute on function public.w2_build_prompt(p_name text) to service_role;
revoke all on function public.w2_bump(p_key text) from public, anon, authenticated, service_role;
grant execute on function public.w2_bump(p_key text) to public;
grant execute on function public.w2_bump(p_key text) to anon;
grant execute on function public.w2_bump(p_key text) to authenticated;
grant execute on function public.w2_bump(p_key text) to service_role;
revoke all on function public.w2_cache_plan(p_model text, p_refresh_minutes integer) from public, anon, authenticated, service_role;
grant execute on function public.w2_cache_plan(p_model text, p_refresh_minutes integer) to public;
grant execute on function public.w2_cache_plan(p_model text, p_refresh_minutes integer) to anon;
grant execute on function public.w2_cache_plan(p_model text, p_refresh_minutes integer) to authenticated;
grant execute on function public.w2_cache_plan(p_model text, p_refresh_minutes integer) to service_role;
revoke all on function public.w2_cache_saved(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_cache_saved(p jsonb) to public;
grant execute on function public.w2_cache_saved(p jsonb) to anon;
grant execute on function public.w2_cache_saved(p jsonb) to authenticated;
grant execute on function public.w2_cache_saved(p jsonb) to service_role;
revoke all on function public.w2_catalog_index() from public, anon, authenticated, service_role;
grant execute on function public.w2_catalog_index() to public;
grant execute on function public.w2_catalog_index() to anon;
grant execute on function public.w2_catalog_index() to authenticated;
grant execute on function public.w2_catalog_index() to service_role;
revoke all on function public.w2_commit_turn(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_commit_turn(p jsonb) to public;
grant execute on function public.w2_commit_turn(p jsonb) to anon;
grant execute on function public.w2_commit_turn(p jsonb) to authenticated;
grant execute on function public.w2_commit_turn(p jsonb) to service_role;
revoke all on function public.w2_crm_owned(p_phone text) from public, anon, authenticated, service_role;
grant execute on function public.w2_crm_owned(p_phone text) to authenticated;
grant execute on function public.w2_crm_owned(p_phone text) to service_role;
revoke all on function public.w2_crm_payload(p_phone text, p_event text, p_key text, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_crm_payload(p_phone text, p_event text, p_key text, p jsonb) to public;
grant execute on function public.w2_crm_payload(p_phone text, p_event text, p_key text, p jsonb) to anon;
grant execute on function public.w2_crm_payload(p_phone text, p_event text, p_key text, p jsonb) to authenticated;
grant execute on function public.w2_crm_payload(p_phone text, p_event text, p_key text, p jsonb) to service_role;
revoke all on function public.w2_drive_done(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_drive_done(p jsonb) to public;
grant execute on function public.w2_drive_done(p jsonb) to anon;
grant execute on function public.w2_drive_done(p jsonb) to authenticated;
grant execute on function public.w2_drive_done(p jsonb) to service_role;
revoke all on function public.w2_drive_kind(p_mime text, p_name text) from public, anon, authenticated, service_role;
grant execute on function public.w2_drive_kind(p_mime text, p_name text) to public;
grant execute on function public.w2_drive_kind(p_mime text, p_name text) to anon;
grant execute on function public.w2_drive_kind(p_mime text, p_name text) to authenticated;
grant execute on function public.w2_drive_kind(p_mime text, p_name text) to service_role;
revoke all on function public.w2_drive_plan(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_drive_plan(p jsonb) to public;
grant execute on function public.w2_drive_plan(p jsonb) to anon;
grant execute on function public.w2_drive_plan(p jsonb) to authenticated;
grant execute on function public.w2_drive_plan(p jsonb) to service_role;
revoke all on function public.w2_fee_sanity(p_level text, p_dual boolean, p_y numeric, p_s numeric, p_t numeric) from public, anon, authenticated, service_role;
grant execute on function public.w2_fee_sanity(p_level text, p_dual boolean, p_y numeric, p_s numeric, p_t numeric) to public;
grant execute on function public.w2_fee_sanity(p_level text, p_dual boolean, p_y numeric, p_s numeric, p_t numeric) to anon;
grant execute on function public.w2_fee_sanity(p_level text, p_dual boolean, p_y numeric, p_s numeric, p_t numeric) to authenticated;
grant execute on function public.w2_fee_sanity(p_level text, p_dual boolean, p_y numeric, p_s numeric, p_t numeric) to service_role;
revoke all on function public.w2_inbox_add(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_inbox_add(p jsonb) to public;
grant execute on function public.w2_inbox_add(p jsonb) to anon;
grant execute on function public.w2_inbox_add(p jsonb) to authenticated;
grant execute on function public.w2_inbox_add(p jsonb) to service_role;
revoke all on function public.w2_is_blocked(p_phone text) from public, anon, authenticated, service_role;
grant execute on function public.w2_is_blocked(p_phone text) to public;
grant execute on function public.w2_is_blocked(p_phone text) to anon;
grant execute on function public.w2_is_blocked(p_phone text) to authenticated;
grant execute on function public.w2_is_blocked(p_phone text) to service_role;
revoke all on function public.w2_is_test(p_phone text) from public, anon, authenticated, service_role;
grant execute on function public.w2_is_test(p_phone text) to public;
grant execute on function public.w2_is_test(p_phone text) to anon;
grant execute on function public.w2_is_test(p_phone text) to authenticated;
grant execute on function public.w2_is_test(p_phone text) to service_role;
revoke all on function public.w2_issue_code(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_issue_code(p jsonb) to public;
grant execute on function public.w2_issue_code(p jsonb) to anon;
grant execute on function public.w2_issue_code(p jsonb) to authenticated;
grant execute on function public.w2_issue_code(p jsonb) to service_role;
revoke all on function public.w2_kb_commit(p_batch text, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_kb_commit(p_batch text, p jsonb) to public;
grant execute on function public.w2_kb_commit(p_batch text, p jsonb) to anon;
grant execute on function public.w2_kb_commit(p_batch text, p jsonb) to authenticated;
grant execute on function public.w2_kb_commit(p_batch text, p jsonb) to service_role;
revoke all on function public.w2_kb_missing(p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.w2_kb_missing(p_limit integer) to public;
grant execute on function public.w2_kb_missing(p_limit integer) to anon;
grant execute on function public.w2_kb_missing(p_limit integer) to authenticated;
grant execute on function public.w2_kb_missing(p_limit integer) to service_role;
revoke all on function public.w2_kb_remove(p_source_file text) from public, anon, authenticated, service_role;
grant execute on function public.w2_kb_remove(p_source_file text) to public;
grant execute on function public.w2_kb_remove(p_source_file text) to anon;
grant execute on function public.w2_kb_remove(p_source_file text) to authenticated;
grant execute on function public.w2_kb_remove(p_source_file text) to service_role;
revoke all on function public.w2_kb_search(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_kb_search(p jsonb) to public;
grant execute on function public.w2_kb_search(p jsonb) to anon;
grant execute on function public.w2_kb_search(p jsonb) to authenticated;
grant execute on function public.w2_kb_search(p jsonb) to service_role;
revoke all on function public.w2_kb_set_embeddings(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_kb_set_embeddings(p jsonb) to public;
grant execute on function public.w2_kb_set_embeddings(p jsonb) to anon;
grant execute on function public.w2_kb_set_embeddings(p jsonb) to authenticated;
grant execute on function public.w2_kb_set_embeddings(p jsonb) to service_role;
revoke all on function public.w2_kb_stage_add(p_batch text, p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_kb_stage_add(p_batch text, p jsonb) to public;
grant execute on function public.w2_kb_stage_add(p_batch text, p jsonb) to anon;
grant execute on function public.w2_kb_stage_add(p_batch text, p jsonb) to authenticated;
grant execute on function public.w2_kb_stage_add(p_batch text, p jsonb) to service_role;
revoke all on function public.w2_learning_apply() from public, anon, authenticated, service_role;
grant execute on function public.w2_learning_apply() to public;
grant execute on function public.w2_learning_apply() to anon;
grant execute on function public.w2_learning_apply() to authenticated;
grant execute on function public.w2_learning_apply() to service_role;
revoke all on function public.w2_learning_digest(p_hours integer, p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.w2_learning_digest(p_hours integer, p_limit integer) to public;
grant execute on function public.w2_learning_digest(p_hours integer, p_limit integer) to anon;
grant execute on function public.w2_learning_digest(p_hours integer, p_limit integer) to authenticated;
grant execute on function public.w2_learning_digest(p_hours integer, p_limit integer) to service_role;
revoke all on function public.w2_learning_save(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_learning_save(p jsonb) to public;
grant execute on function public.w2_learning_save(p jsonb) to anon;
grant execute on function public.w2_learning_save(p jsonb) to authenticated;
grant execute on function public.w2_learning_save(p jsonb) to service_role;
revoke all on function public.w2_nurture_done(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_nurture_done(p jsonb) to public;
grant execute on function public.w2_nurture_done(p jsonb) to anon;
grant execute on function public.w2_nurture_done(p jsonb) to authenticated;
grant execute on function public.w2_nurture_done(p jsonb) to service_role;
revoke all on function public.w2_nurture_due(p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.w2_nurture_due(p_limit integer) to public;
grant execute on function public.w2_nurture_due(p_limit integer) to anon;
grant execute on function public.w2_nurture_due(p_limit integer) to authenticated;
grant execute on function public.w2_nurture_due(p_limit integer) to service_role;
revoke all on function public.w2_nurture_offset(p_step integer) from public, anon, authenticated, service_role;
grant execute on function public.w2_nurture_offset(p_step integer) to public;
grant execute on function public.w2_nurture_offset(p_step integer) to anon;
grant execute on function public.w2_nurture_offset(p_step integer) to authenticated;
grant execute on function public.w2_nurture_offset(p_step integer) to service_role;
revoke all on function public.w2_outbox_claim(p_worker text, p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.w2_outbox_claim(p_worker text, p_limit integer) to public;
grant execute on function public.w2_outbox_claim(p_worker text, p_limit integer) to anon;
grant execute on function public.w2_outbox_claim(p_worker text, p_limit integer) to authenticated;
grant execute on function public.w2_outbox_claim(p_worker text, p_limit integer) to service_role;
revoke all on function public.w2_outbox_result(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_outbox_result(p jsonb) to public;
grant execute on function public.w2_outbox_result(p jsonb) to anon;
grant execute on function public.w2_outbox_result(p jsonb) to authenticated;
grant execute on function public.w2_outbox_result(p jsonb) to service_role;
revoke all on function public.w2_outbox_retry(p_limit integer) from public, anon, authenticated, service_role;
grant execute on function public.w2_outbox_retry(p_limit integer) to public;
grant execute on function public.w2_outbox_retry(p_limit integer) to anon;
grant execute on function public.w2_outbox_retry(p_limit integer) to authenticated;
grant execute on function public.w2_outbox_retry(p_limit integer) to service_role;
revoke all on function public.w2_parse_rating(p_text text) from public, anon, authenticated, service_role;
grant execute on function public.w2_parse_rating(p_text text) to public;
grant execute on function public.w2_parse_rating(p_text text) to anon;
grant execute on function public.w2_parse_rating(p_text text) to authenticated;
grant execute on function public.w2_parse_rating(p_text text) to service_role;
revoke all on function public.w2_pv(pr jsonb, f text) from public, anon, authenticated, service_role;
grant execute on function public.w2_pv(pr jsonb, f text) to public;
grant execute on function public.w2_pv(pr jsonb, f text) to anon;
grant execute on function public.w2_pv(pr jsonb, f text) to authenticated;
grant execute on function public.w2_pv(pr jsonb, f text) to service_role;
revoke all on function public.w2_redeem_code(p_phone text, p_text text) from public, anon, authenticated, service_role;
grant execute on function public.w2_redeem_code(p_phone text, p_text text) to public;
grant execute on function public.w2_redeem_code(p_phone text, p_text text) to anon;
grant execute on function public.w2_redeem_code(p_phone text, p_text text) to authenticated;
grant execute on function public.w2_redeem_code(p_phone text, p_text text) to service_role;
revoke all on function public.w2_register_lead(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_register_lead(p jsonb) to public;
grant execute on function public.w2_register_lead(p jsonb) to anon;
grant execute on function public.w2_register_lead(p jsonb) to authenticated;
grant execute on function public.w2_register_lead(p jsonb) to service_role;
revoke all on function public.w2_release(p_phone text, p_run text) from public, anon, authenticated, service_role;
grant execute on function public.w2_release(p_phone text, p_run text) to public;
grant execute on function public.w2_release(p_phone text, p_run text) to anon;
grant execute on function public.w2_release(p_phone text, p_run text) to authenticated;
grant execute on function public.w2_release(p_phone text, p_run text) to service_role;
revoke all on function public.w2_search_programs(q jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_search_programs(q jsonb) to public;
grant execute on function public.w2_search_programs(q jsonb) to anon;
grant execute on function public.w2_search_programs(q jsonb) to authenticated;
grant execute on function public.w2_search_programs(q jsonb) to service_role;
revoke all on function public.w2_search_programs_cached(q jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_search_programs_cached(q jsonb) to public;
grant execute on function public.w2_search_programs_cached(q jsonb) to anon;
grant execute on function public.w2_search_programs_cached(q jsonb) to authenticated;
grant execute on function public.w2_search_programs_cached(q jsonb) to service_role;
revoke all on function public.w2_source_report(p_days integer) from public, anon, authenticated, service_role;
grant execute on function public.w2_source_report(p_days integer) to public;
grant execute on function public.w2_source_report(p_days integer) to anon;
grant execute on function public.w2_source_report(p_days integer) to authenticated;
grant execute on function public.w2_source_report(p_days integer) to service_role;
revoke all on function public.w2_stale_inbox(p_older_than_seconds integer) from public, anon, authenticated, service_role;
grant execute on function public.w2_stale_inbox(p_older_than_seconds integer) to public;
grant execute on function public.w2_stale_inbox(p_older_than_seconds integer) to anon;
grant execute on function public.w2_stale_inbox(p_older_than_seconds integer) to authenticated;
grant execute on function public.w2_stale_inbox(p_older_than_seconds integer) to service_role;
revoke all on function public.w2_test_prepare(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_test_prepare(p jsonb) to public;
grant execute on function public.w2_test_prepare(p jsonb) to anon;
grant execute on function public.w2_test_prepare(p jsonb) to authenticated;
grant execute on function public.w2_test_prepare(p jsonb) to service_role;
revoke all on function public.w2_test_reset(p_phone text) from public, anon, authenticated, service_role;
grant execute on function public.w2_test_reset(p_phone text) to public;
grant execute on function public.w2_test_reset(p_phone text) to anon;
grant execute on function public.w2_test_reset(p_phone text) to authenticated;
grant execute on function public.w2_test_reset(p_phone text) to service_role;
revoke all on function public.w2_test_result(p_phone text, p_since timestamp with time zone) from public, anon, authenticated, service_role;
grant execute on function public.w2_test_result(p_phone text, p_since timestamp with time zone) to public;
grant execute on function public.w2_test_result(p_phone text, p_since timestamp with time zone) to anon;
grant execute on function public.w2_test_result(p_phone text, p_since timestamp with time zone) to authenticated;
grant execute on function public.w2_test_result(p_phone text, p_since timestamp with time zone) to service_role;
revoke all on function public.w2_test_send(p_phone text, p_text text, p_tag text) from public, anon, authenticated, service_role;
grant execute on function public.w2_test_send(p_phone text, p_text text, p_tag text) to public;
grant execute on function public.w2_test_send(p_phone text, p_text text, p_tag text) to anon;
grant execute on function public.w2_test_send(p_phone text, p_text text, p_tag text) to authenticated;
grant execute on function public.w2_test_send(p_phone text, p_text text, p_tag text) to service_role;
revoke all on function public.w2_test_step(p jsonb) from public, anon, authenticated, service_role;
grant execute on function public.w2_test_step(p jsonb) to public;
grant execute on function public.w2_test_step(p jsonb) to anon;
grant execute on function public.w2_test_step(p jsonb) to authenticated;
grant execute on function public.w2_test_step(p jsonb) to service_role;
revoke all on function public.w2_test_transcript(p_phone text) from public, anon, authenticated, service_role;
grant execute on function public.w2_test_transcript(p_phone text) to public;
grant execute on function public.w2_test_transcript(p_phone text) to anon;
grant execute on function public.w2_test_transcript(p_phone text) to authenticated;
grant execute on function public.w2_test_transcript(p_phone text) to service_role;
revoke all on function public.w2_try_claim(p_phone text, p_run text, p_lease_seconds integer) from public, anon, authenticated, service_role;
grant execute on function public.w2_try_claim(p_phone text, p_run text, p_lease_seconds integer) to public;
grant execute on function public.w2_try_claim(p_phone text, p_run text, p_lease_seconds integer) to anon;
grant execute on function public.w2_try_claim(p_phone text, p_run text, p_lease_seconds integer) to authenticated;
grant execute on function public.w2_try_claim(p_phone text, p_run text, p_lease_seconds integer) to service_role;
revoke all on function public.w2_turn_prompts() from public, anon, authenticated, service_role;
grant execute on function public.w2_turn_prompts() to public;
grant execute on function public.w2_turn_prompts() to anon;
grant execute on function public.w2_turn_prompts() to authenticated;
grant execute on function public.w2_turn_prompts() to service_role;
revoke all on function public.w2_unblock(p_phone text, p_by text, p_note text) from public, anon, authenticated, service_role;
grant execute on function public.w2_unblock(p_phone text, p_by text, p_note text) to public;
grant execute on function public.w2_unblock(p_phone text, p_by text, p_note text) to anon;
grant execute on function public.w2_unblock(p_phone text, p_by text, p_note text) to authenticated;
grant execute on function public.w2_unblock(p_phone text, p_by text, p_note text) to service_role;
