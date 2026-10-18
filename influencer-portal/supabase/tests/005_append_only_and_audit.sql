-- Append-only tables refuse updates and deletes even for the table owner; the audit trigger records diffs.
begin;
\ir _helpers.psql
select plan(11);

select tests.make_staff('admin', array['super_admin']);
select inf.audit('test', '1', 'create', null, '{"a":1}');
select throws_ok($$ update inf.audit_log set action = 'x' $$, '42501', null, 'audit_log: update refused');
select throws_ok($$ delete from inf.audit_log $$, '42501', null, 'audit_log: delete refused');
select throws_ok($$ truncate inf.audit_log $$, '42501', null, 'audit_log: truncate refused');

insert into inf.domain_events (type, subject_type, subject_id, idem_key) values ('test.event', 't', '1', 'k1');
select throws_ok($$ delete from inf.domain_events $$, '42501', null, 'domain_events: delete refused');
select is(inf.emit_event('test.event', 't', '1', '{}', 'k1'), (select id from inf.domain_events where idem_key = 'k1'), 'emit_event is idempotent on its key');

insert into inf.sign_in_log (email, portal, method, outcome) values ('a@b.test', 'staff', 'password', 'failed');
select throws_ok($$ update inf.sign_in_log set outcome = 'ok' $$, '42501', null, 'sign_in_log: update refused');

insert into inf.terms_versions (kind, version, title, body) values ('platform_terms', 1, 'Terms', repeat('x', 30));
select throws_ok($$ update inf.terms_versions set body = 'changed' $$, '42501', null, 'terms_versions: published terms are immutable');

-- Audit trigger: only changed keys, redaction-free table, actor captured.
select tests.as_person('admin');
select tests.reset();
insert into inf.creators (display_name, handle) values ('Audit Me', 'audit_me');
select is((select action from inf.audit_log where entity_type = 'creator' order by id desc limit 1), 'insert', 'insert audited');
update inf.creators set city = 'Pune' where handle = 'audit_me';
select is((select after from inf.audit_log where entity_type = 'creator' order by id desc limit 1), '{"city": "Pune"}'::jsonb, 'update stores only the changed keys');
update inf.creators set updated_at = now() where handle = 'audit_me';
select is((select count(*)::int from inf.audit_log where entity_type = 'creator'), 2, 'an update that only touches updated_at is not logged');

-- Lockout after ten failures in fifteen minutes.
insert into inf.sign_in_log (email, portal, method, outcome) select 'locked@b.test', 'staff', 'password', 'failed' from generate_series(1, 10);
select is(inf.sign_in_locked('LOCKED@b.test'), true, 'ten failed sign-ins lock the email');

select * from finish();
rollback;
