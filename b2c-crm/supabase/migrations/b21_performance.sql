-- B2C CRM b21 (Phase 3): team performance (spec B12). Staging first. Idempotent.
--   targets              per counsellor per month (calls, connected, counselled, applications, enrollments, commission);
--                        the users.monthly_target default applies to months with no row
--   perf_actuals()       the same six numbers, counted from the records
--   my_progress()        target progress for Today
--   leaderboard()        opt-in: counsellors appear by name only if they chose to; Admin and sales head see everyone
--   activity_monitor()   calls, connect rate, messages, first-contact time, SLA breaches, overdue, untouched, unlogged calls
--   capacity()           assigned this month against the cap, and the hiring trigger
-- Coaching notes already exist (b5: notes with internal = true).

alter table b2c.users add column if not exists leaderboard_visible boolean not null default false;
insert into b2c.settings (key, value) values ('performance', '{"leaderboard_for_counsellors": true, "untouched_hours": 48}') on conflict (key) do nothing;

create table if not exists b2c.targets (
  user_id uuid not null references b2c.users (user_id),
  month date not null check (month = date_trunc('month', month)::date),
  calls int check (calls >= 0),
  connected int check (connected >= 0),
  counselled int check (counselled >= 0),
  applications int check (applications >= 0),
  enrollments int check (enrollments >= 0),
  commission numeric(12, 2) check (commission >= 0),
  set_by uuid,
  set_at timestamptz not null default now(),
  primary key (user_id, month)
);

/* The month's bounds in IST. */
create or replace function b2c.ist_month(p_month date) returns tstzrange language sql immutable set search_path = '' as $f$
  select tstzrange((date_trunc('month', p_month)::timestamp at time zone 'Asia/Kolkata'), ((date_trunc('month', p_month) + interval '1 month')::timestamp at time zone 'Asia/Kolkata'))
$f$;

create or replace function b2c.target_for(p_user uuid, p_month date) returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(
    (select jsonb_strip_nulls(jsonb_build_object('calls', t.calls, 'connected', t.connected, 'counselled', t.counselled, 'applications', t.applications,
                                                 'enrollments', t.enrollments, 'commission', t.commission, 'source', 'month'))
       from b2c.targets t where t.user_id = p_user and t.month = date_trunc('month', p_month)::date),
    (select u.monthly_target || jsonb_build_object('source', 'default') from b2c.users u where u.user_id = p_user), '{}'::jsonb)
$f$;

/* The six numbers for one person over a range. Counselled: leads they moved to Qualified or later for the first time. */
create or replace function b2c.perf_actuals(p_user uuid, p_range tstzrange) returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object(
    'calls', (select count(*) from b2c.calls c where c.user_id = p_user and c.logged_at <@ p_range),
    'connected', (select count(*) from b2c.calls c where c.user_id = p_user and c.logged_at <@ p_range and c.outcome = 'connected'),
    'counselled', (select count(distinct a.lead_id) from b2c.activities a where a.actor_id = p_user and a.kind = 'stage' and a.at <@ p_range
                     and a.meta ->> 'to' in ('Qualified', 'Follow Up', 'Program Details Explained', 'Applicant', 'Docs Submitted', 'Enrolled')
                     and not exists (select 1 from b2c.activities b where b.lead_id = a.lead_id and b.kind = 'stage' and b.at < lower(p_range)
                                      and b.meta ->> 'to' in ('Qualified', 'Follow Up', 'Program Details Explained', 'Applicant', 'Docs Submitted', 'Enrolled'))),
    'applications', (select count(*) from b2c.applications a where a.created_by = p_user and a.created_at <@ p_range),
    'enrollments', (select count(*) from b2c.enrollments e where e.counsellor_id = p_user and e.status in ('reported', 'verified')
                      and (e.enrolled_on::timestamp at time zone 'Asia/Kolkata') <@ p_range),
    'commission', (select coalesce(sum(l.amount), 0) from b2c.commission_lines l join b2c.enrollments e on e.id = l.enrollment_id
                    where l.counsellor_id = p_user and l.status <> 'void' and not l.is_test and (e.enrolled_on::timestamp at time zone 'Asia/Kolkata') <@ p_range))
$f$;

