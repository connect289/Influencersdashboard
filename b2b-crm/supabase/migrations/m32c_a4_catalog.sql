-- M32c Addendum 4 (14 Oct, Vikas): the B2C CRM link, final shape, part 3: the shared catalogue and the B2C CRM's views.
--   (1) schema catalog         NEW, read-only views owned by the B2B CRM (§6). Nothing in public.catalog_* moves; Witty is
--                              unaffected. The views join the tables directly (no b2b function calls), so the reader needs
--                              no grant on b2b:
--         catalog.universities_v, catalog.synonyms_v   over public.catalog_universities / catalog_synonyms
--         catalog.programmes_v     one row per live programme: catalogue facts, fees (catalogue, else the lowest live
--                                  partner offer), eligibility, intakes and deadlines from the live offers, accreditation,
--                                  offered_by_partner_count. Duration, EMI and scholarship come from catalog_programs.fee_other
--                                  when the sheet had them (null otherwise).
--         catalog.partner_rates_v  one row per live partner offer (the rate in force: partner + programme, partner +
--                                  university, partner), plus one row per partner + university rate (programme null);
--                                  the current tier of a tiered rate is the last settled conversion's (else the first
--                                  tier); is_highest_for_programme compares the commission in rupees on the programme's
--                                  fee base, is_highest_for_university the effective percentage.
--         catalog.changes          append-only (id, at, kind, ref_id): a published programme version or any rate change
--   (2) role b2c_app           NEW (no login): usage on catalog and select on its views and changes. Nothing on
--                              student_leads, b2b or w2_*.
--   (3) b2c_money_of / b2c_status_of  NEW: read public.b2c_enrollment_money_v / b2c_lead_status_v when the B2C CRM has
--                              published them (its Phase 3), null before (§7). The referral view b2b_referral_outcomes is
--                              not built yet (design §6); when it is, it reads b2c_status_of for B2C-held leads.
--   (5) b2c_link_overview      REPLACED (m22c): contract_version 4 and deliveries.lag_seconds_p95 against a 5-second target.
--   (4) lead_a3_columns_sql    REPLACED (m31l): the Master Lead Table shows b2c_stage, b2c_sub_stage, b2c_owner_name and
--                              b2c_money for B2C-held leads.
-- Triggers only on b2b.rates and b2b.partner_programme_versions (never on student_leads). Re-appliable.

create schema if not exists catalog;
comment on schema catalog is 'Read-only catalogue views owned by the B2B CRM, read by the B2C CRM (Addendum 4 §6)';
revoke all on schema catalog from public;

create table if not exists catalog.changes (
  id      bigint generated always as identity primary key,
  at      timestamptz not null default now(),
  kind    text not null check (kind in ('programme_version', 'rate')),
  ref_id  bigint not null
);
create index if not exists changes_at_idx on catalog.changes (at desc);
alter table catalog.changes enable row level security;

create or replace function b2b.catalog_change_log()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if tg_table_name = 'rates' then
    insert into catalog.changes (kind, ref_id) values ('rate', new.id);
  elsif tg_table_name = 'partner_programme_versions' and new.status = 'published'
        and (tg_op = 'INSERT' or old.status is distinct from new.status) then
    insert into catalog.changes (kind, ref_id) values ('programme_version', new.id);
  end if;
  return null;
end $fn$;
create or replace trigger catalog_change_log after insert or update on b2b.rates
  for each row execute function b2b.catalog_change_log();
create or replace trigger catalog_change_log after insert or update of status on b2b.partner_programme_versions
  for each row execute function b2b.catalog_change_log();

create or replace view catalog.universities_v as
  select u.id, u.name, u.short_name, u.institution_type, u.recognitions, u.accreditation_text, u.updated_at
    from public.catalog_universities u;

create or replace view catalog.synonyms_v as
  select s.alias, s.course_key from public.catalog_synonyms s;

