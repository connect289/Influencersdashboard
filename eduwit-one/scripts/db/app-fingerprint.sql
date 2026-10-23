-- The catalogue outside schema one, as one md5, stored in the transaction setting one.fp_<phase>. Included by
-- fp-before.sql and fp-after.sql, which every apply in local-test.sh, rehearse.sh and apply.sh wraps around each
-- migration file, in the same transaction: a migration that changes any of these is rolled back whole (M8 of the second
-- review). Eduwit One's own grants to its two roles, its role memberships and its one-* cron jobs are left out, since
-- 0001 and 0005 add exactly those. A null ACL is read as its default, since the first grant on an object writes the
-- owner's default entry out next to the new one. Read-only.
select pg_catalog.set_config('one.fp_' || :'fp_phase', md5(concat_ws('|',
  -- relations: kind, RLS switches, ACL
  (select md5(string_agg(c.oid::regclass::text || ':' || c.relkind::text || ':' || c.relrowsecurity || ':' || c.relforcerowsecurity || ':'
                         || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(coalesce(c.relacl, acldefault(case when c.relkind = 'S' then 's' else 'r' end::"char", c.relowner))) a where a::text !~ '^"?eduwit_one_'), ''),
                         ';' order by c.oid::regclass::text))
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname <> 'one' and n.nspname !~ '^(pg_catalog|information_schema|pg_toast|pg_temp)' and c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')),
  -- columns
  (select md5(string_agg(a.attrelid::regclass::text || '.' || a.attname || ':' || a.atttypid::regtype::text || ':' || a.attnotnull || ':' || a.attisdropped,
                         ';' order by a.attrelid::regclass::text, a.attnum))
     from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
    where n.nspname <> 'one' and n.nspname !~ '^(pg_catalog|information_schema|pg_toast|pg_temp)' and c.relkind in ('r', 'p', 'v', 'm', 'f') and a.attnum > 0),
  -- policies
  (select md5(string_agg(p.polrelid::regclass::text || ':' || p.polname || ':' || p.polcmd::text || ':' || p.polpermissive || ':' || p.polroles::text || ':'
                         || coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ':' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''),
                         ';' order by p.polrelid::regclass::text, p.polname))
     from pg_policy p join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname <> 'one'),
  -- triggers
  (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgfoid::regprocedure::text || ':' || t.tgenabled::text,
                         ';' order by t.tgrelid::regclass::text, t.tgname))
     from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where not t.tgisinternal and n.nspname <> 'one'),
  -- functions: body, rights, settings, ACL
  (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(coalesce(p.prosrc, '')) || ':' || p.prosecdef || ':' || coalesce(p.proconfig::text, '') || ':'
                         || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(coalesce(p.proacl, acldefault('f', p.proowner))) a where a::text !~ '^"?eduwit_one_'), ''),
                         ';' order by p.oid::regprocedure::text))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname <> 'one' and n.nspname !~ '^(pg_catalog|information_schema|pg_toast|pg_temp)'),
  -- schemas and default privileges
  (select md5(string_agg(n.nspname || ':' || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(coalesce(n.nspacl, acldefault('n', n.nspowner))) a where a::text !~ '^"?eduwit_one_'), ''),
                         ';' order by n.nspname))
     from pg_namespace n where n.nspname <> 'one' and n.nspname !~ '^(pg_toast|pg_temp)'),
  (select md5(string_agg(d.defaclrole::regrole::text || ':' || d.defaclnamespace || ':' || d.defaclobjtype::text || ':'
                         || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(d.defaclacl) a where a::text !~ '^"?eduwit_one_'), ''),
                         ';' order by d.defaclrole::regrole::text, d.defaclnamespace, d.defaclobjtype))
     from pg_default_acl d
    -- a row that holds only the reader's default SELECT is 0001's own
    where exists (select 1 from unnest(d.defaclacl) a where a::text !~ '^"?eduwit_one_')),
  -- roles, memberships, extensions, publications, event triggers
  (select md5(string_agg(r.rolname || ':' || r.rolsuper || r.rolbypassrls || r.rolcreaterole || r.rolcreatedb || r.rolcanlogin || r.rolreplication, ';' order by r.rolname))
     from pg_roles r where r.rolname !~ '^eduwit_one_'),
  (select md5(string_agg(m.roleid::regrole::text || '>' || m.member::regrole::text, ';' order by 1))
     from pg_auth_members m where m.roleid::regrole::text !~ '^"?eduwit_one_' and m.member::regrole::text !~ '^"?eduwit_one_'),
  (select md5(string_agg(e.extname || ':' || e.extversion, ';' order by e.extname)) from pg_extension e),
  (select md5(string_agg(p.pubname || ':' || p.puballtables || ':' || coalesce((select string_agg(r.prrelid::regclass::text, ',' order by 1) from pg_publication_rel r where r.prpubid = p.oid), ''),
                         ';' order by p.pubname)) from pg_publication p),
  (select md5(string_agg(e.evtname || ':' || e.evtenabled::text, ';' order by e.evtname)) from pg_event_trigger e),
  -- the apps' cron jobs
  (select md5(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active, ';' order by j.jobname))
     from cron.job j where j.jobname !~ '^one-')
)), true) is not null as fingerprinted \gset fp_
