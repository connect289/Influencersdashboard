-- B2C CRM b3: the link with the B2B CRM (contract v3, Addendum 4) and in-app notifications. Staging first.
--   inbox      every B2B envelope (webhook or feed), unique on its id: processed once (contract §1)
--   outbox     every B2C write to B2B. Updates merge into one per lead until the 15-minute batch takes them (K2);
--              consent, opt-out, erasure, route-to-partners and intake are urgent and go at once
--   handoff_receive()  store + apply in one call, well inside B2B's 10-second budget
--   apply_envelope()   what each event means for B2C (hand-off → allocate or pool, re-enquiry, requalified, routed …)
--   notifications, notify()

create table if not exists b2c.inbox (
  envelope_id text primary key,
  type text not null,
  lead_id bigint,
  occurred_at timestamptz,
  payload jsonb not null,
  via text not null default 'webhook' check (via in ('webhook', 'feed', 'test')),
  status text not null default 'stored' check (status in ('stored', 'applied', 'ignored', 'error')),
  error text,
  attempts int not null default 0,
  received_at timestamptz not null default now(),
  applied_at timestamptz
);
alter table b2c.inbox enable row level security;
create index if not exists inbox_status on b2c.inbox (status, received_at) where status in ('stored', 'error');

create table if not exists b2c.outbox (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('update', 'activity', 'event', 'route', 'intake')),
  lead_id bigint,
  request_id text not null unique,
  body jsonb not null,
  urgent boolean not null default false,
  occurred_at timestamptz not null default now(),
  status text not null default 'queued' check (status in ('queued', 'sending', 'applied', 'conflict', 'refused', 'failed')),
  attempts int not null default 0,
  next_attempt_at timestamptz not null default now(),
  answer jsonb,
  actor jsonb,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  done_at timestamptz
);
alter table b2c.outbox enable row level security;
create index if not exists outbox_due on b2c.outbox (status, urgent, next_attempt_at) where status = 'queued';
create unique index if not exists outbox_one_open_update on b2c.outbox (lead_id, urgent) where kind = 'update' and status = 'queued';

create table if not exists b2c.sync_state (
  key text primary key,          -- handoffs_after, feed_after, last_batch_at, last_reconcile_at, schema
  value jsonb not null,
  updated_at timestamptz not null default now()
);
alter table b2c.sync_state enable row level security;

create table if not exists b2c.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references b2c.users (user_id),
  kind text not null,
  title text not null,
  body text,
  link text,
  lead_id bigint,
  dedupe_key text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  pushed_at timestamptz,
  emailed_at timestamptz
);
alter table b2c.notifications enable row level security;
create unique index if not exists notifications_dedupe on b2c.notifications (user_id, dedupe_key) where dedupe_key is not null;
create index if not exists notifications_user on b2c.notifications (user_id, created_at desc);

create table if not exists b2c.consent_requests (
  request_id bigint primary key,           -- B2B's id
  lead_id bigint not null,
  context text,
  programme text,
  text_body text,
  text_version text,
  expires_at timestamptz,
  status text not null default 'received' check (status in ('received', 'queued', 'sent', 'answered', 'expired', 'cancelled', 'held')),
  send_message_id bigint,
  sent_wamid text,
  sent_at timestamptz,
  answer text check (answer in ('yes', 'no')),
  answer_wamid text,
  answered_at timestamptz,
  closed_at timestamptz,
  close_why text,
  created_at timestamptz not null default now()
);
alter table b2c.consent_requests enable row level security;

-- ---------- notify ----------
create or replace function b2c.notify(p_user uuid, p_kind text, p_title text, p_body text default null, p_link text default null,
                                      p_lead bigint default null, p_dedupe text default null) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  if p_user is null then return; end if;
  insert into b2c.notifications (user_id, kind, title, body, link, lead_id, dedupe_key)
  values (p_user, p_kind, left(p_title, 200), left(p_body, 1000), p_link, p_lead, p_dedupe)
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end $f$;

/* Every active Admin (and sales heads when p_heads). */
create or replace function b2c.notify_admins(p_kind text, p_title text, p_body text default null, p_link text default null,
                                             p_lead bigint default null, p_dedupe text default null, p_heads boolean default false) returns void
language sql security definer set search_path = '' as $f$
  select b2c.notify(u.user_id, p_kind, p_title, p_body, p_link, p_lead, p_dedupe)
    from b2c.users u where u.is_active and (u.role = 'admin' or (p_heads and u.role = 'sales_head'))
