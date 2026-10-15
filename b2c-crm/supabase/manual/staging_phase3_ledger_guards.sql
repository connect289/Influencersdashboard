-- Run once after b19 and b20 (safe to run again): no row of either money ledger can ever be removed. Corrections are
-- reversing lines (b19, b20); b2c.ledger_guard() refuses the change. Kept apart because the apply path was expected to
-- refuse the delete-trigger statement; in the end the connector accepted it on both staging and production (15 Oct 2026),
-- so both databases carry the two triggers.
create or replace trigger earnings_no_remove before delete on b2c.earnings for each row execute function b2c.ledger_guard('');
create or replace trigger commission_lines_no_remove before delete on b2c.commission_lines for each row execute function b2c.ledger_guard('');
