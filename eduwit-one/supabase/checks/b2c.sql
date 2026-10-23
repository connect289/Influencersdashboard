-- Spark (B2C CRM) checks (spec §6, B2C-*). Sources for scripts/db/gen-checks.ts. The owner chose direct reads over
-- the admin-session b2c.system_health() (23 Oct), so B2C-01 re-states its "bad" conditions on the same tables.
-- Working hours follow b2c.settings.working_defaults (IST start, end and days).

-- check: B2C-01
-- app: b2c
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- tags: cron
-- title: Spark's timers or its answers to them are failing
-- description: Direct read of system_health's "timers" and "app" checks: no b2c-* job at all, a b2c-* job whose latest run failed (startup timeouts excluded, see PLAT-01B; b2c-capacity left to B2C-10), or a Spark job call answered with an error status in the last hour.
with jobs as (
  select j.jobname, (select d.status from cron.job_run_details d where d.jobid = j.jobid and d.return_message is distinct from 'job startup timeout'
                      order by d.start_time desc limit 1) as last_status
    from cron.job j where j.jobname like 'b2c-%' and j.jobname <> 'b2c-capacity' and j.active),
calls as (
  select count(*) as failed from b2c.job_calls c, jsonb_array_elements(c.calls) e join net._http_response r on r.id = (e ->> 'id')::bigint
   where r.created > now() - interval '1 hour' and (r.status_code is null or r.status_code >= 400))
select (select count(*) from jobs) > 0 and not exists (select 1 from jobs where last_status = 'failed') and (select failed from calls) = 0 as ok,
       jsonb_build_object('timers', (select count(*) from jobs),
                          'failed_jobs', (select coalesce(jsonb_agg(jobname order by jobname), '[]') from jobs where last_status = 'failed'),
                          'failed_calls_1h', (select failed from calls)) as value

-- check: B2C-02
-- app: b2c
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- fix: FIX-INBOX-RETRY
-- title: Spark's inbox from the master lead table has errors or is stuck
-- description: b2c.inbox rows in error, or stored and not applied b2c_inbox_min minutes after received_at.
select count(*) = 0 as ok,
       jsonb_build_object('error', count(*) filter (where status = 'error'), 'stuck', count(*) filter (where status = 'stored'), 'oldest_at', min(received_at)) as value
  from b2c.inbox
 where status = 'error' or (status = 'stored' and received_at < now() - make_interval(mins => one.threshold('b2c_inbox_min')::int))

-- check: B2C-03
-- app: b2c
-- kind: sql
-- severity: P2
-- cadence_s: 300
-- fix: FIX-OUTBOX-B2C
-- title: Spark's outbox to the master lead table is not draining
-- description: b2c.outbox rows from the last 7 days not applied after b2c_outbox_urgent_min minutes (urgent) or b2c_outbox_batch_min minutes (batch); failed, refused and conflict count as not applied.
select count(*) = 0 as ok,
       jsonb_build_object('count', count(*), 'by_status', coalesce(jsonb_object_agg(status, n), '{}'), 'urgent', coalesce(sum(n) filter (where urgent), 0)) as value
  from (select status, urgent, count(*) as n from b2c.outbox
         where status <> 'applied' and created_at > now() - interval '7 days'
           and created_at < now() - make_interval(mins => (case when urgent then one.threshold('b2c_outbox_urgent_min') else one.threshold('b2c_outbox_batch_min') end)::int)
         group by status, urgent) o

-- check: B2C-04
-- app: b2c
-- kind: sql
-- severity: P1
-- cadence_s: 60
-- title: A sales-lane lead has no owner
-- description: During Spark's working hours, an active sales-lane b2c.leads_state row (not test, not deleted) without owner_id for more than handoff_min minutes.
with wh as (
  select coalesce(value, '{}') as w, (now() at time zone coalesce(value ->> 'tz', 'Asia/Kolkata')) as local_now from b2c.settings where key = 'working_defaults'),
open_hours as (
  select coalesce(extract(isodow from local_now)::int = any (array(select jsonb_array_elements_text(w -> 'days')::int)), true)
         and local_now::time between coalesce((w ->> 'start')::time, time '09:00') and coalesce((w ->> 'end')::time, time '20:00') as yes
    from wh)
select not coalesce((select yes from open_hours), true) or count(*) = 0 as ok,
       jsonb_build_object('count', count(*), 'in_hours', coalesce((select yes from open_hours), true),
                          'lead_ids', coalesce(to_jsonb((array_agg(lead_id order by lead_id) filter (where lead_id is not null))[1:20]), '[]')) as value
  from b2c.leads_state
 where lane = 'sales' and status = 'active' and owner_id is null and deleted_at is null and not coalesce(is_test, false)
   and coalesce(handed_off_at, created_at) < now() - make_interval(mins => one.threshold('handoff_min')::int)

