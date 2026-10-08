-- PENDING (hand-applied in the Supabase SQL editor after m31m, before m31o): M31n, rebuild the analytics fact views for
-- Addendum 3 (docs/B2B_CRM_ADDENDUM_3.md; design pending/m31n_facts; review findings C53, C64, C69, C70, C71, C90, C102, C103).
-- It is a pending file because it contains DROP, which the Supabase connector holds for manual confirmation.
--   fact_leads         + sub_source, b2c_reason, hold_kind, partner_barred, bar_reason, requalified, reenquiries, consent_state,
--                      not_passed_detail, accepted_at, enrolled_at; enrolled = b2b.is_enrolled_status(enrollment_status) (C64:
--                      'pending' is not an enrolment); paid / platform from the current cycle's lead_campaigns row (m31g)
--   fact_allocations   + stage (the A/B/C score stage; the metric dimension is 'score_stage', C90), score_inr, effort_factor,
--                      sla_factor, p_enroll, origin, from_b2c, paid, platform, campaign_id, interest_rank, programme_id, programme,
--                      received (the m31c predicate), accepted = status accepted or accepted_at set (C102: closed-never-accepted is
--                      not accepted), accepted_at, duplicate_upheld (an upheld duplicate_after_acceptance dispute, C53), lost_grace,
--                      days_to_enrol, the lead dimensions (C70); the effort columns are null unless received (C69), activities_7d
--                      counts outbound activities only (C71), stale covers open allocations not lost in grace, matured reads
--                      engine.a3_fixed.matured_days
--   fact_sla           + lead_id, segment, course, level, mode, routing_mode, attempt_no, source, campaign, state, lead_status, language
--   fact_enrollments   + programme, enrolled_at, segment, source, sub_source, campaign, city, state, lead_status, language, paid, platform
--   fact_money         + segment, course, source, campaign, state
--   fact_sync          + discarded (dead_letter stays: error or held_unmapped and not discarded, m16c's rule)
--   fact_ai            recommendation rows carry their kind in run_kind and their status in status (C103)
-- fact_invoices, fact_notifications and fact_capi are unchanged and not rebuilt.
-- One transaction: the refresh lock is held (a running refresh finishes first; later ticks return busy), the cron job
-- b2b-refresh-facts is paused, the views are removed in dependency order (fact_allocations, fact_sla, fact_enrollments and
-- fact_money read fact_leads) and recreated populated (CREATE fills them, so no refresh is needed), every unique index, the
-- created_at indexes and the m27a grants are recreated, and the job is re-enabled at every 15 minutes (F8). refresh_facts()
-- (m27a) is unchanged: it refreshes fact_leads first. Column names, types and the primary keys the metric layer, the reports
-- and the AI read keep their meaning; only columns are added (and fact_ai's status is corrected).
-- Re-applying this file is harmless: it rebuilds the same views again.

begin;
select pg_advisory_xact_lock(hashtext('b2b.refresh_facts'));
select cron.alter_job(jobid, active := false) from cron.job where jobname = 'b2b-refresh-facts';

drop materialized view if exists b2b.fact_allocations;
drop materialized view if exists b2b.fact_sla;
drop materialized view if exists b2b.fact_enrollments;
drop materialized view if exists b2b.fact_money;
drop materialized view if exists b2b.fact_leads;
drop materialized view if exists b2b.fact_sync;
drop materialized view if exists b2b.fact_ai;

-- ---------- fact_leads: one row per lead (not deleted or merged); no personal data ----------
create materialized view b2b.fact_leads as
select l.id lead_id,
       l.created_at,
       coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number) is_test,
       coalesce(nullif(lower(trim(l.lead_source)), ''), 'unknown') source,
       nullif(lower(trim(l.source_detail)), '') sub_source,
       coalesce(nullif(lower(trim(l.channel)), ''), 'unknown') channel,
       coalesce(lc.campaign_name, nullif(l.utm_campaign, ''), nullif(l.campaign, '')) campaign,
       coalesce(lc.platform, 'none') platform,
       coalesce(lc.paid, false) paid,
       lc.form_id form,
       nullif(lower(trim(l.utm_source)), '') utm_source,
       nullif(lower(trim(l.utm_medium)), '') utm_medium,
       nullif(initcap(trim(l.city)), '') city,
       nullif(initcap(trim(l.state)), '') state,
       coalesce(split_part(a.segment, '|', 1), b2b.match_course_key(coalesce(nullif(l.interested_course, ''), l.field_of_interest)), '?') course,
       coalesce(nullif(split_part(a.segment, '|', 2), '*'),
                case when lower(coalesce(l.program_level, '')) ~ '^(pg|post ?grad|master|postgraduate)' then 'PG'
                     when lower(coalesce(l.program_level, '')) ~ '^(ug|under ?grad|bachelor|graduat)' then 'UG' end) level,
       coalesce(nullif(split_part(a.segment, '|', 3), '*'),
                case when lower(coalesce(l.study_mode_preference, '')) ~ 'online' then 'Online'
                     when lower(coalesce(l.study_mode_preference, '')) ~ '(distance|odl|correspond)' then 'ODL'
                     when lower(coalesce(l.study_mode_preference, '')) ~ '(regular|campus|offline|full)' then 'Regular' end) mode,
       a.segment,
       nullif(trim(l.interested_specialization), '') specialization,
       nullif(trim(coalesce(nullif(l.interested_university, ''), l.university_preference)), '') university,
       coalesce(nullif(upper(trim(l.lead_status)), ''), 'NONE') lead_status,
       nullif(lower(l.temperature), '') temperature,
       coalesce(l.stage, 'new') stage,
       l.sub_stage,
       l.lost_reason,
       coalesce(nullif(lower(trim(l.preferred_language)), ''), 'unknown') language,
       case when np.lead_id is not null then 'not_passed' when l.destination_type = 'partner' then 'partner'
            when l.destination_type = 'in_house' then 'b2c' else 'pool' end destination,
       case when l.destination_type = 'in_house' then coalesce(a.b2c_lane, 'sales') end b2c_lane,
       case when l.destination_type = 'in_house' then coalesce(a.reason, l.allocation_reason) end b2c_reason,
       -- b2b.b2c_hold's rule, set-based (the same rule as m31l's lead lists)
       case when bar.reason is not null and (l.destination_type = 'in_house' or (ih.status = 'handed_off' and l.allocation_id = ih.id)) then 'barred'
            when ih.id is null or ih.outcome in ('requalified', 'routed_to_partners') then null
            when exists (select 1 from b2b.allocations pa where pa.lead_id = l.id and pa.destination_type = 'partner'
                            and pa.origin in ('to_partners', 'requalify', 'reroute') and (pa.created_at, pa.id) > (ih.created_at, ih.id)) then null
            when ih.reason in ('not_qualified', 'consent_no_answer') then 'qualification_nurture'
            else 'selling' end hold_kind,
       bar.reason is not null partner_barred,
       bar.reason bar_reason,
       exists (select 1 from b2b.allocations rq where rq.lead_id = l.id and rq.outcome = 'requalified') requalified,
       (select count(*)::int from b2b.lead_reenquiries re where re.lead_id = l.id) reenquiries,
       b2b.consent_state_of(b2b.partner_consent(l)) consent_state,
       np.reason not_passed_reason,
       np.detail not_passed_detail,
       l.partner_id,
       l.allocated_at routed_at,
       a.accepted_at,
       round(extract(epoch from l.allocated_at - l.created_at)::numeric / 3600, 2) hours_to_route,
       a.status = 'accepted' or a.accepted_at is not null accepted,
       l.first_contacted_at is not null contacted,
       l.applied_at is not null applied,
       b2b.is_enrolled_status(l.enrollment_status) enrolled,
       case when b2b.is_enrolled_status(l.enrollment_status)
            then coalesce(l.enrollment_date::timestamp at time zone 'Asia/Kolkata', l.enrollment_verified_at) end enrolled_at,
       l.enrollment_verified_at is not null verified,
       coalesce(l.cycle_no, 1) > 1 reopened,
       coalesce(l.is_opted_out, false) opted_out
  from public.student_leads l
  left join b2b.allocations a on a.id = l.allocation_id
  left join b2b.not_passed np on np.lead_id = l.id and np.passed_at is null
  -- the current cycle's attribution row (m31g), else the latest one
  left join lateral (select c.* from b2b.lead_campaigns c where c.lead_id = l.id
                      order by (c.cycle_no = coalesce(l.cycle_no, 1)) desc, c.cycle_no desc limit 1) lc on true
  -- the oldest partner bar on the lead or on the same phone digits (m31a partner_bars; phone_digits is null for test leads)
  left join lateral (select pb.reason, pb.barred_at from b2b.partner_bars pb
                      where pb.lead_id = l.id
                         or (pb.phone_digits is not null and length(pb.phone_digits) >= 10
                             and pb.phone_digits = regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'))
                      order by pb.barred_at limit 1) bar on true
  -- the lead's latest in_house allocation (any cycle)
  left join lateral (select ih.id, ih.status, ih.reason, ih.outcome, ih.created_at from b2b.allocations ih
                      where ih.lead_id = l.id and ih.destination_type = 'in_house'
                      order by ih.created_at desc, ih.id desc limit 1) ih on true
 where l.deleted_at is null and l.merged_into_id is null;
create unique index fact_leads_pk on b2b.fact_leads (lead_id);
create index fact_leads_created_idx on b2b.fact_leads (created_at);

-- ---------- fact_allocations: one row per partner allocation ----------
create materialized view b2b.fact_allocations as
select a.id allocation_id, a.lead_id, a.created_at, a.partner_id, a.segment,
       split_part(a.segment, '|', 1) course, nullif(split_part(a.segment, '|', 2), '*') level, nullif(split_part(a.segment, '|', 3), '*') mode,
       a.mode routing_mode, a.attempt_no, a.status, a.is_test,
       a.origin,
       coalesce(a.origin in ('to_partners', 'requalify'), false) from_b2c,
       a.stage, a.score_inr, a.effort_factor, a.sla_factor, a.p_enroll, a.interest_rank,
       a.programme_id,
       (select c.program_name from public.catalog_programs c where c.id = a.programme_id) programme,
       coalesce(a.paid, fl.paid, false) paid,
       coalesce(a.paid_platform, fl.platform, 'none') platform,
       a.campaign_id,
       -- received: the m31c predicate (received_counts, stage_score live counts, C69)
       (a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null) received,
       a.status = 'accepted' or a.accepted_at is not null accepted,
       a.accepted_at,
       a.status = 'duplicate' duplicate, a.status = 'rejected' rejected, a.status = 'failed' failed,
       exists (select 1 from b2b.commission_disputes cd where cd.allocation_id = a.id and cd.status = 'upheld' and cd.kind = 'duplicate_after_acceptance') duplicate_upheld,
       a.lost_at is not null and a.lost_revived_at is null and a.status in ('pushed', 'accepted') lost_grace,
       coalesce(d.holdout, false) holdout, d.scoring_mode, coalesce(a.model_version, d.model_version) model_version, d.selection_probability,
       a.cpe_net_inr cpe, a.ncpl_inr ncpl_expected,
       -- effort: only for leads the partner received (C69); a voided first-connect check is not a miss
       case when a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null then fa.hours end first_attempt_hours,
       case when a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null then fa.status = 'met' end first_attempt_met,
       case when (a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null) and fc.status is distinct from 'void' then fc.status in ('met', 'met_late') end connected,
       case when a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null then coalesce(pa.calls_24h, 0) end attempts_24h,
       case when a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null then coalesce(pa.calls_72h, 0) end attempts_72h,
       case when a.status in ('pushed', 'accepted', 'closed') or a.accepted_at is not null then coalesce(pa.calls_7d, 0) end activities_7d,
       pa.counsellor,
       coalesce(o.stage, 'none') stage_reached,
       coalesce(o.enrolled, false) enrolled,
       o.age_days,
       o.age_days >= coalesce(b2b.stats_num((select s.value -> 'a3_fixed' -> 'matured_days' from b2b.settings s where s.key = 'engine')), 60) matured,
       case when o.allocation_id is not null then b2b.allocation_reward(a.id) end reward,
       en.days_to_enrol,
       -- stale: open allocations the partner still works (not lost in grace)
       case when a.status in ('pushed', 'accepted') and (a.lost_at is null or a.lost_revived_at is not null)
            then l.partner_stale_at is not null and l.allocation_id = a.id end stale,
       fl.source, fl.sub_source, fl.channel, fl.form, fl.utm_source, fl.utm_medium, fl.campaign, fl.city, fl.state, fl.university,
       fl.specialization, fl.lead_status, fl.temperature, fl.sub_stage, fl.lost_reason, fl.language
  from b2b.allocations a
  left join b2b.engine_decisions d on d.id = a.engine_decision_id
  left join public.student_leads l on l.id = a.lead_id
  left join b2b.fact_leads fl on fl.lead_id = a.lead_id
  left join lateral (select c.status, round(extract(epoch from c.met_at - c.started_at)::numeric / 3600, 2) hours
                       from b2b.sla_checks c where c.allocation_id = a.id and c.sla = 'first_attempt' order by c.started_at limit 1) fa on true
  left join lateral (select c.status from b2b.sla_checks c where c.allocation_id = a.id and c.sla = 'first_connect' order by c.started_at limit 1) fc on true
  left join lateral (select count(*) filter (where p.kind in ('call', 'whatsapp', 'sms', 'email', 'meeting') and p.direction is distinct from 'inbound' and p.occurred_at < a.created_at + interval '24 hours') calls_24h,
                            count(*) filter (where p.kind in ('call', 'whatsapp', 'sms', 'email', 'meeting') and p.direction is distinct from 'inbound' and p.occurred_at < a.created_at + interval '72 hours') calls_72h,
                            count(*) filter (where p.kind in ('call', 'whatsapp', 'sms', 'email', 'meeting') and p.direction is distinct from 'inbound' and p.occurred_at > now() - interval '7 days') calls_7d,
                            mode() within group (order by p.counsellor_name) filter (where p.counsellor_name is not null) counsellor
                       from b2b.partner_activities p where p.allocation_id = a.id) pa on true
  left join lateral (select (min(e.enrolled_on) - (a.created_at at time zone 'Asia/Kolkata')::date) days_to_enrol
                       from public.enrollments e
                      where e.status <> 'cancelled'
                        and (e.allocation_id = a.id
                             or (e.allocation_id is null and e.lead_id = a.lead_id and e.partner_id = a.partner_id and coalesce(e.cycle_no, 1) = a.cycle_no))) en on true
  left join b2b.allocation_outcomes() o on o.allocation_id = a.id
 where a.destination_type = 'partner';
create unique index fact_allocations_pk on b2b.fact_allocations (allocation_id);
create index fact_allocations_created_idx on b2b.fact_allocations (created_at);

-- ---------- fact_enrollments: one row per enrolment (B2B and shared) ----------
create materialized view b2b.fact_enrollments as
select e.id enrollment_id, e.lead_id, e.allocation_id, e.created_at, e.enrolled_on, e.partner_id, coalesce(e.source_product, 'b2c') product,
       e.status, e.programme_id, coalesce(c.course_key, '?') course, c.level, c.mode, coalesce(u.short_name, u.name, e.university_name) university,
       coalesce(nullif(e.programme_name, ''), c.program_name) programme,
       a.segment,
       e.fee_amount_inr fee, e.expected_net_revenue_inr expected_inr, e.realised_net_revenue_inr realised_inr, e.verified_at, e.refunded_at,
       (e.enrolled_on::timestamp at time zone 'Asia/Kolkata') enrolled_at,
       (e.enrolled_on - (a.created_at at time zone 'Asia/Kolkata')::date) days_to_enrol,
       fl.source, fl.sub_source, fl.campaign, fl.city, fl.state, fl.lead_status, fl.language, fl.paid, fl.platform,
       coalesce(a.is_test, false) is_test
  from public.enrollments e
  left join b2b.allocations a on a.id = e.allocation_id
  left join public.catalog_programs c on c.id = e.programme_id
  left join public.catalog_universities u on u.id = coalesce(e.university_id, c.university_id)
  left join b2b.fact_leads fl on fl.lead_id = e.lead_id;
create unique index fact_enrollments_pk on b2b.fact_enrollments (enrollment_id);

-- ---------- fact_sla: one row per SLA check (void checks left out; a breach met late stays a breach) ----------
create materialized view b2b.fact_sla as
select c.id sla_id, c.allocation_id, c.lead_id, c.partner_id, c.sla, c.started_at, c.due_at, c.status, c.is_test,
       c.status = 'met' met, c.status in ('breached', 'met_late') breached, c.status in ('met', 'met_late', 'breached') decided,
       round(extract(epoch from coalesce(c.met_at, now()) - c.started_at)::numeric / 3600, 2) hours,
       extract(hour from c.due_at at time zone 'Asia/Kolkata')::int due_hour,
       a.segment, split_part(a.segment, '|', 1) course, nullif(split_part(a.segment, '|', 2), '*') level, nullif(split_part(a.segment, '|', 3), '*') mode,
       a.mode routing_mode, a.attempt_no,
       fl.source, fl.campaign, fl.state, fl.lead_status, fl.language
  from b2b.sla_checks c
  left join b2b.allocations a on a.id = c.allocation_id
  left join b2b.fact_leads fl on fl.lead_id = c.lead_id
 where c.status <> 'void';
create unique index fact_sla_pk on b2b.fact_sla (sla_id);

-- ---------- fact_money: one row per earning line ----------
create materialized view b2b.fact_money as
select x.id line_id, x.partner_id, x.period, x.kind, x.status, x.net_inr, x.gross_inr, x.created_at, x.realised_at, x.lead_id,
       a.segment, split_part(a.segment, '|', 1) course,
       fl.source, fl.campaign, fl.state,
       coalesce(a.is_test, false) is_test
  from b2b.earnings x
  left join b2b.allocations a on a.id = x.allocation_id
  left join b2b.fact_leads fl on fl.lead_id = x.lead_id;
create unique index fact_money_pk on b2b.fact_money (line_id);

-- ---------- fact_sync: one row per partner event (test flag from the allocation; discarded events are neither unmapped nor dead letters) ----------
create materialized view b2b.fact_sync as
select e.id event_id, e.partner_id, e.received_at created_at, e.status,
       e.status = 'error' error,
       e.status = 'held_unmapped' and e.discarded_at is null unmapped,
       e.discarded_at is not null discarded,
       e.status in ('error', 'held_unmapped') and e.discarded_at is null dead_letter,
       round(greatest(extract(epoch from e.received_at - b2b.try_timestamptz(e.raw ->> 'occurred_at')), 0)::numeric / 60, 1) lag_minutes,
       coalesce(a.is_test, false) is_test
  from b2b.partner_events e
  left join b2b.allocations a on a.id = e.allocation_id;
create unique index fact_sync_pk on b2b.fact_sync (event_id);
create index fact_sync_created_idx on b2b.fact_sync (created_at);

-- ---------- fact_ai: runs and recommendations (C103: a recommendation's kind is run_kind, its status is status) ----------
create materialized view b2b.fact_ai as
select 'run:' || r.id ai_id, 'run' kind, r.created_at, r.kind run_kind, r.status, r.cost_usd, null::text rec_status, false is_test
  from b2b.ai_runs r
union all
select 'rec:' || x.id, 'recommendation', x.created_at, x.kind, x.status, 0, x.status, false from b2b.ai_recommendations x;
create unique index fact_ai_pk on b2b.fact_ai (ai_id);

-- ---------- grants (as m27a) ----------
do $grants$
declare t text;
begin
  foreach t in array array['fact_leads', 'fact_allocations', 'fact_enrollments', 'fact_sla', 'fact_money', 'fact_sync', 'fact_ai'] loop
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to service_role', t);
  end loop;
end $grants$;

-- the refresh job runs every 15 minutes from now on (F8)
select cron.alter_job(jobid, schedule := '*/15 * * * *', active := true) from cron.job where jobname = 'b2b-refresh-facts';
select b2b.log_event('migration.manual_applied', null, null, null,
                     '{"file":"pending/m31n_facts","fixes":["C53","C64","C69","C70","C71","C90","C102","C103","F8","F60","F158"]}');
commit;
