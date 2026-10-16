-- B2C CRM b28 (Phase 4): follow-ups in each person's Google Calendar (spec B17 Connectors, personal; B19.2 row 4).
--   users.calendar_sync    each person turns it on for themselves (Connectors); off by default
--   calendar_events       one row per follow-up: what the calendar should show (upsert or remove) and what it shows now
--                         (Google event id and etag); a trigger on tasks keeps it current, the app's job pushes it
--   One way, CRM → Calendar. An event carries the task, the student's first name, the programme and the lead link:
--   never a phone number or an email.

alter table b2c.users add column if not exists calendar_sync boolean not null default false;
alter table b2c.users add column if not exists calendar_error text;
alter table b2c.users add column if not exists calendar_synced_at timestamptz;

create table if not exists b2c.calendar_events (
  task_id bigint primary key references b2c.tasks (id),
  user_id uuid references b2c.users (user_id),       -- whose calendar it should be in
  want text not null check (want in ('upsert', 'remove')),
  state text not null default 'pending' check (state in ('pending', 'synced', 'error')),
  event_id text,                                      -- in user_id's calendar
  etag text,
  old_user_id uuid,                                   -- after a reassignment: remove old_event_id from old_user_id's calendar first
  old_event_id text,
  attempts int not null default 0,
  error text,
  updated_at timestamptz not null default now(),
  synced_at timestamptz
);
create index if not exists calendar_events_pending on b2c.calendar_events (updated_at) where state = 'pending';
alter table b2c.calendar_events enable row level security;

/* What the calendar should show for one task, queued for the job. */
create or replace function b2c.calendar_queue(p_task bigint) returns void language plpgsql security definer set search_path = '' as $f$
declare t b2c.tasks; v_on boolean; ce b2c.calendar_events; v_want text;
begin
  select * into t from b2c.tasks where id = p_task;
  if t.id is null then return; end if;
  select calendar_sync into v_on from b2c.users where user_id = t.owner_id and is_active;
  v_want := case when t.status = 'open' and coalesce(v_on, false) then 'upsert' else 'remove' end;
  select * into ce from b2c.calendar_events where task_id = p_task;
  if ce.task_id is null then
    if v_want = 'remove' then return; end if;
    insert into b2c.calendar_events (task_id, user_id, want) values (p_task, t.owner_id, 'upsert');
    return;
  end if;
  if ce.user_id is distinct from t.owner_id and ce.event_id is not null then
    -- reassigned: the old owner's event goes, the new owner's comes
    update b2c.calendar_events set old_user_id = ce.user_id, old_event_id = ce.event_id, event_id = null, etag = null where task_id = p_task;
  end if;
  update b2c.calendar_events set user_id = t.owner_id, want = v_want, state = 'pending', attempts = 0, error = null, updated_at = now() where task_id = p_task;
end $f$;

create or replace function b2c.tasks_calendar() returns trigger language plpgsql security definer set search_path = '' as $f$
begin
  if tg_op = 'INSERT' or new.due_at is distinct from old.due_at or new.status is distinct from old.status or new.title is distinct from old.title
     or new.owner_id is distinct from old.owner_id or new.kind is distinct from old.kind then
    perform b2c.calendar_queue(new.id);
  end if;
  return null;
end $f$;
do $d$ begin
  if not exists (select 1 from pg_trigger where tgname = 'tasks_calendar' and tgrelid = 'b2c.tasks'::regclass) then
    create trigger tasks_calendar after insert or update on b2c.tasks for each row execute function b2c.tasks_calendar();
  end if;
end $d$;

/* The person turns their own sync on or off. On: their open follow-ups from yesterday on are queued; off: removed. */
create or replace function b2c.calendar_set(p_on boolean) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); t record; n int := 0;
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2c.users set calendar_sync = p_on, calendar_error = null where user_id = me;
  for t in select id from b2c.tasks where owner_id = me and ((p_on and status = 'open' and due_at > now() - interval '1 day')
                                                            or (not p_on and id in (select task_id from b2c.calendar_events where user_id = me and event_id is not null))) loop
    perform b2c.calendar_queue(t.id); n := n + 1;
  end loop;
  perform b2c.log('calendar.sync_set', null, jsonb_build_object('on', p_on, 'queued', n));
  return jsonb_build_object('on', p_on, 'queued', n);
