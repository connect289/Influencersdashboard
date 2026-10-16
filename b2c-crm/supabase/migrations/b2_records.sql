-- B2C CRM b2: the lead records B2B pushes (a read-only cache, decision K1), B2C's own lifecycle per lead, Eduwit stages,
-- contact details and field history. Staging first.
--   stages / sub_stages   Eduwit's ten stages (spec B5.1) with the canonical mapping and Lost return rules (B6.4)
--   lead_records          the latest record B2B sent per lead (by version); never edited by B2C
--   leads_state           B2C's pipeline per lead: lane, pool, owner, Eduwit stage, effort, SLA, closing
--   lead_contacts         every phone and email on a lead; intake rows locked; one primary per purpose (B8.3)
--   field_history         every human correction and Admin edit

-- ---------- helpers ----------
create or replace function b2c.norm_phone(p text) returns text language sql immutable set search_path = '' as $f$
  select case
    when d is null or d = '' then null
    when length(d) = 10 then '91' || d
    when length(d) = 11 and left(d, 1) = '0' then '91' || substr(d, 2)
    else d end
  from (select regexp_replace(coalesce(p, ''), '\D', '', 'g') as d) x
$f$;

create or replace function b2c.is_test_phone(p text) returns boolean language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from jsonb_array_elements_text(coalesce(b2c.setting('test_phones') -> 'prefixes', '[]')) pre
                  where b2c.norm_phone(p) like pre || '%')
$f$;

-- ---------- Eduwit stages ----------
create table if not exists b2c.stages (
  id smallint primary key,
  name text not null unique,
  rank int not null,
  canon text not null check (canon in ('assigned', 'contacted', 'counselled', 'applied', 'enrolled', 'lost')),
  required jsonb not null default '[]'::jsonb,     -- codes checked by set_stage(): call_attempt, contact, profile, followup, programme_shared, application, checklist, enrollment, comment
  reachable_from_any boolean not null default false,
  is_closed boolean not null default false,
  active boolean not null default true
);
alter table b2c.stages enable row level security;

create table if not exists b2c.sub_stages (
  id int generated always as identity primary key,
  stage_id smallint not null references b2c.stages (id),
  name text not null,
  rank int not null,
  returns_to_pool boolean not null default true,     -- Lost only: false = never back to nurture
  journey text,                                      -- Lost only: the nurture journey it starts
  first_message_days int,                            -- Lost only: delay before the first nurture message
  comment_required boolean not null default false,
  active boolean not null default true,
  unique (stage_id, name)
);
alter table b2c.sub_stages enable row level security;

insert into b2c.stages (id, name, rank, canon, required, reachable_from_any, is_closed) values
  (1, 'New Lead', 10, 'assigned', '[]', false, false),
  (2, 'Could Not Connect', 20, 'contacted', '["call_attempt"]', true, false),
  (3, 'Contacted', 30, 'contacted', '["contact"]', false, false),
  (4, 'Qualified', 40, 'counselled', '["profile"]', false, false),
  (5, 'Follow Up', 50, 'counselled', '["followup"]', true, false),
  (6, 'Program Details Explained', 60, 'counselled', '["programme_shared"]', false, false),
  (7, 'Applicant', 70, 'applied', '["application"]', false, false),
  (8, 'Docs Submitted', 80, 'applied', '["checklist"]', false, false),
  (9, 'Enrolled', 90, 'enrolled', '["enrollment"]', false, true),
  (10, 'Lost', 999, 'lost', '["comment"]', true, true)
on conflict (id) do nothing;

