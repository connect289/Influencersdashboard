-- M7a: Addenda 1 and 2 (docs/B2B_CRM_ADDENDUM_1.md, _2.md; Addendum 2 wins where they differ).
-- Every lead is passed to a CRM except junk and programme mismatch; B2C hand-offs carry a lane (sales | nurture);
-- rules may send leads to B2C. Tables and helpers here; the engine is in m7b, admin functions in m7c.

-- ---------- allocations: B2C lane, and handed_off → closed when a manual route to partners replaces them ----------
alter table b2b.allocations add column if not exists b2c_lane text;
update b2b.allocations set b2c_lane = 'sales' where destination_type = 'in_house' and b2c_lane is null;
do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'allocations_b2c_lane_check' and conrelid = 'b2b.allocations'::regclass) then
    alter table b2b.allocations add constraint allocations_b2c_lane_check
      check (b2c_lane in ('sales', 'nurture') and destination_type = 'in_house' or b2c_lane is null and destination_type = 'partner');
  end if;
end $c$;
alter table b2b.engine_decisions add column if not exists b2c_lane text check (b2c_lane in ('sales', 'nurture'));

-- ---------- rules may now send a lead to B2C (action to_b2c, with a lane and no partners) ----------
alter table b2b.routing_rules add column if not exists b2c_lane text check (b2c_lane in ('sales', 'nurture'));
alter table b2b.routing_rules drop constraint if exists routing_rules_action_check;
alter table b2b.routing_rules drop constraint if exists routing_rules_partner_ids_check;
do $c$
begin
  if not exists (select 1 from pg_constraint where conname = 'routing_rules_action_shape' and conrelid = 'b2b.routing_rules'::regclass) then
    alter table b2b.routing_rules add constraint routing_rules_action_shape check (
      case action
        when 'to_b2c' then b2c_lane is not null and cardinality(partner_ids) = 0
        when 'fix_partner' then b2c_lane is null and cardinality(partner_ids) between 1 and 50
        when 'narrow' then b2c_lane is null and cardinality(partner_ids) between 1 and 50
        when 'exclude' then b2c_lane is null and cardinality(partner_ids) between 1 and 50
        else false end);
  end if;
end $c$;

-- ---------- not passed: junk and programme mismatch stay in student_leads, but no CRM works them (Addendum 2) ----------
create table if not exists b2b.not_passed (
  lead_id           bigint primary key,
  reason            text not null check (reason in ('junk', 'program_mismatch', 'invalid_phone', 'blocked_phone')),
  lead_status       text,
  requested_course  text,
  lead_source       text,
  fingerprint       text not null,          -- what the decision saw; the sweep re-decides only when it changes
  times             int not null default 1,
  decided_at        timestamptz not null default now(),
  passed_at         timestamptz,            -- set when the lead is passed later (rescued, or reclassified)
  passed_by         text,
  pass_note         text
);
create index if not exists not_passed_open_idx on b2b.not_passed (decided_at desc) where passed_at is null;

-- ---------- review queue: a passed lead later classified junk or mismatch is flagged, never pulled back ----------
create table if not exists b2b.review_flags (
  id                bigint generated always as identity primary key,
  lead_id           bigint not null,
  allocation_id     bigint not null references b2b.allocations (id) on delete restrict,
  kind              text not null default 'reclassified' check (kind in ('reclassified')),
  lead_status       text,
  destination_type  text not null,
  created_at        timestamptz not null default now(),
  resolved_at       timestamptz,
  resolution        text check (resolution in ('keep', 'close')),
  resolved_by       text,
  note              text,
  unique (allocation_id, kind)
);
create index if not exists review_flags_open_idx on b2b.review_flags (created_at desc) where resolved_at is null;

