-- Rollback of 0008: removes the app's functions. Audit rows they wrote stay in one.audit (0002).

drop function if exists one.watchdog();
drop function if exists one.witty_escalations(integer);
drop function if exists one.app_report(jsonb, text, text);
drop function if exists one.app_tick_state();
