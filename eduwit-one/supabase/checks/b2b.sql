-- B2B CRM checks (spec §6, B2B-*). Sources for scripts/db/gen-checks.ts. Test rows (is_test) are excluded wherever
-- the table carries the flag; values carry counts and row ids only.

-- check: B2B-01
-- app: b2b
-- kind: rpc
-- severity: P1
-- cadence_s: 60
-- fix: FIX-OUTBOX-B2B
-- title: The B2B CRM's own health check is not ok
-- description: b2b.health_check(): a stale or failed b2b-* job, a dead or waiting delivery, or the B2C sync cursor over 600 s. FIX-CURSOR-B2C attaches to the cursor case.
select coalesce((h ->> 'ok')::boolean, false) as ok, h as value from (select b2b.health_check() as h) x

-- check: B2B-02
-- app: b2b
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- title: The B2B CRM raised an alert or routing error event
-- description: A b2b.events row of type alert.* or routing.error since this check last ran (2 min on the first run).
select count(*) = 0 as ok,
       jsonb_build_object('count', count(*), 'types', coalesce(jsonb_agg(distinct e.type), '[]'), 'ids', coalesce(to_jsonb((array_agg(e.id order by e.id) filter (where e.id is not null))[1:20]), '[]')) as value
  from b2b.events e
 where (e.type like 'alert.%' or e.type = 'routing.error')
   and e.occurred_at > coalesce((select s.last_ran_at from one.check_state s where s.check_id = 'B2B-02'), now() - interval '2 minutes')

-- check: B2B-03
-- app: b2b
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- title: A B2B intake request errored or is stuck
-- description: b2b.intake_requests in status error (last 24 h), or still received after b2b_intake_received_min minutes. Test requests excluded.
select count(*) = 0 as ok,
       jsonb_build_object('error_24h', count(*) filter (where status = 'error'), 'stuck_received', count(*) filter (where status = 'received'),
                          'ids', coalesce(to_jsonb((array_agg(id order by id) filter (where id is not null))[1:20]), '[]')) as value
  from b2b.intake_requests
 where not coalesce(is_test, false)
   and ((status = 'error' and received_at > now() - interval '24 hours')
        or (status = 'received' and received_at < now() - make_interval(mins => one.threshold('b2b_intake_received_min')::int)))

-- check: B2B-04
-- app: b2b
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- title: A sales-ready lead has not been allocated
-- description: student_leads with is_sales_ready, not a test, not deleted or merged, and no allocation_id allocation_min minutes after sales_ready_at.
select count(*) = 0 as ok, jsonb_build_object('count', count(*), 'lead_ids', coalesce(to_jsonb((array_agg(id order by id) filter (where id is not null))[1:20]), '[]')) as value
  from public.student_leads
 where is_sales_ready and not coalesce(is_test, false) and deleted_at is null and merged_into_id is null and allocation_id is null
   and coalesce(sales_ready_at, created_at) < now() - make_interval(mins => one.threshold('allocation_min')::int)

-- check: B2B-05
-- app: b2b
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- title: A partner allocation is stuck in the push queue or keeps failing
-- description: b2b.allocations queued or pushing for more than push_ack_min minutes, or an allocation whose last push_fail_streak push requests all failed (no 2xx).
with stuck as (
  select id from b2b.allocations
   where status in ('queued', 'pushing') and not coalesce(is_test, false)
     and updated_at < now() - make_interval(mins => one.threshold('push_ack_min')::int)),
streaks as (
  select p.allocation_id from (
    select allocation_id, status_code, row_number() over (partition by allocation_id order by id desc) as rn
      from b2b.push_requests where sent_at > now() - interval '7 days') p
   group by p.allocation_id
  having count(*) filter (where p.rn <= one.threshold('push_fail_streak')) = one.threshold('push_fail_streak')
     and bool_and(p.rn > one.threshold('push_fail_streak') or coalesce(p.status_code, 0) not between 200 and 299))
select (select count(*) from stuck) = 0 and (select count(*) from streaks) = 0 as ok,
       jsonb_build_object('stuck', (select coalesce(jsonb_agg(id order by id), '[]') from stuck),
                          'failing_streaks', (select coalesce(jsonb_agg(allocation_id order by allocation_id), '[]') from streaks)) as value

