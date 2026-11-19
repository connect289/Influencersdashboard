-- Migration 20261120000100_inf_test_creator (D-200): staff with creator.write mark a creator as a test creator (or
-- back) with a reason that goes to the audit log; nobody else can; a creator with ledger entries cannot become one.
begin;
\ir _helpers.psql
select plan(21);

select tests.make_staff('mona', array['influencer_manager']);
select tests.make_staff('vik', array['viewer']);
select tests.make_staff('una', array['influencer_manager'], false);
select tests.make_creator('riya');
select tests.make_creator('arjun');
select tests.make_creator('paid');

create temporary table ids (label text primary key, id uuid);
grant select on ids to authenticated, service_role;
insert into ids select label, creator_id from tests.people where creator_id is not null;

-- Money was recorded for 'paid'.
select inf.ledger_post(jsonb_build_object('creator_id', (select id from ids where label = 'paid'), 'type', 'tds', 'direction', 'debit',
  'amount_paise', 1000, 'confirmed_paise', 1000, 'paid_paise', 1000, 'source', 'payout', 'event_key', 'testcreator:tds',
  'due_on', (now() at time zone 'Asia/Kolkata')::date));

-- ---------------------------------------------------------------------------------------------------------------
-- Who may call it
-- ---------------------------------------------------------------------------------------------------------------
select ok(has_function_privilege('authenticated', 'inf.creator_set_test(uuid, boolean, text)', 'execute')
          and not has_function_privilege('anon', 'inf.creator_set_test(uuid, boolean, text)', 'execute'),
          'signed-in users may call it, signed-out visitors may not');
select ok((select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p
            where p.oid = 'inf.creator_set_test(uuid, boolean, text)'::regprocedure),
          'it is security definer with an empty search path');

select tests.as_person('vik');
select throws_ok($$ select inf.creator_set_test((select id from ids where label = 'riya'), true, 'for tests') $$, '42501', null,
                 'staff without creator.write cannot mark a test creator');
select tests.as_person('una');
select throws_ok($$ select inf.creator_set_test((select id from ids where label = 'riya'), true, 'for tests') $$, '42501', null,
                 'nor can staff whose session is not verified');
select tests.as_person('riya');
select throws_ok($$ select inf.creator_set_test((select id from ids where label = 'riya'), true, 'for tests') $$, '42501', null,
                 'a creator cannot mark themselves');
select tests.reset();
select is((select count(*)::int from inf.creators where is_test), 0, 'refused calls change nothing');

-- ---------------------------------------------------------------------------------------------------------------
-- Input rules
-- ---------------------------------------------------------------------------------------------------------------
select tests.as_person('mona');
select throws_ok($$ select inf.creator_set_test((select id from ids where label = 'riya'), true, '  ') $$, '22023', 'a reason is required',
                 'a reason is required to mark');
select throws_ok($$ select inf.creator_set_test((select id from ids where label = 'riya'), true, null) $$, '22023', 'a reason is required',
                 'a missing reason is refused');
select throws_ok($$ select inf.creator_set_test((select id from ids where label = 'riya'), null, 'for tests') $$, '22023', null,
                 'the flag cannot be null');
select throws_ok($$ select inf.creator_set_test('00000000-0000-0000-0000-000000000001', true, 'for tests') $$, '22023', 'no such creator',
                 'an unknown creator is refused');
select throws_ok($$ select inf.creator_set_test((select id from ids where label = 'paid'), true, 'for tests') $$, '22023',
                 'a creator with ledger entries cannot be a test creator', 'a creator with ledger entries cannot become a test creator');

-- ---------------------------------------------------------------------------------------------------------------
-- Marking and unmarking
-- ---------------------------------------------------------------------------------------------------------------
select lives_ok($$ select inf.creator_set_test((select id from ids where label = 'riya'), true, 'Eduwit One end-to-end test') $$,
                'an influencer manager marks a test creator');
select tests.reset();
select ok((select is_test from inf.creators where id = (select id from ids where label = 'riya')), 'the creator is now a test creator');
select ok(not (select is_test from inf.creators where id = (select id from ids where label = 'arjun')), 'nobody else changes');
select is((select status from inf.creators where id = (select id from ids where label = 'riya')), 'active', 'the status is left alone');
select is((select count(*)::int from inf.audit_log a where a.entity_type = 'creator' and a.entity_id = (select id from ids where label = 'riya')::text
            and a.action = 'mark_test' and a.after ->> 'reason' = 'Eduwit One end-to-end test'
            and a.actor_id = (select user_id from tests.people where label = 'mona')),
          1, 'the audit log records who marked it and why');

select tests.as_person('mona');
select lives_ok($$ select inf.creator_set_test((select id from ids where label = 'riya'), true, 'again') $$, 'marking twice is harmless');
select tests.reset();
select is((select count(*)::int from inf.audit_log where action = 'mark_test'), 1, 'and logs nothing more');

select tests.as_person('mona');
select lives_ok($$ select inf.creator_set_test((select id from ids where label = 'riya'), false, 'Test finished') $$, 'unmarking works');
select tests.reset();
select ok(not (select is_test from inf.creators where id = (select id from ids where label = 'riya')), 'the creator is a real creator again');
select is((select count(*)::int from inf.audit_log where action = 'unmark_test' and after ->> 'reason' = 'Test finished'), 1,
          'unmarking is in the audit log with its reason');

select * from finish();
rollback;
