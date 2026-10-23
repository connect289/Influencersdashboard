-- Phase 4 Apps, Marketing and Analytics reads (migration 0012): every panel answers without raising, as the signed-in
-- person, redacted, with its time; the funnel counts leads per step from one.events. Local test cluster only.
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
create or replace function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then return sqlstate;
end $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.err(text) to authenticated;

delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in');
insert into auth.sessions (id, user_id) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001');
insert into one.users (user_id, email, role) values ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner');
insert into one.session_checks (session_id, user_id, method) values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000001', 'email_code');
-- Two app functions as the apps write them: one returns contact data, one refuses a caller who is not its admin.
create function b2b.command_center() returns jsonb language sql security definer as $$
  select '{"today": {"leads": 3}, "latest": [{"student_name": "Asha Kumar", "phone": "+91 98111 22334", "note": "call on 9811122334"}]}'::jsonb
$$;
create function b2b.ai_overview() returns jsonb language plpgsql security definer as $$
begin
  raise exception 'not allowed' using errcode = '42501';
end $$;
insert into one.events (app, source_table, source_id, occurred_at, type, lead_id) values
  ('witty', 'test', 't1', now() - interval '3 hours', 'turn', 501),
  ('integrity', 'test', 't2', now() - interval '2 hours', 'touch.lead.qualified', 501),
  ('b2b', 'test', 't3', now() - interval '1 hour', 'allocation.allocated', 501),
  ('witty', 'test', 't4', now() - interval '3 hours', 'turn', 502);

set role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000001", "session_id": "00000000-0000-0000-0000-0000000000c1"}', false);

-- 1. Every panel answers: data, or a reason it cannot (missing on this database, needs access), never an exception -------
select pg_temp.ok((select bool_and(r ? 'ok' and r ? 'ms' and (r ->> 'ok')::boolean or r ->> 'kind' in ('missing', 'needs_access', 'busy', 'error'))
                     from unnest(array['witty.health_alerts', 'witty.digest', 'witty.outbox', 'witty.replies', 'witty.learnings', 'witty.prompts', 'witty.n8n',
                                       'b2b.command_center', 'b2b.alert_feed', 'b2b.b2c_link', 'b2b.capi', 'b2b.ai', 'b2b.dashboards', 'b2b.health', 'b2b.partners',
                                       'b2c.timers', 'b2c.queues', 'b2c.connectors', 'b2c.nurture', 'b2c.counsellors',
                                       'web.health', 'web.overview', 'web.quality', 'web.seo', 'web.funnel',
                                       'influencer.health', 'influencer.creators', 'influencer.clicks', 'influencer.outcomes',
                                       'one.health', 'one.runs', 'one.events', 'platform.cron']) p, lateral (select one.ui_embed(p) as r) x),
                  'every panel answers with ok, or a kind of failure');
select pg_temp.ok(pg_temp.err('select one.ui_embed(''nope.nothing'')') = 'P0002', 'an unknown panel is refused');

-- 2. An app's answer is redacted before it leaves the database ---------------------------------------------------------------
select pg_temp.ok((select (r ->> 'ok')::boolean and r::text !~* '(asha|98111|9811122334)' and r #>> '{data,today,leads}' = '3'
                     from (select one.ui_embed('b2b.command_center') as r) x),
                  'names and phones in an app''s answer are removed: ' || (select one.ui_embed('b2b.command_center')::text));
select pg_temp.ok((select r ->> 'kind' = 'needs_access' from (select one.ui_embed('b2b.ai') as r) x), 'an app that refuses the caller says so');
select pg_temp.ok((select (r ->> 'ok')::boolean and jsonb_typeof(r -> 'data') = 'object' from (select one.ui_embed('one.health') as r) x), 'Eduwit One''s own health');

-- 3. Marketing and Analytics -----------------------------------------------------------------------------------------------
select pg_temp.ok((select (m ->> 'days')::int = 30 and m ? 'numbers' from (select one.ui_marketing(30) as m) x), 'Marketing answers, with what each section could read');
select pg_temp.ok((select (a #>> '{funnel,1,leads}')::int >= 2 and (a #>> '{funnel,2,leads}')::int = 1 and (a #>> '{funnel,3,leads}')::int = 1
                          and (a #>> '{funnel,2,median_min_from_previous}')::numeric = 60
                     from (select one.ui_analytics(30) as a) x),
                  'the funnel counts leads per step and the median time between steps: ' || (select one.ui_analytics(30) -> 'funnel')::text);
reset role;
select set_config('request.jwt.claims', '', false);

drop function b2b.command_center();
drop function b2b.ai_overview();
delete from one.events where source_table = 'test';
delete from one.session_checks; delete from one.users; delete from auth.sessions; delete from auth.users;

-- 4. The builder's proposals (0013); earlier files truncate one.proposals, so the seed is applied again here ---------------
delete from one.proposals where source = 'builder';
\ir ../../migrations/0013_seed_builder_proposals.sql
select pg_temp.ok((select count(*) = 12 and bool_and(status = 'open' and expires_at is null and source_key like 'builder:%')
                     from one.proposals where source = 'builder'), 'twelve builder proposals, open, never expiring');
select pg_temp.ok((select bool_and(change ? 'where' and change ? 'owner_action') from one.proposals where source = 'builder'),
                  'each names where the change is made and what the owner does');
select pg_temp.ok((select array_agg(source_key order by source_key) = array['builder:gap-influencer-login-attempts', 'builder:gap-spark-tickets-campaigns',
                                                                           'builder:gap-witty-blocks-security-log']
                     from one.proposals where source = 'builder' and not one.proposal_sensitive(kind, change)),
                  'only the three feature requests are the engineer''s to approve; config and security cleanups are the owner''s');
\ir ../../migrations/0013_seed_builder_proposals.sql
select pg_temp.ok((select count(*) = 12 from one.proposals where source = 'builder'), 'running 0013 again inserts nothing');
