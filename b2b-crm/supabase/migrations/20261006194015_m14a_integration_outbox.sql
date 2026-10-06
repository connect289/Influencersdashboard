-- M14a: the integration hub (spec A5 rule 5, Addendum 1 §2). Other products (the B2C CRM first; later the influencer
-- dashboard and the website) register a webhook endpoint and subscribe to published events. Every published event in
-- b2b.events is copied into b2b.integration_outbox once per subscribed endpoint, and b2b.outbox_tick (pg_cron, every
-- 15 seconds) delivers it with pg_net: signed like partner pushes (HMAC-SHA256 of "<timestamp>.<body>"), retried with
-- back-off, then dead-lettered with an alert. An endpoint receives nothing until the Admin activates it.

create table if not exists b2b.webhook_endpoints (
  id               bigint generated always as identity primary key,
  name             text not null check (length(trim(name)) between 2 and 80),
  consumer         text not null check (consumer in ('b2c_crm', 'influencer_dashboard', 'website', 'other')),
  url              text not null check (url ~ '^https://[^\s]+$' and length(url) <= 500),
  events           text[] not null check (cardinality(events) between 1 and 30),
  secret_id        uuid,
  active           boolean not null default false,
  last_success_at  timestamptz,
  last_failure_at  timestamptz,
  last_error       text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index if not exists webhook_endpoints_one_b2c on b2b.webhook_endpoints (consumer) where consumer = 'b2c_crm';

alter table b2b.integration_outbox add column if not exists endpoint_id bigint references b2b.webhook_endpoints (id) on delete restrict;
alter table b2b.integration_outbox add column if not exists source_event_id bigint;
alter table b2b.integration_outbox add column if not exists net_request_id bigint;
alter table b2b.integration_outbox add column if not exists response_status int;
create index if not exists integration_outbox_endpoint_idx on b2b.integration_outbox (endpoint_id, created_at desc);
create index if not exists integration_outbox_sending_idx on b2b.integration_outbox (id) where status = 'sending';

do $rls$
begin
  alter table b2b.webhook_endpoints enable row level security;
  if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = 'webhook_endpoints' and policyname = 'admin_read') then
    create policy admin_read on b2b.webhook_endpoints for select to authenticated using ((select b2b.is_admin()));
  end if;
  revoke all on b2b.webhook_endpoints from public, anon, authenticated;
  grant select on b2b.webhook_endpoints to authenticated;
  grant all on b2b.webhook_endpoints to service_role;
end $rls$;

/* The published form of an internal event: zero, one or two envelopes. Test leads are flagged, never hidden, so the
   B2C CRM can run its own tests on them. */
create or replace function b2b.published_events(e b2b.events)
returns table (event_type text, envelope jsonb) language plpgsql stable set search_path = '' as $$
declare
  a b2b.allocations;
  v_test boolean;
  v_base jsonb;
  v_type text;
begin
  if e.allocation_id is not null then select * into a from b2b.allocations where id = e.allocation_id; end if;
  v_test := coalesce(a.is_test, (select coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number) from public.student_leads l where l.id = e.lead_id), false);
  v_type := case e.type
    when 'lead.routed' then 'lead.allocated'
    when 'lead.accepted' then 'lead.accepted'
    when 'b2c.lead_handed_off' then 'b2c.lead_handed_off'
    when 'b2c.lead_reenquired' then 'b2c.lead_reenquired'
    when 'b2c.lead_flagged' then 'b2c.lead_flagged'
    when 'b2c.lead_close_agreed' then 'b2c.lead_close_agreed'
    when 'partner.stage_applied' then 'lead.status_changed'
    when 'lead.enrolled' then 'lead.enrolled'
  end;
  if v_type is null then return; end if;
  v_base := jsonb_build_object('occurred_at', e.occurred_at, 'lead_id', e.lead_id, 'test', v_test);
  event_type := v_type;
  envelope := v_base || jsonb_build_object('id', 'evt_' || e.id, 'type', v_type,
    'data', coalesce(e.payload, '{}') || jsonb_strip_nulls(jsonb_build_object('allocation_id', e.allocation_id, 'reference', a.reference,
                                                                              'partner_id', e.partner_id, 'b2c_lane', a.b2c_lane)));
  return next;
  -- Addendum 1 §1: a B2C lead that a partner accepted after a manual route to partners
  if e.type = 'lead.accepted' and a.mode = 'manual' then
    event_type := 'b2b.lead_routed_to_partner';
    envelope := v_base || jsonb_build_object('id', 'evt_' || e.id || '_r', 'type', event_type,
      'data', jsonb_build_object('allocation_id', a.id, 'reference', a.reference, 'partner_id', a.partner_id));
    return next;
  end if;
end $$;

/* Does an endpoint's subscription list cover this event type? Entries: an exact type, a prefix like 'b2c.*', or '*'. */
create or replace function b2b.event_subscribed(p_events text[], p_type text)
returns boolean language sql immutable set search_path = '' as $$
  select exists (select 1 from unnest(p_events) s
                  where s = '*' or s = p_type or (right(s, 2) = '.*' and p_type like left(s, -1) || '%'));
$$;

