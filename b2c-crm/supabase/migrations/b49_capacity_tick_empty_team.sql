-- B2C CRM b49 (audit of 30 Oct 2026): the daily b2c-capacity job (04:15 UTC) no longer fails when nobody takes leads.
-- Production failed every day with "cannot extract elements from a scalar ... b2c.capacity_tick() line 7 at FOR over
-- SELECT rows": its only person is the Admin, who does not take leads, so jsonb_agg() over no rows is SQL null,
-- jsonb_build_object('rows', null) is {"rows": null}, and coalesce(c -> 'rows', '[]') keeps that JSON null (it is not a
-- SQL null), which jsonb_array_elements() refuses. The list is now '[]' when empty; nothing else changes.
-- Idempotent. Checks: supabase/tests/test_audit_2026_10.sql. Rollback: the block at the end.

/* Daily: the Admin hears when someone passes the alert share of their monthly cap, and when the team reaches the hiring trigger. */
create or replace function b2c.capacity_tick() returns int language plpgsql security definer set search_path = '' as $f$
declare c jsonb; x jsonb; n int := 0; v_month text := to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM');
begin
  select jsonb_build_object('rows', coalesce(jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'cap', u.monthly_cap,
           'assigned', (select count(*) from b2c.assignments g where g.user_id = u.user_id and g.at <@ b2c.ist_month((now() at time zone 'Asia/Kolkata')::date)))), '[]'::jsonb))
    into c from b2c.users u where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head', 'admin') and not u.is_test_user;
  for x in select * from jsonb_array_elements(coalesce(c -> 'rows', '[]')) loop
    if (x ->> 'cap')::numeric > 0 and (x ->> 'assigned')::numeric / (x ->> 'cap')::numeric * 100 >= coalesce((b2c.setting('allocation') ->> 'capacity_alert_pct')::int, 90) then
      perform b2c.notify_admins('capacity', (x ->> 'name') || ' is at ' || round((x ->> 'assigned')::numeric / (x ->> 'cap')::numeric * 100) || '% of their monthly cap',
                                (x ->> 'assigned') || ' of ' || (x ->> 'cap') || ' leads this month', '/w/allocation', null, 'cap:' || (x ->> 'user_id') || ':' || v_month, false);
      n := n + 1;
    end if;
  end loop;
  if (select avg((y ->> 'assigned')::numeric / nullif((y ->> 'cap')::numeric, 0)) from jsonb_array_elements(coalesce(c -> 'rows', '[]')) y) * 100
       >= coalesce((b2c.setting('allocation') ->> 'capacity_alert_pct')::int, 90) then
    perform b2c.notify_admins('capacity', 'The team is near capacity: time to hire', null, '/w/allocation', null, 'hire:' || v_month, true);
    n := n + 1;
  end if;
  return n;
end $f$;

-- rollback (restores the b42 definition, which fails again while nobody takes leads):
-- create or replace function b2c.capacity_tick() returns int language plpgsql security definer set search_path = '' as $f$
-- declare c jsonb; x jsonb; n int := 0; v_month text := to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM');
-- begin
--   select jsonb_build_object('rows', jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'cap', u.monthly_cap,
--            'assigned', (select count(*) from b2c.assignments g where g.user_id = u.user_id and g.at <@ b2c.ist_month((now() at time zone 'Asia/Kolkata')::date)))))
--     into c from b2c.users u where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head', 'admin') and not u.is_test_user;
--   for x in select * from jsonb_array_elements(coalesce(c -> 'rows', '[]')) loop
--     if (x ->> 'cap')::numeric > 0 and (x ->> 'assigned')::numeric / (x ->> 'cap')::numeric * 100 >= coalesce((b2c.setting('allocation') ->> 'capacity_alert_pct')::int, 90) then
--       perform b2c.notify_admins('capacity', (x ->> 'name') || ' is at ' || round((x ->> 'assigned')::numeric / (x ->> 'cap')::numeric * 100) || '% of their monthly cap',
--                                 (x ->> 'assigned') || ' of ' || (x ->> 'cap') || ' leads this month', '/w/allocation', null, 'cap:' || (x ->> 'user_id') || ':' || v_month, false);
--       n := n + 1;
--     end if;
--   end loop;
--   if (select avg((y ->> 'assigned')::numeric / nullif((y ->> 'cap')::numeric, 0)) from jsonb_array_elements(coalesce(c -> 'rows', '[]')) y) * 100
--        >= coalesce((b2c.setting('allocation') ->> 'capacity_alert_pct')::int, 90) then
--     perform b2c.notify_admins('capacity', 'The team is near capacity: time to hire', null, '/w/allocation', null, 'hire:' || v_month, true);
--     n := n + 1;
--   end if;
--   return n;
-- end $f$;
