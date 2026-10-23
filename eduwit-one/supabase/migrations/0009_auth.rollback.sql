-- Rollback of 0009: the sign-in functions and tables. one.users rows stay (0002's table, dropped by its rollback).

delete from one.api_grants where fn in ('one.me()', 'one.auth_verify_code(text,boolean,text)', 'one.auth_device_check(text)',
  'one.auth_sign_out()', 'one.auth_issue_code(uuid,uuid)', 'one.auth_record(jsonb)');
revoke usage on schema one from authenticated;
drop function if exists one.auth_record(jsonb);
drop function if exists one.auth_sign_out();
drop function if exists one.auth_device_check(text);
drop function if exists one.auth_verify_code(text, boolean, text);
drop function if exists one.auth_issue_code(uuid, uuid);
drop function if exists one.ui_require(text);
drop function if exists one.me();
drop function if exists one.session_checked();
drop function if exists one.session_alive();
drop function if exists one.session_id();
drop function if exists one.uid();
drop table if exists one.sign_in_log, one.trusted_devices, one.session_checks, one.email_codes;