$f$;

create or replace function b2c.log(p_type text, p_lead bigint, p_payload jsonb default '{}'::jsonb, p_actor_type text default 'user') returns void
language sql security definer set search_path = '' as $f$
  insert into b2c.events (type, lead_id, actor_type, actor_id, payload) values (p_type, p_lead, p_actor_type, b2c.uid(), coalesce(p_payload, '{}'))
$f$;

-- ---------- outbox writers ----------
/* A change to the lead in student_leads, through B2B's PATCH (contract §3.4). Non-urgent changes merge into the lead's
   one queued update (later fields win) until the 15-minute batch takes it. */
create or replace function b2c.queue_update(p_lead bigint, p_set jsonb, p_urgent boolean default false) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare v_id bigint; v_actor jsonb;
begin
  if p_set is null or p_set = '{}'::jsonb then return null; end if;
  select jsonb_build_object('id', u.user_id, 'email', u.email, 'name', u.full_name) into v_actor from b2c.users u where u.user_id = b2c.uid();
  update b2c.outbox set body = jsonb_set(body, '{set}', coalesce(body -> 'set', '{}') || p_set), occurred_at = now(),
         actor = coalesce(v_actor, actor)
   where lead_id = p_lead and kind = 'update' and status = 'queued' and urgent = p_urgent
  returning id into v_id;
  if v_id is null then
    insert into b2c.outbox (kind, lead_id, request_id, body, urgent, actor)
    values ('update', p_lead, 'b2c-u-' || gen_random_uuid(), jsonb_build_object('set', p_set), p_urgent, v_actor)
    returning id into v_id;
  end if;
  return v_id;
end $f$;

/* A call, message, meeting or note for B2B's timeline and effort roll-ups (contract §3.5). Always batched. */
create or replace function b2c.queue_activity(p_lead bigint, p_kind text, p_at timestamptz, p_outcome text default null,
                                              p_duration int default null, p_note text default null) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare v_id bigint; v_actor jsonb;
begin
  if p_kind not in ('call', 'whatsapp', 'sms', 'email', 'meeting', 'note') then raise exception 'unknown activity kind %', p_kind; end if;
  select jsonb_build_object('id', u.user_id, 'name', u.full_name) into v_actor from b2c.users u where u.user_id = b2c.uid();
  insert into b2c.outbox (kind, lead_id, request_id, body, urgent, occurred_at, actor)
  values ('activity', p_lead, 'b2c-a-' || gen_random_uuid(),
          jsonb_strip_nulls(jsonb_build_object('kind', p_kind, 'at', p_at, 'outcome', p_outcome, 'duration_seconds', p_duration, 'note', left(p_note, 2000))),
          false, p_at, v_actor)
  returning id into v_id;
  return v_id;
end $f$;

/* A signed event to POST /v1/events/b2ccrm (contract §4). Consent, opt-out and erasure are urgent. */
create or replace function b2c.queue_event(p_type text, p_lead bigint, p_data jsonb, p_urgent boolean default true) returns bigint
language plpgsql security definer set search_path = '' as $f$
declare v_id bigint; v_req text := 'b2c-evt-' || gen_random_uuid();
begin
  insert into b2c.outbox (kind, lead_id, request_id, body, urgent)
  values ('event', p_lead, v_req, jsonb_build_object('event_id', v_req, 'type', p_type, 'occurred_at', now(),
                                                    'data', coalesce(p_data, '{}') || jsonb_build_object('lead_id', p_lead)), p_urgent)
  returning id into v_id;
  return v_id;
end $f$;

-- ---------- the record cache ----------
/* Stores a record B2B sent when its version is higher than ours, and mirrors the intake phone and email as locked
   contact rows. Returns true when stored. */