create or replace view catalog.programmes_v as
  select c.id, c.university_id, u.name as university_name, c.program_name as programme_name, c.course, c.course_key,
         c.specialization, c.level, c.mode,
         nullif(c.fee_other ->> 'duration', '') as duration,
         c.min_qualification, c.min_pct_general as min_pct, c.min_pct_reserved, c.eligibility_text,
         coalesce(c.fee_yearly, o.fee_yearly) as fee_per_year, coalesce(c.fee_semester, o.fee_semester) as fee_per_semester,
         coalesce(c.fee_total, o.fee_total) as fee_total, coalesce(c.fee_exam, o.fee_exam) as fee_exam,
         coalesce(c.fee_registration, o.fee_registration) as fee_registration,
         case when c.fee_other ? 'emi_available' then (c.fee_other ->> 'emi_available') in ('true', 'yes', '1') end as emi_available,
         nullif(c.fee_other ->> 'typical_emi', '') as typical_emi,
         nullif(c.fee_other ->> 'scholarship', '') as scholarship_notes,
         o.intakes, o.deadlines,
         u.accreditation_text as accreditation, u.recognitions,
         c.brochure_url,
         coalesce(o.partners, 0)::int as offered_by_partner_count,
         greatest(c.updated_at, u.updated_at, o.updated_at) as updated_at
    from public.catalog_programs c
    join public.catalog_universities u on u.id = c.university_id
    left join lateral (
      select count(distinct pp.partner_id) as partners,
             min(nullif(pp.fees ->> 'yearly', '')::numeric) as fee_yearly, min(nullif(pp.fees ->> 'semester', '')::numeric) as fee_semester,
             min(nullif(pp.fees ->> 'total', '')::numeric) as fee_total, min(nullif(pp.fees ->> 'exam', '')::numeric) as fee_exam,
             min(nullif(pp.fees ->> 'registration', '')::numeric) as fee_registration,
             array_remove(array_agg(distinct pp.intake), null) as intakes,
             array_remove(array_agg(distinct pp.season_to), null) as deadlines,
             max(pp.valid_from) as updated_at
        from b2b.partner_programmes pp
        join b2b.partners p on p.id = pp.partner_id
       where pp.programme_id = c.id and pp.active and pp.valid_to is null and p.status <> 'closed'
         and (pp.season_to is null or pp.season_to >= current_date)) o on true
   where c.active;

