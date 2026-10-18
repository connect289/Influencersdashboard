-- Settings: database-side validation, permissions per key, optimistic versioning, history and audit (spec 2.9, 21).
begin;
\ir _helpers.psql
select plan(16);

select tests.make_staff('admin', array['super_admin']);
select tests.make_staff('finance', array['finance']);
select tests.make_staff('manager', array['influencer_manager']);

create temporary table n_defs as select count(*) as n from inf.setting_definitions;
create temporary table defs as select default_value as v from inf.setting_definitions where key = 'attribution.rules';
grant select on n_defs, defs to authenticated;
select tests.as_person('manager');
select ok((select count(*) from inf.settings_list()) = (select n from n_defs), 'manager: reads every setting');
select is((select bool_or(can_edit) from inf.settings_list()), false, 'manager: can edit none');
select throws_ok($$ select inf.setting_set('attribution.rules', '{}'::jsonb, 'x', 0) $$, '42501', null, 'manager: cannot change attribution rules');

select tests.as_person('admin');
select is(inf.setting_set('attribution.rules', '{"window_days": 0}'::jsonb, 'test', 0) ->> 'error', 'invalid', 'invalid value refused by the database');
select ok(jsonb_array_length(inf.setting_set('attribution.rules', '{"window_days": 0}'::jsonb, 'test', 0) -> 'details') > 1, 'every problem is reported');
select is(inf.setting_set('attribution.rules', (select v from defs) || '{"window_days": 60}', '', 0) ->> 'error',
          'reason_required', 'a reason is required');
select is((inf.setting_set('attribution.rules', (select v from defs) || '{"window_days": 60}', 'shorter window', 0) ->> 'version')::int,
          1, 'valid change stored as version 1');
select is(inf.setting_set('attribution.rules', (select v from defs) || '{"window_days": 45}', 'again', 0) ->> 'error',
          'stale', 'a stale expected version is refused');
select is((inf.setting_set('attribution.rules', (select v from defs) || '{"window_days": 45}', 'again', 1) ->> 'version')::int,
          2, 'with the current version it succeeds');
select is((select value ->> 'window_days' from inf.settings_list() where key = 'attribution.rules'), '45', 'effective value is the new one');
select is((select count(*)::int from inf.setting_history('attribution.rules')), 2, 'both versions are in the history');
select is((select count(*)::int from inf.audit_log where entity_type = 'setting' and entity_id = 'attribution.rules'), 2, 'each change is audited');
select is(inf.setting_set('lead_visibility.creator', '{"fields":["whatsapp_number"],"name_format":"full","public_mail_domains":[]}'::jsonb, 'try', 0) ->> 'error',
          'invalid', 'phone can never be added to the creator-visible fields');

select tests.as_person('finance');
select is((inf.setting_set('finance.gst', '{"rate_pct": 18, "require_invoice_for_registered": true, "sac_code": "998361"}'::jsonb, 'confirmed by CA', 0) ->> 'version')::int,
          1, 'finance edits finance settings');
select throws_ok($$ select inf.setting_set('organisation.profile', '{}'::jsonb, 'x', 0) $$, '42501', null, 'finance cannot edit organisation settings');
select lives_ok($$ select inf.setting_confirm('finance.gst', 'CA letter of 20 Oct') $$, 'finance confirms a flagged setting');

select tests.reset();
select * from finish();
rollback;
