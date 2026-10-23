-- Demo state for the phase 4 click-through (e2e/run.sh), on the local test cluster only: two staff with signed-in,
-- checked sessions, a few ticks' worth of results and incidents, a brief, a test, events for the funnel, and two app
-- functions as the apps write them (one answers with a name and a phone, which must not reach the page).
\set ON_ERROR_STOP 1
do $$ begin
  if current_database() <> 'rehearsal' or to_regclass('public.stub_health') is null then
    raise exception 'refused: the click-through fixture runs only on the local test cluster';
  end if;
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in'),
  ('00000000-0000-0000-0000-000000000004', 'new@eduwit.in')
on conflict do nothing;
insert into auth.sessions (id, user_id) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000002');
insert into one.users (user_id, email, role) values
  ('00000000-0000-0000-0000-000000000001', 'connect@eduwit.in', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'eng@eduwit.in', 'engineer')
on conflict (user_id) do nothing;
insert into one.session_checks (session_id, user_id, method) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000001', 'email_code'),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000002', 'email_code');

create function b2b.command_center() returns jsonb language sql security definer set search_path = '' as $$
  select '{"today": {"leads": 3, "allocated": 2}, "latest": [{"student_name": "Asha Kumar", "phone": "+91 98111 22334", "note": "call on 9811122334"}]}'::jsonb
$$;
create function b2b.ai_overview() returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'not allowed' using errcode = '42501';
end $$;
grant execute on function b2b.command_center(), b2b.ai_overview() to authenticated;

insert into one.events (app, source_table, source_id, occurred_at, type, lead_id) values
  ('witty', 'e2e', 'e1', now() - interval '5 hours', 'turn', 601),
  ('witty', 'e2e', 'e2', now() - interval '5 hours', 'turn', 602),
  ('witty', 'e2e', 'e3', now() - interval '4 hours', 'turn', 603),
  ('integrity', 'e2e', 'e4', now() - interval '4 hours', 'touch.lead.qualified', 601),
  ('integrity', 'e2e', 'e5', now() - interval '3 hours', 'touch.lead.qualified', 602),
  ('b2b', 'e2e', 'e6', now() - interval '2 hours', 'allocation.allocated', 601);

insert into one.tests (id, app, title, schedule, severity, enabled, disabled_reason)
values ('T-E2E', 'one', 'Click-through stand-in test', '0 * * * *', 'P3', false, 'phase 5');

insert into one.briefs (for_date, tier, body_md, stats)
values (current_date, 'regular', e'# Morning brief\n\n- **2 P1** open: PLAT-05 and HB-website.\n- Spend under cap.\n\n| App | Open |\n| --- | --- |\n| b2c | 1 |',
        '{"open": 2}');

-- A P1 and a P2 the way checks open them, then two real ticks (checks against the stubs, the event copy).
select one.open_or_touch_incident('PLAT-05', 'P1', '{"value": {"spark_base_url": false}}');
select one.open_or_touch_incident('B2C-10', 'P2', '{"value": {"job": "b2c-capacity", "failures_24h": 1}}');
call one.tick_job();
call one.tick_job();