create or replace view catalog.partner_rates_v as
  with offers as (
    select pp.partner_id, pp.programme_id, c.university_id, c.fee_yearly, c.fee_total,
           coalesce(nullif(pp.fees ->> 'yearly', '')::numeric, c.fee_yearly) as yearly,
           coalesce(nullif(pp.fees ->> 'total', '')::numeric, c.fee_total) as total
      from b2b.partner_programmes pp
      join public.catalog_programs c on c.id = pp.programme_id and c.active
      join b2b.partners p on p.id = pp.partner_id and p.status <> 'closed'
     where pp.active and pp.valid_to is null and (pp.season_to is null or pp.season_to >= current_date)
  ), rows as (
    -- the rate in force for each live offer (precedence as b2b.rate_for: partner + programme, partner + university, partner)
    select o.partner_id, o.programme_id, o.university_id, r.id as rate_id, r.scope, r.rate_type, r.value, r.fee_base, r.tiers,
           r.gst_inclusive, r.valid_from, r.valid_to,
           case r.fee_base when 'total' then o.total else coalesce(o.yearly, o.total) end as fee_base_inr
      from offers o
      join lateral (
        select x.* from b2b.rates x
         where x.valid_from <= current_date and (x.valid_to is null or x.valid_to >= current_date)
           and ((x.scope = 'partner_programme' and x.partner_id = o.partner_id and x.programme_id = o.programme_id)
             or (x.scope = 'partner_university' and x.partner_id = o.partner_id and x.university_id = o.university_id)
             or (x.scope = 'partner' and x.partner_id = o.partner_id))
         order by case x.scope when 'partner_programme' then 1 when 'partner_university' then 2 else 3 end, x.valid_from desc, x.id desc
         limit 1) r on true
    union all
    -- university-wide rates of a partner (programme null)
    select x.partner_id, null, x.university_id, x.id, x.scope, x.rate_type, x.value, x.fee_base, x.tiers, x.gst_inclusive, x.valid_from, x.valid_to, null
      from b2b.rates x
     where x.scope = 'partner_university' and x.valid_from <= current_date and (x.valid_to is null or x.valid_to >= current_date)
  ), priced as (
    select w.*,
           case when w.rate_type = 'tiered' then (
             select (t ->> 'pct')::numeric from jsonb_array_elements(coalesce(w.tiers, '[]')) t
              where mp.conversion_pct is null or coalesce((t ->> 'from_pct')::numeric, 0) <= mp.conversion_pct
              order by case when mp.conversion_pct is null then -coalesce((t ->> 'from_pct')::numeric, 0) else coalesce((t ->> 'from_pct')::numeric, 0) end desc
              limit 1) end as current_tier_pct,
           mp.conversion_pct as tier_conversion_pct
      from rows w
      left join lateral (select m.conversion_pct from b2b.money_periods m where m.partner_id = w.partner_id order by m.period desc limit 1) mp on true
  ), eff as (
    select q.*,
           case when q.rate_type = 'percent' then q.value
                when q.rate_type = 'tiered' then q.current_tier_pct
                when q.rate_type = 'fixed' and q.fee_base_inr > 0 then round(q.value / q.fee_base_inr * 100, 4) end as effective_pct,
           case when q.rate_type = 'fixed' then q.value
                when q.fee_base_inr is not null then round(q.fee_base_inr * coalesce(case when q.rate_type = 'percent' then q.value else q.current_tier_pct end, 0) / 100, 2) end as effective_inr
      from priced q
  )
  select e.partner_id, coalesce(p.display_name, p.name) as partner_name, e.university_id, u.name as university_name,
         e.programme_id, c.program_name as programme_name, e.rate_id, e.scope as rate_scope, e.rate_type, e.value, e.fee_base,
         e.tiers as tier_table, e.current_tier_pct, e.tier_conversion_pct, e.gst_inclusive, e.valid_from, e.valid_to,
         e.fee_base_inr, e.effective_pct, e.effective_inr,
         e.programme_id is not null and e.effective_inr is not null
           and e.effective_inr = max(e.effective_inr) filter (where e.programme_id is not null) over (partition by e.programme_id) as is_highest_for_programme,
         e.effective_pct is not null
           and e.effective_pct = max(e.effective_pct) over (partition by e.university_id) as is_highest_for_university
    from eff e
    join b2b.partners p on p.id = e.partner_id
    left join public.catalog_universities u on u.id = e.university_id
    left join public.catalog_programs c on c.id = e.programme_id;

-- ---------- the B2C CRM's database role ----------
do $r$ begin
  if not exists (select 1 from pg_roles where rolname = 'b2c_app') then
    create role b2c_app nologin;
  end if;
end $r$;
grant usage on schema catalog to b2c_app, service_role;
grant select on catalog.programmes_v, catalog.universities_v, catalog.synonyms_v, catalog.partner_rates_v, catalog.changes to b2c_app, service_role;
revoke all on catalog.programmes_v, catalog.universities_v, catalog.synonyms_v, catalog.partner_rates_v, catalog.changes from anon, authenticated;
do $p$ begin
  if not exists (select 1 from pg_policies where schemaname = 'catalog' and tablename = 'changes' and policyname = 'readers') then
    create policy readers on catalog.changes for select to b2c_app, service_role using (true);
  end if;
end $p$;