-- check: B2B-06
-- app: b2b
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- fix: FIX-WEBHOOK-REKICK
-- title: The B2B webhook to Spark is failing
-- description: An active b2b.webhook_endpoints row for consumer b2c_crm whose last failure is newer than its last success.
select count(*) = 0 as ok,
       jsonb_build_object('endpoints', coalesce(jsonb_agg(jsonb_build_object('id', id, 'last_failure_at', last_failure_at, 'last_success_at', last_success_at, 'error', left(last_error, 200))) filter (where id is not null), '[]')) as value
  from b2b.webhook_endpoints
 where consumer = 'b2c_crm' and active and last_failure_at > coalesce(last_success_at, '-infinity'::timestamptz)

-- check: B2B-07
-- app: b2b
-- kind: sql
-- severity: P1
-- cadence_s: 300
-- title: B2B and Spark disagree on a lead's version, or Spark's write-backs fail
-- description: An in-scope b2b.b2c_sync row changed more than b2b_sync_lag_min minutes ago whose version differs from b2c.lead_records, or a b2b.b2c_writes row with http_status 400 and up in the last hour.
with lag as (
  select s.lead_id from b2b.b2c_sync s left join b2c.lead_records r on r.lead_id = s.lead_id
   where s.in_scope and s.changed_at < now() - make_interval(mins => one.threshold('b2b_sync_lag_min')::int)
     and s.version is distinct from r.version),
writes as (select id from b2b.b2c_writes where http_status >= 400 and created_at > now() - interval '1 hour')
select (select count(*) from lag) = 0 and (select count(*) from writes) = 0 as ok,
       jsonb_build_object('version_mismatch', (select count(*) from lag), 'lead_ids', (select coalesce(jsonb_agg(lead_id order by lead_id), '[]') from (select lead_id from lag limit 20) l),
                          'failed_writes_1h', (select count(*) from writes)) as value

-- check: B2B-08
-- app: b2b
-- kind: sql
-- severity: P2
-- cadence_s: 300
-- title: A partner integration is failing, drifting, paused or switched off
-- description: Per partner: adapter poll or token error newer than the last good poll; latest schema snapshot with drift; partners.auto_paused_at set (P1); live switch partner:<id> off.
with p as (
  select pt.id, pt.slug,
         coalesce(greatest(st.token_failed_at, case when st.last_poll_error is not null then st.last_poll_at end) > coalesce(st.last_poll_ok_at, '-infinity'::timestamptz), false) as adapter_error,
         coalesce((select s.drift is not null and s.drift not in ('null'::jsonb, '{}'::jsonb, '[]'::jsonb, 'false'::jsonb)
                     from b2b.partner_schema_snapshots s where s.partner_id = pt.id order by s.created_at desc limit 1), false) as drift,
         pt.auto_paused_at is not null as auto_paused,
         coalesce((select not ls.live from b2b.live_switches ls where ls.scope = 'partner:' || pt.id), false) as switched_off
    from b2b.partners pt left join b2b.partner_adapter_state st on st.partner_id = pt.id
   where pt.status is distinct from 'archived')
select count(*) filter (where adapter_error or drift or auto_paused or switched_off) = 0 as ok,
       jsonb_build_object('partners', count(*),
         'problems', coalesce(jsonb_agg(jsonb_build_object('partner', slug, 'adapter_error', adapter_error, 'drift', drift, 'auto_paused', auto_paused, 'switched_off', switched_off))
                              filter (where adapter_error or drift or auto_paused or switched_off), '[]'),
         'severity', case when bool_or(auto_paused) then 'P1' else 'P2' end) as value
  from p

-- check: B2B-09
-- app: b2b
-- kind: sql
-- severity: P2
-- cadence_s: 900
-- title: Partner mapping, event or review work is waiting too long
-- description: b2b.mapping_queue open for more than partner_queue_h hours, b2b.partner_events in error (last 24 h), or b2b.review_flags unresolved for more than partner_queue_h hours.
with v as (
  select (select count(*) from b2b.mapping_queue where status = 'open' and first_seen < now() - make_interval(hours => one.threshold('partner_queue_h')::int)) as mapping_open,
         (select count(*) from b2b.partner_events where status = 'error' and received_at > now() - interval '24 hours') as partner_event_errors,
         (select count(*) from b2b.review_flags where resolved_at is null and created_at < now() - make_interval(hours => one.threshold('partner_queue_h')::int)) as review_flags_open)
