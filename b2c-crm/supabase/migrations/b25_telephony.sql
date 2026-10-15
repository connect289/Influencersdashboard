-- B2C CRM b25 (Phase 4): cloud telephony behind an adapter (spec B8.4 "telephony later"). Staging first.
--   settings 'telephony'  provider none (counsellors dial from their own phones, as today) | mock (tests) | exotel
--   call_start()          the Call button: the manual tel: flow while the provider is none; otherwise a bridged call.
--                         Test leads are never dialled by a real provider: they go to the mock.
--   call_event()          the provider's webhooks (service): idempotent; a finished bridged call logs itself (outcome,
--                         real talk time, attempts, the automatic stage moves, a suggested next task)
--   missed inbound calls  a callback task for the owner; unknown numbers wait in unknown_calls for the Admin
--   recordings            every bridged call is recorded once a provider is on; kept in a private bucket, opened only by
--                         someone who may see the lead (every play logged), removed after the retention period
-- Students' numbers stay visible to counsellors (decision of 15 Oct).

insert into b2c.settings (key, value) values
  ('telephony', '{"provider": "none", "caller_id": null, "retention_days": 180, "missed_call_minutes": 15}')
on conflict (key) do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('b2c-recordings', 'b2c-recordings', false, 52428800, array['audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/x-wav', 'audio/ogg'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

alter table b2c.calls alter column user_id drop not null;
alter table b2c.calls add column if not exists direction text not null default 'out';
alter table b2c.calls add column if not exists status text;
alter table b2c.calls add column if not exists provider_status text;
alter table b2c.calls add column if not exists from_number text;
alter table b2c.calls add column if not exists bridged_at timestamptz;
alter table b2c.calls add column if not exists ended_at timestamptz;
alter table b2c.calls add column if not exists auto_logged boolean not null default false;
alter table b2c.calls add column if not exists recording_status text not null default 'none';
alter table b2c.calls add column if not exists recording_path text;
alter table b2c.calls add column if not exists recording_attempts int not null default 0;
alter table b2c.calls add column if not exists recording_error text;
alter table b2c.calls add column if not exists recording_stored_at timestamptz;
alter table b2c.calls add column if not exists cost numeric(10, 2);
do $d$ begin
  if not exists (select 1 from pg_constraint where conname = 'calls_direction_check') then
    alter table b2c.calls add constraint calls_direction_check check (direction in ('in', 'out'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'calls_recording_status_check') then
    alter table b2c.calls add constraint calls_recording_status_check check (recording_status in ('none', 'pending', 'stored', 'failed', 'deleted'));
  end if;
end $d$;
create unique index if not exists calls_provider_ref on b2c.calls (provider, provider_ref) where provider_ref is not null;
create index if not exists calls_recording_pending on b2c.calls (id) where recording_status = 'pending';

create table if not exists b2c.call_events (
  id bigint generated always as identity primary key,
  event_key text not null unique,      -- provider + its call id + status: a repeated webhook is a no-op
  provider text not null,
  call_id bigint,
  status text not null,
  payload jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
alter table b2c.call_events enable row level security;

create table if not exists b2c.unknown_calls (
  id bigint generated always as identity primary key,
  provider text not null,
  provider_ref text,
  from_number text not null,
  status text not null,
  at timestamptz not null default now(),
  handled_at timestamptz,
  handled_by uuid,
  note text
);
alter table b2c.unknown_calls enable row level security;

/* The provider in force for one lead: test leads never reach a real provider. */
create or replace function b2c.telephony_provider(p_lead bigint) returns text language sql stable security definer set search_path = '' as $f$
  select case when coalesce(b2c.setting('telephony') ->> 'provider', 'none') not in ('exotel', 'mock') then 'manual'
              when coalesce((select is_test from b2c.leads_state where lead_id = p_lead), true) then 'mock'
              else b2c.setting('telephony') ->> 'provider' end
$f$;

/* The Call button (B8.4). Provider none: exactly the old tap (tel: link, log sheet). Otherwise: a call row the app
   bridges through the provider; the counsellor's own mobile rings first. */
create or replace function b2c.call_start(p_lead bigint, p_contact bigint default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require_lead(p_lead); v_provider text := b2c.telephony_provider(p_lead); v_num text; v_agent text; v_id bigint; r jsonb;
begin
  if v_provider = 'manual' then
    return b2c.call_tap(p_lead, p_contact) || jsonb_build_object('mode', 'manual');
  end if;
  select value into v_num from b2c.lead_contacts
   where lead_id = p_lead and kind = 'phone' and removed_at is null and (id = p_contact or (p_contact is null and primary_call))
   order by (id = p_contact) desc nulls last limit 1;
  if v_num is null then raise exception 'this lead has no phone number'; end if;
  select phone into v_agent from b2c.users where user_id = me;
  if coalesce(b2c.norm_phone(v_agent), '') = '' then raise exception 'add your mobile number under Teams first: the call rings your phone, then the student'; end if;
  insert into b2c.calls (lead_id, user_id, number, provider, direction, status, from_number)
  values (p_lead, me, v_num, v_provider, 'out', 'initiated', v_agent) returning id into v_id;
  insert into b2c.audit_log (actor_id, action, lead_id, detail) values (me, 'call_tap', p_lead, jsonb_build_object('call_id', v_id, 'provider', v_provider));
  r := jsonb_build_object('mode', 'bridge', 'provider', v_provider, 'call_id', v_id, 'agent', '+' || b2c.norm_phone(v_agent), 'student', '+' || b2c.norm_phone(v_num),
                          'caller_id', b2c.setting('telephony') ->> 'caller_id', 'number', v_num, 'tel', 'tel:+' || b2c.norm_phone(v_num));
  return r;
end $f$;

/* The record of one call outcome, shared by the manual log sheet and the bridged calls (B5.2 automatic moves, B8.4). */
create or replace function b2c.call_record(p_call bigint, p_outcome text, p_duration_s int, p_note text, p_next_due timestamptz,
                                           p_next_kind text, p_next_note text, p_actor uuid, p_suggested boolean, p_how text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare c b2c.calls; s b2c.leads_state; v_new_stage smallint; v_new_sub text; v_label text; v_set jsonb := '{}'::jsonb; v_dur int;
begin
  select * into c from b2c.calls where id = p_call;
  v_label := case p_outcome when 'connected' then 'Connected' when 'no_answer' then 'No answer' when 'busy' then 'Busy' when 'switched_off' then 'Switched off'
                            when 'wrong_number' then 'Wrong number' else 'Call back requested' end;
  v_dur := case when p_outcome = 'connected' then greatest(coalesce(p_duration_s, 0), 0) else 0 end;
  update b2c.calls set logged_at = now(), outcome = p_outcome, duration_s = v_dur, note = left(p_note, 2000), auto_logged = p_how <> 'manual' where id = p_call;
  select * into s from b2c.leads_state where lead_id = c.lead_id for update;
  update b2c.leads_state set contact_attempts = contact_attempts + case when c.direction = 'out' then 1 else 0 end,
         first_contacted_at = case when c.direction = 'out' or p_outcome = 'connected' then coalesce(first_contacted_at, c.tapped_at) else first_contacted_at end,
         last_contacted_at = greatest(coalesce(last_contacted_at, c.tapped_at), c.tapped_at),
         last_activity_at = now(), sla_met_at = coalesce(sla_met_at, case when sla_due_at is not null then now() end), updated_at = now()
   where lead_id = c.lead_id;
  -- automatic moves (B5.2)
  if s.stage_id = 1 and p_outcome in ('no_answer', 'busy', 'switched_off', 'wrong_number', 'call_back') then
    v_new_stage := 2; v_new_sub := case p_outcome when 'call_back' then 'Call back requested' else v_label end;
  elsif s.stage_id in (1, 2) and p_outcome = 'connected' then
    v_new_stage := 3; v_new_sub := 'Spoke briefly';
  end if;
  if v_new_stage is not null then
    update b2c.leads_state set stage_id = v_new_stage, sub_stage = v_new_sub, stage_changed_at = now() where lead_id = c.lead_id;
    insert into b2c.activities (lead_id, kind, body, meta, actor_id)
    values (c.lead_id, 'stage', (select name from b2c.stages where id = v_new_stage) || ' · ' || v_new_sub || ' (automatic, from the call)',
            jsonb_build_object('auto', true, 'call_id', p_call), p_actor);
    v_set := jsonb_build_object('stage', (select canon from b2c.stages where id = v_new_stage), 'sub_stage', v_new_sub, 'stage_changed_at', now(),
                                'b2c_stage', (select name from b2c.stages where id = v_new_stage), 'b2c_sub_stage', v_new_sub);
  end if;
  insert into b2c.activities (lead_id, kind, direction, outcome, duration_s, body, meta, actor_id, at)
  values (c.lead_id, 'call', c.direction, p_outcome, v_dur,
          case when c.direction = 'in' then 'Incoming call: ' else 'Call: ' end || v_label
            || case when p_how <> 'manual' and v_dur > 0 then format(' (%s min %s s)', v_dur / 60, v_dur % 60) else '' end
            || coalesce(' · ' || nullif(trim(p_note), ''), ''),
          jsonb_build_object('call_id', p_call, 'provider', c.provider, 'bridged', p_how <> 'manual'), p_actor, c.tapped_at);
  -- the call that was the open first-call task is done
  update b2c.tasks set status = 'done', done_at = now(), outcome = v_label
   where id = (select t.id from b2c.tasks t where t.lead_id = c.lead_id and t.status = 'open' and t.kind = 'call' order by t.due_at limit 1);
  perform b2c.add_task(c.lead_id, coalesce(s.owner_id, p_actor), coalesce(p_next_kind, 'call'),
                       coalesce(p_next_note, (b2c.call_suggestion(c.lead_id, p_outcome) ->> 'note')), p_next_due, null, p_suggested, case when p_how = 'manual' then 'call_log' else 'call_auto' end);
  perform b2c.queue_activity(c.lead_id, 'call', c.tapped_at, p_outcome, v_dur, p_note);
  perform b2c.queue_update(c.lead_id, v_set || jsonb_build_object('next_task_due_at', b2c.refresh_next_task(c.lead_id)), false);
  return jsonb_build_object('logged', true, 'moved_to', (select name from b2c.stages where id = v_new_stage), 'sub_stage', v_new_sub,
                            'suggestion', b2c.call_suggestion(c.lead_id, p_outcome));
end $f$;

/* The manual log sheet: unchanged for the counsellor, now through call_record. A bridged call logs itself, but the
   counsellor may still add a note and a next step to it with call_note(). */
create or replace function b2c.call_log(p_call bigint, p_outcome text, p_duration_s int, p_note text, p_next_due timestamptz,
                                        p_next_kind text default 'call', p_next_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare c b2c.calls; me uuid;
begin
  select * into c from b2c.calls where id = p_call for update;
  if c.id is null then raise exception 'no such call'; end if;
  me := b2c.require_lead(c.lead_id);
  if c.logged_at is not null then raise exception 'this call is already logged'; end if;
  if c.provider <> 'manual' and c.ended_at is null then raise exception 'this call is still going on; it logs itself when it ends'; end if;
  if p_outcome not in ('connected', 'no_answer', 'busy', 'switched_off', 'wrong_number', 'call_back') then raise exception 'choose the call outcome'; end if;
  if p_next_due is null then raise exception 'set the next follow-up'; end if;
  return b2c.call_record(p_call, p_outcome, p_duration_s, p_note, p_next_due, p_next_kind, p_next_note, me, false, 'manual');
end $f$;

create or replace function b2c.call_note(p_call bigint, p_note text) returns void
language plpgsql security definer set search_path = '' as $f$
declare c b2c.calls; me uuid;
begin
  select * into c from b2c.calls where id = p_call;
  if c.id is null then raise exception 'no such call'; end if;
  me := b2c.require_lead(c.lead_id);
  if c.logged_at is null then raise exception 'log the call first'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'write the note'; end if;
  update b2c.calls set note = left(trim(p_note), 2000) where id = p_call;
  insert into b2c.activities (lead_id, kind, body, meta, actor_id) values (c.lead_id, 'note', 'Call note: ' || left(trim(p_note), 2000), jsonb_build_object('call_id', p_call), me);
  perform b2c.queue_activity(c.lead_id, 'note', now(), null, null, p_note);
end $f$;

/* The provider's events (service role; the app's webhook normalises them). p: provider, event_key, call_id (ours, from
   the custom field) or provider_ref, status (initiated, ringing, answered, completed, no_answer, busy, failed,
   agent_no_answer, missed), direction, from, agent (who answered an inbound call), duration_s, recording_url, cost. */
create or replace function b2c.call_event(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare
  v_provider text := coalesce(p ->> 'provider', 'exotel'); v_status text := p ->> 'status'; v_ref text := nullif(p ->> 'provider_ref', '');
  v_key text; c b2c.calls; v_lead bigint; v_owner uuid; v_user uuid; v_from text := b2c.norm_phone(p ->> 'from'); v_outcome text; v_dur int; v_inserted bigint; r jsonb;
  v_minutes int := coalesce((b2c.setting('telephony') ->> 'missed_call_minutes')::int, 15);
begin
  if v_status not in ('initiated', 'ringing', 'answered', 'completed', 'no_answer', 'busy', 'failed', 'agent_no_answer', 'missed') then
    raise exception 'unknown call status: %', v_status;
  end if;
  v_key := coalesce(nullif(p ->> 'event_key', ''), v_provider || ':' || coalesce(v_ref, p ->> 'call_id', '') || ':' || v_status);
  insert into b2c.call_events (event_key, provider, call_id, status, payload) values (v_key, v_provider, nullif(p ->> 'call_id', '')::bigint, v_status, p)
  on conflict (event_key) do nothing returning id into v_inserted;
  if v_inserted is null then return jsonb_build_object('duplicate', true); end if;

  if nullif(p ->> 'call_id', '') is not null then select * into c from b2c.calls where id = (p ->> 'call_id')::bigint for update; end if;
  if c.id is null and v_ref is not null then select * into c from b2c.calls where provider = v_provider and provider_ref = v_ref for update; end if;

  if c.id is null then
    if coalesce(p ->> 'direction', 'in') <> 'in' then raise exception 'unknown call'; end if;
    -- an inbound call: whose number is it?
    select lc.lead_id, s.owner_id into v_lead, v_owner from b2c.lead_contacts lc join b2c.leads_state s on s.lead_id = lc.lead_id and s.deleted_at is null
     where lc.kind = 'phone' and lc.removed_at is null and lc.value_norm = v_from
     order by (s.status = 'active') desc, s.updated_at desc limit 1;
    if v_lead is null then
      insert into b2c.unknown_calls (provider, provider_ref, from_number, status) values (v_provider, v_ref, coalesce(p ->> 'from', ''), v_status);
      if v_status in ('missed', 'no_answer', 'agent_no_answer') then
        perform b2c.notify_admins('missed_call', 'Missed call from an unknown number', p ->> 'from', '/w/connectors', null, 'unknown:' || coalesce(v_ref, v_key), false);
      end if;
      update b2c.call_events set call_id = null where id = v_inserted;
      return jsonb_build_object('unknown_number', true);
    end if;
    select user_id into v_user from b2c.users where is_active and b2c.norm_phone(phone) = b2c.norm_phone(p ->> 'agent') limit 1;
    insert into b2c.calls (lead_id, user_id, number, provider, provider_ref, direction, status, from_number, tapped_at)
    values (v_lead, coalesce(v_user, v_owner), coalesce(p ->> 'from', ''), v_provider, v_ref, 'in', v_status, p ->> 'from', now())
    returning * into c;
    update b2c.call_events set call_id = c.id where id = v_inserted;
  end if;

  update b2c.calls set provider_ref = coalesce(provider_ref, v_ref), status = v_status, provider_status = coalesce(p ->> 'provider_status', provider_status),
         bridged_at = case when v_status = 'answered' then coalesce(bridged_at, now()) else bridged_at end,
         cost = coalesce(nullif(p ->> 'cost', '')::numeric, cost)
   where id = c.id;
  if v_status not in ('completed', 'no_answer', 'busy', 'failed', 'agent_no_answer', 'missed') or c.ended_at is not null then
    return jsonb_build_object('call_id', c.id, 'status', v_status);
  end if;

  -- the call has ended
  v_dur := greatest(coalesce(nullif(p ->> 'duration_s', '')::int, 0), 0);
  update b2c.calls set ended_at = now(),
         recording_status = case when nullif(p ->> 'recording_url', '') is not null then 'pending' else recording_status end,
         recording_url = coalesce(nullif(p ->> 'recording_url', ''), recording_url)
   where id = c.id;
  if c.direction = 'in' and (v_status in ('missed', 'no_answer', 'agent_no_answer', 'busy', 'failed') or (v_status = 'completed' and v_dur = 0)) then
    -- a missed incoming call: call them back
    update b2c.calls set logged_at = now(), auto_logged = true where id = c.id;
    insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id, at)
    values (c.lead_id, 'call', 'in', 'Missed call from the student', jsonb_build_object('call_id', c.id, 'provider', c.provider, 'missed', true), null, c.tapped_at);
    select owner_id into v_owner from b2c.leads_state where lead_id = c.lead_id;
    perform b2c.add_task(c.lead_id, v_owner, 'call', 'Call back: missed call from the student', now() + make_interval(mins => v_minutes), null, false, 'missed_call');
    perform b2c.queue_update(c.lead_id, jsonb_build_object('next_task_due_at', b2c.refresh_next_task(c.lead_id)), false);
    if v_owner is not null then
      perform b2c.notify(v_owner, 'missed_call', 'Missed call: call back', null, '/s/leads/' || c.lead_id, c.lead_id, 'missed:' || c.id);
    else
      perform b2c.notify_admins('missed_call', 'Missed call from an unassigned lead', null, '/w/leads/' || c.lead_id, c.lead_id, 'missed:' || c.id, false);
    end if;
    return jsonb_build_object('call_id', c.id, 'missed', true);
  end if;
  if v_status = 'agent_no_answer' then
    -- the counsellor's phone did not answer: the student was never rung, so no attempt is counted
    update b2c.calls set logged_at = now(), auto_logged = true where id = c.id;
    insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id, at)
    values (c.lead_id, 'call', 'out', 'Call not placed: your phone did not answer', jsonb_build_object('call_id', c.id, 'provider', c.provider, 'not_placed', true), c.user_id, c.tapped_at);
    if c.user_id is not null then
      perform b2c.notify(c.user_id, 'call_not_placed', 'Your phone did not answer', 'The student was not called. Tap Call again when you are ready.', '/s/leads/' || c.lead_id, c.lead_id, 'np:' || c.id);
    end if;
    return jsonb_build_object('call_id', c.id, 'not_placed', true);
  end if;
  v_outcome := case v_status when 'completed' then case when v_dur > 0 then 'connected' else 'no_answer' end
                             when 'no_answer' then 'no_answer' when 'busy' then 'busy' else 'switched_off' end;
  r := b2c.call_record(c.id, v_outcome, v_dur, null, now() + make_interval(mins => (b2c.call_suggestion(c.lead_id, v_outcome) ->> 'in_minutes')::int),
                       b2c.call_suggestion(c.lead_id, v_outcome) ->> 'kind', null, c.user_id, true, 'bridged');
  return jsonb_build_object('call_id', c.id, 'outcome', v_outcome) || r;
end $f$;

/* The mock provider, played from the lead screen: only for a mock call the person may see. Real providers reach
   call_event() only through the webhook with the service key. */
create or replace function b2c.call_mock_event(p_call bigint, p_status text, p_duration_s int default 0) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare c b2c.calls;
begin
  select * into c from b2c.calls where id = p_call;
  if c.id is null or c.provider <> 'mock' then raise exception 'not a mock call'; end if;
  perform b2c.require_lead(c.lead_id);
  if p_status not in ('ringing', 'answered', 'completed', 'no_answer', 'busy', 'failed', 'agent_no_answer') then raise exception 'unknown call status: %', p_status; end if;
  return b2c.call_event(jsonb_build_object('provider', 'mock', 'call_id', c.id, 'provider_ref', 'MOCK-' || c.id, 'status', p_status, 'duration_s', p_duration_s,
                                           'recording_url', case when p_status = 'completed' and p_duration_s > 0 then 'mock://recording/' || c.id end));
end $f$;

/* The call sheet's live view of one call. */
create or replace function b2c.call_get(p_call bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare c b2c.calls;
begin
  select * into c from b2c.calls where id = p_call;
  if c.id is null then raise exception 'no such call'; end if;
  perform b2c.require_lead(c.lead_id);
  return jsonb_build_object('id', c.id, 'provider', c.provider, 'status', c.status, 'outcome', c.outcome, 'duration_s', c.duration_s, 'logged', c.logged_at is not null,
                            'ended', c.ended_at is not null or c.logged_at is not null, 'note', c.note, 'recording', c.recording_status);
end $f$;

/* Service role: the provider refused to start the call (no credentials, LIVE_MODE off, an API error). Nothing was dialled,
   so no attempt is counted; the counsellor sees why. */
create or replace function b2c.call_start_failed(p_call bigint, p_error text) returns void language plpgsql security definer set search_path = '' as $f$
declare c b2c.calls;
begin
  select * into c from b2c.calls where id = p_call for update;
  if c.id is null or c.logged_at is not null then return; end if;
  update b2c.calls set status = 'failed', ended_at = now(), logged_at = now(), auto_logged = true, note = left('Not placed: ' || p_error, 300) where id = p_call;
  insert into b2c.activities (lead_id, kind, direction, body, meta, actor_id, at)
  values (c.lead_id, 'call', 'out', 'Call not placed: ' || left(p_error, 200), jsonb_build_object('call_id', c.id, 'provider', c.provider, 'not_placed', true), c.user_id, c.tapped_at);
end $f$;

-- ---------- recordings (the app moves the file; the database keeps the state) ----------
create or replace function b2c.recordings_take(p_limit int default 5) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with t as (select id from b2c.calls where recording_status = 'pending' and recording_attempts < 5 order by id limit p_limit for update skip locked),
       m as (update b2c.calls c set recording_attempts = c.recording_attempts + 1 from t where c.id = t.id returning c.id, c.lead_id, c.provider, c.recording_url, c.tapped_at)
  select coalesce(jsonb_agg(to_jsonb(m)), '[]') into v from m;
  return v;
end $f$;

create or replace function b2c.recording_saved(p_call bigint, p_path text, p_error text default null) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.calls set recording_status = case when p_error is null then 'stored' when recording_attempts >= 5 then 'failed' else 'pending' end,
         recording_path = case when p_error is null then p_path else recording_path end,
         recording_stored_at = case when p_error is null then now() else recording_stored_at end,
         recording_error = left(p_error, 300)
   where id = p_call;
end $f$;

create or replace function b2c.recordings_expired(p_limit int default 50) returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'path', recording_path)), '[]') from (
    select id, recording_path from b2c.calls
     where recording_status = 'stored' and recording_stored_at < now() - make_interval(days => coalesce((b2c.setting('telephony') ->> 'retention_days')::int, 180))
     order by id limit p_limit) s
$f$;

create or replace function b2c.recording_removed(p_call bigint) returns void language sql security definer set search_path = '' as $f$
  update b2c.calls set recording_status = 'deleted', recording_path = null, recording_url = null where id = p_call
$f$;

/* Opening a recording: only for someone who may see the lead; every play is logged. Returns the storage path. */
create or replace function b2c.recording_open(p_call bigint) returns text language plpgsql security definer set search_path = '' as $f$
declare c b2c.calls; me uuid;
begin
  select * into c from b2c.calls where id = p_call;
  if c.id is null then raise exception 'no such call'; end if;
  if not coalesce(b2c.can_see(c.lead_id), false) then raise exception 'not allowed' using errcode = '42501'; end if;
  me := b2c.uid();
  if c.recording_status <> 'stored' then
    raise exception '%', case c.recording_status when 'pending' then 'the recording is still being fetched' when 'deleted' then 'the recording was removed after the retention period'
                              when 'failed' then 'the recording could not be fetched' else 'this call has no recording' end;
  end if;
  insert into b2c.audit_log (actor_id, action, lead_id, detail) values (me, 'recording_play', c.lead_id, jsonb_build_object('call_id', c.id));
  return c.recording_path;
end $f$;

-- ---------- the Admin's view ----------
create or replace function b2c.telephony_status() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return jsonb_build_object('settings', b2c.setting('telephony'),
    'last_event', (select max(at) from b2c.call_events),
    'events_24h', (select count(*) from b2c.call_events where at > now() - interval '24 hours'),
    'bridged_7d', (select count(*) from b2c.calls where provider not in ('manual') and tapped_at > now() - interval '7 days'),
    'recordings', (select jsonb_object_agg(recording_status, n) from (select recording_status, count(*) n from b2c.calls where recording_status <> 'none' group by 1) s),
    'unknown_calls', (select coalesce(jsonb_agg(to_jsonb(u) order by u.at desc), '[]') from (select * from b2c.unknown_calls where handled_at is null order by at desc limit 50) u),
    'agents_without_phone', (select coalesce(jsonb_agg(full_name order by full_name), '[]') from b2c.users
                              where is_active and takes_leads and role in ('counsellor', 'sales_head', 'admin') and coalesce(b2c.norm_phone(phone), '') = ''));
end $f$;

create or replace function b2c.unknown_call_handled(p_id bigint, p_note text default null) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings');
begin
  update b2c.unknown_calls set handled_at = now(), handled_by = me, note = left(p_note, 300) where id = p_id;
end $f$;

/* Unlogged-call flags apply to manual calls only: a bridged call logs itself when it ends. */
create or replace function b2c.reminder_tick() returns jsonb language plpgsql security definer set search_path = '' as $f$
declare f jsonb := b2c.setting('followups'); r record; a int := 0; b int := 0; c int := 0; d int := 0;
begin
  for r in select t.id, t.lead_id, t.owner_id, t.title, t.due_at, v.name from b2c.tasks t join b2c.leads_v v on v.lead_id = t.lead_id
            where t.status = 'open' and t.reminded_at is null and t.due_at <= now() + make_interval(mins => coalesce((f ->> 'reminder_minutes_before')::int, 10))
              and t.due_at > now() - interval '5 minutes' limit 500 loop
    perform b2c.notify(r.owner_id, 'reminder', 'In 10 minutes: ' || r.title, coalesce(r.name, ''), '/s/leads/' || r.lead_id, r.lead_id, 'rem:' || r.id);
    update b2c.tasks set reminded_at = now() where id = r.id; a := a + 1;
  end loop;
  for r in select t.id, t.lead_id, t.owner_id, t.title from b2c.tasks t where t.status = 'open' and t.due_at < now() and t.overdue_alerted_at is null limit 500 loop
    perform b2c.notify(r.owner_id, 'overdue', 'Overdue: ' || r.title, null, '/s/leads/' || r.lead_id, r.lead_id, 'over:' || r.id);
    update b2c.tasks set overdue_alerted_at = now() where id = r.id; b := b + 1;
  end loop;
  for r in select t.id, t.lead_id, t.title, u.full_name from b2c.tasks t left join b2c.users u on u.user_id = t.owner_id
            where t.status = 'open' and t.escalated_at is null and t.due_at < now() - make_interval(mins => coalesce((f ->> 'escalate_after_minutes')::int, 120)) limit 500 loop
    perform b2c.notify_admins('escalation', 'Missed follow-up: ' || r.title, coalesce(r.full_name, '') || ' has not done it', '/w/leads/' || r.lead_id, r.lead_id, 'esc:' || r.id, true);
    update b2c.tasks set escalated_at = now() where id = r.id; c := c + 1;
  end loop;
  for r in select x.id, x.lead_id, x.user_id from b2c.calls x where x.logged_at is null and x.unlogged_flagged_at is null and x.provider = 'manual'
              and x.tapped_at < now() - make_interval(mins => coalesce((f ->> 'call_unlogged_minutes')::int, 10)) limit 500 loop
    perform b2c.notify(r.user_id, 'call_not_logged', 'Call not logged', 'Log the outcome of your call.', '/s/leads/' || r.lead_id, r.lead_id, 'unlogged:' || r.id);
    update b2c.calls set unlogged_flagged_at = now() where id = r.id; d := d + 1;
  end loop;
  return jsonb_build_object('reminders', a, 'overdue', b, 'escalated', c, 'unlogged', d);
end $f$;

grant execute on function b2c.call_start(bigint, bigint), b2c.call_note(bigint, text), b2c.call_mock_event(bigint, text, integer), b2c.call_get(bigint), b2c.recording_open(bigint), b2c.telephony_status(),
  b2c.unknown_call_handled(bigint, text) to authenticated;
grant execute on function b2c.call_event(jsonb), b2c.call_start_failed(bigint, text), b2c.recordings_take(integer), b2c.recording_saved(bigint, text, text), b2c.recordings_expired(integer),
  b2c.recording_removed(bigint), b2c.call_start(bigint, bigint), b2c.reminder_tick() to service_role;
revoke execute on function b2c.call_event(jsonb), b2c.call_start_failed(bigint, text), b2c.call_record(bigint, text, integer, text, timestamptz, text, text, uuid, boolean, text), b2c.recordings_take(integer),
  b2c.recording_saved(bigint, text, text), b2c.recordings_expired(integer), b2c.recording_removed(bigint), b2c.telephony_provider(bigint) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
