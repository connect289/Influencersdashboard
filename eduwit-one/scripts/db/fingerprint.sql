-- Fingerprint of what the migrations created in schema one: function bodies, columns, constraints, checks and seeded
-- settings. Equal fingerprints on the local cluster and on a target prove the target received the files unaltered.
-- Read-only. The rows are sorted with the binary collation "C": a database whose default collation sorts punctuation
-- differently (staging and production use en_US.UTF-8; a local cluster often C) would otherwise fingerprint the same
-- objects differently (found in the rehearsal of 24 Oct).
select
  (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(p.prosrc), ',' order by p.oid::regprocedure::text collate "C"))
     from pg_proc p where p.pronamespace = 'one'::regnamespace) as functions,
  (select md5(string_agg(table_name || '.' || column_name || ':' || data_type || ':' || is_nullable, ',' order by table_name collate "C", ordinal_position))
     from information_schema.columns where table_schema = 'one') as columns,
  (select md5(string_agg(conrelid::regclass::text || ':' || conname, ',' order by conrelid::regclass::text collate "C", conname collate "C"))
     from pg_constraint where connamespace = 'one'::regnamespace) as constraints,
  (select md5(string_agg(id || ':' || md5(coalesce(sql, '')) || ':' || severity || ':' || cadence_s, ',' order by id collate "C")) from one.checks) as checks,
  (select md5(string_agg(key || ':' || md5(value::text), ',' order by key collate "C")) from one.settings where actor = 'seed') as settings,
  (select count(*) from pg_proc where pronamespace = 'one'::regnamespace) as function_count,
  (select count(*) from pg_class where relnamespace = 'one'::regnamespace and relkind = 'r') as table_count;