create or replace function b2c.apply_record(p_lead bigint, p_version int, p_seq bigint, p_record jsonb, p_origin text default null)
returns boolean language plpgsql security definer set search_path = '' as $f$
declare v_cur int; v_phone text; v_email text; v_test boolean;
begin
  if p_record is null or p_lead is null then return false; end if;
  select version into v_cur from b2c.lead_records where lead_id = p_lead for update;
  if v_cur is not null and v_cur >= coalesce(p_version, 0) then return false; end if;
  v_phone := p_record -> 'student' ->> 'phone';
  v_email := lower(nullif(trim(p_record -> 'student' ->> 'email'), ''));
  v_test := coalesce((p_record ->> 'is_test')::boolean, false) or b2c.is_test_phone(v_phone);
  insert into b2c.lead_records (lead_id, version, seq, record, held_by_b2c, is_test, deleted, merged_into_id, origin, received_at)
  values (p_lead, coalesce(p_version, 0), p_seq, p_record, coalesce((p_record ->> 'held_by_b2c')::boolean, false), v_test,
          coalesce((p_record ->> 'deleted')::boolean, false), nullif(p_record ->> 'merged_into_id', '')::bigint, p_origin, now())
  on conflict (lead_id) do update set version = excluded.version, seq = excluded.seq, record = excluded.record,
         held_by_b2c = excluded.held_by_b2c, is_test = excluded.is_test, deleted = excluded.deleted,
         merged_into_id = excluded.merged_into_id, origin = excluded.origin, received_at = now();
  perform set_config('b2c.trusted', 'on', true);
  if v_phone is not null and b2c.norm_phone(v_phone) is not null then
    insert into b2c.lead_contacts (lead_id, kind, value, value_norm, label, origin, primary_call, primary_wa)
    select p_lead, 'phone', v_phone, b2c.norm_phone(v_phone), 'intake', 'intake',
           not exists (select 1 from b2c.lead_contacts c where c.lead_id = p_lead and c.primary_call and c.removed_at is null),
           not exists (select 1 from b2c.lead_contacts c where c.lead_id = p_lead and c.primary_wa and c.removed_at is null)
    on conflict (lead_id, kind, value_norm) do update set origin = 'intake', label = 'intake';
  end if;
  if v_email is not null then
    insert into b2c.lead_contacts (lead_id, kind, value, value_norm, label, origin, primary_email)
    select p_lead, 'email', v_email, v_email, 'intake', 'intake',
           not exists (select 1 from b2c.lead_contacts c where c.lead_id = p_lead and c.primary_email and c.removed_at is null)
    on conflict (lead_id, kind, value_norm) do update set origin = 'intake', label = 'intake';
  end if;
  perform set_config('b2c.trusted', 'off', true);
  update b2c.leads_state set is_test = v_test, updated_at = now() where lead_id = p_lead and is_test is distinct from v_test;
  return true;
end $f$;

-- ---------- closing a lead's B2C work ----------
create or replace function b2c.close_lead(p_lead bigint, p_status text, p_reason text) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.leads_state set status = p_status, closed_at = case when p_status = 'closed' then now() else closed_at end,
         closed_reason = p_reason, journey = null, updated_at = now()
   where lead_id = p_lead;
  update b2c.tasks set status = 'cancelled', done_at = now(), outcome = 'cancelled: ' || p_reason
   where lead_id = p_lead and status = 'open';
end $f$;

-- ---------- envelopes ----------
create or replace function b2c.handoff_receive(p_env jsonb, p_via text default 'webhook') returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_id text := p_env ->> 'id'; v_new boolean;
begin
  if v_id is null or p_env ->> 'type' is null then raise exception 'envelope needs id and type'; end if;
  insert into b2c.inbox (envelope_id, type, lead_id, occurred_at, payload, via)
  values (v_id, p_env ->> 'type', nullif(p_env ->> 'lead_id', '')::bigint, nullif(p_env ->> 'occurred_at', '')::timestamptz, p_env, p_via)
  on conflict (envelope_id) do nothing
  returning true into v_new;
  if not coalesce(v_new, false) then return jsonb_build_object('status', 'duplicate'); end if;
  return b2c.apply_envelope(v_id);
end $f$;

