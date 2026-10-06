-- M15a: the mapping layer's tables (spec B8.3.6) and the canonical registry (B8.3.1).
-- Normalised tables in schema b2b. The old CRM's public.partner_mapping_profiles is left untouched (empty, unused by
-- the B2B CRM). A partner has at most one active and one draft profile; rules belong to one profile version, so a
-- published version never changes and any earlier version can be restored.
-- Canonical values that have no column on student_leads (counsellor, call outcome, documents status, refunds…) are kept
-- per allocation in allocations.partner_fields; partner fields nobody mapped are kept in allocations.partner_custom.
-- Nothing a partner sends is dropped. No row here is ever erased either: a discarded draft is retired without a
-- version number, removing a rule makes a new draft without it, and golden files are archived.

create table if not exists b2b.canonical_fields (
  key            text primary key check (key ~ '^[a-z][a-z0-9_]{1,60}$'),
  grp            text not null check (grp in ('lead', 'sales')),
  label          text not null,
  data_type      text not null check (data_type in ('text', 'number', 'date', 'datetime', 'boolean', 'phone', 'email', 'picklist')),
  allowed        text[],
  lead_column    text,          -- student_leads column it reads (out) and writes (in); null: kept in allocations.partner_fields
  source         text,          -- computed outbound value ($reference, $phone_e164, $course…) when not a plain column
  owner          text not null check (owner in ('witty', 'intake', 'b2b')),
  outbound       boolean not null default false,   -- may be sent to a partner (never budget, source, campaign, score)
  inbound        boolean not null default false,   -- may be written from partner data
  required_out   boolean not null default false,
  required_in    boolean not null default false,
  sort           int not null default 100
);

