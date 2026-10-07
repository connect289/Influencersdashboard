-- M27a: analytics facts (spec B13: "Analytics never slow down operational screens. They read rollup tables or materialized
-- views refreshed every minute (pg_cron)"). One row per business object, already joined and bucketed, with no personal
-- data (no names, phones or e-mails). Every metric, dashboard, report, alert and the AI's "Ask the CRM" read only these.
--   fact_leads         one row per lead (not deleted or merged): source, campaign, place, interest, Witty status, stage,
--                      destination, routing and outcome flags
--   fact_allocations   one row per partner allocation: partner, segment, mode, attempt, outcome flags, effort (time to
--                      first attempt, attempts in 24 h / 72 h, connect), stage reached, enrolment, realised commission, holdout
--   fact_enrollments   one row per enrolment (B2B and shared): partner, programme, status, amounts, days to enrol
--   fact_sla           one row per SLA check; fact_money one row per earning line; fact_invoices one row per invoice
--   fact_notifications, fact_capi, fact_sync (partner events), fact_ai (runs and recommendations)
-- refresh_facts() refreshes them all concurrently (readers are never blocked); pg_cron runs it every minute.

create materialized view if not exists b2b.fact_leads as
select l.id lead_id,
       l.created_at,
       coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number) is_test,
       coalesce(nullif(lower(trim(l.lead_source)), ''), 'unknown') source,
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
       np.reason not_passed_reason,
       l.partner_id,
       l.allocated_at routed_at,
       round(extract(epoch from l.allocated_at - l.created_at)::numeric / 3600, 2) hours_to_route,
       a.status = 'accepted' or a.accepted_at is not null accepted,
       l.first_contacted_at is not null contacted,
       l.applied_at is not null applied,
       l.enrollment_status is not null and l.enrollment_status not in ('cancelled') enrolled,
       l.enrollment_verified_at is not null verified,
       coalesce(l.cycle_no, 1) > 1 reopened,
       coalesce(l.is_opted_out, false) opted_out
  from public.student_leads l
  left join b2b.allocations a on a.id = l.allocation_id
  left join b2b.not_passed np on np.lead_id = l.id and np.passed_at is null
  left join lateral (select c.* from b2b.lead_campaigns c where c.lead_id = l.id order by c.cycle_no desc limit 1) lc on true
 where l.deleted_at is null and l.merged_into_id is null;
create unique index if not exists fact_leads_pk on b2b.fact_leads (lead_id);
create index if not exists fact_leads_created_idx on b2b.fact_leads (created_at);

