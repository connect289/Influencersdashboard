-- M31a: Addendum 3 schema, settings and data (docs/B2B_CRM_ADDENDUM_3.md, incl. Amendment 1). No function body of the
-- routing engine changes here (that is m31b onwards); routing stays off for the whole m31 series.
--   (1) validates the two m31a0 checks on b2b.allocations (SHARE UPDATE EXCLUSIVE: readers such as Witty's
--       w2_crm_owned are not blocked);
--   (2) new tables: partner_bars (the permanent partner bar, insert-only), consent_requests (R8 asks), lead_consents
--       (per-purpose consent ledger, insert-only), consent_texts (registered wording; covers_admission_partners is what
--       PART 7.1 requires), lead_interests (secondary interests, positions 2-10), lead_reenquiries (new enquiries on
--       held leads), scan_cursors, lead_waits (stored decision waits, keyed on the lead's updated_at), nurture_watch,
--       geo_places (city aliases -> city, state), ad_spend_daily (for cost per enrolment once spend is imported);
--   (3) b2b.append_only_guard() and UPDATE guards on partner_bars and lead_consents (the guards against removing rows
--       or emptying the tables are in pending/m31a_guards, applied by hand in the SQL editor right after this file);
--   (4) new columns on engine_decisions, commission_disputes, not_passed, partner_segment_stats, segment_stats,
--       partner_adapter_state and partners;
--   (5) indexes (none on public.* tables);
--   (6) settings, through b2b.set_setting:
--       engine         new Admin keys (existing values kept) and the rulebook numbers in the read-only engine.a3_fixed.
--                      Owner's correction (7 Oct): the sales-effort bounds and the six effort weights
--                      (engine.effort_factor), and the SLA-adherence bounds, step and the three SLA weights
--                      (engine.sla_factor) are versioned Admin settings, validated inside the rulebook ranges that
--                      a3_fixed holds (effort_range 0.85-1.15, sla_range 0.80-1.00). Defaults: the rulebook values,
--                      equal weights. Every other rulebook number stays fixed.
--       engine_policy  'highest score wins': leading_weight 0; partner weights, Monte-Carlo draws, segment pins,
--                      share caps, per-segment exploration and the segment kill list are retired;
--       attribution, lost_nurture_delays, golive_acks   new keys;
--   (7) data, on b2b tables only: allocation origins, duplicate-claim proof columns, the consent ledger backfilled from
--       the student_leads stamps, the seeded consent texts, partner hold windows, scan cursors at the current maximum
--       ids (read-only selects on public.touchpoints and public.w2_messages), geo_places, models retired, and AI
--       recommendations for retired levers closed.
-- Nothing is added to or changed in public.student_leads, Witty (w2_*) or the catalogue (catalog_*).
--
-- Read-only checks recorded for the promotion window (expected 0 on production, which has no allocations):
--   select count(*) from b2b.allocations where destination_type = 'in_house' and reason in ('duplicate_cascade', 'partner_lost');
--   (there is no retro-bar: leads handed to B2C before Addendum 3 are not barred). The count is also raised as a NOTICE
--   at the end of this file, which also asserts that no engine_policy.segments entry keeps a pin, share cap or
--   per-segment exploration share.

-- ---------- (1) the m31a0 checks ----------
alter table b2b.allocations validate constraint allocations_stage_check;
alter table b2b.allocations validate constraint allocations_origin_check;

-- ---------- (2) new tables ----------
/* The permanent partner bar (PART 3 R2, PART 5.4, PART 6.1). One row per barred lead; it also bars the leads merged into
   it and any non-test lead with the same phone digits (b2b.partner_bar). Insert-only. */
create table if not exists b2b.partner_bars (
  lead_id         bigint primary key,
  phone_digits    text,
  reason          text not null check (reason in ('duplicate', 'lost')),
  barred_at       timestamptz not null default now(),
  allocation_id   bigint references b2b.allocations (id),
  cycle_no        int,
  providers       jsonb not null default '[]',
  set_by          text not null check (set_by in ('engine', 'grace', 'manual_route', 'backfill')),
  source_lead_id  bigint,
  erased_at       timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists partner_bars_phone_idx on b2b.partner_bars (phone_digits) where phone_digits is not null;

/* R8 / PART 7.2: one-tap requests for partner-sharing consent. At most one open request per lead. */
create table if not exists b2b.consent_requests (
  id             bigint generated always as identity primary key,
  lead_id        bigint not null,
  cycle_no       int not null default 1,
  purpose        text not null default 'partner_share' check (purpose = 'partner_share'),
  channel        text not null default 'b2c_crm' check (channel in ('b2c_crm', 'witty')),
  context        text not null check (context in ('decision', 'nurture', 'admin')),
  status         text not null default 'requested'
                   check (status in ('queued', 'requested', 'sent', 'unsendable', 'answered', 'expired', 'cancelled')),
  text_version   text not null default 'wa_partner_consent:v1',
  programme      text,
  created_at     timestamptz not null default now(),
  published_at   timestamptz,
  sent_at        timestamptz,
  expires_at     timestamptz,            -- null while queued; published_at (or sent_at) + 48 hours
  answer         text check (answer in ('yes', 'no')),
  answered_at    timestamptz,
  answer_source  text,
  evidence       jsonb not null default '{}',
  closed_at      timestamptz,
  is_test        boolean not null default false
);
create unique index if not exists consent_requests_one_open on b2b.consent_requests (lead_id)
  where status in ('queued', 'requested', 'sent', 'unsendable');
create index if not exists consent_requests_status_idx on b2b.consent_requests (status, expires_at);
create index if not exists consent_requests_published_idx on b2b.consent_requests (published_at desc);
create index if not exists consent_requests_lead_idx on b2b.consent_requests (lead_id, cycle_no, created_at desc);

/* Per-purpose consent ledger (PART 7.1). Insert-only: a refusal or withdrawal is a new row. */
create table if not exists b2b.lead_consents (
  id            bigint generated always as identity primary key,
  lead_id       bigint not null,
  purpose       text not null check (purpose in ('partner_share', 'sales', 'marketing')),
  state         text not null check (state in ('given', 'refused', 'withdrawn')),
  at            timestamptz not null,
  text_version  text,
  source        text not null check (source in ('form', 'api', 'import', 'manual', 'witty', 'meta_form', 'google_form', 'b2c_crm',
                                                'admin', 'wa_request', 'backfill')),
  request_id    bigint references b2b.consent_requests (id),
  evidence      jsonb not null default '{}',
  actor         jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists lead_consents_lead_idx on b2b.lead_consents (lead_id, purpose, at desc);

/* Registered consent wording. Only an active version that covers admission partners (edtech companies) and lists
   partner_share counts as partner-sharing consent (b2b.consent_text_covers). The lawyer's approval gates go-live. */
create table if not exists b2b.consent_texts (
  version                    text primary key,
  channel                    text not null check (channel in ('witty', 'website_agent', 'web_form', 'meta_form', 'google_form', 'import',
                                                              'manual', 'api', 'wa_request')),
  purposes                   text[] not null,
  body                       text,
  covers_admission_partners  boolean not null default false,
  active                     boolean not null default true,
  lawyer_approved_at         timestamptz,
  approved_by                text,
  approval_note              text,
  created_at                 timestamptz not null default now()
);

/* Secondary interests (PART 4 'Several interests'). Position 1 is always the lead's own course (b2b.lead_interest). */
create table if not exists b2b.lead_interests (
  id               bigint generated always as identity primary key,
  lead_id          bigint not null,
  position         smallint not null check (position between 2 and 10),
  course_text      text not null,
  course_key       text,
  specialization   text,
  level            text,
  mode             text,
  university_text  text,
  university_id    bigint,
  source           text not null check (source in ('witty', 'web_agent', 'api', 'meta', 'google', 'import', 'manual', 'admin', 'b2c', 'backfill')),
  stated_at        timestamptz not null default now(),
  removed_at       timestamptz,
  created_by       text
);
create unique index if not exists lead_interests_live_uidx
  on b2b.lead_interests (lead_id, coalesce(course_key, lower(course_text)), coalesce(lower(specialization), ''))
  where removed_at is null;

/* New enquiries on a lead that a partner or B2C already holds (R2, R3, R4). */
create table if not exists b2b.lead_reenquiries (
  id               bigint generated always as identity primary key,
  lead_id          bigint not null,
  cycle_no         int,
  allocation_id    bigint,
  holder           text not null check (holder in ('partner', 'b2c_selling', 'barred', 'qualification_nurture')),
  partner_id       bigint,
  kind             text not null check (kind in ('touchpoint', 'witty_message')),
  touchpoint_id    bigint unique,
  message_id       bigint unique,
  source_system    text,
  event_type       text,
  campaign         text,
  paid_label       text,
  interest         boolean not null default false,
  occurred_at      timestamptz not null,
  event_id         bigint,
  acknowledged_at  timestamptz,
  acknowledged_by  text,
  note             text,
  created_at       timestamptz not null default now()
);
create index if not exists lead_reenquiries_lead_idx on b2b.lead_reenquiries (lead_id, occurred_at desc);
create index if not exists lead_reenquiries_open_idx on b2b.lead_reenquiries (created_at desc) where acknowledged_at is null;

/* Read cursors of the per-minute scanners (touchpoints, Witty messages, requalification). */
create table if not exists b2b.scan_cursors (
  key         text primary key,
  last_id     bigint,
  last_at     timestamptz,
  updated_at  timestamptz not null default now()
);

/* A lead that is not ready yet: skipped by the sweep while decide_after > now() and the lead row is unchanged
   (lead_updated_at = student_leads.updated_at). Any write to the lead re-evaluates it at once. */
create table if not exists b2b.lead_waits (
  lead_id          bigint primary key,
  decide_after     timestamptz not null,
  why              text not null,
  set_at           timestamptz not null default now(),
  lead_updated_at  timestamptz
);
create index if not exists lead_waits_due_idx on b2b.lead_waits (decide_after);

/* Qualification-nurture leads being watched for requalification (R7 -> R9). */
create table if not exists b2b.nurture_watch (
  lead_id             bigint primary key,
  allocation_id       bigint,
  fingerprint         text,
  class               text,
  missing             jsonb,
  qualified_at        timestamptz,
  recheck_at          timestamptz,
  consent_request_id  bigint,
  reengaged_at        timestamptz,
  checked_at          timestamptz,
  times               int not null default 0
);
create index if not exists nurture_watch_checked_idx on b2b.nurture_watch (checked_at);
create index if not exists nurture_watch_recheck_idx on b2b.nurture_watch (recheck_at) where recheck_at is not null;

/* City names and aliases -> city and state, for partner geography criteria (b2b.lead_geo). alias = b2b.norm_key(name).
   Names shared by two states are left out. */
create table if not exists b2b.geo_places (
  alias  text primary key,
  city   text not null,
  state  text not null
);

/* Ad spend per platform, campaign and day (cost per enrolment and ROAS once a spend import exists). */
create table if not exists b2b.ad_spend_daily (
  platform     text not null check (platform in ('meta', 'google')),
  campaign_id  text not null,
  day          date not null,
  spend_inr    numeric(14, 2) not null,
  source       text,
  imported_at  timestamptz not null default now(),
  imported_by  text,
  primary key (platform, campaign_id, day)
);

do $rls$
declare t text;
begin
  foreach t in array array['partner_bars', 'consent_requests', 'lead_consents', 'consent_texts', 'lead_interests', 'lead_reenquiries',
                           'scan_cursors', 'lead_waits', 'nurture_watch', 'geo_places', 'ad_spend_daily'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- ---------- (3) immutability ----------
/* Rows of partner_bars and lead_consents are never changed. The one exception: an erasure (GUC b2b.erasure = 'on' in
   the same transaction) may change a partner bar's phone_digits, providers and erased_at, and nothing else, so the bar
   itself (lead, reason, date) survives the erasure of the student's personal data. */
create or replace function b2b.append_only_guard()
returns trigger language plpgsql set search_path = '' as $fn$
begin
  if tg_op = 'UPDATE' and tg_table_name = 'partner_bars' and coalesce(current_setting('b2b.erasure', true), '') = 'on' then
    if (to_jsonb(new) - 'phone_digits' - 'providers' - 'erased_at') = (to_jsonb(old) - 'phone_digits' - 'providers' - 'erased_at') then
      return new;
    end if;
  end if;
  raise exception 'b2b.% is append-only (% blocked)', tg_table_name, tg_op using errcode = '42501';
end $fn$;
revoke execute on function b2b.append_only_guard() from public, anon, authenticated;

create or replace trigger partner_bars_append_only before update on b2b.partner_bars
  for each row execute function b2b.append_only_guard();
create or replace trigger lead_consents_append_only before update on b2b.lead_consents
  for each row execute function b2b.append_only_guard();

-- ---------- (4) other columns ----------
alter table b2b.engine_decisions
  add column if not exists stage          text,
  add column if not exists score          numeric(14, 2),
  add column if not exists eval_segment   text,
  add column if not exists segment_exact  text,
  add column if not exists class          text,
  add column if not exists attribution    jsonb,
  add column if not exists interest_rank  smallint,
  add column if not exists interests      jsonb,
  add column if not exists hold           jsonb,
  add column if not exists bar            jsonb,
  add column if not exists how            text,
  add column if not exists holdout_share  numeric(4, 3),
  add column if not exists draw           numeric(13, 12),
  add column if not exists features       jsonb,
  add column if not exists features_hash  text,
  add column if not exists feature_hash   text;

alter table b2b.commission_disputes
  add column if not exists kind                 text not null default 'duplicate_after_acceptance',
  add column if not exists partner_event_id     bigint references b2b.partner_events (id),
  add column if not exists existing_created_on  timestamptz,
  add column if not exists also                 jsonb not null default '[]';

alter table b2b.not_passed
  add column if not exists detail    text,
  add column if not exists override  boolean not null default false;

alter table b2b.partner_segment_stats
  add column if not exists n_received         int not null default 0,
  add column if not exists first_lead_at      timestamptz,
  add column if not exists n_matured_c        int not null default 0,
  add column if not exists leads_30d          int not null default 0,
  add column if not exists effort_factor      numeric(5, 4) not null default 1,
  add column if not exists effort_detail      jsonb,
  add column if not exists has_activity       boolean not null default false,
  add column if not exists activity_coverage  numeric(5, 4),
  add column if not exists sla_met            int,
  add column if not exists sla_total          int,
  add column if not exists sla_adherence      numeric(6, 5),
  add column if not exists sla_factor         numeric(5, 4) not null default 1;

alter table b2b.segment_stats
  add column if not exists auto_stage  text,
  add column if not exists params      jsonb;

alter table b2b.partner_adapter_state add column if not exists last_poll_ok_at timestamptz;

alter table b2b.partners
  add column if not exists dedupe_confirmed_at  timestamptz,
  add column if not exists push_options         jsonb not null default '{}';

do $chk$
begin
  if not exists (select 1 from pg_constraint where conname = 'engine_decisions_stage_check' and conrelid = 'b2b.engine_decisions'::regclass) then
    alter table b2b.engine_decisions add constraint engine_decisions_stage_check check (stage is null or stage in ('A', 'B', 'C'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'commission_disputes_kind_check' and conrelid = 'b2b.commission_disputes'::regclass) then
    alter table b2b.commission_disputes add constraint commission_disputes_kind_check
      check (kind in ('duplicate_after_acceptance', 'late_activity_after_lost'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'segment_stats_auto_stage_check' and conrelid = 'b2b.segment_stats'::regclass) then
    alter table b2b.segment_stats add constraint segment_stats_auto_stage_check check (auto_stage is null or auto_stage in ('A', 'B', 'C'));
  end if;
end $chk$;

-- ---------- (5) indexes ----------
create index if not exists allocations_lead_status_idx on b2b.allocations (lead_id, status);
create index if not exists allocations_segment_exact_idx on b2b.allocations (segment_exact, partner_id) where segment_exact is not null;
create index if not exists allocations_lost_grace_idx on b2b.allocations (lost_grace_until) where lost_at is not null and lost_revived_at is null;
create index if not exists allocations_lead_in_house_idx on b2b.allocations (lead_id, created_at desc) where destination_type = 'in_house';
create index if not exists commission_disputes_upheld_idx on b2b.commission_disputes (allocation_id) where status = 'upheld';
create index if not exists intake_requests_lead_idx on b2b.intake_requests (lead_id) where lead_id is not null;   -- b2b.lead_attribution

-- ---------- (7a) one-time data, before the settings mark the file as applied ----------
/* Runs only on the first application (engine.a3_fixed not yet set), so a re-run never retires models retrained after
   m31m or closes recommendations for the Addendum 3 levers. */
do $first$
begin
  if exists (select 1 from b2b.settings where key = 'engine' and value ? 'a3_fixed') then
    return;
  end if;
  -- models trained on the old features and scoring: none may decide until retrained after m31m
  update b2b.ml_models
     set status = 'retired', status_at = now(), status_by = 'system',
         status_reason = 'Addendum 3: features and scoring changed; retrain after m31m'
   where status in ('shadow', 'challenger', 'champion');
  -- AI recommendations for levers Addendum 3 retired (pins, share caps, exploration, partner weights, speed, reliability,
  -- maturity): open ones are superseded; applied ones are final, so no review or rollback writes the retired slots again
  update b2b.ai_recommendations
     set status = 'superseded', decision_note = left(coalesce(decision_note || ' | ', '') || 'Addendum 3 retired this lever', 500)
   where status = 'open' and kind = 'setting_change'
     and coalesce(change ->> 'lever', '') not in ('half_life_days', 'prior_weight');
  update b2b.ai_recommendations
     set check_result = coalesce(check_result, '{}') || '{"final":true,"verdict":"retired","why":"Addendum 3 retired this lever"}'
   where status = 'applied' and kind = 'setting_change'
     and not coalesce(applied -> 'path' ->> 0 = 'ai' and applied -> 'path' ->> 1 in ('half_life_days', 'prior_weight'), false);
end $first$;

-- ---------- (6) settings ----------
/* engine: new Admin keys with their defaults (existing values kept; object values merged key by key), then the
   rulebook numbers and the retired switches written over. */
do $eng$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  d jsonb;
  n jsonb;
  k text;
begin
  perform set_config('b2b.actor', 'system', true);
  d := jsonb_build_object(
    'witty_unqualified_idle_hours', 18,
    'consent_admin_yes', false,
    'consent_requests_per_hour', 100,
    'reenquiry_quiet_hours', 24,
    'max_interests', 5,
    'criteria_unknown', 'fail',
    'welcome_for_all_nurture', false,
    'require_verified_phone_sources', jsonb_build_array('website_agent', 'web_agent'),
    -- PART 4 sales-effort factor: bounds inside a3_fixed.effort_range, equal weights for the six metrics
    'effort_factor', jsonb_build_object(
      'enabled', true,
      'bounds', jsonb_build_array(0.85, 1.15),
      'weights', jsonb_build_object('first_call', 1, 'attempts_72h', 1, 'connect_rate', 1, 'followup', 1, 'acts_per_open', 1, 'stale_share', 1),
      'min_sample', 10),
    -- PART 4 SLA-adherence factor: floor and ceiling inside a3_fixed.sla_range, 0.05 per full 10 points below 100%,
    -- equal weights for the three SLAs
    'sla_factor', jsonb_build_object(
      'enabled', true,
      'floor', 0.80,
      'ceiling', 1.00,
      'step', 0.05,
      'weights', jsonb_build_object('first_attempt', 1, 'status_update', 1, 'enrollment_proof', 1)),
    'requalify', jsonb_build_object('enabled', true, 'wait_for_chat_gate', true, 'max_per_run', 25),
    'guard', jsonb_build_object('duplicate_rate_pause', false),
    'spam', jsonb_build_object(
      'use_witty_blocks', true,
      'disposable_email_domains', jsonb_build_array('mailinator.com', 'guerrillamail.com', '10minutemail.com', 'tempmail.com', 'yopmail.com',
                                                    'trashmail.com', 'getnada.com', 'sharklasers.com', 'dispostable.com', 'maildrop.cc'),
      'max_leads_per_ip_hour', 5,
      'max_leads_per_fingerprint_hour', 5));
  n := d || e;
  -- object-valued keys: keep what is stored, add sub-keys it lacks
  foreach k in array array['effort_factor', 'sla_factor', 'requalify', 'guard', 'spam'] loop
    if jsonb_typeof(e -> k) = 'object' then n := jsonb_set(n, array[k], (d -> k) || (e -> k)); end if;
  end loop;
  n := n || jsonb_build_object(
    -- the rulebook's numbers (Addendum 3, PART 4-6 and Amendment 1): read by the engine, refused by every settings save
    -- and the AI path. effort_range, sla_range, sla_step_range and weight_range are the ranges the Admin's (and the
    -- AI's) bounds, step and weights must stay inside.
    'a3_fixed', jsonb_build_object(
      'stage_b_min_leads', 20, 'stage_b_min_age_days', 7,
      'stage_c_min_matured', 30, 'stage_c_min_partners', 2, 'matured_days', 60,
      'learn_leads', 30, 'exploration_share', 0.2,
      'exact_segment_min_leads', 30, 'tier_projected_min_matured', 30,
      'effort_range', jsonb_build_array(0.85, 1.15),
      'sla_range', jsonb_build_array(0.80, 1.00),
      'sla_step_range', jsonb_build_array(0.01, 0.20),
      'weight_range', jsonb_build_array(0, 5),
      'factor_window_days', 30,
      'attempt_limit', 2, 'partner_limit', 3,
      'hold_minutes_sync', 0, 'hold_minutes_async', 30, 'duplicate_window_hours', 24,
      'push_retry_seconds', jsonb_build_array(10, 60, 300, 900, 2400),
      'lost_grace_days', 7, 'consent_wait_hours', 48, 'witty_idle_minutes', 30,
      'auto_pause_breaches', 5, 'auto_pause_sync_minutes', 30,
      'cpe_aggregate', 'median'),
    -- the push code reads the schedule here (about 62 minutes of retries)
    'push_retry_seconds', jsonb_build_array(10, 60, 300, 900, 2400),
    -- R8 asks; 'b2c_sales' (the pre-Addendum behaviour) only when already chosen; there is no 'off'
    'consent_policy', case when e ->> 'consent_policy' = 'b2c_sales' then 'b2c_sales' else 'ask' end,
    -- legacy key read by pre-A3 code: consent is never skipped
    'require_partner_consent', true,
    -- retired: the kill switch and its fixed split
    'kill_switch', false,
    'fixed_split', '{}'::jsonb);
  if n is distinct from e then
    perform b2b.set_setting('engine', n, 'Addendum 3 defaults (m31a)');
  end if;
end $eng$;

/* engine_policy: highest score wins. Leading indicators off, partner weights, Monte-Carlo draws and the segment kill
   list retired, and every segments.* entry loses pin, share_cap and exploration_share whatever its source (an entry
   left empty is removed). The AI overlay loses the retired levers. holdout_share is kept. */
do $pol$
declare
  p jsonb := coalesce((select value from b2b.settings where key = 'engine_policy'), '{}');
  v_seg jsonb;
  v_ai jsonb;
  n jsonb;
begin
  perform set_config('b2b.actor', 'system', true);
  select coalesce(jsonb_object_agg(x.k, case when jsonb_typeof(x.v) = 'object' then x.v - 'pin' - 'share_cap' - 'exploration_share' else x.v end), '{}'::jsonb)
    into v_seg
    from jsonb_each(case when jsonb_typeof(p -> 'segments') = 'object' then p -> 'segments' else '{}'::jsonb end) x(k, v)
   where not (jsonb_typeof(x.v) = 'object' and (x.v - 'pin' - 'share_cap' - 'exploration_share') = '{}'::jsonb);
  v_ai := (case when jsonb_typeof(p -> 'ai') = 'object' then p -> 'ai' else '{}'::jsonb end)
          - 'speed_factor' - 'reliability_factor' - 'maturity_days' - 'segment_pin' - 'share_cap' - 'exploration_share' - 'partner_weight';
  n := (p - 'mc_draws') || jsonb_build_object('leading_weight', 0, 'partner_weights', '{}'::jsonb, 'kill_segments', '[]'::jsonb,
                                              'segments', v_seg, 'ai', v_ai);
  if n is distinct from p then
    perform b2b.set_setting('engine_policy', n, 'Addendum 3: highest score wins; rulebook numbers fixed');
  end if;
end $pol$;

/* New keys, seeded once with a first version row (later changes go through their save functions). */
insert into b2b.settings (key, value) values
  ('attribution', jsonb_build_object(
     'influencer_markers', jsonb_build_object(
       'lead_sources', jsonb_build_array('influencer', 'referral', 'affiliate', 'partner_referral'),
       'utm_values', jsonb_build_array('influencer', 'referral', 'affiliate')),
     'exclude_campaigns', coalesce((select s.value -> 'paid_rule' -> 'exclude_campaigns' from b2b.settings s where s.key = 'engine'), '[]'::jsonb),
     'meta_ad_params', jsonb_build_array('ad_id', 'adset_id', 'campaign_id', 'utm_id', 'fb_ad_id'))),
  -- PART 6.1: the lost reason sets when B2C's first nurture message goes out (3-90 days); per-reason values need Vikas
  ('lost_nurture_delays', jsonb_build_object('default', 14, 'reasons', '{}'::jsonb)),
  -- routing go-live checklist items the Admin acknowledged with a reason (m31e)
  ('golive_acks', '{}'::jsonb)
on conflict (key) do nothing;
insert into b2b.settings_versions (key, version, value, reason, actor_type)
select s.key, 1, s.value, 'Addendum 3 defaults (m31a)', 'system' from b2b.settings s
 where s.key in ('attribution', 'lost_nurture_delays', 'golive_acks')
   and not exists (select 1 from b2b.settings_versions v where v.key = s.key);

-- ---------- (7) data ----------
/* Where each existing allocation came from (only where unknown). */
update b2b.allocations
   set origin = case when mode = 'manual' then 'to_partners' when is_test then 'sandbox' when override then 'pass' else 'auto' end
 where origin is null;

/* Duplicate claims: the proof in columns (PART 5.3: an existing record ID, the partner's created date, or a CRM's native
   duplicate error). */
update b2b.allocations a
   set claim_existing_record_id = x.rec,
       claim_existing_created_at = x.created,
       claim_proof_ok = (x.rec is not null or x.created is not null or coalesce(a.claim_proof, '{}'::jsonb) ? 'crm_message')
  from (select y.id,
               nullif(trim(coalesce(y.claim_proof ->> 'existing_record_id', y.claim_proof ->> 'existing_id', y.claim_proof ->> 'record_id')), '') rec,
               coalesce(b2b.try_timestamptz(y.claim_proof ->> 'existing_created_at'), b2b.try_timestamptz(y.claim_proof ->> 'created_at'),
                        b2b.try_timestamptz(y.claim_proof ->> 'first_seen_at')) created
          from b2b.allocations y where y.status = 'duplicate' and y.claim_proof_ok is null) x
 where a.id = x.id;

/* Consent texts: the three covering versions (lawyer approval still to be recorded), then every version already in use,
   which does not cover admission partners until the Admin registers it as such. */
insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners) values
  ('witty-notice-2026-10-v2', 'witty', '{sales,partner_share}',
   'Your details are used only to help with your admission and may be shared with our partner universities and our admission partners (edtech companies). Reply STOP anytime to opt out.',
   true),
  ('witty_partner_consent_v1', 'witty', '{partner_share}',
   'To connect you with the best admission counsellor for {{programme}}, may we share your details with our admission partner? Reply YES or NO.',
   true),
  ('wa_partner_consent:v1', 'wa_request', '{partner_share}',
   'To connect you with the best admission counsellor for {{programme}}, may we share your details with our admission partner? Reply YES or NO.',
   true)
on conflict (version) do nothing;

insert into b2b.consent_texts (version, channel, purposes, body, covers_admission_partners)
select distinct on (f.consent_version) f.consent_version, case f.platform when 'meta' then 'meta_form' else 'google_form' end,
       coalesce(f.consent_purposes, '{sales}'), f.consent_text, false
  from b2b.lead_forms f
 where nullif(trim(f.consent_version), '') is not null
 order by f.consent_version, f.updated_at desc
on conflict (version) do nothing;

insert into b2b.consent_texts (version, channel, purposes, covers_admission_partners)
select v.version, v.channel, case when cardinality(v.purposes) = 0 then '{sales}'::text[] else v.purposes end, false
  from (select l.consent_text_version as version,
               (array_agg(case when lower(coalesce(l.lead_source, '')) ~ '(whatsapp|witty)' or lower(coalesce(l.first_agent_channel, '')) = 'whatsapp' then 'witty'
                               when lower(coalesce(l.lead_source, '')) ~ '(website_agent|web_agent)' then 'website_agent'
                               when lower(coalesce(l.lead_source, '')) ~ 'meta' then 'meta_form'
                               when lower(coalesce(l.lead_source, '')) ~ 'google' then 'google_form'
                               when lower(coalesce(l.lead_source, '')) ~ 'import' then 'import'
                               when lower(coalesce(l.lead_source, '')) ~ 'manual' then 'manual'
                               when lower(coalesce(l.lead_source, '')) ~ '(web|form|landing|site)' then 'web_form'
                               else 'api' end order by l.created_at desc))[1] as channel,
               array_remove(array[case when bool_or(l.consent_sales_at is not null) then 'sales' end,
                                  case when bool_or(l.consent_marketing_at is not null) then 'marketing' end,
                                  case when bool_or(l.consent_partner_share_at is not null) then 'partner_share' end], null) as purposes
          from public.student_leads l
         where nullif(trim(l.consent_text_version), '') is not null
         group by l.consent_text_version) v
on conflict (version) do nothing;

/* The consent ledger, backfilled from the student_leads stamps (one 'given' row per purpose, for leads with no ledger row
   for that purpose yet). */
insert into b2b.lead_consents (lead_id, purpose, state, at, text_version, source, evidence)
select l.id, x.purpose, 'given', x.at, nullif(trim(l.consent_text_version), ''), 'backfill', jsonb_build_object('column', x.col)
  from public.student_leads l
  cross join lateral (values ('partner_share', l.consent_partner_share_at, 'consent_partner_share_at'),
                             ('sales', l.consent_sales_at, 'consent_sales_at'),
                             ('marketing', l.consent_marketing_at, 'consent_marketing_at')) x(purpose, at, col)
 where l.deleted_at is null and x.at is not null
   and not exists (select 1 from b2b.lead_consents c where c.lead_id = l.id and c.purpose = x.purpose);

/* PART 5.1: the hold window is derived (0 minutes for a CRM that rejects duplicates at once, else 30); PART 5.8: the
   after-acceptance duplicate window is 24 hours. */
update b2b.partners
   set hold_minutes = case when dedupe_mode = 'sync' then 0 else 30 end, duplicate_window_hours = 24
 where hold_minutes is distinct from (case when dedupe_mode = 'sync' then 0 else 30 end) or duplicate_window_hours is distinct from 24;

/* Scanners start at the current end of Witty's tables (read-only selects), so history is never replayed as new
   enquiries; requalification looks back one day. */
insert into b2b.scan_cursors (key, last_id, last_at, updated_at) values
  ('touchpoints', (select coalesce(max(t.id), 0) from public.touchpoints t), now(), now()),
  ('w2_messages', (select coalesce(max(m.id), 0) from public.w2_messages m), now(), now()),
  ('requalify', null, now() - interval '1 day', now())
on conflict (key) do nothing;

/* City names and common aliases (alias stored as b2b.norm_key). Names used in two states are left out
   (Aurangabad, Bilaspur, Hamirpur, Pratapgarh, Amravati/Amaravati, Raigarh, Fatehpur...). */
insert into b2b.geo_places (alias, city, state)
select b2b.norm_key(v.alias), v.city, v.state
  from (values
    ('Delhi', 'Delhi', 'Delhi'), ('New Delhi', 'Delhi', 'Delhi'), ('Delhi NCR', 'Delhi', 'Delhi'), ('Dilli', 'Delhi', 'Delhi'),
    ('Noida', 'Noida', 'Uttar Pradesh'), ('Greater Noida', 'Greater Noida', 'Uttar Pradesh'), ('Ghaziabad', 'Ghaziabad', 'Uttar Pradesh'),
    ('Gurugram', 'Gurugram', 'Haryana'), ('Gurgaon', 'Gurugram', 'Haryana'), ('Faridabad', 'Faridabad', 'Haryana'),
    ('Panipat', 'Panipat', 'Haryana'), ('Ambala', 'Ambala', 'Haryana'), ('Karnal', 'Karnal', 'Haryana'), ('Hisar', 'Hisar', 'Haryana'),
    ('Rohtak', 'Rohtak', 'Haryana'), ('Sonipat', 'Sonipat', 'Haryana'), ('Sonepat', 'Sonipat', 'Haryana'), ('Panchkula', 'Panchkula', 'Haryana'),
    ('Yamunanagar', 'Yamunanagar', 'Haryana'),
    ('Mumbai', 'Mumbai', 'Maharashtra'), ('Bombay', 'Mumbai', 'Maharashtra'), ('Navi Mumbai', 'Navi Mumbai', 'Maharashtra'),
    ('Thane', 'Thane', 'Maharashtra'), ('Kalyan', 'Kalyan', 'Maharashtra'), ('Vasai', 'Vasai', 'Maharashtra'), ('Pune', 'Pune', 'Maharashtra'),
    ('Poona', 'Pune', 'Maharashtra'), ('Pimpri Chinchwad', 'Pimpri-Chinchwad', 'Maharashtra'), ('Pimpri', 'Pimpri-Chinchwad', 'Maharashtra'),
    ('Nagpur', 'Nagpur', 'Maharashtra'), ('Nashik', 'Nashik', 'Maharashtra'), ('Nasik', 'Nashik', 'Maharashtra'),
    ('Kolhapur', 'Kolhapur', 'Maharashtra'), ('Solapur', 'Solapur', 'Maharashtra'), ('Sangli', 'Sangli', 'Maharashtra'),
    ('Jalgaon', 'Jalgaon', 'Maharashtra'), ('Akola', 'Akola', 'Maharashtra'), ('Latur', 'Latur', 'Maharashtra'), ('Nanded', 'Nanded', 'Maharashtra'),
    ('Ahmednagar', 'Ahmednagar', 'Maharashtra'), ('Satara', 'Satara', 'Maharashtra'),
    ('Chhatrapati Sambhajinagar', 'Chhatrapati Sambhajinagar', 'Maharashtra'),
    ('Bengaluru', 'Bengaluru', 'Karnataka'), ('Bangalore', 'Bengaluru', 'Karnataka'), ('Mysuru', 'Mysuru', 'Karnataka'), ('Mysore', 'Mysuru', 'Karnataka'),
    ('Mangaluru', 'Mangaluru', 'Karnataka'), ('Mangalore', 'Mangaluru', 'Karnataka'), ('Hubballi', 'Hubballi', 'Karnataka'), ('Hubli', 'Hubballi', 'Karnataka'),
    ('Dharwad', 'Dharwad', 'Karnataka'), ('Belagavi', 'Belagavi', 'Karnataka'), ('Belgaum', 'Belagavi', 'Karnataka'),
    ('Kalaburagi', 'Kalaburagi', 'Karnataka'), ('Gulbarga', 'Kalaburagi', 'Karnataka'), ('Davanagere', 'Davanagere', 'Karnataka'),
    ('Ballari', 'Ballari', 'Karnataka'), ('Bellary', 'Ballari', 'Karnataka'), ('Shivamogga', 'Shivamogga', 'Karnataka'), ('Shimoga', 'Shivamogga', 'Karnataka'),
    ('Tumakuru', 'Tumakuru', 'Karnataka'), ('Tumkur', 'Tumakuru', 'Karnataka'), ('Udupi', 'Udupi', 'Karnataka'),
    ('Chennai', 'Chennai', 'Tamil Nadu'), ('Madras', 'Chennai', 'Tamil Nadu'), ('Coimbatore', 'Coimbatore', 'Tamil Nadu'),
    ('Madurai', 'Madurai', 'Tamil Nadu'), ('Tiruchirappalli', 'Tiruchirappalli', 'Tamil Nadu'), ('Trichy', 'Tiruchirappalli', 'Tamil Nadu'),
    ('Salem', 'Salem', 'Tamil Nadu'), ('Tirunelveli', 'Tirunelveli', 'Tamil Nadu'), ('Erode', 'Erode', 'Tamil Nadu'), ('Vellore', 'Vellore', 'Tamil Nadu'),
    ('Thoothukudi', 'Thoothukudi', 'Tamil Nadu'), ('Tuticorin', 'Thoothukudi', 'Tamil Nadu'), ('Tiruppur', 'Tiruppur', 'Tamil Nadu'),
    ('Hosur', 'Hosur', 'Tamil Nadu'),
    ('Thiruvananthapuram', 'Thiruvananthapuram', 'Kerala'), ('Trivandrum', 'Thiruvananthapuram', 'Kerala'), ('Kochi', 'Kochi', 'Kerala'),
    ('Cochin', 'Kochi', 'Kerala'), ('Ernakulam', 'Kochi', 'Kerala'), ('Kozhikode', 'Kozhikode', 'Kerala'), ('Calicut', 'Kozhikode', 'Kerala'),
    ('Thrissur', 'Thrissur', 'Kerala'), ('Trichur', 'Thrissur', 'Kerala'), ('Kollam', 'Kollam', 'Kerala'), ('Kannur', 'Kannur', 'Kerala'),
    ('Kottayam', 'Kottayam', 'Kerala'), ('Palakkad', 'Palakkad', 'Kerala'), ('Malappuram', 'Malappuram', 'Kerala'),
    ('Hyderabad', 'Hyderabad', 'Telangana'), ('Secunderabad', 'Secunderabad', 'Telangana'), ('Warangal', 'Warangal', 'Telangana'),
    ('Karimnagar', 'Karimnagar', 'Telangana'), ('Nizamabad', 'Nizamabad', 'Telangana'),
    ('Visakhapatnam', 'Visakhapatnam', 'Andhra Pradesh'), ('Vizag', 'Visakhapatnam', 'Andhra Pradesh'), ('Vijayawada', 'Vijayawada', 'Andhra Pradesh'),
    ('Guntur', 'Guntur', 'Andhra Pradesh'), ('Nellore', 'Nellore', 'Andhra Pradesh'), ('Tirupati', 'Tirupati', 'Andhra Pradesh'),
    ('Kakinada', 'Kakinada', 'Andhra Pradesh'), ('Kurnool', 'Kurnool', 'Andhra Pradesh'), ('Rajahmundry', 'Rajamahendravaram', 'Andhra Pradesh'),
    ('Rajamahendravaram', 'Rajamahendravaram', 'Andhra Pradesh'), ('Anantapur', 'Anantapur', 'Andhra Pradesh'),
    ('Ahmedabad', 'Ahmedabad', 'Gujarat'), ('Amdavad', 'Ahmedabad', 'Gujarat'), ('Surat', 'Surat', 'Gujarat'), ('Vadodara', 'Vadodara', 'Gujarat'),
    ('Baroda', 'Vadodara', 'Gujarat'), ('Rajkot', 'Rajkot', 'Gujarat'), ('Gandhinagar', 'Gandhinagar', 'Gujarat'), ('Bhavnagar', 'Bhavnagar', 'Gujarat'),
    ('Jamnagar', 'Jamnagar', 'Gujarat'), ('Junagadh', 'Junagadh', 'Gujarat'), ('Anand', 'Anand', 'Gujarat'), ('Gandhidham', 'Gandhidham', 'Gujarat'),
    ('Jaipur', 'Jaipur', 'Rajasthan'), ('Jodhpur', 'Jodhpur', 'Rajasthan'), ('Udaipur', 'Udaipur', 'Rajasthan'), ('Kota', 'Kota', 'Rajasthan'),
    ('Ajmer', 'Ajmer', 'Rajasthan'), ('Bikaner', 'Bikaner', 'Rajasthan'), ('Alwar', 'Alwar', 'Rajasthan'), ('Bhilwara', 'Bhilwara', 'Rajasthan'),
    ('Sikar', 'Sikar', 'Rajasthan'),
    ('Bhopal', 'Bhopal', 'Madhya Pradesh'), ('Indore', 'Indore', 'Madhya Pradesh'), ('Gwalior', 'Gwalior', 'Madhya Pradesh'),
    ('Jabalpur', 'Jabalpur', 'Madhya Pradesh'), ('Ujjain', 'Ujjain', 'Madhya Pradesh'), ('Sagar', 'Sagar', 'Madhya Pradesh'), ('Rewa', 'Rewa', 'Madhya Pradesh'),
    ('Satna', 'Satna', 'Madhya Pradesh'),
    ('Lucknow', 'Lucknow', 'Uttar Pradesh'), ('Kanpur', 'Kanpur', 'Uttar Pradesh'), ('Agra', 'Agra', 'Uttar Pradesh'), ('Varanasi', 'Varanasi', 'Uttar Pradesh'),
    ('Banaras', 'Varanasi', 'Uttar Pradesh'), ('Benares', 'Varanasi', 'Uttar Pradesh'), ('Prayagraj', 'Prayagraj', 'Uttar Pradesh'),
    ('Allahabad', 'Prayagraj', 'Uttar Pradesh'), ('Meerut', 'Meerut', 'Uttar Pradesh'), ('Bareilly', 'Bareilly', 'Uttar Pradesh'),
    ('Aligarh', 'Aligarh', 'Uttar Pradesh'), ('Moradabad', 'Moradabad', 'Uttar Pradesh'), ('Gorakhpur', 'Gorakhpur', 'Uttar Pradesh'),
    ('Jhansi', 'Jhansi', 'Uttar Pradesh'), ('Mathura', 'Mathura', 'Uttar Pradesh'), ('Saharanpur', 'Saharanpur', 'Uttar Pradesh'),
    ('Ayodhya', 'Ayodhya', 'Uttar Pradesh'), ('Firozabad', 'Firozabad', 'Uttar Pradesh'), ('Muzaffarnagar', 'Muzaffarnagar', 'Uttar Pradesh'),
    ('Patna', 'Patna', 'Bihar'), ('Gaya', 'Gaya', 'Bihar'), ('Bhagalpur', 'Bhagalpur', 'Bihar'), ('Muzaffarpur', 'Muzaffarpur', 'Bihar'),
    ('Darbhanga', 'Darbhanga', 'Bihar'), ('Purnia', 'Purnia', 'Bihar'),
    ('Ranchi', 'Ranchi', 'Jharkhand'), ('Jamshedpur', 'Jamshedpur', 'Jharkhand'), ('Dhanbad', 'Dhanbad', 'Jharkhand'), ('Bokaro', 'Bokaro', 'Jharkhand'),
    ('Bokaro Steel City', 'Bokaro', 'Jharkhand'),
    ('Kolkata', 'Kolkata', 'West Bengal'), ('Calcutta', 'Kolkata', 'West Bengal'), ('Howrah', 'Howrah', 'West Bengal'), ('Durgapur', 'Durgapur', 'West Bengal'),
    ('Asansol', 'Asansol', 'West Bengal'), ('Siliguri', 'Siliguri', 'West Bengal'), ('Kharagpur', 'Kharagpur', 'West Bengal'),
    ('Bhubaneswar', 'Bhubaneswar', 'Odisha'), ('Cuttack', 'Cuttack', 'Odisha'), ('Rourkela', 'Rourkela', 'Odisha'), ('Sambalpur', 'Sambalpur', 'Odisha'),
    ('Berhampur', 'Berhampur', 'Odisha'), ('Brahmapur', 'Berhampur', 'Odisha'),
    ('Ludhiana', 'Ludhiana', 'Punjab'), ('Amritsar', 'Amritsar', 'Punjab'), ('Jalandhar', 'Jalandhar', 'Punjab'), ('Patiala', 'Patiala', 'Punjab'),
    ('Mohali', 'Mohali', 'Punjab'), ('SAS Nagar', 'Mohali', 'Punjab'), ('Bathinda', 'Bathinda', 'Punjab'),
    ('Chandigarh', 'Chandigarh', 'Chandigarh'),
    ('Shimla', 'Shimla', 'Himachal Pradesh'), ('Dharamshala', 'Dharamshala', 'Himachal Pradesh'), ('Solan', 'Solan', 'Himachal Pradesh'),
    ('Dehradun', 'Dehradun', 'Uttarakhand'), ('Haridwar', 'Haridwar', 'Uttarakhand'), ('Rishikesh', 'Rishikesh', 'Uttarakhand'),
    ('Haldwani', 'Haldwani', 'Uttarakhand'), ('Roorkee', 'Roorkee', 'Uttarakhand'), ('Nainital', 'Nainital', 'Uttarakhand'),
    ('Jammu', 'Jammu', 'Jammu and Kashmir'), ('Srinagar', 'Srinagar', 'Jammu and Kashmir'),
    ('Guwahati', 'Guwahati', 'Assam'), ('Gauhati', 'Guwahati', 'Assam'), ('Dibrugarh', 'Dibrugarh', 'Assam'), ('Silchar', 'Silchar', 'Assam'),
    ('Jorhat', 'Jorhat', 'Assam'),
    ('Shillong', 'Shillong', 'Meghalaya'), ('Imphal', 'Imphal', 'Manipur'), ('Agartala', 'Agartala', 'Tripura'), ('Aizawl', 'Aizawl', 'Mizoram'),
    ('Kohima', 'Kohima', 'Nagaland'), ('Itanagar', 'Itanagar', 'Arunachal Pradesh'), ('Gangtok', 'Gangtok', 'Sikkim'),
    ('Raipur', 'Raipur', 'Chhattisgarh'), ('Bhilai', 'Bhilai', 'Chhattisgarh'), ('Durg', 'Durg', 'Chhattisgarh'),
    ('Panaji', 'Panaji', 'Goa'), ('Panjim', 'Panaji', 'Goa'), ('Margao', 'Margao', 'Goa'), ('Madgaon', 'Margao', 'Goa'),
    ('Vasco da Gama', 'Vasco da Gama', 'Goa'),
    ('Puducherry', 'Puducherry', 'Puducherry'), ('Pondicherry', 'Puducherry', 'Puducherry')
  ) v(alias, city, state)
on conflict (alias) do nothing;

-- ---------- checks (read-only, and an assertion on this file's own settings step) ----------
do $check$
declare
  v_n bigint;
  v_bad bigint;
begin
  select count(*) into v_n from b2b.allocations where destination_type = 'in_house' and reason in ('duplicate_cascade', 'partner_lost');
  raise notice 'm31a: % in_house allocations with reason duplicate_cascade or partner_lost (expected 0 on production; no retro-bar)', v_n;
  select count(*) into v_bad
    from b2b.settings s, jsonb_each(case when jsonb_typeof(s.value -> 'segments') = 'object' then s.value -> 'segments' else '{}'::jsonb end) e
   where s.key = 'engine_policy' and jsonb_typeof(e.value) = 'object' and (e.value ? 'pin' or e.value ? 'share_cap' or e.value ? 'exploration_share');
  if v_bad > 0 or exists (select 1 from b2b.settings s where s.key = 'engine_policy'
                            and (s.value ? 'mc_draws' or coalesce(s.value -> 'kill_segments', '[]'::jsonb) <> '[]'::jsonb
                                 or coalesce(s.value -> 'partner_weights', '{}'::jsonb) <> '{}'::jsonb)) then
    raise exception 'm31a: engine_policy still holds retired overrides';
  end if;
  if not exists (select 1 from b2b.settings s where s.key = 'engine' and s.value ? 'a3_fixed'
                   and s.value ->> 'consent_policy' in ('ask', 'b2c_sales') and s.value ->> 'kill_switch' = 'false') then
    raise exception 'm31a: engine settings were not written';
  end if;
end $check$;
