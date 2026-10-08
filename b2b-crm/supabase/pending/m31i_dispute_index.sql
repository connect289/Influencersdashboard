-- pending/m31i_dispute_index (optional, hand-applied in the Supabase SQL editor after m31i_a3_after_push).
-- Allows one open commission dispute of EACH kind per allocation: the m8a index commission_disputes_one_open (one open dispute
-- per allocation, whatever its kind) is swapped for commission_disputes_one_open_kind on (allocation_id, kind) where status = 'open'.
-- Without this file m31i still works: a second-kind claim on an allocation with an open dispute is appended to that dispute's
-- 'also' column (apply_partner_duplicate, late_activity_dispute catch the unique violation).
-- Re-applying is safe. Not in supabase_migrations: it ends with log_event('migration.manual_applied') and is listed in the README.

drop index if exists b2b.commission_disputes_one_open;
create unique index if not exists commission_disputes_one_open_kind on b2b.commission_disputes (allocation_id, kind) where status = 'open';

select b2b.log_event('migration.manual_applied', null, null, null, jsonb_build_object('file', 'pending/m31i_dispute_index'));