end $f$;

create or replace function b2c.calendar_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select jsonb_build_object('on', u.calendar_sync, 'error', u.calendar_error, 'synced_at', u.calendar_synced_at,
           'pending', (select count(*) from b2c.calendar_events c where c.user_id = u.user_id and c.state = 'pending'),
           'events', (select count(*) from b2c.calendar_events c where c.user_id = u.user_id and c.event_id is not null))
    from b2c.users u where u.user_id = b2c.uid()
$f$;

/* Service role: the changes to push now, each with what the event shows. */
create or replace function b2c.calendar_take(p_limit int default 25) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with due as (select c.task_id from b2c.calendar_events c where c.state = 'pending' and c.attempts < 6
                and c.updated_at <= now() - make_interval(secs => case when c.attempts = 0 then 0 else power(2, c.attempts) * 30 end)
                order by c.updated_at limit p_limit for update skip locked),
       m as (update b2c.calendar_events c set attempts = c.attempts + 1 from due where c.task_id = due.task_id returning c.*)
  select coalesce(jsonb_agg(jsonb_build_object(
           'task_id', m.task_id, 'want', m.want, 'event_id', m.event_id, 'etag', m.etag, 'old_event_id', m.old_event_id,
           'email', (select email from b2c.users where user_id = m.user_id), 'old_email', (select email from b2c.users where user_id = m.old_user_id),
           'title', t.title, 'kind', t.kind, 'due_at', t.due_at, 'note', left(b2c.scrub_pii(t.note), 300), 'lead_id', t.lead_id,
           'first_name', split_part(trim(coalesce(r.record -> 'student' ->> 'name', '')), ' ', 1), 'course', r.record -> 'interest' ->> 'course')), '[]') into v
    from m join b2c.tasks t on t.id = m.task_id left join b2c.lead_records r on r.lead_id = t.lead_id;
  return v;
end $f$;

create or replace function b2c.calendar_done(p_task bigint, p_event_id text, p_etag text, p_error text default null) returns void
language plpgsql security definer set search_path = '' as $f$
declare ce b2c.calendar_events;
begin
  select * into ce from b2c.calendar_events where task_id = p_task;
  if ce.task_id is null then return; end if;
  if p_error is not null then
    update b2c.calendar_events set state = case when attempts >= 6 then 'error' else 'pending' end, error = left(p_error, 300), updated_at = now() where task_id = p_task;
    update b2c.users set calendar_error = left(p_error, 300) where user_id = ce.user_id;
    return;
  end if;
  update b2c.calendar_events set state = 'synced', event_id = case when want = 'remove' then null else p_event_id end, etag = case when want = 'remove' then null else p_etag end,
         old_user_id = null, old_event_id = null, error = null, synced_at = now(), attempts = 0
   where task_id = p_task;
  update b2c.users set calendar_synced_at = now(), calendar_error = null where user_id = ce.user_id;
end $f$;

/* The Admin's view: who syncs, and errors. */
create or replace function b2c.calendar_status() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return (select coalesce(jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', u.full_name, 'on', u.calendar_sync, 'error', u.calendar_error, 'synced_at', u.calendar_synced_at,
            'pending', (select count(*) from b2c.calendar_events c where c.user_id = u.user_id and c.state = 'pending'),
            'failed', (select count(*) from b2c.calendar_events c where c.user_id = u.user_id and c.state = 'error')) order by u.full_name), '[]')
            from b2c.users u where u.is_active);
end $f$;

grant execute on function b2c.calendar_set(boolean), b2c.calendar_mine(), b2c.calendar_status() to authenticated;
grant execute on function b2c.calendar_take(integer), b2c.calendar_done(bigint, text, text, text) to service_role;
revoke execute on function b2c.calendar_queue(bigint), b2c.tasks_calendar(), b2c.calendar_take(integer), b2c.calendar_done(bigint, text, text, text) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