insert into b2c.sub_stages (stage_id, name, rank, returns_to_pool, journey, first_message_days, comment_required)
select s, n, r, coalesce(rp, true), j, d, coalesce(cr, false) from (values
  (1, 'Fresh assignment', 1, null, null, null, null), (1, 'Re-engaged from nurture', 2, null, null, null, null), (1, 'Re-enquiry', 3, null, null, null, null),
  (1, 'Created by me', 4, null, null, null, null), (1, 'Returned from partners', 5, null, null, null, null),
  (2, 'No answer', 1, null, null, null, null), (2, 'Busy', 2, null, null, null, null), (2, 'Switched off', 3, null, null, null, null),
  (2, 'Wrong number', 4, null, null, null, null), (2, 'Call back requested', 5, null, null, null, null), (2, 'Invalid number', 6, null, null, null, null),
  (3, 'Spoke briefly', 1, null, null, null, null), (3, 'Asked to call later', 2, null, null, null, null), (3, 'Parent or guardian spoke', 3, null, null, null, null),
  (3, 'WhatsApp reply only', 4, null, null, null, null),
  (4, 'Eligible and interested', 1, null, null, null, null), (4, 'Eligible, undecided', 2, null, null, null, null), (4, 'Budget confirmed', 3, null, null, null, null),
  (4, 'Timeline confirmed', 4, null, null, null, null),
  (5, 'Call back on date', 1, null, null, null, null), (5, 'Awaiting parent decision', 2, null, null, null, null), (5, 'Comparing options', 3, null, null, null, null),
  (5, 'Awaiting documents', 4, null, null, null, null), (5, 'Awaiting fee arrangement or loan', 5, null, null, null, null),
  (6, 'Brochure shared', 1, null, null, null, null), (6, 'Fee and EMI explained', 2, null, null, null, null), (6, 'Comparison shared', 3, null, null, null, null),
  (6, 'University call arranged', 4, null, null, null, null),
  (7, 'Application started', 1, null, null, null, null), (7, 'Application submitted', 2, null, null, null, null), (7, 'Application fee paid', 3, null, null, null, null),
  (8, 'Partial', 1, null, null, null, null), (8, 'Complete', 2, null, null, null, null), (8, 'Verification pending', 3, null, null, null, null),
  (8, 'Verification query', 4, null, null, null, null),
  (9, 'Fee paid (partial)', 1, null, null, null, null), (9, 'Fee paid (full)', 2, null, null, null, null),
  (9, 'Enrollment confirmed by university', 3, null, null, null, null), (9, 'Verified by Admin', 4, null, null, null, null),
  (10, 'Uncontactable', 1, true, 'we_tried_to_reach_you', 3, false),
  (10, 'Not eligible', 2, true, 'eligible_programmes', 7, false),
  (10, 'Not interested', 3, true, 'reengage_60d', 60, false),
  (10, 'Can''t afford fee or EMI', 4, true, 'lower_fee_emi', 7, false),
  (10, 'Loan not approved', 5, true, 'lower_fee_emi', 7, false),
  (10, 'Document verification failed', 6, true, 'fix_and_reapply', 3, false),
  (10, 'Lost to competitor', 7, true, 'long_term_update', 90, false),
  (10, 'Chose another provider', 8, true, 'long_term_update', 90, false),
  (10, 'Not now, later', 9, true, 'monthly_update', 30, false),
  (10, 'Wrong number', 10, false, null, null, false),
  (10, 'Junk or test', 11, false, null, null, false),
  (10, 'Enrolled elsewhere', 12, false, null, null, false),
  (10, 'Opted out', 13, false, null, null, false),
  (10, 'Other', 14, true, 'monthly_update', 30, true)
) v(s, n, r, rp, j, d, cr)
where not exists (select 1 from b2c.sub_stages);

-- ---------- the B2B record cache ----------
create table if not exists b2c.lead_records (
  lead_id bigint primary key,
  version int not null,
  seq bigint,
  record jsonb not null,
  held_by_b2c boolean not null default false,
  is_test boolean not null default false,
  deleted boolean not null default false,
  merged_into_id bigint,
  origin text,
  received_at timestamptz not null default now()
);
alter table b2c.lead_records enable row level security;
create index if not exists lead_records_phone on b2c.lead_records ((b2c.norm_phone(record -> 'student' ->> 'phone')));

