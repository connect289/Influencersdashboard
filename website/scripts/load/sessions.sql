-- Load tests only: N verified test students with a live session each, for the Witty load test (LOCAL database).
-- Prints one session id per line. Emails use the reserved example.test domain; `npm run db:reset` removes everything.
\set ON_ERROR_STOP on
\pset tuples_only on
\o /dev/null
\pset format unaligned
\o
with s as (
  insert into public.web_students (email_norm, phone_e164, full_name, email_verified_at)
  select 'load-' || g || '-' || extract(epoch from now())::bigint || '@example.test', '+9199999' || lpad((g + (extract(epoch from now())::bigint % 90000))::text, 5, '0'),
         'Load Tester ' || g, now()
  from generate_series(1, :n) g
  returning id
)
insert into public.web_student_sessions (student_id, expires_at) select id, now() + interval '1 day' from s returning id;
