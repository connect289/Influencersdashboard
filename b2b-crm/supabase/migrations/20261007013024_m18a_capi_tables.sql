-- M18a: conversion feedback to Meta and Google (spec B11; Addendum 1 §6; Addendum 2 CAPI note). Part 1:
--   conversion_events   one row per lead, platform and milestone (event_id = <lead id>:<stage>:<cycle>, unique per platform)
--   settings 'capi'     consent rule, Meta dataset, Google Ads account, stage-to-event maps (secrets live in Vault)
--   capi_milestones     the milestones a lead has reached in its current cycle, whoever wrote them (B2B, B2C CRM, partners)
--   capi_ids            the lead's ad identifiers: its click_ids, and Witty's click for the phone (read only)
--   capi_hash_email / capi_hash_phone   SHA-256 after normalisation; raw email and phone never leave
-- Building events is m18b, the sender (pg_net) m18c, the Admin's functions m18d.

create table if not exists b2b.conversion_events (
  id              bigint generated always as identity primary key,
  lead_id         bigint not null,
  platform        text not null check (platform in ('meta', 'google')),
  stage           text not null check (stage in ('lead', 'ready_to_route', 'partner_accepted', 'contacted', 'applied', 'enrolled', 'verified', 'disqualified')),
  event_name      text not null,
  event_id        text not null,
  cycle_no        int not null default 1,
  occurred_at     timestamptz not null,
  value_inr       numeric(12, 2),
  is_test         boolean not null default false,
  status          text not null default 'pending'
                  check (status in ('pending', 'sending', 'sent', 'failed', 'rejected', 'dead', 'held', 'dry_run', 'skipped')),
  reason          text,
  match_keys      text[] not null default '{}',
  payload         jsonb not null,
  attempts        int not null default 0,
  next_attempt_at timestamptz,
  request_id      bigint,
  response        jsonb,
  error           text,
  created_at      timestamptz not null default now(),
  sent_at         timestamptz,
  unique (platform, event_id)
);
create index if not exists conversion_events_open_idx on b2b.conversion_events (platform, status, next_attempt_at)
  where status in ('pending', 'sending', 'failed', 'held');
create index if not exists conversion_events_lead_idx on b2b.conversion_events (lead_id);
create index if not exists conversion_events_created_idx on b2b.conversion_events (created_at);

alter table b2b.conversion_events enable row level security;
do $do$ begin
  if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = 'conversion_events' and policyname = 'admin_read') then
    create policy admin_read on b2b.conversion_events for select to authenticated using ((select b2b.is_admin()));
  end if;
end $do$;
revoke all on b2b.conversion_events from anon, authenticated;
grant select on b2b.conversion_events to authenticated;
grant all on b2b.conversion_events to service_role;

/* consent: which consent the student must have given for their conversions to be reported to the ad platforms.
   'marketing' (default) or 'sales'. Maps: stage → Meta event name / Google conversion action resource name. */
insert into b2b.settings (key, value) values ('capi', jsonb_build_object(
  'consent', 'marketing',
  'meta', jsonb_build_object('api_version', 'v21.0', 'dataset_id', null, 'test_event_code', null, 'window_days', 7,
    'map', jsonb_build_object(
      'lead',             jsonb_build_object('event', 'Lead', 'enabled', false),
      'ready_to_route',   jsonb_build_object('event', 'Qualified Lead', 'enabled', true),
      'partner_accepted', jsonb_build_object('event', 'Sales Accepted Lead', 'enabled', true),
      'contacted',        jsonb_build_object('event', 'Contacted', 'enabled', true),
      'applied',          jsonb_build_object('event', 'Applied', 'enabled', true),
      'enrolled',         jsonb_build_object('event', 'Enrolled', 'enabled', true),
      'verified',         jsonb_build_object('event', 'Enrollment Verified', 'enabled', true),
      'disqualified',     jsonb_build_object('event', 'Disqualified Lead', 'enabled', true))),
  'google', jsonb_build_object('api_version', 'v21', 'customer_id', null, 'login_customer_id', null, 'window_days', 90,
    'map', jsonb_build_object(
      'lead',             jsonb_build_object('action', null, 'enabled', false),
      'ready_to_route',   jsonb_build_object('action', null, 'enabled', true),
      'partner_accepted', jsonb_build_object('action', null, 'enabled', true),
      'contacted',        jsonb_build_object('action', null, 'enabled', false),
      'applied',          jsonb_build_object('action', null, 'enabled', true),
      'enrolled',         jsonb_build_object('action', null, 'enabled', true),
      'verified',         jsonb_build_object('action', null, 'enabled', true),
      'disqualified',     jsonb_build_object('action', null, 'enabled', false)))))
on conflict (key) do nothing;

