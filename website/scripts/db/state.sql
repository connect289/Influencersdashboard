-- State of the shared database for rollback checks: the schema fingerprint rows (fingerprint.sql) plus hashes of the
-- shared data the proposals touch and the installed extensions. Read-only.
\i scripts/db/fingerprint.sql
select 'data', 'w2_prompts', count(*), md5(coalesce(string_agg(name || ':' || version || ':' || md5(body), ',' order by name), '')) from public.w2_prompts
union all select 'data', 'consent_texts', count(*), md5(coalesce(string_agg(version || ':' || active || ':' || md5(body), ',' order by version), '')) from b2b.consent_texts
union all select 'data', 'b2b_engine', count(*), md5(coalesce(string_agg(value::text, ','), '')) from b2b.settings where key = 'engine'
union all select 'data', 'extensions', count(*), md5(string_agg(extname, ',' order by extname)) from pg_extension
union all select 'data', 'cron_jobs', count(*), md5(coalesce(string_agg(jobname, ',' order by jobname), '')) from cron.job;
