-- M6a: routing tables and helpers (spec B7, B5.3; design 4.2, 4.5, 4.6).
-- New b2b tables; the old CRM's empty public.allocations / routing_rules / engine_decisions / earning_rates stay as
-- they are. Nothing here touches student_leads: there is no trigger on it, so Witty's write path is unchanged.

-- ---------- commission rates (B5.3) ----------
create table if not exists b2b.rates (
  id                 bigint generated always as identity primary key,
  scope              text not null check (scope in ('partner_programme', 'partner', 'programme', 'university')),
  partner_id         bigint references b2b.partners (id) on delete restrict,
  programme_id       bigint,
  university_id      bigint,
  rate_type          text not null check (rate_type in ('percent', 'fixed', 'tiered')),
  fee_base           text not null default 'first_year' check (fee_base in ('first_year', 'total')),
  value              numeric(12, 2) check (value is null or value >= 0),
  tiers              jsonb,
  gst_inclusive      boolean not null default false,
  valid_from         date not null default current_date,
  valid_to           date,
  source             text not null default 'manual' check (source in ('manual', 'file')),
  source_version_id  bigint references b2b.partner_programme_versions (id) on delete restrict,
  note               text,
  created_by         text,
  created_at         timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from),
  check ((rate_type = 'tiered') = (tiers is not null) and (rate_type = 'tiered' or value is not null)),
  check (case scope
           when 'partner_programme' then partner_id is not null and programme_id is not null
           when 'partner' then partner_id is not null and programme_id is null
           when 'programme' then partner_id is null and programme_id is not null
           else partner_id is null and programme_id is null and university_id is not null end)
);
create index if not exists rates_partner_idx on b2b.rates (partner_id, programme_id) where valid_to is null;

-- ---------- routing rules (B7.1 step 4) ----------
create table if not exists b2b.routing_rules (
  id           bigint generated always as identity primary key,
  name         text not null check (length(trim(name)) between 1 and 120),
  priority     int not null default 100,
  conditions   jsonb not null default '{}' check (jsonb_typeof(conditions) = 'object'),
  action       text not null check (action in ('fix_partner', 'narrow', 'exclude')),
  partner_ids  bigint[] not null check (cardinality(partner_ids) between 1 and 50),
  active       boolean not null default true,
  version      int not null default 1,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   text
);

-- ---------- decisions and allocations ----------
create table if not exists b2b.engine_decisions (
  id                     bigint generated always as identity primary key,
  lead_id                bigint not null,
  cycle_no               int not null default 1,
  segment                text,
  interest               jsonb not null,
  mode                   text not null,
  destination_type       text not null check (destination_type in ('partner', 'in_house')),
  winner_partner_id      bigint,
  reason                 text,
  candidates             jsonb not null default '[]',
  excluded               jsonb not null default '[]',
  rules                  jsonb not null default '[]',
  seed                   numeric,
  selection_probability  numeric(5, 4),
  settings_version       int,
  is_test                boolean not null default false,
  actor_type             text not null,
  actor_id               text,
  created_at             timestamptz not null default now()
);
create index if not exists engine_decisions_lead_idx on b2b.engine_decisions (lead_id, created_at desc);
create index if not exists engine_decisions_created_idx on b2b.engine_decisions (created_at desc);

create table if not exists b2b.allocations (
  id                     bigint generated always as identity primary key,
  lead_id                bigint not null,
  cycle_no               int not null default 1,
  segment                text,
  destination_type       text not null check (destination_type in ('partner', 'in_house')),
  partner_id             bigint references b2b.partners (id) on delete restrict,
  reference              text unique,
  status                 text not null check (status in ('queued', 'pushing', 'pushed', 'accepted', 'duplicate', 'rejected', 'failed', 'recalled', 'handed_off', 'closed')),
  mode                   text not null check (mode in ('commission_first', 'exploration', 'minimum', 'rule', 'manual', 'fallback', 'performance', 'holdout')),
  attempt_no             int not null default 1,
  reason                 text,
  cpe_net_inr            numeric(12, 2),
  ncpl_inr               numeric(12, 2),
  selection_probability  numeric(5, 4),
  engine_decision_id     bigint references b2b.engine_decisions (id) on delete restrict,
  is_test                boolean not null default false,
  hold_until             timestamptz,
  partner_record_id      text,
  accepted_at            timestamptz,
  outcome                text,
  outcome_at             timestamptz,
  override               boolean not null default false,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check ((destination_type = 'partner') = (partner_id is not null)),
  check (destination_type = 'partner' or status in ('handed_off', 'closed'))
);
create unique index if not exists allocations_one_open_per_cycle on b2b.allocations (lead_id, cycle_no) where status in ('queued', 'pushing', 'pushed', 'accepted', 'handed_off');
create index if not exists allocations_partner_created_idx on b2b.allocations (partner_id, created_at desc) where partner_id is not null;
create index if not exists allocations_segment_idx on b2b.allocations (segment, partner_id);