create or replace function b2c.apply_envelope(p_id text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare
  e b2c.inbox; d jsonb; v_type text; v_lead bigint; s b2c.leads_state; x jsonb; v_out jsonb := '{}'::jsonb; v_reason text; v_lane text;
  v_sub b2c.sub_stages; v_test boolean;
begin
  select * into e from b2c.inbox where envelope_id = p_id for update;
  if e.envelope_id is null then raise exception 'no such envelope'; end if;
  if e.status = 'applied' then return jsonb_build_object('status', 'applied'); end if;
  d := coalesce(e.payload -> 'data', '{}'); v_type := e.type; v_lead := e.lead_id;
  update b2c.inbox set attempts = attempts + 1 where envelope_id = p_id;
  begin
    if v_type = 'b2c.lead_upserted' then
      perform b2c.apply_record(v_lead, (d ->> 'version')::int, (d ->> 'seq')::bigint, d -> 'record', d ->> 'origin');

    elsif v_type = 'b2c.leads_batch' then
      for x in select * from jsonb_array_elements(coalesce(d -> 'leads', '[]')) loop
        if x ->> 'type' = 'b2c.lead_released' then
          perform b2c.apply_released((x ->> 'lead_id')::bigint, x -> 'record');
        else
          perform b2c.apply_record((x ->> 'lead_id')::bigint, (x ->> 'version')::int, (x ->> 'seq')::bigint, x -> 'record', x ->> 'origin');
        end if;
      end loop;

    elsif v_type = 'b2c.lead_released' then
      perform b2c.apply_released(v_lead, d -> 'record');

    elsif v_type = 'b2c.lead_handed_off' then
      v_reason := d ->> 'reason'; v_lane := coalesce(d ->> 'b2c_lane', 'sales');
      v_test := coalesce((e.payload ->> 'test')::boolean, false) or coalesce((d ->> 'test')::boolean, false);
      insert into b2c.leads_state (lead_id, lane, status, handoff_reason, cause, allocation_id, handoff_event_id, handed_off_at, handling,
                                   partner_bar_reason, providers, b2c_actions, missing, partner_lost, is_test,
                                   pool_entered_at, pool_reason, first_message_due_at, lost_by, hot)
      values (v_lead, v_lane, case when v_lane = 'nurture' then 'pool' else 'active' end, v_reason, d ->> 'cause',
              (d ->> 'allocation_id')::bigint, e.envelope_id, coalesce(e.occurred_at, now()), coalesce(d -> 'handling', '{}'),
              d -> 'partner_bar' ->> 'reason', coalesce(d -> 'already_with_providers', '[]'), coalesce(d -> 'b2c_actions', '[]'),
              coalesce(d -> 'missing', '[]'), d -> 'lost', v_test,
              case when v_lane = 'nurture' then now() end, case when v_lane = 'nurture' then v_reason end,
              case when v_reason = 'partner_lost' then nullif(d ->> 'nurture_first_message_at', '')::timestamptz end,
              case when v_reason = 'partner_lost' then 'partner' end,
              coalesce(v_reason = 'duplicate_cascade' or d -> 'handling' ->> 'assignment' = 'round_robin_now', false))
      on conflict (lead_id) do update set
        lane = excluded.lane,
        status = excluded.status,
        handoff_reason = excluded.handoff_reason, cause = excluded.cause, allocation_id = excluded.allocation_id,
        handoff_event_id = excluded.handoff_event_id, handed_off_at = excluded.handed_off_at, handling = excluded.handling,
        partner_bar_reason = coalesce(excluded.partner_bar_reason, b2c.leads_state.partner_bar_reason),
        providers = case when excluded.providers <> '[]'::jsonb then excluded.providers else b2c.leads_state.providers end,
        b2c_actions = excluded.b2c_actions, missing = excluded.missing, partner_lost = coalesce(excluded.partner_lost, b2c.leads_state.partner_lost),
        is_test = excluded.is_test,
        pool_entered_at = case when excluded.lane = 'nurture' then now() else b2c.leads_state.pool_entered_at end,
        pool_reason = case when excluded.lane = 'nurture' then excluded.pool_reason else b2c.leads_state.pool_reason end,
        first_message_due_at = excluded.first_message_due_at,
        lost_by = coalesce(excluded.lost_by, b2c.leads_state.lost_by),
        hot = excluded.hot,
        -- a new hand-off reopens a closed lead (re-enquiry after a requalification, manual_route_failed …)
        closed_at = null, closed_reason = null, released_at = null, routing_requested_at = null,
        previous_owner_id = coalesce(b2c.leads_state.owner_id, b2c.leads_state.previous_owner_id),
        owner_id = case when excluded.lane = 'nurture' then null else b2c.leads_state.owner_id end,
        updated_at = now();
      insert into b2c.activities (lead_id, kind, body, meta, at)
      values (v_lead, 'handoff', 'Handed to B2C: ' || coalesce(v_reason, '?') || coalesce(' (' || (d ->> 'cause') || ')', '') || ', ' || v_lane || ' lane',
              jsonb_build_object('envelope', e.envelope_id, 'reason', v_reason, 'lane', v_lane), coalesce(e.occurred_at, now()));
      if v_lane = 'sales' then
        v_out := b2c.allocate(v_lead, case when v_reason = 'manual_route_failed' then 'returned_from_partners' else 'handoff' end);
      elsif d -> 'b2c_actions' ? 'welcome_explore_programmes' then
        perform b2c.queue_system_template(v_lead, 'explore_programmes', 'welcome');
      end if;

    elsif v_type = 'b2c.lead_reenquired' then
      select * into s from b2c.leads_state where lead_id = v_lead;
      update b2c.leads_state set reenquired_at = now(), updated_at = now() where lead_id = v_lead;
      insert into b2c.activities (lead_id, kind, body, meta, at)
      values (v_lead, 'reenquiry', 'New enquiry: ' || coalesce(d -> 'what' ->> 'source_system', '') || ' ' || coalesce(d -> 'what' ->> 'event_type', ''),
              d, coalesce(e.occurred_at, now()));
      if s.owner_id is not null and s.status = 'active' then
        perform b2c.notify(s.owner_id, 'reenquiry', 'New enquiry from a lead you own', coalesce(d -> 'what' ->> 'source', 'A new form or message'),
                           '/s/leads/' || v_lead, v_lead, 'reenq:' || e.envelope_id);
      elsif s.lead_id is not null and s.status = 'pool' and coalesce(s.pool_reason, '') in ('partner_lost', 'counsellor_lost') then
        v_out := b2c.reengage(v_lead, case when coalesce((d ->> 'interest')::boolean, false) then 'witty_interest' else 'new_enquiry' end);
      elsif s.lead_id is not null and s.status = 'active' and s.owner_id is null then
        v_out := b2c.allocate(v_lead, 're_enquiry');
      end if;

    elsif v_type = 'b2c.lead_requalified' then
      perform b2c.close_lead(v_lead, 'closed', 'requalified');
      insert into b2c.activities (lead_id, kind, body, meta, at)
      values (v_lead, 'system', 'Qualified: back to partner routing (' || coalesce(d ->> 'destination', '?') || ')', d, coalesce(e.occurred_at, now()));

    elsif v_type = 'b2c.lead_reengaged' then
      update b2c.leads_state set missing = coalesce(d -> 'missing', missing), tags = (select array(select distinct unnest(tags || array['to_qualify']))), updated_at = now()
       where lead_id = v_lead;
      insert into b2c.activities (lead_id, kind, body, meta, at)
      values (v_lead, 'reengaged', 'Re-engaged, still missing: ' || coalesce((select string_agg(m, ', ') from jsonb_array_elements_text(d -> 'missing') m), '?'), d, coalesce(e.occurred_at, now()));

    elsif v_type = 'b2c.consent_requested' then
      insert into b2c.consent_requests (request_id, lead_id, context, programme, text_body, text_version, expires_at)
      values ((d ->> 'request_id')::bigint, v_lead, d ->> 'context', d ->> 'programme', d ->> 'text', d ->> 'text_version', nullif(d ->> 'expires_at', '')::timestamptz)
      on conflict (request_id) do nothing;
      perform b2c.queue_consent_request((d ->> 'request_id')::bigint);

    elsif v_type = 'b2c.consent_closed' then
      update b2c.consent_requests set status = coalesce(d ->> 'status', status), answer = coalesce(d ->> 'answer', answer),
             closed_at = coalesce(nullif(d ->> 'closed_at', '')::timestamptz, now()), close_why = d ->> 'why'
       where request_id = (d ->> 'request_id')::bigint;
      update b2c.send_queue set status = 'cancelled' where consent_request_id = (d ->> 'request_id')::bigint and status = 'queued';

    elsif v_type = 'b2c.lead_flagged' then
      update b2c.leads_state set flagged = coalesce(d ->> 'classification', 'flagged'), updated_at = now() where lead_id = v_lead;
      perform b2c.notify_admins('flagged', 'Lead flagged: ' || coalesce(d ->> 'classification', ''), 'Review it: close as junk or keep it.',
                                '/w/leads/' || v_lead, v_lead, 'flag:' || e.envelope_id);

    elsif v_type = 'b2c.lead_close_agreed' then
      perform b2c.notify_admins('close_agreed', 'A partner agreed to stop working a lead you hold', null, '/w/leads/' || v_lead, v_lead, 'close:' || e.envelope_id);

    elsif v_type = 'b2b.lead_routed_to_partner' then
      update b2c.leads_state set routed_to_partner_at = now(), updated_at = now() where lead_id = v_lead;
      perform b2c.close_lead(v_lead, 'closed', 'routed_to_partner');
      insert into b2c.activities (lead_id, kind, body, meta, at)
      values (v_lead, 'system', 'Accepted by a partner: closed in B2C', d, coalesce(e.occurred_at, now()));

    elsif v_type = 'ping' then
      null;
    else
      update b2c.inbox set status = 'ignored', applied_at = now() where envelope_id = p_id;
      return jsonb_build_object('status', 'ignored');
    end if;
    update b2c.inbox set status = 'applied', applied_at = now(), error = null where envelope_id = p_id;
    return jsonb_build_object('status', 'applied') || coalesce(v_out, '{}');
  exception when others then
    update b2c.inbox set status = 'error', error = left(sqlerrm, 500) where envelope_id = p_id;
    return jsonb_build_object('status', 'error', 'error', sqlerrm);
  end;
end $f$;

create or replace function b2c.apply_released(p_lead bigint, p_record jsonb) returns void
language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.lead_records set held_by_b2c = false,
         deleted = coalesce((p_record ->> 'deleted')::boolean, deleted),
         merged_into_id = coalesce(nullif(p_record ->> 'merged_into_id', '')::bigint, merged_into_id), received_at = now()
   where lead_id = p_lead;
  update b2c.leads_state set released_at = now(), updated_at = now() where lead_id = p_lead;
  perform b2c.close_lead(p_lead, 'closed', 'released');
end $f$;

/* Envelopes stuck in 'stored' or 'error' are retried by the minute job, up to 8 times. */
create or replace function b2c.inbox_retry(p_limit int default 50) returns int language plpgsql security definer set search_path = '' as $f$
declare r record; n int := 0;
begin
  for r in select envelope_id from b2c.inbox where status in ('stored', 'error') and attempts < 8 order by received_at limit p_limit loop
    perform b2c.apply_envelope(r.envelope_id); n := n + 1;
  end loop;
  return n;
end $f$;

-- ---------- outbox: what the app sends ----------
/* Claims due items. p_mode 'urgent': urgent items only (every minute). 'batch': everything due (every 15 minutes). */
create or replace function b2c.outbox_take(p_mode text, p_limit int default 400) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with c as (
    select id from b2c.outbox
     where status = 'queued' and next_attempt_at <= now() and (p_mode = 'batch' or urgent)
     order by urgent desc, occurred_at limit p_limit for update skip locked),
  u as (
    update b2c.outbox o set status = 'sending', attempts = attempts + 1, sent_at = now()
      from c where o.id = c.id
    returning o.id, o.kind, o.lead_id, o.request_id, o.body, o.occurred_at, o.actor, o.urgent)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'kind', u.kind, 'lead_id', u.lead_id, 'request_id', u.request_id,
                                               'body', u.body, 'occurred_at', u.occurred_at, 'actor', u.actor, 'urgent', u.urgent)
                            order by u.occurred_at), '[]')
    into v from u;
  if p_mode = 'batch' then
    insert into b2c.sync_state (key, value) values ('last_batch_at', to_jsonb(now()))
    on conflict (key) do update set value = excluded.value, updated_at = now();
  end if;
  return v;
