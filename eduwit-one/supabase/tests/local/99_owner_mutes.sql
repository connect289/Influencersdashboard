-- Muting a top-priority alarm is the owner's (migration 0040, D-139). A mute holds every alert of a check, or of every
-- check of an app, so an engineer is refused on a P1 check and on an app that has one (switched on or off), with a
-- message the app can show; any other check or app is muted by an engineer as before, with its audit row; the owner
-- mutes both; ending a mute stays with engineers. The rollback file brings 0037's function back, and the migration
-- applies again over it. Everything here runs in one transaction that is rolled back. Local test cluster only.
\set ON_ERROR_STOP 1
do $$ begin
  if current_database() <> 'rehearsal' or to_regclass('public.stub_health') is null then
    raise exception 'refused: this test rewrites fixtures and runs only on the local test cluster';
  end if;
end $$;
create or replace function pg_temp.ok(p_cond boolean, p_msg text) returns void language plpgsql as $$
begin
  if not coalesce(p_cond, false) then raise exception 'ASSERT FAILED: %', p_msg; end if;
end $$;
-- 'ok', or the refusal as "SQLSTATE: message".
create or replace function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate || ': ' || sqlerrm;
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text) to authenticated, anon;
create or replace function pg_temp.as_owner() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000c1"}', false)
$$;
create or replace function pg_temp.as_engineer() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000002", "session_id": "00000000-0000-0000-0000-0000000000c2"}', false)
$$;
grant execute on function pg_temp.as_owner(), pg_temp.as_engineer() to authenticated;

begin;
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000002');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer');
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001', 'email_code'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-000000000002', 'email_code');
delete from one.mutes;

-- The fixtures the rule is read from: the seeded severities, and one app whose P1 checks are all switched off.
select pg_temp.ok((select severity = 'P1' and enabled from one.checks where id = 'B2B-03'), 'fixture: B2B-03 is a P1 that is on');
select pg_temp.ok((select severity = 'P3' from one.checks where id = 'WEB-05'), 'fixture: WEB-05 is a P3');
select pg_temp.ok((select severity = 'P2' from one.checks where id = 'WITTY-04'), 'fixture: WITTY-04 is a P2');
select pg_temp.ok(not exists (select 1 from one.checks where app = 'catalogue' and severity = 'P1'), 'fixture: catalogue has no P1 check');
update one.checks set enabled = false, disabled_reason = 'builder:test-0040' where app = 'influencer' and severity = 'P1';
select pg_temp.ok((select count(*) >= 1 and not bool_or(enabled) from one.checks where app = 'influencer' and severity = 'P1'),
                  'fixture: every P1 check of influencer is switched off');
select id as inf_p1 from one.checks where app = 'influencer' and severity = 'P1' order by id limit 1 \gset
select count(*) as audit_before from one.audit where action = 'mute' \gset

-- 1. An engineer is refused on a P1 check and on an app that has one --------------------------------------------------------
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('check', 'B2B-03', 60, 'partner maintenance', 'req-0040a')$q$)
                  = '42501: only the owner can mute a top-priority alarm: check B2B-03 is P1', 'an engineer cannot mute a P1 check');
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('app', 'b2b', 60, 'partner maintenance', 'req-0040b')$q$)
                  = '42501: only the owner can mute a top-priority alarm: app b2b has P1 checks', 'nor an app that has one');
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('check', 'B2B-03', 1, 'one minute only')$q$) like '42501: only the owner can mute%',
                  'not for a minute either');
select pg_temp.ok(pg_temp.err(format('select one.ui_mute(%L, %L, 60, %L)', 'check', :'inf_p1', 'it is off anyway')) like '42501: only the owner can mute%',
                  'a P1 check that is switched off is still the owner''s to mute');
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('app', 'influencer', 60, 'its P1 checks are off')$q$)
                  = '42501: only the owner can mute a top-priority alarm: app influencer has P1 checks',
                  'and so is an app whose P1 checks are all switched off');
