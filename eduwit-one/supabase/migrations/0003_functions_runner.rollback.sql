-- Rollback of 0003 (runner). Run after the 0004 rollback.

drop function if exists one.inf_health();
drop function if exists one.health();
drop function if exists one.nightly();
drop function if exists one.capture_baselines();
drop function if exists one.purge_test_rows();
drop function if exists one.retention();
drop function if exists one.privilege_audit();
drop function if exists one.tick();
drop function if exists one.run_sql_checks();
drop function if exists one.report_result(text, text, jsonb, text, integer);
drop function if exists one.run_check(text);
drop function if exists one.evaluate(text, text, jsonb, text, integer);
