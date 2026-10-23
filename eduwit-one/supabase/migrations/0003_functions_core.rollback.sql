-- Rollback of 0003 (core). Run after the 0003 (runner) rollback.

drop function if exists one.record_action(text, bigint, text, jsonb, boolean, text, jsonb, text, text);
drop function if exists one.acknowledge_incident(bigint, text);
drop function if exists one.resolve_incident(bigint, text, text, text);
drop function if exists one.open_or_touch_incident(text, one.severity, jsonb, text[]);
drop function if exists one.route_incident(bigint);
drop function if exists one.enqueue_ai(text, jsonb, text, text, bigint);
drop function if exists one.enqueue_alert(bigint, integer);
drop function if exists one.is_muted(text, text);
drop function if exists one.job_call(text, integer);
drop function if exists one.heartbeat(text, boolean, jsonb, text, integer);
drop function if exists one.vault_names();
drop function if exists one.secret(text);
drop function if exists one.settings_put(text, jsonb, text, text);
drop function if exists one.threshold(text);
drop function if exists one.setting(text);