create materialized view if not exists b2b.fact_allocations as
select a.id allocation_id, a.lead_id, a.created_at, a.partner_id, a.segment,
       split_part(a.segment, '|', 1) course, nullif(split_part(a.segment, '|', 2), '*') level, nullif(split_part(a.segment, '|', 3), '*') mode,
       a.mode routing_mode, a.attempt_no, a.status, a.is_test,
       a.status = 'accepted' or a.accepted_at is not null or a.status = 'closed' accepted,
       a.status = 'duplicate' duplicate, a.status = 'rejected' rejected, a.status = 'failed' failed,
       coalesce(d.holdout, false) holdout, d.scoring_mode, d.model_version, d.selection_probability,
       a.cpe_net_inr cpe, a.ncpl_inr ncpl_expected,
       fa.hours first_attempt_hours, fa.status = 'met' first_attempt_met,
       fc.status in ('met', 'met_late') connected,
       coalesce(pa.calls_24h, 0) attempts_24h, coalesce(pa.calls_72h, 0) attempts_72h, coalesce(pa.calls_7d, 0) activities_7d,
       pa.counsellor,
       coalesce(o.stage, 'none') stage_reached,
       coalesce(o.enrolled, false) enrolled,
       o.age_days,
       o.age_days >= coalesce((select (value ->> 'maturity_days')::numeric from b2b.settings where key = 'engine'), 60) matured,
       case when o.allocation_id is not null then b2b.allocation_reward(a.id) end reward,
       l.partner_stale_at is not null and l.allocation_id = a.id stale,
       fl.source, fl.campaign, fl.state, fl.lead_status, fl.language
  from b2b.allocations a
  left join b2b.engine_decisions d on d.id = a.engine_decision_id
  left join public.student_leads l on l.id = a.lead_id
  left join b2b.fact_leads fl on fl.lead_id = a.lead_id
  left join lateral (select c.status, round(extract(epoch from c.met_at - c.started_at)::numeric / 3600, 2) hours
                       from b2b.sla_checks c where c.allocation_id = a.id and c.sla = 'first_attempt' order by c.started_at limit 1) fa on true
  left join lateral (select c.status from b2b.sla_checks c where c.allocation_id = a.id and c.sla = 'first_connect' order by c.started_at limit 1) fc on true
  left join lateral (select count(*) filter (where p.kind in ('call', 'whatsapp', 'sms', 'email', 'meeting') and p.direction is distinct from 'inbound' and p.occurred_at < a.created_at + interval '24 hours') calls_24h,
                            count(*) filter (where p.kind in ('call', 'whatsapp', 'sms', 'email', 'meeting') and p.direction is distinct from 'inbound' and p.occurred_at < a.created_at + interval '72 hours') calls_72h,
                            count(*) filter (where p.occurred_at > now() - interval '7 days') calls_7d,
                            mode() within group (order by p.counsellor_name) filter (where p.counsellor_name is not null) counsellor
                       from b2b.partner_activities p where p.allocation_id = a.id) pa on true
  left join b2b.allocation_outcomes() o on o.allocation_id = a.id
 where a.destination_type = 'partner';
create unique index if not exists fact_allocations_pk on b2b.fact_allocations (allocation_id);
create index if not exists fact_allocations_created_idx on b2b.fact_allocations (created_at);

create materialized view if not exists b2b.fact_enrollments as
select e.id enrollment_id, e.lead_id, e.allocation_id, e.created_at, e.enrolled_on, e.partner_id, coalesce(e.source_product, 'b2c') product,
       e.status, e.programme_id, coalesce(c.course_key, '?') course, c.level, c.mode, coalesce(u.short_name, u.name, e.university_name) university,
       e.fee_amount_inr fee, e.expected_net_revenue_inr expected_inr, e.realised_net_revenue_inr realised_inr, e.verified_at, e.refunded_at,
       (e.enrolled_on - (a.created_at at time zone 'Asia/Kolkata')::date) days_to_enrol,
       coalesce(a.is_test, false) is_test
  from public.enrollments e
  left join b2b.allocations a on a.id = e.allocation_id
  left join public.catalog_programs c on c.id = e.programme_id
  left join public.catalog_universities u on u.id = coalesce(e.university_id, c.university_id);
create unique index if not exists fact_enrollments_pk on b2b.fact_enrollments (enrollment_id);

create materialized view if not exists b2b.fact_sla as
select c.id sla_id, c.allocation_id, c.partner_id, c.sla, c.started_at, c.due_at, c.status, c.is_test,
       c.status = 'met' met, c.status = 'breached' breached, c.status in ('met', 'met_late', 'breached') decided,
       round(extract(epoch from coalesce(c.met_at, now()) - c.started_at)::numeric / 3600, 2) hours,
       extract(hour from c.due_at at time zone 'Asia/Kolkata')::int due_hour
  from b2b.sla_checks c where c.status <> 'void';
create unique index if not exists fact_sla_pk on b2b.fact_sla (sla_id);

create materialized view if not exists b2b.fact_money as
select x.id line_id, x.partner_id, x.period, x.kind, x.status, x.net_inr, x.gross_inr, x.created_at, x.realised_at, x.lead_id,
       coalesce(a.is_test, false) is_test
  from b2b.earnings x left join b2b.allocations a on a.id = x.allocation_id;
create unique index if not exists fact_money_pk on b2b.fact_money (line_id);

