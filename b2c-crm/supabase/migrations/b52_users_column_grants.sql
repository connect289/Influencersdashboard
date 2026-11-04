-- B2C CRM b52 (audit of 30 Oct 2026): staff read b2c.users without push_subscription and the unused invite_token_hash;
-- each person reads their own push subscriptions (endpoints and dates) through b2c.my_push_subscriptions().
-- The grant is per column from here on: a column added to b2c.users later needs its own grant to be readable by the app.
-- Idempotent. Checks: supabase/tests/test_audit_2026_10.sql. Rollback: the block at the end.

revoke select on b2c.users from authenticated;   -- also clears earlier column grants, so the grant below is the whole set
grant select (user_id, email, full_name, role, is_active, phone, team, languages, skills, weight, monthly_cap, open_cap, daily_cap, monthly_target,
              takes_leads, is_test_user, on_call, away_until, tz, workspace_user_id, job_title, photo_url, synced_at, invited_at, deactivated_at,
              created_at, updated_at, actor_id, leaderboard_visible, calendar_sync, calendar_error, calendar_synced_at, caller_id, wa_alerts,
              invite_expires_at, first_sign_in_at)
  on b2c.users to authenticated;

/* This person's browser push subscriptions: where alerts go and since when (the keys stay in the database). */
create or replace function b2c.my_push_subscriptions() returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce((select jsonb_agg(jsonb_build_object('endpoint', x ->> 'endpoint', 'at', x -> 'at') order by n)
                     from b2c.users u, jsonb_array_elements(case when jsonb_typeof(u.push_subscription) = 'array' then u.push_subscription else '[]'::jsonb end)
                          with ordinality e(x, n)
                    where u.user_id = b2c.uid() and (select b2c.is_staff())), '[]'::jsonb)
$f$;
revoke execute on function b2c.my_push_subscriptions() from public, anon;
grant execute on function b2c.my_push_subscriptions() to authenticated, service_role;

-- rollback:
-- drop function if exists b2c.my_push_subscriptions();
-- revoke select on b2c.users from authenticated;
-- grant select on b2c.users to authenticated;