end $f$;

/* Results from the app, one per item: {id, ok, status (HTTP), answer}. 2xx → applied (and the returned record is cached);
   409 → conflict; 422 → refused (the refused fields shown to the person); 5xx or no answer → retry with backoff;
   after 8 attempts → failed and the Admin is alerted. */
create or replace function b2c.outbox_done(p_results jsonb) returns int language plpgsql security definer set search_path = '' as $f$
declare r jsonb; o b2c.outbox; v_status int; n int := 0; v_backoff int[] := array[1, 2, 5, 15, 30, 60, 120, 240];
begin
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]')) loop
    select * into o from b2c.outbox where id = (r ->> 'id')::bigint for update;
    continue when o.id is null or o.status <> 'sending';
    v_status := coalesce((r ->> 'status')::int, 0);
    if coalesce((r ->> 'ok')::boolean, false) then
      update b2c.outbox set status = 'applied', answer = r -> 'answer', done_at = now() where id = o.id;
      perform b2c.outbox_after(o.id, true);
      if r -> 'answer' -> 'record' is not null then
        perform b2c.apply_record(o.lead_id, (r -> 'answer' ->> 'version')::int, null, r -> 'answer' -> 'record', 'b2c:' || o.request_id);
      end if;
    elsif v_status = 409 then
      update b2c.outbox set status = 'conflict', answer = r -> 'answer', done_at = now() where id = o.id;
      perform b2c.notify_admins('sync_conflict', 'A change could not be saved to the master lead table', coalesce(r -> 'answer' ->> 'error', 'conflict'),
                                '/w/leads/' || o.lead_id, o.lead_id, 'conflict:' || o.id);
    elsif v_status in (400, 404, 410, 422) then
      update b2c.outbox set status = 'refused', answer = r -> 'answer', done_at = now() where id = o.id;
      perform b2c.outbox_after(o.id, false);
      perform b2c.notify_admins('sync_refused', 'The B2B CRM refused a change', coalesce(r -> 'answer' ->> 'error', ''),
                                '/w/connectors', o.lead_id, 'refused:' || o.id);
    elsif o.attempts >= 8 then
      update b2c.outbox set status = 'failed', answer = r -> 'answer', done_at = now() where id = o.id;
      perform b2c.notify_admins('sync_failed', 'A change to the B2B CRM failed 8 times', coalesce(r -> 'answer' ->> 'error', ''),
                                '/w/connectors', o.lead_id, 'failed:' || o.id);
    else
      update b2c.outbox set status = 'queued', answer = r -> 'answer',
             next_attempt_at = now() + make_interval(mins => v_backoff[least(o.attempts, 8)]) where id = o.id;
    end if;
    n := n + 1;
  end loop;
  return n;