/* Copies a published event into the outbox for every active endpoint that subscribed. Never fails the original insert. */
create or replace function b2b.events_fanout()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r record; w b2b.webhook_endpoints;
begin
  begin
    for r in select * from b2b.published_events(new) loop
      for w in select * from b2b.webhook_endpoints where active and b2b.event_subscribed(events, r.event_type) loop
        insert into b2b.integration_outbox (event_type, target, payload, idempotency_key, endpoint_id, source_event_id)
        values (r.event_type, w.consumer, r.envelope, w.id || ':' || (r.envelope ->> 'id'), w.id, new.id)
        on conflict (idempotency_key) do nothing;
      end loop;
    end loop;
  exception when others then
    raise warning 'b2b.events_fanout: %', sqlerrm;
  end;
  return null;
end $$;

create or replace trigger events_fanout after insert on b2b.events for each row
  when (new.type in ('lead.routed', 'lead.accepted', 'b2c.lead_handed_off', 'b2c.lead_reenquired', 'b2c.lead_flagged',
                     'b2c.lead_close_agreed', 'partner.stage_applied', 'lead.enrolled'))
  execute function b2b.events_fanout();

/* Delivers due outbox rows and reads the answers of earlier ones. */
create or replace function b2b.outbox_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_backoff int[] := array[30, 120, 600, 1800, 3600, 10800, 21600];
  v_max int := 8;
  r record;
  o b2b.integration_outbox;
  w b2b.webhook_endpoints;
  v_ts text;
  v_secret text;
  v_net bigint;
  v_why text;
  v_sent int := 0;
  v_done int := 0;
begin
  perform set_config('b2b.actor', 'engine', true);
  -- 1. answers
  for r in
    -- while sending, next_attempt_at holds the time the request went out
    select x.id, x.attempts, x.endpoint_id, x.event_type, x.next_attempt_at as sent_at, h.status_code, h.content, h.timed_out, h.error_msg,
           h.id is not null as done
      from b2b.integration_outbox x left join net._http_response h on h.id = x.net_request_id
     where x.status = 'sending' limit 300
  loop
    if not r.done and r.sent_at > now() - interval '2 minutes' then continue; end if;
    if r.done and not coalesce(r.timed_out, false) and r.error_msg is null and r.status_code between 200 and 299 then
      update b2b.integration_outbox set status = 'delivered', delivered_at = now(), response_status = r.status_code, net_request_id = null, last_error = null
       where id = r.id;
      update b2b.webhook_endpoints set last_success_at = now() where id = r.endpoint_id;
    else
      v_why := left(coalesce(r.error_msg, case when not r.done or r.timed_out then 'no answer within the timeout' end,
                             'HTTP ' || r.status_code || ': ' || left(coalesce(r.content, ''), 200)), 300);
      if r.attempts >= v_max then
        update b2b.integration_outbox set status = 'dead', response_status = r.status_code, net_request_id = null, last_error = v_why where id = r.id;
        perform b2b.log_event('alert.webhook_dead', null, null, null,
                              jsonb_build_object('outbox_id', r.id, 'endpoint_id', r.endpoint_id, 'event_type', r.event_type, 'error', v_why));
      else
        update b2b.integration_outbox set status = 'failed', response_status = r.status_code, net_request_id = null, last_error = v_why,
               next_attempt_at = now() + make_interval(secs => v_backoff[least(r.attempts, array_length(v_backoff, 1))])
         where id = r.id;
      end if;
      update b2b.webhook_endpoints set last_failure_at = now(), last_error = v_why where id = r.endpoint_id;
    end if;
    v_done := v_done + 1;
  end loop;

  -- 2. due deliveries, oldest first, only to active endpoints (a test ping goes out before activation)
  for o in
    select x.* from b2b.integration_outbox x join b2b.webhook_endpoints e on e.id = x.endpoint_id
     where x.status in ('pending', 'failed') and x.next_attempt_at <= now() and (e.active or x.event_type = 'ping') and e.secret_id is not null
     order by x.id limit 100 for update of x skip locked
  loop
    begin
      select * into w from b2b.webhook_endpoints where id = o.endpoint_id;
      v_secret := b2b.partner_secret(w.secret_id);
      v_ts := floor(extract(epoch from now()))::bigint::text;
      v_net := net.http_post(
        url := w.url,
        body := o.payload,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Eduwit-Event', o.event_type,
          'X-Eduwit-Delivery', o.id::text,
          'X-Eduwit-Timestamp', v_ts,
          'X-Eduwit-Signature', 'sha256=' || encode(extensions.hmac(convert_to(v_ts || '.' || o.payload::text, 'UTF8'), convert_to(v_secret, 'UTF8'), 'sha256'), 'hex'),
          'Idempotency-Key', o.idempotency_key),
        timeout_milliseconds := 10000);
      update b2b.integration_outbox set status = 'sending', attempts = attempts + 1, net_request_id = v_net, next_attempt_at = now() where id = o.id;
      v_sent := v_sent + 1;
    exception when others then
      update b2b.integration_outbox set status = 'failed', attempts = attempts + 1, last_error = left(sqlerrm, 300),
             next_attempt_at = now() + interval '5 minutes' where id = o.id;
    end;
  end loop;
  return jsonb_build_object('answers', v_done, 'sent', v_sent);
end $$;

revoke execute on function b2b.published_events(b2b.events), b2b.events_fanout(), b2b.outbox_tick() from public, anon, authenticated;
grant execute on function b2b.published_events(b2b.events), b2b.outbox_tick() to service_role;
revoke execute on function b2b.event_subscribed(text[], text) from public, anon;
grant execute on function b2b.event_subscribed(text[], text) to authenticated, service_role;

select cron.schedule('b2b-outbox-tick', '15 seconds', 'select b2b.outbox_tick()');