insert into b2b.canonical_fields (key, grp, label, data_type, allowed, lead_column, source, owner, outbound, inbound, required_out, required_in, sort) values
  ('reference',             'lead',  'Eduwit reference (EDW-…)',      'text',     null, null, '$reference', 'b2b', true, false, true, false, 1),
  ('full_name',             'lead',  'Student name',                  'text',     null, 'student_name', null, 'witty', true, true, true, false, 2),
  ('phone',                 'lead',  'Phone (E.164)',                 'phone',    null, null, '$phone_e164', 'intake', true, false, true, false, 3),
  ('email',                 'lead',  'Email',                         'email',    null, 'email_id', null, 'witty', true, true, false, false, 4),
  ('alternate_phone',       'lead',  'Alternate phone',               'phone',    null, 'alternate_phone', null, 'witty', true, true, false, false, 5),
  ('city',                  'lead',  'City',                          'text',     null, 'city', null, 'witty', true, true, false, false, 6),
  ('state',                 'lead',  'State',                         'text',     null, 'state', null, 'witty', true, true, false, false, 7),
  ('country',               'lead',  'Country',                       'text',     null, 'country', null, 'witty', true, true, false, false, 8),
  ('preferred_language',    'lead',  'Preferred language',            'text',     null, 'preferred_language', null, 'witty', true, true, false, false, 9),
  ('guardian_name',         'lead',  'Parent or guardian name',       'text',     null, 'guardian_name', null, 'witty', true, true, false, false, 10),
  ('guardian_phone',        'lead',  'Parent or guardian phone',      'phone',    null, 'guardian_phone', null, 'witty', true, true, false, false, 11),
  ('university',            'lead',  'University',                    'text',     null, null, '$university', 'b2b', true, false, false, false, 20),
  ('course',                'lead',  'Course',                        'text',     null, null, '$course', 'b2b', true, true, true, false, 21),
  ('specialization',        'lead',  'Specialization',                'text',     null, null, '$specialization', 'b2b', true, true, false, false, 22),
  ('programme_level',       'lead',  'Level',                         'picklist', array['UG', 'PG', 'DIPLOMA', 'CERTIFICATE'], null, '$level', 'b2b', true, true, false, false, 23),
  ('study_mode',            'lead',  'Study mode',                    'picklist', array['Online', 'ODL', 'Regular'], null, '$mode', 'b2b', true, true, false, false, 24),
  ('partner_course_code',   'lead',  'Partner course code',           'text',     null, null, '$partner_course_code', 'b2b', true, false, false, false, 25),
  ('highest_qualification', 'lead',  'Highest qualification',         'picklist', array['10th', '12th', 'Diploma', 'Bachelors', 'Masters', 'Doctorate'], 'highest_qualification', null, 'witty', true, true, false, false, 30),
  ('academic_score_pct',    'lead',  'Academic score (%)',            'number',   null, 'academic_score_pct', null, 'witty', true, true, false, false, 31),
  ('work_experience_years', 'lead',  'Work experience (years)',       'number',   null, 'work_experience_years_num', null, 'witty', true, true, false, false, 32),
  ('current_job_role',      'lead',  'Current job role',              'text',     null, 'current_job_role', null, 'witty', true, true, false, false, 33),
  ('enrollment_timeline',   'lead',  'Wants to start',                'text',     null, 'enrollment_timeline', null, 'witty', true, true, false, false, 34),
  ('annual_budget_inr',     'lead',  'Annual budget (₹)', 'number',   null, 'annual_budget_inr', null, 'witty', false, true, false, false, 35),
  ('consent_partner_share_at', 'lead', 'Partner-sharing consent time', 'datetime', null, 'consent_partner_share_at', null, 'intake', true, false, false, false, 36),
  ('partner_record_id',     'sales', 'Partner record ID',             'text',     null, 'partner_record_id', null, 'b2b', false, true, false, false, 50),
  ('counsellor_name',       'sales', 'Counsellor name',               'text',     null, null, null, 'b2b', false, true, false, true, 51),
  ('counsellor_id',         'sales', 'Counsellor external ID',        'text',     null, null, null, 'b2b', false, true, false, false, 52),
  ('counsellor_email',      'sales', 'Counsellor email',              'email',    null, null, null, 'b2b', false, true, false, false, 53),
  ('counsellor_phone',      'sales', 'Counsellor phone',              'phone',    null, null, null, 'b2b', false, true, false, false, 54),
  ('call_outcome',          'sales', 'Last call outcome',             'picklist', array['connected', 'no_answer', 'busy', 'switched_off', 'wrong_number', 'call_back'], null, null, 'b2b', false, true, false, true, 55),
  ('call_attempts',         'sales', 'Call attempts',                 'number',   null, 'contact_attempts', null, 'b2b', false, true, false, false, 56),
  ('first_call_at',         'sales', 'First call time',               'datetime', null, 'first_contacted_at', null, 'b2b', false, true, false, false, 57),
  ('last_call_at',          'sales', 'Last call time',                'datetime', null, 'last_contacted_at', null, 'b2b', false, true, false, false, 58),
  ('next_follow_up_at',     'sales', 'Next follow-up',                'datetime', null, 'next_task_due_at', null, 'b2b', false, true, false, true, 59),
  ('counselling_done',      'sales', 'Counselling done',              'boolean',  null, null, null, 'b2b', false, true, false, false, 60),
  ('counselling_at',        'sales', 'Counselling time',              'datetime', null, null, null, 'b2b', false, true, false, false, 61),
  ('application_id',        'sales', 'Application ID',                'text',     null, 'application_id', null, 'b2b', false, true, false, false, 62),
  ('application_status',    'sales', 'Application status',            'picklist', array['not_started', 'in_progress', 'submitted', 'under_review', 'accepted', 'rejected'], 'application_status', null, 'b2b', false, true, false, true, 63),
  ('applied_at',            'sales', 'Application date',              'datetime', null, 'applied_at', null, 'b2b', false, true, false, false, 64),
  ('documents_status',      'sales', 'Documents status',              'picklist', array['pending', 'partial', 'complete', 'verified'], null, null, 'b2b', false, true, false, false, 65),
  ('fee_amount_inr',        'sales', 'Fee amount (₹)',                'number',   null, 'fee_amount_inr', null, 'b2b', false, true, false, false, 66),
  ('fee_paid_inr',          'sales', 'Amount paid (₹)',               'number',   null, 'fee_paid_inr', null, 'b2b', false, true, false, true, 67),
  ('payment_date',          'sales', 'Payment date',                  'date',     null, null, null, 'b2b', false, true, false, false, 68),
  ('enrollment_id',         'sales', 'Enrollment ID',                 'text',     null, null, null, 'b2b', false, true, false, false, 69),
  ('enrollment_date',       'sales', 'Enrollment date',               'date',     null, 'enrollment_date', null, 'b2b', false, true, false, true, 70),
  ('enrolled_program',      'sales', 'Enrolled programme',            'text',     null, 'enrolled_program', null, 'b2b', false, true, false, false, 71),
  ('enrolled_university',   'sales', 'Enrolled university',           'text',     null, 'enrolled_university', null, 'b2b', false, true, false, false, 72),
  ('enrollment_status',     'sales', 'Enrollment status',             'picklist', array['pending', 'enrolled', 'cancelled', 'refunded'], 'enrollment_status', null, 'b2b', false, true, false, false, 73),
  ('refund_amount_inr',     'sales', 'Refund amount (₹)',             'number',   null, null, null, 'b2b', false, true, false, false, 74),
  ('refund_date',           'sales', 'Refund date',                   'date',     null, null, null, 'b2b', false, true, false, false, 75),
  ('refund_reason',         'sales', 'Refund reason',                 'text',     null, null, null, 'b2b', false, true, false, false, 76),
  ('lost_reason',           'sales', 'Lost reason',                   'picklist', null, 'lost_reason', null, 'b2b', false, true, false, true, 77),
  ('remarks',               'sales', 'Counsellor remarks',            'text',     null, null, null, 'b2b', false, true, false, false, 78)
