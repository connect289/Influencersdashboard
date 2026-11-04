-- Rollback of 0011: the page writes. Their audit rows stay in one.audit; secrets saved in Vault stay there (they are
-- the owner's, and the Vault is not Eduwit One's to empty).

delete from one.api_grants where why = 'page write (0011)' or fn in ('one.app_secrets()', 'one.setup_validated(text,boolean,text,text,text)');
drop function if exists one.ui_view_save(text, text, jsonb, text, text);
drop function if exists one.ui_brief_regenerate(date, text, text);
drop function if exists one.ui_ask_pin(bigint, text);
drop function if exists one.ui_ask(text, text);
drop function if exists one.app_secrets();
drop function if exists one.ui_secret_put(text, text, text);
drop function if exists one.setup_validated(text, boolean, text, text, text);
drop function if exists one.ui_devices_revoke(uuid, text);
drop function if exists one.ui_user_put(text, text, boolean, text);
drop function if exists one.ui_baseline_accept(text, text);
drop function if exists one.ui_privilege_ack(text, text);
drop function if exists one.ui_test_run(text, text);
drop function if exists one.ui_test_update(text, jsonb, text, text);
drop function if exists one.ui_check_update(text, jsonb, text, text);
drop function if exists one.ui_settings_put(text, jsonb, text, text);
drop function if exists one.ui_proposal_decide(bigint, text, text, jsonb, integer, text);
drop function if exists one.ui_proposal_create(text, text, text, text, jsonb, text, bigint, text);
drop function if exists one.ui_rerun_deep(bigint, text);
drop function if exists one.ui_unmute(bigint, text);
drop function if exists one.ui_mute(text, text, integer, text, text);
drop function if exists one.ui_resolve(bigint, text, text, text);
drop function if exists one.ui_ack(bigint, text);
drop function if exists one.ui_reason(text);
drop function if exists one.ui_audit_write(text, text, text, jsonb, jsonb, text);