create or replace function b2b.capi_secret(p_name text)
returns text language sql stable security definer set search_path = '' as $fn$
  select s.decrypted_secret from vault.decrypted_secrets s
   where s.id = nullif((select value #>> string_to_array(p_name, '.') from b2b.settings where key = 'capi'), '')::uuid;
$fn$;

-- ---------- hashing (B11: SHA-256 after normalisation) ----------
/* Meta: trimmed, lower case. Google: the same, and for gmail.com / googlemail.com the dots in the name are removed. */
create or replace function b2b.capi_hash_email(p_email text, p_platform text)
returns text language plpgsql immutable set search_path = '' as $fn$
declare e text := lower(trim(coalesce(p_email, '')));
begin
  if e !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then return null; end if;
  if p_platform = 'google' and split_part(e, '@', 2) in ('gmail.com', 'googlemail.com') then
    e := replace(split_part(e, '@', 1), '.', '') || '@' || split_part(e, '@', 2);
  end if;
  return encode(extensions.digest(e, 'sha256'), 'hex');
end $fn$;

/* Meta: digits with the country code. Google: E.164 (+ and digits). A 10-digit Indian mobile gets 91. */
create or replace function b2b.capi_hash_phone(p_phone text, p_platform text)
returns text language plpgsql immutable set search_path = '' as $fn$
declare d text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  if length(d) = 10 and left(d, 1) in ('6', '7', '8', '9') then d := '91' || d; end if;
  if length(d) < 11 or length(d) > 15 then return null; end if;
  return encode(extensions.digest(case when p_platform = 'google' then '+' || d else d end, 'sha256'), 'hex');
end $fn$;

-- ---------- what a lead has reached ----------
/* Milestones of the lead's current cycle, each with its time and (for money) value. Read from the shared tables, so
   stage changes written by the B2C CRM or a partner count as much as the B2B CRM's own. */
create or replace function b2b.capi_milestones(l public.student_leads)
returns table (stage text, at timestamptz, value_inr numeric)
language sql stable security definer set search_path = '' as $fn$
  with c as (select coalesce(l.cycle_no, 1) cyc, coalesce(l.reopened_at, l.created_at) cycle_start),
  a as (select min(x.created_at) routed,
               min(coalesce(x.accepted_at, case when x.destination_type <> 'partner' and x.status = 'handed_off' then x.created_at end))
                 filter (where x.status in ('accepted', 'handed_off') or x.accepted_at is not null) accepted
          from b2b.allocations x, c where x.lead_id = l.id and x.cycle_no = c.cyc),
  e as (select min(x.created_at) filter (where x.status in ('reported', 'verified')) reported,
               (array_agg(x.expected_net_revenue_inr order by x.created_at) filter (where x.status in ('reported', 'verified')))[1] expected,
               min(x.verified_at) filter (where x.status = 'verified') verified,
               (array_agg(x.realised_net_revenue_inr order by x.verified_at) filter (where x.status = 'verified'))[1] realised
          from public.enrollments x, c where x.lead_id = l.id and coalesce(x.cycle_no, 1) = c.cyc),
  np as (select n.decided_at from b2b.not_passed n where n.lead_id = l.id and n.reason = 'junk' and n.passed_at is null)
  select m.stage, m.at, m.value_inr from (
    select 'lead' stage, (select cycle_start from c) at, null::numeric value_inr
    union all select 'ready_to_route', a.routed, null from a
    union all select 'partner_accepted', a.accepted, null from a
    union all select 'contacted', case when l.first_contacted_at >= (select cycle_start from c) then l.first_contacted_at end, null
    union all select 'applied', case when l.applied_at >= (select cycle_start from c) then l.applied_at end, null
    union all select 'enrolled', coalesce(e.reported, case when l.enrollment_status is not null and l.enrollment_date is not null
                                                           then greatest(l.enrollment_date::timestamptz, (select cycle_start from c)) end),
                                 coalesce(e.expected, l.expected_net_revenue_inr) from e
    union all select 'verified', coalesce(e.verified, case when l.enrollment_verified_at >= (select cycle_start from c) then l.enrollment_verified_at end),
                                 coalesce(e.realised, l.realised_net_revenue_inr) from e
    union all select 'disqualified', (select decided_at from np), null) m
   where m.at is not null;
$fn$;

/* The lead's ad identifiers. Website and API leads carry click_ids; a Witty lead's click (fbclid, gclid, fbp…) is on
   the access code its phone redeemed (Witty's tables are only read). Keys: leadgen_id, fbclid, fbc, fbp, gclid, gbraid,
   wbraid, google_lead_id. */
create or replace function b2b.capi_ids(l public.student_leads)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select jsonb_strip_nulls(jsonb_build_object(
           'leadgen_id', nullif(coalesce(k ->> 'leadgen_id', w ->> 'leadgen_id'), ''),
           'fbclid', nullif(coalesce(k ->> 'fbclid', w ->> 'fbclid'), ''),
           'fbc', nullif(coalesce(k ->> 'fbc', w ->> 'fbc', wa ->> 'fbc'), ''),
           'fbp', nullif(coalesce(k ->> 'fbp', w ->> 'fbp', wa ->> 'fbp'), ''),
           'gclid', nullif(coalesce(k ->> 'gclid', w ->> 'gclid'), ''),
           'gbraid', nullif(coalesce(k ->> 'gbraid', w ->> 'gbraid'), ''),
           'wbraid', nullif(coalesce(k ->> 'wbraid', w ->> 'wbraid'), ''),
           'google_lead_id', nullif(k ->> 'google_lead_id', '')))
    from (select coalesce(l.click_ids, '{}') k,
                 coalesce((select ck.click_ids from public.w2_access_codes ac join public.w2_clicks ck on ck.id = ac.click_id
                            where ac.phone in (l.whatsapp_number, regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'))
                            order by ac.bound_at desc nulls last limit 1), '{}') w,
                 coalesce((select ac.attribution from public.w2_access_codes ac
                            where ac.phone in (l.whatsapp_number, regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'))
                            order by ac.bound_at desc nulls last limit 1), '{}') wa) x;
$fn$;

revoke execute on function b2b.capi_secret(text), b2b.capi_hash_email(text, text), b2b.capi_hash_phone(text, text),
                           b2b.capi_milestones(public.student_leads), b2b.capi_ids(public.student_leads)
  from public, anon, authenticated;
grant execute on function b2b.capi_secret(text), b2b.capi_hash_email(text, text), b2b.capi_hash_phone(text, text),
                          b2b.capi_milestones(public.student_leads), b2b.capi_ids(public.student_leads)
  to service_role;
