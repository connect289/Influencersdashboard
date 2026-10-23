-- Rollback of 0015: the catalogue's tests and their checks, where nothing refers to them yet. A test that ran keeps
-- its row, its check and its runs (history is kept, spec §13); remove those by hand only after reading them.

delete from one.check_state s using one.checks c
 where s.check_id = c.id and c.kind = 'test' and c.id like 'T-%'
   and not exists (select 1 from one.test_runs r where r.test_id = c.id)
   and not exists (select 1 from one.incidents i where i.check_id = c.id);
delete from one.results r using one.checks c
 where r.check_id = c.id and c.kind = 'test' and c.id like 'T-%'
   and not exists (select 1 from one.test_runs tr where tr.test_id = c.id)
   and not exists (select 1 from one.incidents i where i.check_id = c.id);
delete from one.tests t where not exists (select 1 from one.test_runs r where r.test_id = t.id);
delete from one.checks c
 where c.kind = 'test' and c.id like 'T-%' and not exists (select 1 from one.tests t where t.id = c.id)
   and not exists (select 1 from one.incidents i where i.check_id = c.id);