do $rls$
declare t text;
begin
  foreach t in array array['rates', 'routing_rules', 'engine_decisions', 'allocations'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- Engine defaults the new code reads (existing keys are kept as they are).
update b2b.settings
   set value = jsonb_build_object('trusted_sources', jsonb_build_array('whatsapp_direct', 'whatsapp', 'witty', 'meta_lead_ad', 'google_ads'),
                                  'min_route_confidence', 0.6) || value
 where key = 'engine';

-- ---------- helpers ----------

/* The lead's interest in catalogue terms: course key, specialization, level, mode, university (only when confident). */
create or replace function b2b.lead_interest(l public.student_leads)
returns jsonb language sql stable set search_path = '' as $$
  with x as (
    select b2b.match_course_key(coalesce(nullif(l.interested_course, ''), l.field_of_interest)) as ck,
           nullif(trim(l.interested_specialization), '') as spec,
           case when lower(coalesce(l.program_level, '')) ~ '^(pg|post ?grad|master|postgraduate)' then 'PG'
                when lower(coalesce(l.program_level, '')) ~ '^(ug|under ?grad|bachelor|graduat)' then 'UG'
                when lower(coalesce(l.program_level, '')) ~ 'diploma' then 'DIPLOMA'
                when lower(coalesce(l.program_level, '')) ~ 'cert' then 'CERTIFICATE' end as lvl,
           case when lower(coalesce(l.study_mode_preference, '')) ~ 'online' then 'Online'
                when lower(coalesce(l.study_mode_preference, '')) ~ '(distance|odl|correspond)' then 'ODL'
                when lower(coalesce(l.study_mode_preference, '')) ~ '(regular|campus|offline|full)' then 'Regular' end as mode,
           coalesce(nullif(l.interested_university, ''), nullif(l.university_preference, '')) as uni_text
  )
  select jsonb_build_object(
    'course_key', x.ck,
    'specialization', case when b2b.norm_key(x.spec) in ('', 'general', 'any', 'notsure', 'none', 'na') then null else x.spec end,
    'level', x.lvl,
    'mode', x.mode,
    'university_id', (select u.id from public.catalog_universities u
                       where x.uni_text is not null
                         and (b2b.norm_key(u.name) = b2b.norm_key(x.uni_text) or b2b.norm_key(u.short_name) = b2b.norm_key(x.uni_text)
                              or public.similarity(lower(u.name), lower(x.uni_text)) >= 0.6)
                       order by public.similarity(lower(u.name), lower(x.uni_text)) desc limit 1),
    'university_text', x.uni_text,
    'segment', coalesce(x.ck, '?') || '|' || coalesce(x.lvl, '*') || '|' || coalesce(x.mode, '*'))
  from x;
$$;

/* Readiness (design 4.2): ready, plus the reasons it is not. Test leads are reported but never auto-routed. */
create or replace function b2b.lead_readiness(l public.student_leads)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  m text[] := '{}';
  v_witty boolean := lower(coalesce(l.lead_source, '')) ~ '(whatsapp|witty|website_agent)' or lower(coalesce(l.channel, '')) = 'whatsapp';
  v_idle int := coalesce((e ->> 'witty_idle_minutes')::int, 30);
begin
  if l.deleted_at is not null or l.merged_into_id is not null then m := array_append(m, 'deleted or merged'); end if;
  if coalesce(l.is_opted_out, false) then m := array_append(m, 'opted out'); end if;
  if l.destination_type is not null then m := array_append(m, 'already routed'); end if;
  if l.phone_verified_at is null
     and not (coalesce(l.lead_source, '') in (select jsonb_array_elements_text(coalesce(e -> 'trusted_sources', '[]')))) then
    m := array_append(m, 'phone not verified');
  end if;
  if coalesce(nullif(l.interested_course, ''), nullif(l.field_of_interest, '')) is null then m := array_append(m, 'no course yet'); end if;
  if v_witty then
    if upper(coalesce(l.lead_status, '')) not in ('HOT', 'WARM', 'COLD') then
      m := array_append(m, 'Witty has not classified the lead');
    elsif not (coalesce(l.lead_stage, '') = 'ESCALATION' or coalesce(l.is_bot_paused, false)
               or exists (select 1 from public.touchpoints t where t.lead_id = l.id and t.event_type = 'lead.escalated')
               or coalesce(l.last_agent_message_at, l.last_activity_at, l.created_at) < now() - make_interval(mins => v_idle)) then
      m := array_append(m, 'still chatting with Witty');
    end if;
  end if;
  return jsonb_build_object('ready', cardinality(m) = 0, 'missing', to_jsonb(m),
                            'is_test', coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number));