-- The refusal comes before the form is read: a bad duration or reason does not change the answer.
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('check', 'B2B-03', 0, '')$q$) like '42501: only the owner can mute%',
                  'the refusal does not depend on the rest of the form');
reset role;
select pg_temp.ok((select count(*) = 0 from one.mutes) and (select count(*) = :audit_before from one.audit where action = 'mute'),
                  'the refused calls wrote no mute and no audit row');

-- 2. Everything else is as it was for an engineer ----------------------------------------------------------------------------
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok((one.ui_mute('check', 'WEB-05', 60, 'search is being rebuilt', 'req-0040c') ->> 'ok')::boolean, 'an engineer mutes a P3 check');
select pg_temp.ok((one.ui_mute('check', 'WITTY-04', 30, 'deploy window', 'req-0040d') ->> 'mute_id') is not null, 'and a P2 check');
select pg_temp.ok((one.ui_mute('app', 'catalogue', 120, 'catalogue import', 'req-0040e') ->> 'ok')::boolean, 'and an app that has no P1 check');
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('check', 'WEB-05', 0, 'too short')$q$) like '22023:%', 'a duration under a minute is refused as before');
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('check', 'WEB-05', 10081, 'too long')$q$) like '22023:%', 'and one over 7 days');
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('check', 'WEB-05', 60, '')$q$) like '22023:%', 'a mute needs a reason');
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('check', 'NO-SUCH', 60, 'unknown')$q$) like '22023:%', 'an unknown check is refused as unknown');
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('app', 'nowhere', 60, 'unknown')$q$) like '22023:%', 'and an unknown app');
reset role;
select pg_temp.ok((select count(*) = 3 from one.mutes where created_by = 'eng@eduwit.in'), 'three mutes under the engineer''s name');
select pg_temp.ok((select ends_at - starts_at = interval '60 minutes' and reason = 'search is being rebuilt' from one.mutes where target = 'WEB-05'),
                  'for the time and with the reason given');
select pg_temp.ok((select count(*) = 1 from one.audit where action = 'mute' and target = 'check:WEB-05' and actor = 'eng@eduwit.in'
                     and request_id = 'req-0040c' and (after ->> 'minutes')::int = 60 and after ->> 'reason' = 'search is being rebuilt'),
                  'the audit row is written once, with the actor from the JWT and the request id');
select pg_temp.ok((select count(*) = :audit_before + 3 from one.audit where action = 'mute'), 'one audit row per mute');
select pg_temp.ok(one.is_muted('WEB-05', 'web') and one.is_muted('CAT-01', 'catalogue') and not one.is_muted('B2B-03', 'b2b'),
                  'the mutes hold what they name and nothing else');

-- 3. The owner mutes a P1 check and an app that has one -----------------------------------------------------------------------
set role authenticated;
select pg_temp.as_owner();
select (one.ui_mute('check', 'B2B-03', 60, 'partner maintenance, agreed with the partner', 'req-0040f') ->> 'mute_id')::bigint as owner_mute \gset
select pg_temp.ok(:owner_mute > 0, 'the owner mutes a P1 check');
select pg_temp.ok((one.ui_mute('app', 'b2b', 45, 'database upgrade tonight', 'req-0040g') ->> 'ok')::boolean, 'and an app that has P1 checks');
select pg_temp.ok((one.ui_mute('app', 'influencer', 45, 'portal release', 'req-0040h') ->> 'ok')::boolean, 'and an app whose P1 checks are off');
select pg_temp.ok((one.ui_mute('check', 'WEB-05', 15, 'same for the owner', 'req-0040i') ->> 'ok')::boolean, 'and any other check, as before');
reset role;
select pg_temp.ok(one.is_muted('B2B-03', 'b2b') and one.is_muted('B2B-01', 'b2b'), 'both hold');
select pg_temp.ok((select count(*) = 4 from one.audit where action = 'mute' and actor = 'connect@eduwit.in'
                     and request_id in ('req-0040f', 'req-0040g', 'req-0040h', 'req-0040i')), 'each in the audit under the owner''s name');