on conflict (key) do nothing;

create table if not exists b2b.partner_schema_snapshots (
  id          bigint generated always as identity primary key,
  partner_id  bigint not null references b2b.partners (id) on delete cascade,
  source      text not null check (source in ('upload', 'api', 'events')),
  schema      jsonb not null,   -- {fields:[{name,label,type,values[]}], stages:[{stage, sub_stages[]}], pipelines[], activities:[{type, outcomes[]}]}
  drift       jsonb,            -- differences found against the previous snapshot
  created_at  timestamptz not null default now(),
  created_by  text
);
create index if not exists partner_schema_snapshots_partner_idx on b2b.partner_schema_snapshots (partner_id, id desc);

create table if not exists b2b.mapping_profiles (
  id             bigint generated always as identity primary key,
  partner_id     bigint not null references b2b.partners (id) on delete cascade,
  version        int,                 -- null while draft; numbered on publish
  status         text not null default 'draft' check (status in ('draft', 'active', 'retired')),
  pipeline_field text not null default 'pipeline',   -- which payload field names the partner pipeline
  note           text,
  based_on       bigint references b2b.mapping_profiles (id),
  created_at     timestamptz not null default now(),
  created_by     text,
  activated_at   timestamptz,
  activated_by   text,
  unique (partner_id, version)
);
create unique index if not exists mapping_profiles_one_active on b2b.mapping_profiles (partner_id) where status = 'active';
create unique index if not exists mapping_profiles_one_draft on b2b.mapping_profiles (partner_id) where status = 'draft';

create table if not exists b2b.mapping_pipelines (
  id          bigint generated always as identity primary key,
  profile_id  bigint not null references b2b.mapping_profiles (id) on delete cascade,
  key         text not null,
  label       text,
  unique (profile_id, key)
);

create table if not exists b2b.status_rules (
  id                 bigint generated always as identity primary key,
  profile_id         bigint not null references b2b.mapping_profiles (id) on delete cascade,
  pipeline_key       text,               -- null: every pipeline
  partner_stage      text not null,
  partner_sub_stage  text,               -- null: any sub-stage (wildcard)
  conditions         jsonb not null default '[]',   -- [{field, op: eq|neq|in|empty|not_empty, value}], all must hold
  stage              text,               -- Eduwit stage; null when ignored
  sub_stage          text,
  lost_reason        text,
  is_reopen          boolean not null default false,
  ignore             boolean not null default false,
  ignore_reason      text,
  priority           int not null default 100,
  check (ignore or stage is not null),
  check (not ignore or length(trim(coalesce(ignore_reason, ''))) >= 3)
);
create index if not exists status_rules_profile_idx on b2b.status_rules (profile_id);