end $f$;

/* Items left in 'sending' for 10 minutes (the app crashed mid-call) go back to the queue; request_id makes a resend safe. */
create or replace function b2c.outbox_unstick() returns int language sql security definer set search_path = '' as $f$
  with u as (update b2c.outbox set status = 'queued', next_attempt_at = now() where status = 'sending' and sent_at < now() - interval '10 minutes' returning 1)
  select count(*)::int from u
$f$;

create or replace function b2c.sync_get(p_key text) returns jsonb language sql stable security definer set search_path = '' as $f$
  select value from b2c.sync_state where key = p_key
$f$;
create or replace function b2c.sync_set(p_key text, p_value jsonb) returns void language sql security definer set search_path = '' as $f$
  insert into b2c.sync_state (key, value) values (p_key, p_value) on conflict (key) do update set value = excluded.value, updated_at = now()
$f$;

-- ---------- grants ----------
grant select on b2c.notifications to authenticated;
do $p$ begin
  if not exists (select 1 from pg_policies where schemaname = 'b2c' and tablename = 'notifications' and policyname = 'own notifications') then
    create policy "own notifications" on b2c.notifications for select to authenticated using (user_id = (select b2c.uid()));
  end if;
end $p$;
revoke all on function b2c.handoff_receive(jsonb, text), b2c.apply_envelope(text), b2c.apply_record(bigint, int, bigint, jsonb, text),
  b2c.apply_released(bigint, jsonb), b2c.inbox_retry(int), b2c.outbox_take(text, int), b2c.outbox_done(jsonb), b2c.outbox_unstick(),
  b2c.sync_get(text), b2c.sync_set(text, jsonb), b2c.queue_update(bigint, jsonb, boolean), b2c.queue_activity(bigint, text, timestamptz, text, int, text),
  b2c.queue_event(text, bigint, jsonb, boolean), b2c.notify(uuid, text, text, text, text, bigint, text),
  b2c.notify_admins(text, text, text, text, bigint, text, boolean), b2c.close_lead(bigint, text, text), b2c.log(text, bigint, jsonb, text) from public, authenticated;
grant execute on function b2c.handoff_receive(jsonb, text), b2c.apply_envelope(text), b2c.inbox_retry(int), b2c.outbox_take(text, int),
  b2c.outbox_done(jsonb), b2c.outbox_unstick(), b2c.sync_get(text), b2c.sync_set(text, jsonb), b2c.apply_record(bigint, int, bigint, jsonb, text) to service_role;
grant all on all tables in schema b2c to service_role;