create or replace function b2c.target_save(p_user uuid, p_month date, p jsonb) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid();
begin
  if not (b2c.can('settings') or (b2c.can('reassign') and exists (select 1 from b2c.users where user_id = p_user and role = 'counsellor'))) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into b2c.targets as t (user_id, month, calls, connected, counselled, applications, enrollments, commission, set_by)
  values (p_user, date_trunc('month', p_month)::date, nullif(p ->> 'calls', '')::int, nullif(p ->> 'connected', '')::int, nullif(p ->> 'counselled', '')::int,
          nullif(p ->> 'applications', '')::int, nullif(p ->> 'enrollments', '')::int, nullif(p ->> 'commission', '')::numeric, me)
  on conflict (user_id, month) do update set calls = excluded.calls, connected = excluded.connected, counselled = excluded.counselled, applications = excluded.applications,
     enrollments = excluded.enrollments, commission = excluded.commission, set_by = me, set_at = now();
  perform b2c.log('performance.target_set', null, jsonb_build_object('user_id', p_user, 'month', date_trunc('month', p_month)::date) || p);
end $f$;

/* Today's progress bar (the person's own month). */
create or replace function b2c.my_progress() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); m date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not b2c.is_staff() then raise exception 'not allowed'; end if;
  return jsonb_build_object('month', date_trunc('month', m)::date, 'target', b2c.target_for(me, m), 'actual', b2c.perf_actuals(me, b2c.ist_month(m)),
                            'day_of_month', extract(day from m), 'days_in_month', extract(day from (date_trunc('month', m) + interval '1 month - 1 day')));
end $f$;

create or replace function b2c.leaderboard_opt(p_visible boolean) returns void language sql security definer set search_path = '' as $f$
  update b2c.users set leaderboard_visible = coalesce(p_visible, false), updated_at = now() where user_id = b2c.uid() and is_active
$f$;

/* The month's leaderboard. Counsellors see it only when the Admin allows, and see names only of people who opted in. */
create or replace function b2c.leaderboard(p_month date default null) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v_role text := b2c.my_role(); m date := coalesce(p_month, (now() at time zone 'Asia/Kolkata')::date); v_all boolean;
begin
  if v_role is null then raise exception 'not allowed'; end if;
  v_all := v_role in ('admin', 'marketing', 'sales_head');
  if not v_all and not coalesce((b2c.setting('performance') ->> 'leaderboard_for_counsellors')::boolean, true) then raise exception 'the leaderboard is off'; end if;
  return jsonb_build_object('month', date_trunc('month', m)::date, 'me_visible', (select leaderboard_visible from b2c.users where user_id = me),
    'rows', (select coalesce(jsonb_agg(x order by (x -> 'actual' ->> 'enrollments')::int desc, (x -> 'actual' ->> 'commission')::numeric desc, (x -> 'actual' ->> 'connected')::int desc), '[]') from (
      select jsonb_build_object('user_id', case when v_all or u.leaderboard_visible or u.user_id = me then u.user_id end,
               'name', case when v_all or u.leaderboard_visible or u.user_id = me then u.full_name else 'A counsellor' end,
               'me', u.user_id = me, 'actual', b2c.perf_actuals(u.user_id, b2c.ist_month(m)), 'target', case when v_all or u.user_id = me then b2c.target_for(u.user_id, m) end) x
        from b2c.users u where u.is_active and u.role in ('counsellor', 'sales_head') and not (u.is_test_user and not exists (select 1 from b2c.users w where w.user_id = me and w.is_test_user))) s));
end $f$;