-- 4. Ending a mute stays with engineers; muting the P1 again does not ----------------------------------------------------------
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok((one.ui_unmute(:owner_mute, 'req-0040j') ->> 'ok')::boolean, 'an engineer ends the owner''s mute of a P1 check');
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('check', 'B2B-03', 60, 'again')$q$) like '42501: only the owner can mute%',
                  'and cannot start it again');
reset role;
-- one.unmute ends a mute a second after it started at the earliest, and this whole file is one transaction (one now()).
select pg_temp.ok((select ends_at <= now() + interval '1 second' from one.mutes where id = :owner_mute), 'the mute was ended');

-- 5. The rule reads the check as it is now ----------------------------------------------------------------------------------------
update one.checks set severity = 'P1' where id = 'WITTY-04';
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('check', 'WITTY-04', 30, 'deploy window')$q$)
                  = '42501: only the owner can mute a top-priority alarm: check WITTY-04 is P1', 'a check raised to P1 is the owner''s to mute from then on');
reset role;
update one.checks set severity = 'P2' where id = 'WITTY-04';
update one.checks set severity = 'P2' where id = 'B2B-03';
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok((one.ui_mute('check', 'B2B-03', 30, 'no longer a P1') ->> 'ok')::boolean, 'and one the owner lowered is an engineer''s again');
reset role;
update one.checks set severity = 'P1' where id = 'B2B-03';

-- 6. The door itself: one form, for signed-in people only ---------------------------------------------------------------------------
select pg_temp.ok(has_function_privilege('authenticated', 'one.ui_mute(text,text,integer,text,text)', 'execute')
                  and not has_function_privilege('anon', 'one.ui_mute(text,text,integer,text,text)', 'execute')
                  and (select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'one' and p.proname = 'ui_mute'),
                  'one.ui_mute keeps its one signature, executable by signed-in people and not by anon');
select pg_temp.ok(not has_function_privilege('authenticated', 'one.mute(text,text,integer,text,text,text)', 'execute')
                  and not has_function_privilege('anon', 'one.mute(text,text,integer,text,text,text)', 'execute'),
                  'one.mute itself is not callable through the API: one.ui_mute is the only door');

-- 7. The rollback file brings 0037's function back; the migration applies again over it ------------------------------------------------
delete from one.mutes;
set role postgres;
\ir ../../migrations/0040_owner_mutes_p1.rollback.sql
reset role;
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok((one.ui_mute('check', 'B2B-03', 60, 'after the rollback', 'req-0040k') ->> 'ok')::boolean,
                  'after the rollback an engineer mutes a P1 check again, as before 0040');
select pg_temp.ok((one.ui_mute('app', 'b2b', 60, 'after the rollback', 'req-0040l') ->> 'ok')::boolean, 'and an app that has one');
reset role;
select pg_temp.ok((select count(*) = 2 from one.audit where action = 'mute' and actor = 'eng@eduwit.in' and request_id in ('req-0040k', 'req-0040l')),
                  'with the audit rows 0037 wrote');
set role postgres;
\ir ../../migrations/0040_owner_mutes_p1.sql
reset role;
set role authenticated;
select pg_temp.as_engineer();
select pg_temp.ok(pg_temp.err($q$select one.ui_mute('check', 'B2B-03', 60, 'after the second apply')$q$) like '42501: only the owner can mute%',
                  'applied again, the engineer is refused again');
select pg_temp.ok((one.ui_mute('check', 'WEB-05', 60, 'after the second apply') ->> 'ok')::boolean, 'and still mutes a P3');
reset role;
select pg_temp.ok((select pg_get_userbyid(p.proowner) = 'postgres' and p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'one' and p.proname = 'ui_mute'), 'the function is the database owner''s and security definer, as it was');

rollback;
select 'OWNER MUTES PASSED';