end $$;

/* The rate in force for a partner and programme: partner + programme, then partner, then programme, then university. */
create or replace function b2b.rate_for(p_partner bigint, p_programme bigint, p_on date default current_date)
returns b2b.rates language sql stable set search_path = '' as $$
  select r.* from b2b.rates r
   where r.valid_from <= p_on and (r.valid_to is null or r.valid_to >= p_on)
     and ((r.scope = 'partner_programme' and r.partner_id = p_partner and r.programme_id = p_programme)
       or (r.scope = 'partner' and r.partner_id = p_partner)
       or (r.scope = 'programme' and r.programme_id = p_programme)
       or (r.scope = 'university' and r.university_id = (select c.university_id from public.catalog_programs c where c.id = p_programme)))
   order by case r.scope when 'partner_programme' then 1 when 'partner' then 2 when 'programme' then 3 else 4 end, r.valid_from desc, r.id desc
   limit 1;
$$;

/* Commission per enrollment, net of GST (B5.3), for one partner offer. Null when no rate is in force. */
create or replace function b2b.cpe_net(p_partner bigint, p_programme bigint, p_fees jsonb)
returns numeric language plpgsql stable set search_path = '' as $$
declare
  r b2b.rates;
  c public.catalog_programs;
  v_base numeric;
  v_cpe numeric;
  v_gst numeric := coalesce((select (value ->> 'gst_rate')::numeric from b2b.settings where key = 'money'), 0.18);
begin
  r := b2b.rate_for(p_partner, p_programme);
  if r.id is null then return null; end if;
  select * into c from public.catalog_programs where id = p_programme;
  v_base := case r.fee_base
              when 'total' then coalesce((p_fees ->> 'total')::numeric, c.fee_total)
              else coalesce((p_fees ->> 'yearly')::numeric, c.fee_yearly, (p_fees ->> 'total')::numeric, c.fee_total) end;
  v_cpe := case r.rate_type
             when 'fixed' then r.value
             when 'percent' then r.value / 100 * v_base
             else (r.tiers -> 0 ->> 'pct')::numeric / 100 * v_base end; -- tiered: the first tier until period close (crm_tier_pct)
  if v_cpe is null then return null; end if;
  return round(case when r.gst_inclusive then v_cpe / (1 + v_gst) else v_cpe end, 2);
end $$;

revoke execute on function b2b.lead_interest(public.student_leads), b2b.lead_readiness(public.student_leads),
                           b2b.rate_for(bigint, bigint, date), b2b.cpe_net(bigint, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function b2b.lead_interest(public.student_leads), b2b.lead_readiness(public.student_leads),
                          b2b.rate_for(bigint, bigint, date), b2b.cpe_net(bigint, bigint, jsonb)
  to service_role;
