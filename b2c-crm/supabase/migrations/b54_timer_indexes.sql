-- B2C CRM b54 (11 Nov 2026): indexes for the every-minute timers and the navigation counts. No function changes.
--
-- Each of these statements read its whole table every minute (or on every page, for the navigation counts) because no
-- index matched it. Each index below was checked on a local database with 60,000 to 100,000 rows in the table: the
-- planner uses it for the statement as written in the function named, and for a partial index the predicate is the
-- statement's own text (a partial index is ignored unless the query implies its predicate).
--
--   outbox_sending           b2c.outbox_unstick (minute timer):   status = 'sending' and sent_at < now() - 10 minutes
--                            (outbox_due is partial on status = 'queued', so it could not serve this)
--   tasks_open_due           b2c.reminder_tick (minute timer), its three task loops, and b2c.brief_due_take (the
--                            every-minute sync route):   status = 'open' and a bound on due_at
--                            (tasks_owner_due and tasks_lead start with other columns)
--   leads_state_sla_open     b2c.sla_tick (minute timer):   status = 'active' and sla_due_at < now() and sla_met_at is null
--                            and sla_breached_at is null and first_contacted_at is null. It holds only leads whose first
--                            contact is still awaited, so it stays small.
--   calls_recording_stored   b2c.recordings_expired (the every-minute sync route):   recording_status = 'stored' and
--                            recording_stored_at < the retention date (calls_recording_pending covers 'pending' only)
--   commission_lines_lead    b2c.facts_build (the every-minute facts timer) and b2c.leads_wide_v (lead lists): the sum of
--                            a lead's commission lines, where l.lead_id = <lead>, once per lead
--   wa_conversations_unread  b2c.nav_counts (every page): the conversations with unread > 0
--   notifications_unread     b2c.nav_counts (every page) and b2c.notifications_read: user_id = <me> and read_at is null
--                            (notifications_user reads every alert the person ever had)
--
-- Write cost: one more index to maintain on each table. Three of them name columns no index named before, so an update
-- of those columns is no longer a heap-only update: sla_met_at, sla_breached_at and first_contacted_at on leads_state
-- (each set once in a lead's life), unread on wa_conversations (each inbound message, each "read") and read_at on
-- notifications (once per alert).
--
-- The tables are nearly empty today, so a plain "create index" is instant. On a large table it blocks writes while it
-- builds: there, run each statement by hand with "create index concurrently if not exists" (outside a transaction).
-- Idempotent. Rollback:
--   drop index if exists b2c.outbox_sending;
--   drop index if exists b2c.tasks_open_due;
--   drop index if exists b2c.leads_state_sla_open;
--   drop index if exists b2c.calls_recording_stored;
--   drop index if exists b2c.commission_lines_lead;
--   drop index if exists b2c.wa_conversations_unread;
--   drop index if exists b2c.notifications_unread;

create index if not exists outbox_sending on b2c.outbox (sent_at) where status = 'sending';
create index if not exists tasks_open_due on b2c.tasks (due_at) where status = 'open';
create index if not exists leads_state_sla_open on b2c.leads_state (sla_due_at)
  where status = 'active' and sla_met_at is null and sla_breached_at is null and first_contacted_at is null;
create index if not exists calls_recording_stored on b2c.calls (recording_stored_at) where recording_status = 'stored';
create index if not exists commission_lines_lead on b2c.commission_lines (lead_id);
create index if not exists wa_conversations_unread on b2c.wa_conversations (lead_id) where unread > 0;
create index if not exists notifications_unread on b2c.notifications (user_id) where read_at is null;