create materialized view if not exists b2b.fact_invoices as
select i.id invoice_id, i.partner_id, i.number, i.status, i.issue_date, i.due_date, i.total_inr, coalesce(i.received_inr, 0) received_inr,
       coalesce(i.tds_inr, 0) tds_inr, greatest(i.total_inr - coalesce(i.received_inr, 0) - coalesce(i.tds_inr, 0), 0) outstanding_inr,
       case when i.status in ('sent', 'partly_paid') and i.due_date is not null then greatest(current_date - i.due_date, 0) end days_overdue,
       case when i.status not in ('sent', 'partly_paid') or i.due_date is null then null
            when current_date - i.due_date <= 0 then 'not due' when current_date - i.due_date <= 30 then '1-30'
            when current_date - i.due_date <= 60 then '31-60' when current_date - i.due_date <= 90 then '61-90' else '90+' end ageing,
       coalesce(i.issue_date::timestamptz, i.created_at) created_at, false is_test
  from b2b.invoices i where i.status <> 'cancelled';
create unique index if not exists fact_invoices_pk on b2b.fact_invoices (invoice_id);

create materialized view if not exists b2b.fact_notifications as
select n.id notification_id, n.partner_id, n.channel, n.kind, n.language, n.status, n.created_at, n.sent_at,
       round(extract(epoch from n.sent_at - n.created_at)::numeric / 60, 1) minutes_to_send, false is_test
  from b2b.student_notifications n;
create unique index if not exists fact_notifications_pk on b2b.fact_notifications (notification_id);

create materialized view if not exists b2b.fact_capi as
select e.id event_id, e.platform, e.stage, e.status, e.occurred_at created_at, e.is_test, cardinality(e.match_keys) match_keys
  from b2b.conversion_events e;
create unique index if not exists fact_capi_pk on b2b.fact_capi (event_id);

create materialized view if not exists b2b.fact_sync as
select e.id event_id, e.partner_id, e.received_at created_at, e.status, e.status = 'error' error, e.status = 'held_unmapped' unmapped,
       round(greatest(extract(epoch from e.received_at - b2b.try_timestamptz(e.raw ->> 'occurred_at')), 0)::numeric / 60, 1) lag_minutes, false is_test
  from b2b.partner_events e;
create unique index if not exists fact_sync_pk on b2b.fact_sync (event_id);

create materialized view if not exists b2b.fact_ai as
select 'run:' || r.id ai_id, 'run' kind, r.created_at, r.kind run_kind, r.status, r.cost_usd, null::text rec_status, false is_test
  from b2b.ai_runs r
union all
select 'rec:' || x.id, 'recommendation', x.created_at, null, x.kind, 0, x.status, false from b2b.ai_recommendations x;
create unique index if not exists fact_ai_pk on b2b.fact_ai (ai_id);

create or replace function b2b.refresh_facts()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare t text; t0 timestamptz := clock_timestamp(); v_out jsonb := '{}';
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.refresh_facts')) then return '{"busy":true}'; end if;
  -- fact_leads first: fact_allocations reads it
  foreach t in array array['fact_leads', 'fact_allocations', 'fact_enrollments', 'fact_sla', 'fact_money', 'fact_invoices',
                           'fact_notifications', 'fact_capi', 'fact_sync', 'fact_ai'] loop
    execute format('refresh materialized view concurrently b2b.%I', t);
  end loop;
  insert into b2b.ai_state (key, value, updated_at) values ('facts', jsonb_build_object('refreshed_at', now(), 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - t0) * 1000));
end $fn$;

do $grants$
declare t text;
begin
  foreach t in array array['fact_leads', 'fact_allocations', 'fact_enrollments', 'fact_sla', 'fact_money', 'fact_invoices',
                           'fact_notifications', 'fact_capi', 'fact_sync', 'fact_ai'] loop
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to service_role', t);
  end loop;
end $grants$;

do $cron$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'b2b-refresh-facts';
  perform cron.schedule('b2b-refresh-facts', '* * * * *', 'select b2b.refresh_facts()');
end $cron$;

revoke execute on function b2b.refresh_facts() from public, anon, authenticated;
grant execute on function b2b.refresh_facts() to service_role;
