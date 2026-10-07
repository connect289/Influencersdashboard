-- PENDING (hand-applied in the Supabase SQL editor): M30b, rebuild three analytics fact views with their fixed definitions.
--   fact_sla       breached also counts checks met late (status met_late), so a breach the partner acts on later stays
--                  in 'SLA breaches' (F9)
--   fact_invoices  drafts are left out; outstanding and ageing count only approved, sent and partly paid invoices (F10)
--   fact_sync      is_test comes from the event's allocation; discarded events are neither unmapped nor dead letters; new
--                  dead_letter column and created_at index (F55)
-- m27a creates these views only if they are missing, so a database that already ran the earlier m27a keeps the old
-- definitions. The definitions below are exactly those of the current m27a_analytics_facts.sql.
-- It is a pending file because it contains DROP, which the Supabase connector holds for manual confirmation.
--   Staging (ran the earlier m27a): apply now, together with the re-applied m27b.
--   Production: not needed, because the fixed m27a is applied in the promotion window; running it there is harmless
--   (if run, right after m30a and before m31a0).
-- One transaction: the minute refresh (cron job b2b-refresh-facts) is paused and the refresh lock is held while the views
-- are rebuilt; the job then gets back the active state it had before (a job paused by the window runbook stays paused).
-- Nothing else depends on these views; the metric layer and reports read them by name.

begin;
select pg_advisory_xact_lock(hashtext('b2b.refresh_facts'));  -- waits for a running refresh; later ticks return busy
create temp table m30b_refresh_job on commit drop as select jobid, active from cron.job where jobname = 'b2b-refresh-facts';
select cron.alter_job(j.jobid, active := false) from m30b_refresh_job j;

drop materialized view if exists b2b.fact_sla;
create materialized view b2b.fact_sla as
select c.id sla_id, c.allocation_id, c.partner_id, c.sla, c.started_at, c.due_at, c.status, c.is_test,
       c.status = 'met' met, c.status in ('breached', 'met_late') breached, c.status in ('met', 'met_late', 'breached') decided,
       round(extract(epoch from coalesce(c.met_at, now()) - c.started_at)::numeric / 3600, 2) hours,
       extract(hour from c.due_at at time zone 'Asia/Kolkata')::int due_hour
  from b2b.sla_checks c where c.status <> 'void';
create unique index fact_sla_pk on b2b.fact_sla (sla_id);
revoke all on b2b.fact_sla from public, anon, authenticated;
grant select on b2b.fact_sla to service_role;

drop materialized view if exists b2b.fact_invoices;
create materialized view b2b.fact_invoices as
select i.id invoice_id, i.partner_id, i.number, i.status, i.issue_date, i.due_date, i.total_inr, coalesce(i.received_inr, 0) received_inr,
       coalesce(i.tds_inr, 0) tds_inr,
       case when i.status in ('approved', 'sent', 'partly_paid') then greatest(i.total_inr - coalesce(i.received_inr, 0) - coalesce(i.tds_inr, 0), 0) else 0 end outstanding_inr,
       case when i.status in ('approved', 'sent', 'partly_paid') and i.due_date is not null then greatest(current_date - i.due_date, 0) end days_overdue,
       case when i.status not in ('approved', 'sent', 'partly_paid') or i.due_date is null then null
            when current_date - i.due_date <= 0 then 'not due' when current_date - i.due_date <= 30 then '1-30'
            when current_date - i.due_date <= 60 then '31-60' when current_date - i.due_date <= 90 then '61-90' else '90+' end ageing,
       coalesce(i.issue_date::timestamptz, i.created_at) created_at, false is_test
  from b2b.invoices i where i.status not in ('draft', 'cancelled');
create unique index fact_invoices_pk on b2b.fact_invoices (invoice_id);
revoke all on b2b.fact_invoices from public, anon, authenticated;
grant select on b2b.fact_invoices to service_role;

drop materialized view if exists b2b.fact_sync;
create materialized view b2b.fact_sync as
select e.id event_id, e.partner_id, e.received_at created_at, e.status,
       e.status = 'error' error,
       e.status = 'held_unmapped' and e.discarded_at is null unmapped,
       e.status in ('error', 'held_unmapped') and e.discarded_at is null dead_letter,
       round(greatest(extract(epoch from e.received_at - b2b.try_timestamptz(e.raw ->> 'occurred_at')), 0)::numeric / 60, 1) lag_minutes,
       coalesce(a.is_test, false) is_test
  from b2b.partner_events e
  left join b2b.allocations a on a.id = e.allocation_id;
create unique index fact_sync_pk on b2b.fact_sync (event_id);
create index fact_sync_created_idx on b2b.fact_sync (created_at);
revoke all on b2b.fact_sync from public, anon, authenticated;
grant select on b2b.fact_sync to service_role;

select cron.alter_job(j.jobid, active := j.active) from m30b_refresh_job j;
select b2b.log_event('migration.manual_applied', null, null, null, '{"file":"pending/m30b_fact_views","fixes":["F9","F10","F55"]}');
commit;