do $rls$
declare t text;
begin
  foreach t in array array['not_passed', 'review_flags'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- ---------- settings: the paid-campaign rule, B2C sources, blocked phones (Addendum 1 §1, Addendum 2) ----------
update b2b.settings
   set value = jsonb_build_object(
         'paid_rule', jsonb_build_object(
           'sources', jsonb_build_array('meta_lead_ad', 'meta_lead_ads', 'google_lead_form', 'google_ads', 'google_ads_lead_form'),
           'click_ids', jsonb_build_array('fbclid', 'gclid', 'gbraid', 'wbraid', 'ctwa_clid'),
           'utm_mediums', jsonb_build_array('cpc', 'ppc', 'paid', 'paid_social', 'paidsocial'),
           'include_campaigns', '[]'::jsonb, 'exclude_campaigns', '[]'::jsonb),
         'b2c_sources', jsonb_build_array('b2c_created', 'b2c_whatsapp'),
         'blocked_phones', '[]'::jsonb,
         'junk_capi_signal', false,
         'b2c_sends_own_notification', true) || value
 where key = 'engine';

-- ---------- helpers ----------

/* Is the lead a Witty or website-agent chat (decided at the hand-off point rather than at intake)? */
create or replace function b2b.is_chat_lead(l public.student_leads)
returns boolean language sql stable set search_path = '' as $$
  select lower(coalesce(l.lead_source, '')) ~ '(whatsapp|witty|website_agent)' or lower(coalesce(l.channel, '')) = 'whatsapp';
$$;

/* Junk by phone: invalid (wrong length, one repeated digit, an Indian number not starting 6–9) or blocklisted. */
create or replace function b2b.phone_problem(p_phone text)
returns text language sql stable set search_path = '' as $$
  with d as (select regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') as v)
  select case
    when exists (select 1 from b2b.settings s, jsonb_array_elements_text(coalesce(s.value -> 'blocked_phones', '[]')) b
                  where s.key = 'engine' and regexp_replace(b, '\D', '', 'g') in (d.v, right(d.v, 10)) and length(regexp_replace(b, '\D', '', 'g')) >= 10)
      then 'blocked_phone'
    when length(d.v) < 10 or length(d.v) > 15 or d.v ~ '^(\d)\1+$' then 'invalid_phone'
    when length(d.v) = 12 and d.v like '91%' and substr(d.v, 3, 1) not in ('6', '7', '8', '9') then 'invalid_phone'
    when length(d.v) = 10 and substr(d.v, 1, 1) not in ('6', '7', '8', '9') then 'invalid_phone'
  end from d;
$$;

/* Does the stated course match anything Eduwit offers (catalogue key, synonym, or a close programme or course name)? */
create or replace function b2b.course_in_catalogue(p_course text)
returns boolean language sql stable set search_path = '' as $$
  select b2b.match_course_key(p_course) is not null
      or exists (select 1 from public.catalog_programs c
                  where c.active and (public.similarity(lower(c.course), lower(p_course)) >= 0.45
                                      or public.similarity(lower(c.program_name), lower(p_course)) >= 0.45));
$$;

/*
 * Classification (Addendum 2): junk | mismatch | qualified | unqualified, with the reason and what is missing.
 * Test leads are never junk by phone (their numbers are synthetic).
 */
create or replace function b2b.lead_class(l public.student_leads)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_test boolean := coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number);
  v_chat boolean := b2b.is_chat_lead(l);
  v_status text := upper(coalesce(nullif(trim(l.lead_status), ''), ''));
  v_course text := coalesce(nullif(trim(l.interested_course), ''), nullif(trim(l.field_of_interest), ''));
  v_phone text := case when v_test then null else b2b.phone_problem(l.whatsapp_number) end;
  m text[] := '{}';
begin
  if v_status = 'JUNK' then return jsonb_build_object('class', 'junk', 'reason', 'junk', 'missing', '[]'::jsonb); end if;
  if v_phone is not null then return jsonb_build_object('class', 'junk', 'reason', v_phone, 'missing', '[]'::jsonb); end if;
  if v_status = 'PROGRAM_MISMATCH' or (not v_chat and v_course is not null and not b2b.course_in_catalogue(v_course)) then
    return jsonb_build_object('class', 'mismatch', 'reason', 'program_mismatch', 'missing', '[]'::jsonb);
  end if;

  if v_course is null then m := array_append(m, 'no course'); end if;
  if l.phone_verified_at is null and not (coalesce(l.lead_source, '') in (select jsonb_array_elements_text(coalesce(e -> 'trusted_sources', '[]')))) then
    m := array_append(m, 'phone not verified');
  end if;
  if v_chat and v_status not in ('HOT', 'WARM', 'COLD') then
    m := array_append(m, case when v_status = '' then 'Witty has not classified the lead' else 'Witty classified it ' || v_status end);
  end if;
  return jsonb_build_object('class', case when cardinality(m) = 0 then 'qualified' else 'unqualified' end,
                            'reason', case when cardinality(m) = 0 then null else 'not_qualified' end, 'missing', to_jsonb(m));
end $$;

/* Paid campaign (Addendum 1 §1): the paid source, click ID or utm_medium that makes it paid; null when not paid. */
create or replace function b2b.paid_signal(l public.student_leads)
returns text language plpgsql stable set search_path = '' as $$
declare
  r jsonb := coalesce((select value -> 'paid_rule' from b2b.settings where key = 'engine'), '{}');
  v_camp text := lower(coalesce(nullif(l.campaign, ''), l.utm_campaign, ''));
  v text;
begin
  if v_camp <> '' and exists (select 1 from jsonb_array_elements_text(coalesce(r -> 'exclude_campaigns', '[]')) x where lower(trim(x)) <> '' and v_camp like '%' || lower(trim(x)) || '%') then
    return null;
  end if;
  if v_camp <> '' then
    select 'campaign ' || x into v from jsonb_array_elements_text(coalesce(r -> 'include_campaigns', '[]')) x
     where lower(trim(x)) <> '' and v_camp like '%' || lower(trim(x)) || '%' limit 1;
    if v is not null then return v; end if;
  end if;
  if lower(coalesce(l.lead_source, '')) in (select lower(x) from jsonb_array_elements_text(coalesce(r -> 'sources', '[]')) x) then
    return 'source ' || l.lead_source;
  end if;
  select 'click ID ' || x into v from jsonb_array_elements_text(coalesce(r -> 'click_ids', '[]')) x
   where (jsonb_typeof(l.click_ids) = 'object' and coalesce(l.click_ids ->> x, '') <> '')
      or coalesce(l.landing_url, '') ~* ('[?&]' || x || '=')
   limit 1;
  if v is not null then return v; end if;
  if lower(coalesce(l.utm_medium, '')) in (select lower(x) from jsonb_array_elements_text(coalesce(r -> 'utm_mediums', '[]')) x) then
    return 'utm_medium ' || l.utm_medium;
  end if;
  if lower(coalesce(l.source_detail, '')) ~ '(ctwa|click.to.whatsapp)' then return 'click-to-WhatsApp ad'; end if;
  return null;
end $$;

/*
 * Readiness, revised: a lead is ready when it reaches its decision point. Chat leads (Witty, website agent): on
 * escalation, a paused bot, or when the chat has been idle for witty_idle_minutes (30). Every other source: at once.
 * What it is missing to be qualified no longer blocks it (unqualified leads go to B2C nurture); class says which way.
 */
create or replace function b2b.lead_readiness(l public.student_leads)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  m text[] := '{}';
  v_idle int := coalesce((e ->> 'witty_idle_minutes')::int, 30);
  v_class jsonb := b2b.lead_class(l);
begin
  if l.deleted_at is not null or l.merged_into_id is not null then m := array_append(m, 'deleted or merged'); end if;
  if coalesce(l.is_opted_out, false) then m := array_append(m, 'opted out'); end if;
  if l.destination_type is not null then m := array_append(m, 'already routed'); end if;
  if b2b.is_chat_lead(l)
     and not (coalesce(l.lead_stage, '') = 'ESCALATION' or coalesce(l.is_bot_paused, false)
              or exists (select 1 from public.touchpoints t where t.lead_id = l.id and t.event_type = 'lead.escalated')
              or coalesce(l.last_agent_message_at, l.last_activity_at, l.created_at) < now() - make_interval(mins => v_idle)) then
    m := array_append(m, 'still chatting with Witty');
  end if;
  return jsonb_build_object('ready', cardinality(m) = 0, 'missing', to_jsonb(m),
                            'is_test', coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number),
                            'class', v_class ->> 'class', 'class_reason', v_class ->> 'reason', 'not_qualified', v_class -> 'missing',
                            'paid', b2b.paid_signal(l));
end $$;

revoke execute on function b2b.is_chat_lead(public.student_leads), b2b.phone_problem(text), b2b.course_in_catalogue(text),
                           b2b.lead_class(public.student_leads), b2b.paid_signal(public.student_leads) from public, anon, authenticated;
grant execute on function b2b.is_chat_lead(public.student_leads), b2b.phone_problem(text), b2b.course_in_catalogue(text),
                          b2b.lead_class(public.student_leads), b2b.paid_signal(public.student_leads) to service_role;
