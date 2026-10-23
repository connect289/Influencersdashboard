-- Rollback of 0010: the page reads, the pins and the saved views.

delete from one.api_grants where fn like 'one.ui\_%' escape '\' and why = 'page read (0010)';
drop function if exists one.ui_asks(integer);
drop function if exists one.ui_privileges();
drop function if exists one.ui_users();
drop function if exists one.ui_heartbeats();
drop function if exists one.ui_mutes();
drop function if exists one.ui_checks(text);
drop function if exists one.ui_setup();
drop function if exists one.setting_owner_only(text);
drop function if exists one.alert_recipients(jsonb);
drop function if exists one.ui_setting_versions(text, integer);
drop function if exists one.ui_settings();
drop function if exists one.ui_audit(text, text, integer, bigint);
drop function if exists one.ui_brief(bigint);
drop function if exists one.ui_briefs(integer);
drop function if exists one.ui_tests();
drop function if exists one.ui_proposal(bigint);
drop function if exists one.ui_proposals(text, text, integer, bigint);
drop function if exists one.ui_actions(text, text, date, integer, bigint);
drop function if exists one.ui_incident(bigint);
drop function if exists one.ui_incidents(text, text, text, text, integer, bigint);
drop function if exists one.ui_overview();
drop function if exists one.ui_shell();
drop function if exists one.proposal_sensitive(text, jsonb);
drop function if exists one.app_link(text);
drop function if exists one.app_heartbeats();
drop table if exists one.saved_views, one.brief_pins;