-- ---------- B2C lifecycle per lead ----------
create table if not exists b2c.leads_state (
  lead_id bigint primary key,
  lane text not null check (lane in ('sales', 'nurture')),
  status text not null default 'active' check (status in ('active', 'pool', 'closed')),
  handoff_reason text,
  cause text,
  allocation_id bigint,
  handoff_event_id text,
  handed_off_at timestamptz,
  handling jsonb not null default '{}'::jsonb,
  partner_bar_reason text,
  providers jsonb not null default '[]'::jsonb,
  b2c_actions jsonb not null default '[]'::jsonb,
  missing jsonb not null default '[]'::jsonb,
  partner_lost jsonb,
  -- nurture pool
  pool_entered_at timestamptz,
  pool_reason text,
  first_message_due_at timestamptz,
  journey text,
  reengaged_at timestamptz,
  reengage_trigger text,
  lost_by text check (lost_by in ('partner', 'counsellor')),
  lost_by_user uuid,
  -- ownership and pipeline
  owner_id uuid references b2c.users (user_id),
  previous_owner_id uuid references b2c.users (user_id),
  assigned_at timestamptz,
  stage_id smallint references b2c.stages (id),
  sub_stage text,
  stage_comment text,
  stage_changed_at timestamptz,
  hot boolean not null default false,
  temperature text check (temperature in ('hot', 'warm', 'cold')),
  score int,
  -- effort and SLA
  next_task_due_at timestamptz,
  first_contacted_at timestamptz,
  last_contacted_at timestamptz,
  contact_attempts int not null default 0,
  last_activity_at timestamptz,
  sla_due_at timestamptz,
  sla_met_at timestamptz,
  sla_breached_at timestamptz,
  -- other states
  flagged text,
  reenquired_at timestamptz,
  routing_requested_at timestamptz,
  routed_to_partner_at timestamptz,
  released_at timestamptz,
  dormant_at timestamptz,
  closed_at timestamptz,
  closed_reason text,
  tags text[] not null default '{}',
  is_test boolean not null default false,
  deleted_at timestamptz,
  delete_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table b2c.leads_state enable row level security;
create index if not exists leads_state_owner on b2c.leads_state (owner_id, status) where deleted_at is null;
create index if not exists leads_state_pool on b2c.leads_state (status, pool_entered_at) where status = 'pool';
create index if not exists leads_state_unassigned on b2c.leads_state (lane, status) where owner_id is null and status = 'active';

-- ---------- contacts ----------
create table if not exists b2c.lead_contacts (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  kind text not null check (kind in ('phone', 'email')),
  value text not null,
  value_norm text not null,
  label text check (label in ('intake', 'alternate', 'parent', 'office', 'whatsapp_only')),
  primary_call boolean not null default false,
  primary_wa boolean not null default false,
  primary_email boolean not null default false,
  origin text not null check (origin in ('intake', 'counsellor', 'admin')),
  added_by uuid,
  created_at timestamptz not null default now(),
  removed_at timestamptz,
  unique (lead_id, kind, value_norm)
);
alter table b2c.lead_contacts enable row level security;
create unique index if not exists lead_contacts_one_primary_call on b2c.lead_contacts (lead_id) where primary_call and removed_at is null;
create unique index if not exists lead_contacts_one_primary_wa on b2c.lead_contacts (lead_id) where primary_wa and removed_at is null;
create unique index if not exists lead_contacts_one_primary_email on b2c.lead_contacts (lead_id) where primary_email and removed_at is null;
create index if not exists lead_contacts_value on b2c.lead_contacts (value_norm);

/* Existing values never change except by the Admin (B8.3, B14 integrity rules). Intake rows are mirrored from the B2B
   record by apply_record(), which runs as the table owner with b2c.trusted set. */
create or replace function b2c.guard_contacts() returns trigger language plpgsql set search_path = '' as $f$
begin
  if coalesce(current_setting('b2c.trusted', true), '') = 'on' then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then raise exception 'contact details are never deleted; the Admin can remove one'; end if;
  if (new.value is distinct from old.value or new.value_norm is distinct from old.value_norm or new.kind is distinct from old.kind
      or new.removed_at is distinct from old.removed_at or new.origin is distinct from old.origin)
     and coalesce(b2c.my_role(), '') <> 'admin' then
    raise exception 'only the Admin can change or remove an existing phone number or email';
  end if;
  return new;
end $f$;
do $d$ begin
  if not exists (select 1 from pg_trigger where tgname = 'lead_contacts_guard') then
    create trigger lead_contacts_guard before update or delete on b2c.lead_contacts for each row execute function b2c.guard_contacts();
  end if;
end $d$;

create table if not exists b2c.field_history (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  field text not null,
  old_value jsonb,
  new_value jsonb,
  kind text not null check (kind in ('human_correction', 'admin_edit', 'cross_sell', 'contact')),
  reason text,
  actor_id uuid,
  at timestamptz not null default now()
);
alter table b2c.field_history enable row level security;
create index if not exists field_history_lead on b2c.field_history (lead_id, at desc);
do $d$ begin
  if not exists (select 1 from pg_trigger where tgname = 'field_history_append_only') then
    create trigger field_history_append_only before update or delete on b2c.field_history for each row execute function b2c.forbid_change();
  end if;
end $d$;

-- ---------- who may see a lead ----------
/* Admin and Marketing: every lead B2C knows. Sales head: every lead (team scoping when teams exist). Counsellor: own. */
create or replace function b2c.can_see(p_lead bigint) returns boolean language sql stable security definer set search_path = '' as $f$
  select case b2c.my_role()
    when 'admin' then true when 'marketing' then true when 'sales_head' then true
    when 'counsellor' then exists (select 1 from b2c.leads_state s where s.lead_id = p_lead and s.owner_id = b2c.uid() and s.deleted_at is null)
    else false end
$f$;

/* One lead as the screens need it: B2B record fields with standard names, plus B2C state. */
create or replace view b2c.leads_v with (security_invoker = true) as
select s.lead_id,
       r.version,
       r.record -> 'student' ->> 'name' as name,
       r.record -> 'student' ->> 'phone' as phone,
       r.record -> 'student' ->> 'email' as email,
       r.record -> 'student' ->> 'city' as city,
       r.record -> 'student' ->> 'state' as state,
       r.record -> 'student' ->> 'preferred_language' as language,
       r.record -> 'interest' ->> 'course' as course,
       r.record -> 'interest' ->> 'specialization' as specialization,
       r.record -> 'interest' ->> 'university' as university,
       r.record -> 'interest' ->> 'programme_level' as programme_level,
       r.record -> 'interest' ->> 'study_mode' as study_mode,
       r.record -> 'education' ->> 'highest_qualification' as qualification,
       r.record -> 'source' ->> 'lead_source' as source,
       r.record -> 'source' ->> 'campaign' as campaign,
       r.record -> 'qualification' ->> 'lead_status' as lead_status,
       r.record -> 'consent' ->> 'state' as partner_consent_state,
       (r.record -> 'consent' ->> 'marketing_consent_at') is not null as marketing_consent,
       coalesce((r.record -> 'consent' ->> 'opted_out')::boolean, false) as opted_out,
       r.held_by_b2c,
       r.record -> 'created_at' as lead_created_at,
       s.lane, s.status, s.handoff_reason, s.cause, s.partner_bar_reason, s.providers, s.handling, s.missing,
       s.owner_id, u.full_name as owner_name, s.assigned_at,
       s.stage_id, st.name as stage, st.canon as canonical_stage, s.sub_stage, s.stage_comment, s.stage_changed_at,
       s.hot, coalesce(s.temperature, case when s.hot then 'hot' end) as temperature, s.score,
       s.next_task_due_at, s.first_contacted_at, s.last_contacted_at, s.contact_attempts, s.last_activity_at,
       s.sla_due_at, s.sla_met_at, s.sla_breached_at,
       s.pool_entered_at, s.pool_reason, s.journey, s.lost_by, s.reengaged_at, s.reengage_trigger,
       s.flagged, s.reenquired_at, s.routing_requested_at, s.routed_to_partner_at, s.closed_at, s.closed_reason,
       s.tags, s.is_test or r.is_test as is_test, s.deleted_at, s.handed_off_at, s.updated_at
  from b2c.leads_state s
  left join b2c.lead_records r on r.lead_id = s.lead_id
  left join b2c.stages st on st.id = s.stage_id
  left join b2c.users u on u.user_id = s.owner_id;

-- ---------- read policies (writes only through functions) ----------
grant select on b2c.stages, b2c.sub_stages, b2c.lead_records, b2c.leads_state, b2c.lead_contacts, b2c.field_history, b2c.leads_v to authenticated;
do $p$
begin
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'stages' and policyname = 'staff read') then
    create policy "staff read" on b2c.stages for select to authenticated using ((select b2c.is_staff()));
    create policy "staff read" on b2c.sub_stages for select to authenticated using ((select b2c.is_staff()));
    create policy "who may see" on b2c.leads_state for select to authenticated using ((select b2c.can_see(lead_id)));
    create policy "who may see" on b2c.lead_records for select to authenticated using ((select b2c.can_see(lead_id)));
    create policy "who may see" on b2c.lead_contacts for select to authenticated using ((select b2c.can_see(lead_id)));
    create policy "who may see" on b2c.field_history for select to authenticated using ((select b2c.can_see(lead_id)));
  end if;
end $p$;
grant execute on function b2c.can_see(bigint), b2c.norm_phone(text), b2c.is_test_phone(text) to authenticated;
grant all on all tables in schema b2c to service_role;