/* The Admin's activity monitor (sales head too): per counsellor over a range (default this month). */
create or replace function b2c.activity_monitor(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_from timestamptz := coalesce(nullif(p ->> 'from', '')::date::timestamp at time zone 'Asia/Kolkata', date_trunc('month', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata');
        v_to timestamptz := coalesce((nullif(p ->> 'to', '')::date + 1)::timestamp at time zone 'Asia/Kolkata', now());
        v_hours int := coalesce((b2c.setting('performance') ->> 'untouched_hours')::int, 48);
begin
  if not (b2c.can('read_all') or b2c.can('read_team')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('from', v_from, 'to', v_to, 'rows', (select coalesce(jsonb_agg(x order by x ->> 'name'), '[]') from (
    select jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'role', u.role, 'away_until', u.away_until,
      'calls', (select count(*) from b2c.calls c where c.user_id = u.user_id and c.logged_at >= v_from and c.logged_at < v_to),
      'connected', (select count(*) from b2c.calls c where c.user_id = u.user_id and c.logged_at >= v_from and c.logged_at < v_to and c.outcome = 'connected'),
      'whatsapp_sent', (select count(*) from b2c.wa_messages w where w.user_id = u.user_id and w.direction = 'out' and w.created_at >= v_from and w.created_at < v_to),
      'email_sent', (select count(*) from b2c.emails m where m.user_id = u.user_id and m.direction = 'out' and m.created_at >= v_from and m.created_at < v_to),
      'first_contact_median_min', (select round(extract(epoch from percentile_cont(0.5) within group (order by s.first_contacted_at - s.assigned_at)) / 60)
                                     from b2c.leads_state s where s.owner_id = u.user_id and s.assigned_at >= v_from and s.assigned_at < v_to and s.first_contacted_at is not null and not s.is_test),
      'sla_breaches', (select count(*) from b2c.leads_state s where s.owner_id = u.user_id and s.sla_breached_at >= v_from and s.sla_breached_at < v_to and not s.is_test),
      'overdue_tasks', (select count(*) from b2c.tasks t where t.owner_id = u.user_id and t.status = 'open' and t.due_at < now()),
      'untouched', (select count(*) from b2c.leads_state s where s.owner_id = u.user_id and s.status = 'active' and s.deleted_at is null and not s.is_test
                      and coalesce(s.last_activity_at, s.assigned_at) < now() - make_interval(hours => v_hours)),
      'unlogged_calls', (select count(*) from b2c.calls c where c.user_id = u.user_id and c.logged_at is null and c.unlogged_flagged_at is not null
                           and c.tapped_at >= v_from and c.tapped_at < v_to)) x
      from b2c.users u where u.is_active and u.role in ('counsellor', 'sales_head') or (u.is_active and u.role = 'admin' and u.takes_leads)) s));
end $f$;

/* Assigned this month against each cap; the hiring trigger (enrollments per counsellor per month, B7). */
create or replace function b2c.capacity() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare m tstzrange := b2c.ist_month((now() at time zone 'Asia/Kolkata')::date); a jsonb := b2c.setting('allocation'); v jsonb;
begin
  if not (b2c.can('read_all') or b2c.can('read_team')) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(x order by x ->> 'name'), '[]') into v from (
    select jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'cap', u.monthly_cap,
             'assigned', (select count(*) from b2c.assignments g where g.user_id = u.user_id and g.at <@ m),
             'open', (select count(*) from b2c.leads_state s where s.owner_id = u.user_id and s.status = 'active' and s.deleted_at is null),
             'enrollments', (select count(*) from b2c.enrollments e where e.counsellor_id = u.user_id and e.status in ('reported', 'verified')
                               and (e.enrolled_on::timestamp at time zone 'Asia/Kolkata') <@ m)) x
      from b2c.users u where u.is_active and u.takes_leads and u.role in ('counsellor', 'sales_head', 'admin') and not u.is_test_user) s;
  return jsonb_build_object('rows', v,
    'capacity_alert_pct', coalesce((a ->> 'capacity_alert_pct')::int, 90),
    'hiring_trigger_enrollments', coalesce((a ->> 'hiring_trigger_enrollments')::int, 10),
    'hiring', coalesce((select avg((x ->> 'enrollments')::numeric) from jsonb_array_elements(v) x), 0) >= coalesce((a ->> 'hiring_trigger_enrollments')::int, 10)
              or coalesce((select avg((x ->> 'assigned')::numeric / nullif((x ->> 'cap')::numeric, 0)) from jsonb_array_elements(v) x), 0) * 100 >= coalesce((a ->> 'capacity_alert_pct')::int, 90));
end $f$;

alter table b2c.targets enable row level security;
grant select on b2c.targets to authenticated;
do $p$
begin
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'targets' and policyname = 'own or team') then
    create policy "own or team" on b2c.targets for select to authenticated using (user_id = (select b2c.uid()) or (select b2c.can('read_all')) or (select b2c.can('read_team')));
  end if;
end $p$;
grant execute on function b2c.target_save(uuid, date, jsonb), b2c.my_progress(), b2c.leaderboard_opt(boolean), b2c.leaderboard(date), b2c.activity_monitor(jsonb),
  b2c.capacity() to authenticated;
revoke execute on function b2c.perf_actuals(uuid, tstzrange), b2c.target_for(uuid, date) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
