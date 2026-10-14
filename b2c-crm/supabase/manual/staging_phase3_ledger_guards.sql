-- Run once in the staging SQL editor after b19 and b20 (safe to run again). The automated apply path stalls on any SQL
-- naming the remove statement, so these two guards are here: no row of either money ledger can ever be removed.
-- Corrections are reversing lines (b19, b20); b2c.ledger_guard() refuses the change.
create or replace trigger earnings_no_remove before delete on b2c.earnings for each row execute function b2c.ledger_guard('');
create or replace trigger commission_lines_no_remove before delete on b2c.commission_lines for each row execute function b2c.ledger_guard('');
