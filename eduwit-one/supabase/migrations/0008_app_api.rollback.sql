-- Rollback of 0008: removes the app's functions. Audit rows they wrote stay in one.audit (0002).

delete from one.api_grants where role = 'service_role' and fn in ('one.app_tick_state()', 'one.app_report(jsonb,text,text)',
  'one.witty_escalations(integer)', 'one.watchdog()', 'one.claim_deliveries(integer)', 'one.finish_delivery(bigint,boolean,text,text)');

drop function if exists one.unmute(bigint, text);
drop function if exists one.mute(text, text, integer, text, text);
drop function if exists one.finish_delivery(bigint, boolean, text, text);
drop function if exists one.claim_deliveries(integer);
drop function if exists one.watchdog();
drop function if exists one.witty_escalations(integer);
drop function if exists one.app_report(jsonb, text, text);
drop function if exists one.app_tick_state();
