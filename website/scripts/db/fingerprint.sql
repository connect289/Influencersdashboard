-- Schema fingerprint of the shared Supabase database, per schema (public, b2b, b2c, catalog) and kind of object.
-- Read-only (catalog SELECTs only): safe on production. Run the same file on production and on the replica and compare.
--   psql "postgresql://postgres:postgres@localhost:54330/postgres" -X -A -F ' ' -f website/scripts/db/fingerprint.sql
-- Rows: schema | kind | n (object count) | md5 of the sorted "key value" lines of that kind.
--   tables       table/partitioned/foreign table name + every column: name, type, not null, default, generated (by name)
--   colorder     table name + its columns in attnum order (catches a column order that differs)
--   functions    name(identity args) + result, language, kind, security definer, volatility, proconfig, md5(prosrc)
--   views        view / materialized view name + pg_get_viewdef
--   policies     table.policy + permissive, roles, command, using, with check
--   triggers     table.trigger + pg_get_triggerdef + enabled state (O/D/R/A)
--   indexes      index name + pg_get_indexdef
--   constraints  table.constraint + pg_get_constraintdef
--   types        enums (labels in order), domains (base type, constraints), standalone composite types
--   sequences    name + type, increment, min, max, cycle
--   acl          grants on every relation and function (aclitems sorted); null = owner-only defaults
--   rls          tables with row level security enabled / forced
-- Objects owned by an extension (vector, pg_trgm in public) are excluded. Ordering uses collate "C" so the hash does
-- not depend on the database's collation. For a drill-down replace the final SELECT with
--   select kind, key, md5(val) from items where nspname = 'b2c' and kind = 'functions' order by key collate "C";
with sch as (
  select oid, nspname from pg_namespace where nspname in ('public', 'b2b', 'b2c', 'catalog')
), ext as (
  select objid from pg_depend where deptype = 'e'
), rel as (
  select c.*, s.nspname from pg_class c join sch s on s.oid = c.relnamespace where c.oid not in (select objid from ext)
), fn as (
  select p.*, s.nspname, p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig
  from pg_proc p join sch s on s.oid = p.pronamespace where p.oid not in (select objid from ext)
), items as (
  select r.nspname, 'tables' as kind, r.relname::text as key,
         r.relkind::text || ': ' || coalesce((
           select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
                    || case when a.attnotnull then ' not null' else '' end
                    || coalesce(' default ' || pg_get_expr(d.adbin, d.adrelid), '')
                    || case when a.attgenerated <> '' then ' generated ' || a.attgenerated::text else '' end
                    || case when a.attidentity <> '' then ' identity ' || a.attidentity::text else '' end,
                  ', ' order by a.attname collate "C")
           from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
           where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped), '') as val
  from rel r where r.relkind in ('r', 'p', 'f')
  union all
  select r.nspname, 'colorder', r.relname::text,
         (select string_agg(a.attname::text, ',' order by a.attnum) from pg_attribute a
          where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped)
  from rel r where r.relkind in ('r', 'p', 'f')
  union all
  select f.nspname, 'functions', f.sig,
         pg_get_function_result(f.oid) || ' ' || l.lanname || ' ' || f.prokind::text
         || case when f.prosecdef then ' definer' else ' invoker' end || ' ' || f.provolatile::text
         || ' [' || coalesce(array_to_string(f.proconfig, ','), '') || '] ' || md5(f.prosrc)
  from fn f join pg_language l on l.oid = f.prolang
  union all
  select r.nspname, 'views', r.relname::text, r.relkind::text || ': ' || pg_get_viewdef(r.oid)
  from rel r where r.relkind in ('v', 'm')
  union all
  select r.nspname, 'policies', r.relname || '.' || po.polname,
         case when po.polpermissive then 'permissive' else 'restrictive' end || ' ' || po.polcmd::text || ' to '
         || coalesce((select string_agg(case when x = 0 then 'public' else pg_get_userbyid(x) end, ',' order by 1)
                      from unnest(po.polroles) x), '')
         || ' using ' || coalesce(pg_get_expr(po.polqual, po.polrelid), '-')
         || ' check ' || coalesce(pg_get_expr(po.polwithcheck, po.polrelid), '-')
  from pg_policy po join rel r on r.oid = po.polrelid
  union all
  select r.nspname, 'triggers', r.relname || '.' || t.tgname, pg_get_triggerdef(t.oid) || ' [' || t.tgenabled::text || ']'
  from pg_trigger t join rel r on r.oid = t.tgrelid where not t.tgisinternal
  union all
  select r.nspname, 'indexes', i.relname::text, pg_get_indexdef(i.oid)
  from pg_index x join rel r on r.oid = x.indrelid join pg_class i on i.oid = x.indexrelid
  union all
  select r.nspname, 'constraints', r.relname || '.' || co.conname, pg_get_constraintdef(co.oid)
  from pg_constraint co join rel r on r.oid = co.conrelid
  union all
  select s.nspname, 'types', t.typname::text,
         t.typtype::text || ': ' || case t.typtype
           when 'e' then (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e where e.enumtypid = t.oid)
           when 'd' then format_type(t.typbasetype, t.typtypmod) || case when t.typnotnull then ' not null' else '' end
                         || coalesce(' default ' || t.typdefault, '')
                         || coalesce((select ' ' || string_agg(pg_get_constraintdef(c.oid), ' ' order by c.conname collate "C")
                                      from pg_constraint c where c.contypid = t.oid), '')
           else (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attnum)
                 from pg_attribute a where a.attrelid = t.typrelid and a.attnum > 0 and not a.attisdropped) end
  from pg_type t join sch s on s.oid = t.typnamespace
  where t.oid not in (select objid from ext)
    and (t.typtype in ('e', 'd') or (t.typtype = 'c' and (select relkind from pg_class where oid = t.typrelid) = 'c'))
  union all
  select r.nspname, 'sequences', r.relname::text,
         format_type(q.seqtypid, null) || ' +' || q.seqincrement || ' ' || q.seqmin || '..' || q.seqmax
         || case when q.seqcycle then ' cycle' else '' end
  from pg_sequence q join rel r on r.oid = q.seqrelid
  union all
  select r.nspname, 'acl', r.relkind::text || ' ' || r.relname,
         coalesce((select string_agg(a::text, ' ' order by a::text collate "C") from unnest(r.relacl) a), 'null')
  from rel r where r.relkind in ('r', 'p', 'f', 'v', 'm', 'S')
  union all
  select f.nspname, 'acl', 'f ' || f.sig,
         coalesce((select string_agg(a::text, ' ' order by a::text collate "C") from unnest(f.proacl) a), 'null')
  from fn f
  union all
  select r.nspname, 'rls', r.relname::text,
         case when r.relrowsecurity then 'on' else 'off' end || case when r.relforcerowsecurity then ' forced' else '' end
  from rel r where r.relkind in ('r', 'p')
)
select nspname as schema, kind, count(*) as n, md5(string_agg(key || ' ' || coalesce(val, '<null>'), E'\n' order by key collate "C")) as md5
from items group by nspname, kind order by nspname collate "C", kind collate "C";