-- check: B2C-05
-- app: b2c
-- kind: sql
-- severity: P2
-- cadence_s: 900
-- title: A hot or duplicate-cascade lead breached its SLA today
-- description: b2c.leads_state with sla_breached_at today (IST) for a hot lead, or one whose cause or handoff reason is a duplicate cascade.
select count(*) = 0 as ok, jsonb_build_object('count', count(*), 'lead_ids', coalesce(to_jsonb((array_agg(lead_id order by lead_id) filter (where lead_id is not null))[1:20]), '[]')) as value
  from b2c.leads_state
 where not coalesce(is_test, false) and deleted_at is null
   and (sla_breached_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date
   and (coalesce(hot, false) or coalesce(cause, '') ~* 'duplicate' or coalesce(handoff_reason, '') ~* 'duplicate')

-- check: B2C-06
-- app: b2c
-- kind: sql
-- severity: P2
-- cadence_s: 300
-- title: A Spark connector, staff connection, WhatsApp template or send is failing
-- description: b2c.connector_status with last_error_at newer than last_ok_at; b2c.user_connections in error; a non-archived rejected b2c.wa_templates row; more than 5 failed outgoing b2c.wa_messages in the last hour. Template quality from the WhatsApp API needs Setup item whatsapp.
with v as (
  select (select coalesce(jsonb_agg(key order by key), '[]') from b2c.connector_status where last_error_at > coalesce(last_ok_at, '-infinity'::timestamptz)) as connectors_failing,
         (select count(*) from b2c.user_connections where status = 'error') as staff_connections_error,
         (select count(*) from b2c.wa_templates where status = 'rejected' and archived_at is null) as templates_rejected,
         (select count(*) from b2c.wa_messages where direction = 'out' and status = 'failed' and created_at > now() - interval '1 hour') as wa_failed_1h)
select jsonb_array_length(connectors_failing) = 0 and staff_connections_error = 0 and templates_rejected = 0 and wa_failed_1h <= 5 as ok, to_jsonb(v) as value
  from v

-- check: B2C-07
-- app: b2c
-- kind: sql
-- severity: P2
-- cadence_s: 900
-- title: Spark's sending broke a pacing or quiet-hours rule, or its queue is stuck
-- description: b2c.send_queue queued past not_before by more than 15 min; a marketing WhatsApp (campaign or journey) sent today outside 09:00 to 20:00 IST; a lead with more than 1 marketing WhatsApp today or more than 6 in 30 days; a lead with more than 2 emails today.
with mk as (
  select lead_id, created_at from b2c.wa_messages
   where direction = 'out' and status in ('sent', 'delivered', 'read') and (campaign_id is not null or journey_run_id is not null or coalesce(purpose, '') ~* 'market|campaign')
     and created_at > now() - interval '30 days'),
today as (select (now() at time zone 'Asia/Kolkata')::date as d),
v as (
  select (select count(*) from b2c.send_queue where status = 'queued' and not_before < now() - interval '15 minutes') as queue_stuck,
         (select count(*) from mk, today where (created_at at time zone 'Asia/Kolkata')::date = today.d
            and (created_at at time zone 'Asia/Kolkata')::time not between time '09:00' and time '20:00') as marketing_off_hours_today,
         (select count(*) from (select lead_id from mk, today where (created_at at time zone 'Asia/Kolkata')::date = today.d group by lead_id having count(*) > 1) x) as leads_over_1_today,
         (select count(*) from (select lead_id from mk group by lead_id having count(*) > 6) x) as leads_over_6_30d,
         (select count(*) from (select e.lead_id from b2c.emails e, today where e.direction = 'out' and (e.created_at at time zone 'Asia/Kolkata')::date = today.d
                                  group by e.lead_id having count(*) > 2) x) as leads_over_2_emails_today)
select queue_stuck + marketing_off_hours_today + leads_over_1_today + leads_over_6_30d + leads_over_2_emails_today = 0 as ok, to_jsonb(v) as value
  from v

-- check: B2C-08
-- app: b2c
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: Replies or developer tickets are waiting too long in Spark
-- description: b2c.replies waiting in the inbox for more than 1 h (counted in working hours only), or b2c.support_tickets handed to the developer path (open bug or data tickets) with no developer_at after 24 h.
with v as (
  select (select count(*) from b2c.replies where status = 'inbox' and created_at < now() - interval '1 hour'
            and (now() at time zone 'Asia/Kolkata')::time between time '09:00' and time '20:00') as replies_waiting,
         (select count(*) from b2c.support_tickets where kind in ('bug', 'data') and status in ('open', 'in_progress', 'waiting')
            and developer_at is null and created_at < now() - interval '24 hours') as developer_tickets_waiting)
select replies_waiting + developer_tickets_waiting = 0 as ok, to_jsonb(v) as value from v

-- check: B2C-09
-- app: b2c
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: Spark's AI spend today is over its cap
-- description: Sum of b2c.ai_calls.cost_inr today (IST) above b2c.settings.ai.daily_cap_inr.
select coalesce(sum(c.cost_inr), 0) <= coalesce((select (value ->> 'daily_cap_inr')::numeric from b2c.settings where key = 'ai'), 'infinity'::numeric) as ok,
       jsonb_build_object('spent_inr', round(coalesce(sum(c.cost_inr), 0), 2), 'cap_inr', (select value -> 'daily_cap_inr' from b2c.settings where key = 'ai')) as value
  from b2c.ai_calls c where (c.at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date

-- check: B2C-10
-- app: b2c
-- kind: sql
-- severity: P2
-- cadence_s: 86400
-- tags: cron
-- title: Spark's daily capacity job is failing
-- description: The latest b2c-capacity run (daily) ended in failed. It has failed every day since it was scheduled (survey, 23 Oct).
select coalesce(r.status <> 'failed', true) as ok, jsonb_build_object('at', r.start_time, 'status', r.status, 'message', left(r.return_message, 300)) as value
  from (select 1) x
  left join lateral (select d.start_time, d.status, d.return_message from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                      where j.jobname = 'b2c-capacity' order by d.start_time desc limit 1) r on true
