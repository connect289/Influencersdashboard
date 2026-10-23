-- Rollback of 0016: the seams. Runs and their artefacts stay.

delete from one.api_grants where why like 'test runner (0016):%';
drop function if exists one.test_act(bigint, text, jsonb);
drop function if exists one.test_fact(bigint, text, jsonb);
drop function if exists one.test_run_allows(bigint, text);
drop function if exists one.test_kinds(text);
call one.apply_grants();