select mapping_open + partner_event_errors + review_flags_open = 0 as ok, to_jsonb(v) as value from v

-- check: B2B-10
-- app: b2b
-- kind: sql
-- severity: P2
-- cadence_s: 900
-- title: Partner SLAs are being breached
-- description: Today's (IST) decided b2b.sla_checks breached above sla_breach_pct percent (at least 10 decided), or a partner whose last sla_met_late_run decided checks were all met_late.
with today as (
  select status from b2b.sla_checks
   where not coalesce(is_test, false) and status in ('met', 'met_late', 'breached')
     and (coalesce(breached_at, met_at, updated_at) at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date),
runs as (
  select partner_id from (
    select partner_id, status, row_number() over (partition by partner_id order by coalesce(met_at, breached_at, updated_at) desc) as rn
      from b2b.sla_checks where not coalesce(is_test, false) and status in ('met', 'met_late', 'breached')) s
   where rn <= one.threshold('sla_met_late_run')
   group by partner_id having count(*) = one.threshold('sla_met_late_run') and bool_and(status = 'met_late'))
select ((select count(*) from today) < 10
         or (select count(*) filter (where status = 'breached') * 100.0 / count(*) from today) <= one.threshold('sla_breach_pct'))
       and (select count(*) from runs) = 0 as ok,
       jsonb_build_object('decided_today', (select count(*) from today),
                          'breached_today', (select count(*) filter (where status = 'breached') from today),
                          'late_run_partners', (select coalesce(jsonb_agg(partner_id), '[]') from runs)) as value

-- check: B2B-11
-- app: b2b
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: A B2B ML model failed
-- description: A b2b.events row of type ml.model_failed in the last 24 h.
select count(*) = 0 as ok, jsonb_build_object('count', count(*), 'last_at', max(occurred_at)) as value
  from b2b.events where type = 'ml.model_failed' and occurred_at > now() - interval '24 hours'

-- check: B2B-12
-- app: b2b
-- kind: sql
-- severity: P2
-- cadence_s: 900
-- title: B2B admin messages or conversion events are failing
-- description: b2b.admin_messages not sent after admin_message_attempts attempts (last 7 days), or b2b.conversion_events failed or dead in the last 24 h while that platform's CAPI live switch (capi_meta, capi_google) is on.
with v as (
  select (select count(*) from b2b.admin_messages where status <> 'sent' and status <> 'skipped' and attempts >= one.threshold('admin_message_attempts')
            and created_at > now() - interval '7 days') as admin_messages_failing,
         (select count(*) from b2b.conversion_events c
           where c.status in ('failed', 'dead') and not coalesce(c.is_test, false) and c.created_at > now() - interval '24 hours'
             and exists (select 1 from b2b.live_switches s where s.scope = 'capi_' || c.platform and s.live)) as capi_failing)
select admin_messages_failing + capi_failing = 0 as ok, to_jsonb(v) as value from v

-- check: B2B-13
-- app: b2b
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: A B2B AI recommendation was applied without a decision, or its follow-up check is overdue
-- description: b2b.ai_recommendations applied with decided_by null, or check_due_at passed with check_result still null.
select count(*) = 0 as ok,
       jsonb_build_object('undecided_applied', count(*) filter (where status = 'applied' and decided_by is null),
                          'check_overdue', count(*) filter (where check_due_at < now() and check_result is null),
                          'ids', coalesce(to_jsonb((array_agg(id order by id) filter (where id is not null))[1:20]), '[]')) as value
  from b2b.ai_recommendations
 where (status = 'applied' and decided_by is null) or (check_due_at < now() and check_result is null and status = 'applied')

-- check: B2B-14
-- app: b2b
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: A partner programme source failed or is overdue
-- description: b2b.partner_programme_sources with last_error set, or last_checked_at older than twice sync_every_hours.
select count(*) = 0 as ok,
       jsonb_build_object('sources', coalesce(jsonb_agg(jsonb_build_object('partner_id', partner_id, 'type', type, 'error', left(last_error, 200), 'last_checked_at', last_checked_at)) filter (where partner_id is not null), '[]')) as value
  from b2b.partner_programme_sources
 where last_error is not null
    or coalesce(last_checked_at, '-infinity'::timestamptz) < now() - make_interval(hours => 2 * coalesce(sync_every_hours, 24))
