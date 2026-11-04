-- M34g erasure caller check on STAGING, rolled back (needs m34g): lead_anonymise is the Admin's only, whatever the session's
-- b2b.actor says; the erasure itself (lead_anonymise_core) is not reachable through the API; the nightly retention still
-- erases with no signed-in user. Every row must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
create temp table t (k text primary key, v text);
grant all on r, t to authenticated, anon;
create function pg_temp.v(key text) returns text language sql as $f$ select v from t where k = key $f$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $f$
begin execute p_sql; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end $f$;
insert into auth.users (id, email, aud, role) values
  ('aaaaaaaa-0000-0000-0000-0000000000a7', 'm34g-admin@test.local', 'authenticated', 'authenticated'),
  ('aaaaaaaa-0000-0000-0000-0000000000a8', 'm34g-stranger@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000a7', 'm34g-admin@test.local');
insert into public.student_leads (whatsapp_number, student_name, email_id, interested_course, lead_source)
values ('919876534701', 'M34g One', 'one@example.com', 'MBA', 'website'), ('919876534702', 'M34g Old', 'old@example.com', 'BBA', 'website');
insert into t select 'L', id::text from public.student_leads where whatsapp_number = '919876534701';
insert into t select 'OLD', id::text from public.student_leads where whatsapp_number = '919876534702';

-- a signed-in account that is not on the team, with the engine actor set in its own session: refused
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a8","role":"authenticated","aal":"aal2","email":"m34g-stranger@test.local"}', true);
select set_config('b2b.actor', 'engine', true);
do $x$ declare e text; begin
  e := pg_temp.err(format($q$select b2b.lead_anonymise(%s, 'm34g test')$q$, pg_temp.v('L')));
  insert into r values ('actor_setting_not_trusted', e like '42501%', e);
  perform set_config('b2b.actor', 'system', true);
  e := pg_temp.err(format($q$select b2b.lead_anonymise(%s, 'm34g test', 'retention')$q$, pg_temp.v('L')));
  insert into r values ('system_setting_not_trusted', e like '42501%', e);
  e := pg_temp.err(format($q$select b2b.lead_anonymise_core(%s, 'm34g test')$q$, pg_temp.v('L')));
  insert into r values ('core_not_reachable', e like '42501%', e);
end $x$;
reset role;
select set_config('b2b.actor', '', true);
insert into r select 'lead_untouched', l.anonymised_at is null and l.student_name = 'M34g One', coalesce(l.anonymised_at::text, 'not erased')
  from public.student_leads l where l.id = pg_temp.v('L')::bigint;

-- the Admin still erases
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a7","role":"authenticated","aal":"aal2","email":"m34g-admin@test.local"}', true);
select b2b.lead_anonymise(pg_temp.v('L')::bigint, 'student asked on the phone');
reset role;
insert into r select 'admin_erases', l.anonymised_at is not null and l.student_name = 'Erased', l.student_name
  from public.student_leads l where l.id = pg_temp.v('L')::bigint;

-- the nightly retention erases with no signed-in user, as pg_cron runs it
select set_config('request.jwt.claims', '', true);
alter table public.student_leads disable trigger student_leads_touch_trg;
update public.student_leads set created_at = now() - interval '14 months', updated_at = now() - interval '13 months', last_activity_at = now() - interval '13 months',
       last_contacted_at = null where id = pg_temp.v('OLD')::bigint;
alter table public.student_leads enable trigger student_leads_touch_trg;
update b2b.settings set value = value || '{"inactive_months": 12}' where key = 'retention';
insert into t select 'RT', b2b.retention_tick()::text;
insert into r select 'retention_erases', (pg_temp.v('RT')::jsonb ->> 'erased')::int >= 1 and l.anonymised_at is not null, pg_temp.v('RT')
  from public.student_leads l where l.id = pg_temp.v('OLD')::bigint;
insert into r select 'grants', not has_function_privilege('authenticated', 'b2b.lead_anonymise_core(bigint, text, text)', 'execute')
  and not has_function_privilege('anon', 'b2b.lead_anonymise_core(bigint, text, text)', 'execute')
  and has_function_privilege('authenticated', 'b2b.lead_anonymise(bigint, text, text)', 'execute'), null;
select name, ok, detail from r order by ok, name;
rollback;