create table if not exists b2b.field_rules (
  id             bigint generated always as identity primary key,
  profile_id     bigint not null references b2b.mapping_profiles (id) on delete cascade,
  partner_field  text,                   -- null with not_available: the partner has no such field
  canonical_key  text not null references b2b.canonical_fields (key),
  direction      text not null default 'both' check (direction in ('in', 'out', 'both')),
  transforms     jsonb not null default '[]',   -- chain applied inbound (partner → Eduwit)
  out_transforms jsonb not null default '[]',   -- chain applied outbound (Eduwit → partner)
  trusted        boolean not null default false,
  required       boolean not null default false,   -- the partner's API requires it (outbound)
  not_available  boolean not null default false,
  note           text,
  check (not_available or partner_field is not null)
);
create index if not exists field_rules_profile_idx on b2b.field_rules (profile_id);

create table if not exists b2b.value_rules (
  id               bigint generated always as identity primary key,
  profile_id       bigint not null references b2b.mapping_profiles (id) on delete cascade,
  canonical_key    text not null references b2b.canonical_fields (key),
  partner_value    text not null,
  canonical_value  text not null,
  direction        text not null default 'both' check (direction in ('in', 'out', 'both'))
);
create index if not exists value_rules_profile_idx on b2b.value_rules (profile_id, canonical_key);

create table if not exists b2b.activity_rules (
  id               bigint generated always as identity primary key,
  profile_id       bigint not null references b2b.mapping_profiles (id) on delete cascade,
  partner_type     text not null,
  partner_outcome  text,                 -- null: any outcome
  kind             text not null check (kind in ('call', 'whatsapp', 'email', 'sms', 'meeting', 'note', 'task', 'stage_change')),
  outcome          text
);
create index if not exists activity_rules_profile_idx on b2b.activity_rules (profile_id);

/* Golden files (B8.3.7): a sample raw payload and the canonical result it must produce. Publishing runs them all. */
create table if not exists b2b.mapping_goldens (
  id          bigint generated always as identity primary key,
  partner_id  bigint not null references b2b.partners (id) on delete cascade,
  name        text not null,
  input       jsonb not null,
  expected    jsonb not null,      -- a subset of mapping_in's result that must match
  created_at  timestamptz not null default now(),
  archived_at timestamptz,         -- removed from the studio (rows are kept)
  unique (partner_id, name)
);

create table if not exists b2b.mapping_queue (
  id           bigint generated always as identity primary key,
  partner_id   bigint not null references b2b.partners (id) on delete cascade,
  kind         text not null check (kind in ('stage', 'field', 'value', 'activity', 'drift')),
  item         text not null,       -- e.g. 'Dead / RNR', 'mx_Lead_Quality', 'highest_qualification = Graduate'
  sample       jsonb,
  first_seen   timestamptz not null default now(),
  last_seen    timestamptz not null default now(),
  seen_count   int not null default 1,
  lead_ids     bigint[] not null default '{}',
  status       text not null default 'open' check (status in ('open', 'mapped', 'ignored')),
  resolution   text,
  resolved_at  timestamptz,
  unique (partner_id, kind, item)
);

alter table b2b.allocations add column if not exists partner_fields jsonb not null default '{}';
alter table b2b.allocations add column if not exists partner_custom jsonb not null default '{}';
alter table b2b.allocations add column if not exists mapping_version int;
alter table b2b.partner_events add column if not exists mapping_version int;
alter table b2b.partner_events add column if not exists mapped jsonb;

do $rls$
declare t text;
begin
  foreach t in array array['canonical_fields', 'partner_schema_snapshots', 'mapping_profiles', 'mapping_pipelines', 'status_rules', 'field_rules',
                           'value_rules', 'activity_rules', 'mapping_goldens', 'mapping_queue'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;
