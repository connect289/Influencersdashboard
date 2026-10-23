-- What a full rollback must leave behind: nothing. Counts schema one, the eduwit_one roles, default privileges that
-- name them, and Eduwit One's cron jobs. Read-only.
select (select count(*) from pg_namespace where nspname = 'one')
     + (select count(*) from pg_roles where rolname like 'eduwit\_one\_%')
     + (select count(*) from pg_default_acl where defaclacl::text like '%eduwit_one_%')
     + (select count(*) from cron.job where jobname in ('one-tick', 'one-nightly'));