-- ---------- §7: what the B2C CRM publishes (its Phase 3), read only when it exists ----------
/* The B2C CRM's money for a lead it holds (public.b2c_enrollment_money_v), or null before it publishes the view. */
create or replace function b2b.b2c_money_of(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare r jsonb;
begin
  if to_regclass('public.b2c_enrollment_money_v') is null then return null; end if;
  execute 'select to_jsonb(v) - ''lead_id'' from public.b2c_enrollment_money_v v where v.lead_id = $1 limit 1' into r using p_lead_id;
  return r;
exception when others then
  return null;
end $fn$;

/* The B2C CRM's status of a lead it holds (public.b2c_lead_status_v: Eduwit stage, sub-stage, counsellor, lane), or null. */
create or replace function b2b.b2c_status_of(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare r jsonb;
begin
  if to_regclass('public.b2c_lead_status_v') is null then return null; end if;
  execute 'select to_jsonb(v) - ''lead_id'' from public.b2c_lead_status_v v where v.lead_id = $1 limit 1' into r using p_lead_id;
  return r;
exception when others then
  return null;
end $fn$;

-- ---------- the Master Lead Table: the B2C CRM's stage, counsellor and money ----------
create or replace function b2b.lead_a3_columns_sql()
returns text language sql immutable set search_path = '' as $fn$
  select $c$
               bar.bar_reason as partner_bar_reason, bar.barred_at as partner_barred_at,
               coalesce(op.n, 0)::int as other_providers_count, op.names as other_providers,
               ca.b2c_lane, coalesce(l.allocation_reason, ca.alloc_reason) as allocation_reason,
               case when bar.bar_reason is not null and (l.destination_type = 'in_house' or (ih.status = 'handed_off' and l.allocation_id = ih.id)) then 'barred'
                    when ih.id is null or ih.outcome in ('requalified', 'routed_to_partners') then null
                    when exists (select 1 from b2b.allocations pa where pa.lead_id = l.id and pa.destination_type = 'partner'
                                    and pa.origin in ('to_partners', 'requalify', 'reroute') and (pa.created_at, pa.id) > (ih.created_at, ih.id)) then null
                    when ih.reason in ('not_qualified', 'consent_no_answer') then 'qualification_nurture'
                    else 'selling' end as hold_kind,
               exists (select 1 from b2b.lead_reenquiries rq where rq.lead_id = l.id and rq.acknowledged_at is null) as reenquired_open,
               pc.platform as paid_platform,
               b2b.consent_state_of(b2b.partner_consent(l)) as consent_state,
               ca.lost_grace_until,
               -- Addendum 4 §3: the B2C CRM's own stage and counsellor, for leads it holds; §7: its money, once it publishes it
               case when l.destination_type = 'in_house' then l.custom_fields -> 'b2c' ->> 'stage' end as b2c_stage,
               case when l.destination_type = 'in_house' then l.custom_fields -> 'b2c' ->> 'sub_stage' end as b2c_sub_stage,
               case when l.destination_type = 'in_house' then l.custom_fields -> 'b2c' ->> 'owner_name' end as b2c_owner_name,
               case when l.destination_type = 'in_house' then b2b.b2c_money_of(l.id) end as b2c_money
  $c$;
$fn$;

-- ---------- B2C CRM link overview: the p95 delivery lag against the 5-second target (Addendum 4 §1) ----------
create or replace function b2b.b2c_link_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  w b2b.webhook_endpoints;
  v_keys jsonb;
  v_snap text[] := array['b2c.lead_upserted', 'b2c.lead_released'];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into w from b2b.webhook_endpoints where consumer = 'b2c_crm';
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'prefix', key_prefix, 'scopes', scopes, 'last_used_at', last_used_at) order by id), '[]')
    into v_keys from b2b.api_keys where revoked_at is null and 'b2c' = any (scopes);
  return jsonb_build_object(
    'contract_version', 4,
    'settings', cfg,
    'fields', b2b.b2c_fields(),
    'endpoint', case when w.id is not null then jsonb_build_object('id', w.id, 'name', w.name, 'url', w.url, 'active', w.active, 'events', w.events,
                       'has_secret', w.secret_id is not null, 'last_success_at', w.last_success_at, 'last_failure_at', w.last_failure_at, 'last_error', w.last_error,
                       'subscribed', b2b.event_subscribed(w.events, 'b2c.lead_upserted') and b2b.event_subscribed(w.events, 'b2c.lead_released')) end,
    'keys', v_keys,
    'checks', jsonb_build_object(
      'endpoint', w.id is not null,
      'secret', w.secret_id is not null,
      'subscribed', coalesce(b2b.event_subscribed(w.events, 'b2c.lead_upserted'), false),
      'ping', exists (select 1 from b2b.integration_outbox o where o.endpoint_id = w.id and o.event_type = 'ping' and o.status = 'delivered'),
      'active', coalesce(w.active, false),
      'key', jsonb_array_length(v_keys) > 0,
      'key_used', exists (select 1 from b2b.api_keys where revoked_at is null and 'b2c' = any (scopes) and last_used_at is not null),
      'first_delivery', exists (select 1 from b2b.integration_outbox o where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.status = 'delivered'),
      'first_write', exists (select 1 from b2b.b2c_writes where status in ('applied', 'unchanged'))),
    'sync', jsonb_build_object(
      'in_scope', (select count(*) from b2b.b2c_sync where in_scope),
      'held_now', (select count(*) from public.student_leads l where b2b.b2c_holds(l)),
      'changes_24h', (select count(*) from b2b.b2c_sync where changed_at > now() - interval '24 hours'),
      'last_change_at', (select max(changed_at) from b2b.b2c_sync),
      'last_seq', (select max(seq) from b2b.b2c_sync),
      'tick', (select value from b2b.b2c_link_state where key = 'cursor')),
    'deliveries', jsonb_build_object(
      'by_status', coalesce((select jsonb_object_agg(status, n) from (select o.status, count(*) n from b2b.integration_outbox o
                               where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.created_at > now() - interval '24 hours' group by 1) x), '{}'),
      'waiting', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status in ('pending', 'failed', 'sending')),
      'lag_seconds_avg', (select round(avg(extract(epoch from o.delivered_at - o.created_at))::numeric, 1) from b2b.integration_outbox o
                            where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.delivered_at > now() - interval '1 hour'),
      'lag_seconds_max', (select round(max(extract(epoch from o.delivered_at - o.created_at))::numeric, 1) from b2b.integration_outbox o
                            where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.delivered_at > now() - interval '1 hour'),
      -- Addendum 4 §1: a change to a B2C-held lead is delivered within 5 seconds at p95
      'lag_seconds_p95', (select round((percentile_cont(0.95) within group (order by extract(epoch from o.delivered_at - o.created_at)))::numeric, 1)
                            from b2b.integration_outbox o
                           where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.delivered_at > now() - interval '1 hour'),
      'lag_target_seconds', 5),
    'writes', jsonb_build_object(
      'by_status', coalesce((select jsonb_object_agg(kind || '.' || status, n) from (select kind, status, count(*) n from b2b.b2c_writes
                               where created_at > now() - interval '24 hours' group by 1, 2) x), '{}'),
      'last_at', (select max(created_at) from b2b.b2c_writes)),
    'log', coalesce((select jsonb_agg(x order by x ->> 'at' desc) from (
      (select jsonb_build_object('dir', 'out', 'at', s.changed_at, 'lead_id', s.lead_id, 'name', l.student_name, 'type', case when s.in_scope then 'upserted' else 'released' end,
                                 'version', s.version, 'origin', s.origin,
                                 'delivery', (select jsonb_build_object('status', o.status, 'error', o.last_error, 'attempts', o.attempts) from b2b.integration_outbox o
                                               where o.endpoint_id = w.id and o.idempotency_key = w.id || ':lead_' || s.lead_id || '_v' || s.version)) x
         from b2b.b2c_sync s left join public.student_leads l on l.id = s.lead_id order by s.changed_at desc limit 40)
      union all
      (select jsonb_build_object('dir', 'in', 'at', b.created_at, 'lead_id', b.lead_id, 'name', l.student_name, 'type', b.kind, 'status', b.status,
                                 'http_status', b.http_status, 'error', b.error, 'actor', b.actor, 'changes', b.changes, 'request_id', b.request_id,
                                 'version', b.version_after) x
         from b2b.b2c_writes b left join public.student_leads l on l.id = b.lead_id order by b.created_at desc limit 40)) y), '[]'));
end $fn$;

revoke execute on function b2b.catalog_change_log(), b2b.b2c_money_of(bigint), b2b.b2c_status_of(bigint) from public, anon, authenticated;
grant execute on function b2b.b2c_money_of(bigint), b2b.b2c_status_of(bigint) to authenticated, service_role;
