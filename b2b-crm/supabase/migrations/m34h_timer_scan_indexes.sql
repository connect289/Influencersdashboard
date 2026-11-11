-- M34h (10 Nov 2026, performance review): indexes for two timers that read whole tables on every run. Indexes only: no
-- function, table, column, policy or grant changes, and no result changes.
--
--   b2b.route_ready_leads (m31d, cron b2b-route-ready-leads, every minute)
--     student_leads_review_flag_idx   its first statement, which runs even while routing is off: passed leads that are now
--                                     JUNK or PROGRAM_MISMATCH, joined to their allocation
--                                       where l.destination_type is not null and l.deleted_at is null
--                                         and upper(coalesce(l.lead_status, '')) in ('JUNK', 'PROGRAM_MISMATCH')
--                                     No index covered lead_status, destination_type or allocation_id, so it read every lead.
--     student_leads_unrouted_idx      its sweep, once routing is live: leads with no destination that changed in 90 days
--                                       where l.updated_at > now() - interval '90 days' and l.destination_type is null
--                                     student_leads_updated_at_idx (m22a) found them by date, then read every routed lead of
--                                     those 90 days from the table only to drop it.
--   b2b.b2c_sync_tick (m23a, cron b2b-b2c-sync-tick, every 5 to 30 seconds)
--     allocations_changed_idx         where greatest(a.created_at, a.updated_at) > v_since   (no index on either column)
--     lead_campaigns_updated_at_idx   where c.updated_at > v_since                           (no index on updated_at)
--
-- Each predicate and expression is the query's own text, so the planner can match it; they must change together with the
-- functions. Checked on a local Postgres 16 with 50,000 leads (a fifth unrouted), 42,842 allocations and 30,000 campaigns,
-- all synthetic: the planner uses all four, and the statements read, in 8 kB pages, before and after:
--   review-flag select 8,559 -> 1,159 (the lead table's share 7,486 -> 350) · unrouted sweep 3,642 -> 1,024
--   allocations changed 809 -> 4 · campaigns changed 286 -> 3 (the whole sync statement 1,103 -> 19)
--
-- public.student_leads is shared with Witty and the other apps. A plain create index holds a lock that blocks writes to
-- the table while it builds (well under a second at this size), so the lock is waited for at most 3 seconds: when the
-- table is busy the file fails without changing anything and can be applied again. Re-appliable (if not exists).
--
-- Rollback (the timers return to the plans above; nothing else depends on these indexes):
--   drop index if exists public.student_leads_review_flag_idx;
--   drop index if exists public.student_leads_unrouted_idx;
--   drop index if exists b2b.allocations_changed_idx;
--   drop index if exists b2b.lead_campaigns_updated_at_idx;

set local lock_timeout = '3s';

create index if not exists student_leads_review_flag_idx on public.student_leads (allocation_id)
  where destination_type is not null and deleted_at is null and upper(coalesce(lead_status, '')) in ('JUNK', 'PROGRAM_MISMATCH');

create index if not exists student_leads_unrouted_idx on public.student_leads (updated_at) where destination_type is null;

create index if not exists allocations_changed_idx on b2b.allocations ((greatest(created_at, updated_at)));

create index if not exists lead_campaigns_updated_at_idx on b2b.lead_campaigns (updated_at);
