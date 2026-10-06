-- M14b: the B2C CRM contract, both directions (Addendum 1 §1, §2, §4), and the Admin side of the integration hub.
--   B2B → B2C: signed webhooks from m14a, plus GET /v1/handoffs (reconciliation) through b2b.api_b2c_handoffs.
--   B2C → B2B: POST /v1/events/b2ccrm (b2b.b2ccrm_event_ingest, HMAC with the B2C endpoint's secret) and
--              POST /v1/leads/{id}/route-to-partners (b2b.api_route_to_partners, B2C service key, reason required).
-- The B2C service key is an API key with the 'events' scope (product integrations). The B2C CRM writes its own columns
-- of student_leads (owner_user_id, assigned_at, team_id and the pipeline columns while it holds the lead); B2B records
-- its events for the timeline and analytics, applies opt-outs to its own notifications and flags erasure requests.

create table if not exists b2b.product_events (
  id           bigint generated always as identity primary key,
  source       text not null check (source in ('b2c_crm')),
  event_id     text not null,
  event_type   text not null,
  lead_id      bigint,
  raw          jsonb not null,
  status       text not null default 'received' check (status in ('received', 'applied', 'ignored', 'error')),
  result       text,
  received_at  timestamptz not null default now(),
  unique (source, event_id)
);
create index if not exists product_events_lead_idx on b2b.product_events (lead_id, received_at desc);

create table if not exists b2b.erasure_requests (
  id            bigint generated always as identity primary key,
  lead_id       bigint not null,
  source        text not null,
  requested_at  timestamptz not null default now(),
  status        text not null default 'open' check (status in ('open', 'done', 'rejected')),
  note          text,
  closed_at     timestamptz
);
create unique index if not exists erasure_requests_one_open on b2b.erasure_requests (lead_id) where status = 'open';

do $rls$
declare t text;
begin
  foreach t in array array['product_events', 'erasure_requests'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- ---------- manual route to partners: one core, two doors (the Admin, and the B2C CRM's service key) ----------

create or replace function b2b.route_to_partners_core(p_lead_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  l public.student_leads;
  a b2b.allocations;
begin
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into l from public.student_leads where id = p_lead_id for update;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  if l.consent_partner_share_at is null and not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)) then
    raise exception 'the student has not consented to sharing with partners' using errcode = '22023';
  end if;
  select * into a from b2b.allocations where lead_id = l.id and destination_type = 'in_house' and status = 'handed_off'
   order by created_at desc limit 1;
  if a.id is null or l.destination_type is distinct from 'in_house' then raise exception 'only a lead held by B2C can be sent to partners' using errcode = '22023'; end if;

  update b2b.allocations set status = 'closed', outcome = 'routed_to_partners', outcome_at = now(), updated_at = now() where id = a.id;
  update public.student_leads set destination_type = null, partner_id = null, allocation_id = null, allocated_at = null, allocation_reason = null,
         updated_by = 'b2b' where id = l.id;
  perform b2b.log_event('lead.route_to_partners', l.id, a.id, null, jsonb_build_object('reason', left(trim(p_reason), 300), 'closed_allocation', a.reference));
  return b2b.route_decide(l.id, true, trim(p_reason), 'to_partners');
end $$;

create or replace function b2b.route_to_partners(p_lead_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.can_route() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.route_to_partners_core(p_lead_id, p_reason);
end $$;

/* POST /v1/leads/{id}/route-to-partners for the B2C CRM. Answers with an HTTP status for the route handler. */
create or replace function b2b.api_route_to_partners(p_key text, p_lead_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare k jsonb; v jsonb;
begin
  k := b2b.api_key_check(p_key, 'events');
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  perform set_config('b2b.actor', 'b2c_crm', true);
  begin
    v := b2b.route_to_partners_core(p_lead_id, p_reason);
  exception when sqlstate '22023' then return jsonb_build_object('ok', false, 'status', 422, 'error', sqlerrm);
            when sqlstate 'P0002' then return jsonb_build_object('ok', false, 'status', 404, 'error', sqlerrm);
  end;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
    'destination', v ->> 'destination', 'reference', v ->> 'reference', 'partner_id', (v ->> 'partner_id')::bigint,
    'b2c_lane', v ->> 'b2c_lane', 'reason', v ->> 'reason'));
end $$;

/* GET /v1/handoffs?since=&after= : every B2C-facing event in order, the same envelopes as the webhooks. */
create or replace function b2b.api_b2c_handoffs(p_key text, p_since timestamptz, p_after bigint, p_limit int)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare k jsonb; v_rows jsonb; v_last bigint;
begin
  k := b2b.api_key_check(p_key, 'events');
  if not (k ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  -- the cursor advances past every scanned event, including ones that publish nothing to B2C
  with scanned as (
    select ev from b2b.events ev
     where ev.type in ('b2c.lead_handed_off', 'b2c.lead_reenquired', 'b2c.lead_flagged', 'b2c.lead_close_agreed', 'lead.accepted')
       and ev.id > coalesce(p_after, 0) and ev.occurred_at >= coalesce(p_since, '-infinity')
     order by ev.id limit least(greatest(coalesce(p_limit, 200), 1), 500))
  select coalesce((select jsonb_agg(p.envelope order by (s.ev).id, p.envelope ->> 'id')
                     from scanned s cross join lateral b2b.published_events(s.ev) p
                    where p.event_type like 'b2c.%' or p.event_type = 'b2b.lead_routed_to_partner'), '[]'),
         (select max((s.ev).id) from scanned s)
    into v_rows, v_last;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('events', v_rows, 'next_after', v_last));
end $$;

/* POST /v1/events/b2ccrm: signed with the B2C endpoint's secret, idempotent by event_id. */
create or replace function b2b.b2ccrm_event_ingest(p_body text, p_timestamp text, p_signature text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  w b2b.webhook_endpoints;
  j jsonb;
  v_ts bigint;
  v_type text;
  v_event_id text;
  v_lead bigint;
  v_id bigint;
  l public.student_leads;
  v_result text;
  a record;
begin
  perform set_config('b2b.actor', 'b2c_crm', true);
  select * into w from b2b.webhook_endpoints where consumer = 'b2c_crm';
  if w.id is null or w.secret_id is null then return jsonb_build_object('ok', false, 'status', 503, 'error', 'the B2C connection is not set up'); end if;
  if length(coalesce(p_body, '')) > 100000 then return jsonb_build_object('ok', false, 'status', 413, 'error', 'body too large'); end if;
  begin v_ts := p_timestamp::bigint; exception when others then v_ts := null; end;
  if v_ts is null or abs(extract(epoch from now()) - v_ts) > 300 then
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'timestamp missing or more than 5 minutes off');
  end if;
  if p_signature is distinct from 'sha256=' || encode(extensions.hmac(convert_to(p_timestamp || '.' || p_body, 'UTF8'),
                                                                     convert_to(b2b.partner_secret(w.secret_id), 'UTF8'), 'sha256'), 'hex') then
    perform b2b.log_event('alert.b2c_bad_signature', null, null, null, '{}');
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'bad signature');
  end if;
  begin j := p_body::jsonb; exception when others then return jsonb_build_object('ok', false, 'status', 400, 'error', 'body is not JSON'); end;
  v_event_id := left(nullif(trim(j ->> 'event_id'), ''), 200);
  v_type := lower(coalesce(j ->> 'type', ''));
  begin v_lead := (j -> 'data' ->> 'lead_id')::bigint; exception when others then v_lead := null; end;
  if v_event_id is null or v_type = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'event_id and type are required'); end if;

  insert into b2b.product_events (source, event_id, event_type, lead_id, raw) values ('b2c_crm', v_event_id, v_type, v_lead, j)
  on conflict (source, event_id) do nothing returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', true, 'status', 200, 'result', 'already received'); end if;

  select * into l from public.student_leads where id = v_lead;
  if v_type not in ('b2ccrm.lead_assigned', 'b2ccrm.stage_changed', 'b2ccrm.enrolled', 'b2ccrm.opted_out', 'b2ccrm.erasure_requested') then
    update b2b.product_events set status = 'ignored', result = 'unknown event type' where id = v_id;
    return jsonb_build_object('ok', true, 'status', 200, 'result', 'ignored: unknown type');
  end if;
  if l.id is null then
    update b2b.product_events set status = 'error', result = 'unknown lead_id' where id = v_id;
    return jsonb_build_object('ok', false, 'status', 404, 'error', 'unknown lead_id');
  end if;

  begin
    case v_type
      when 'b2ccrm.lead_assigned' then
        perform b2b.log_event('b2c.counsellor_assigned', l.id, l.allocation_id, null, coalesce(j -> 'data', '{}') - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.stage_changed' then
        perform b2b.log_event('b2c.stage_changed', l.id, l.allocation_id, null, coalesce(j -> 'data', '{}') - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.enrolled' then
        perform b2b.log_event('b2c.enrolled', l.id, l.allocation_id, null, coalesce(j -> 'data', '{}') - 'lead_id');
        v_result := 'recorded';
      when 'b2ccrm.opted_out' then
        perform public.lead_intake(jsonb_build_object('phone', l.whatsapp_number, 'source_system', 'b2c_crm', 'event_type', 'lead.opted_out',
                                                      'lead', jsonb_build_object('is_opted_out', true)));
        update b2b.student_notifications set status = 'cancelled', error = 'student opted out (B2C CRM)', updated_at = now()
         where lead_id = l.id and status = 'scheduled';
        -- every partner that ever received the lead must be told (adapters later; an alert for the Admin until then)
        for a in select distinct x.partner_id from b2b.allocations x where x.lead_id = l.id and x.destination_type = 'partner'
                   and x.status in ('pushed', 'accepted', 'duplicate', 'rejected', 'closed') loop
          perform b2b.log_event('alert.partner_optout_notice', l.id, null, a.partner_id, jsonb_build_object('source', 'b2c_crm'));
        end loop;
        v_result := 'opted out';
      when 'b2ccrm.erasure_requested' then
        insert into b2b.erasure_requests (lead_id, source, note) values (l.id, 'b2c_crm', left(j -> 'data' ->> 'note', 300))
        on conflict (lead_id) where status = 'open' do nothing;
        perform b2b.log_event('alert.erasure_requested', l.id, null, null, jsonb_build_object('source', 'b2c_crm'));
        v_result := 'erasure request recorded for the Admin';
    end case;
    update b2b.product_events set status = 'applied', result = v_result where id = v_id;
  exception when others then
    update b2b.product_events set status = 'error', result = left(sqlerrm, 300) where id = v_id;
    return jsonb_build_object('ok', false, 'status', 500, 'error', 'stored; it will be reviewed');
  end;
  return jsonb_build_object('ok', true, 'status', 200, 'result', v_result);
end $$;

-- ---------- Admin: endpoints, secrets, retries, the System screen ----------

create or replace function b2b.webhook_endpoint_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_events text[];
  v_bad text;
  w b2b.webhook_endpoints;
  v_known text[] := array['lead.allocated', 'lead.accepted', 'lead.status_changed', 'lead.enrolled', 'b2c.lead_handed_off', 'b2c.lead_reenquired',
                          'b2c.lead_flagged', 'b2c.lead_close_agreed', 'b2b.lead_routed_to_partner', 'lead.*', 'b2c.*', 'b2b.*', '*'];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select array_agg(distinct trim(x)) into v_events from jsonb_array_elements_text(coalesce(p -> 'events', '[]')) x where trim(x) <> '';
  if coalesce(cardinality(v_events), 0) = 0 then raise exception 'choose at least one event' using errcode = '22023'; end if;
  select string_agg(x, ', ') into v_bad from unnest(v_events) x where not x = any (v_known);
  if v_bad is not null then raise exception 'unknown event: %', v_bad using errcode = '22023'; end if;
  if coalesce(p ->> 'url', '') !~ '^https://[^\s]+$' then raise exception 'the URL must start with https://' using errcode = '22023'; end if;
  if v_id is null then
    insert into b2b.webhook_endpoints (name, consumer, url, events)
    values (trim(p ->> 'name'), coalesce(p ->> 'consumer', 'other'), trim(p ->> 'url'), v_events) returning * into w;
  else
    update b2b.webhook_endpoints set name = trim(p ->> 'name'), url = trim(p ->> 'url'), events = v_events, updated_at = now()
     where id = v_id returning * into w;
    if w.id is null then raise exception 'endpoint not found' using errcode = 'P0002'; end if;
  end if;
  perform b2b.log_event('webhook.saved', null, null, null, jsonb_build_object('endpoint_id', w.id, 'consumer', w.consumer, 'events', v_events));
  return to_jsonb(w) - 'secret_id' || jsonb_build_object('has_secret', w.secret_id is not null);
exception when unique_violation then
  raise exception 'there is already a B2C CRM endpoint; edit it instead' using errcode = '22023';
end $$;

/* The signing secret, shown once. The B2C CRM uses the same secret to sign the events it sends back. */
create or replace function b2b.webhook_endpoint_rotate_secret(p_id bigint)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare w b2b.webhook_endpoints; v_secret text := 'whsec_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into w from b2b.webhook_endpoints where id = p_id for update;
  if w.id is null then raise exception 'endpoint not found' using errcode = 'P0002'; end if;
  if w.secret_id is null then
    update b2b.webhook_endpoints set secret_id = vault.create_secret(v_secret, 'b2b_webhook_' || w.id, 'Signing secret for ' || w.name), updated_at = now() where id = w.id;
  else
    perform vault.update_secret(w.secret_id, v_secret);
  end if;
  perform b2b.log_event('webhook.secret_rotated', null, null, null, jsonb_build_object('endpoint_id', w.id));
  return v_secret;
end $$;

create or replace function b2b.webhook_endpoint_set_active(p_id bigint, p_active boolean, p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare w b2b.webhook_endpoints;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into w from b2b.webhook_endpoints where id = p_id for update;
  if w.id is null then raise exception 'endpoint not found' using errcode = 'P0002'; end if;
  if p_active and w.secret_id is null then raise exception 'generate the signing secret first' using errcode = '22023'; end if;
  update b2b.webhook_endpoints set active = p_active, updated_at = now() where id = w.id;
  perform b2b.log_event('webhook.' || case when p_active then 'activated' else 'paused' end, null, null, null,
                        jsonb_build_object('endpoint_id', w.id, 'reason', left(trim(p_reason), 300)));
end $$;

/* Queue a signed test event for one endpoint (delivered even before activation, so the receiver can be checked). */
create or replace function b2b.webhook_test(p_id bigint)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare w b2b.webhook_endpoints; v_id bigint; v_key text := 'test_' || encode(extensions.gen_random_bytes(8), 'hex');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into w from b2b.webhook_endpoints where id = p_id;
  if w.id is null then raise exception 'endpoint not found' using errcode = 'P0002'; end if;
  if w.secret_id is null then raise exception 'generate the signing secret first' using errcode = '22023'; end if;
  insert into b2b.integration_outbox (event_type, target, payload, idempotency_key, endpoint_id)
  values ('ping', w.consumer, jsonb_build_object('id', 'evt_' || v_key, 'type', 'ping', 'occurred_at', now(), 'lead_id', null, 'test', true, 'data', '{}'::jsonb),
          w.id || ':' || v_key, w.id)
  returning id into v_id;
  return v_id;
end $$;

create or replace function b2b.outbox_retry(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.integration_outbox set status = 'pending', attempts = 0, next_attempt_at = now(), last_error = null where id = p_id and status in ('dead', 'failed');
  if not found then raise exception 'only a failed or dead delivery can be sent again' using errcode = '22023'; end if;
  perform b2b.log_event('webhook.retry', null, null, null, jsonb_build_object('outbox_id', p_id));
end $$;

/* The System screen: API keys (never their hashes), endpoints, deliveries, events from products, jobs. */
create or replace function b2b.system_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'api_keys', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'scopes', k.scopes, 'prefix', k.key_prefix, 'created_at', k.created_at,
                                                              'last_used_at', k.last_used_at, 'revoked_at', k.revoked_at) order by k.revoked_at nulls first, k.created_at desc)
                          from b2b.api_keys k), '[]'),
    'endpoints', coalesce((select jsonb_agg(to_jsonb(w) - 'secret_id' || jsonb_build_object('has_secret', w.secret_id is not null,
                             'pending', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status in ('pending', 'failed', 'sending')),
                             'dead', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status = 'dead'),
                             'delivered_24h', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status = 'delivered' and o.delivered_at > now() - interval '1 day'))
                           order by w.id) from b2b.webhook_endpoints w), '[]'),
    'deliveries', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'event_type', o.event_type, 'endpoint_id', o.endpoint_id,
                              'endpoint', (select w.name from b2b.webhook_endpoints w where w.id = o.endpoint_id), 'status', o.status, 'attempts', o.attempts,
                              'response_status', o.response_status, 'last_error', o.last_error, 'created_at', o.created_at, 'delivered_at', o.delivered_at,
                              'next_attempt_at', o.next_attempt_at, 'lead_id', (o.payload ->> 'lead_id')::bigint) order by o.id desc)
                            from (select * from b2b.integration_outbox where endpoint_id is not null order by id desc limit 100) o), '[]'),
    'product_events', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'source', e.source, 'event_type', e.event_type, 'lead_id', e.lead_id,
                                  'status', e.status, 'result', e.result, 'received_at', e.received_at) order by e.id desc)
                                from (select * from b2b.product_events order by id desc limit 50) e), '[]'),
    'erasure_open', (select count(*) from b2b.erasure_requests where status = 'open'),
    'jobs', coalesce((select jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'active', j.active,
                         'last_status', (select d.status from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1),
                         'last_run', (select d.start_time from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1),
                         'last_error', (select left(d.return_message, 200) from cron.job_run_details d where d.jobid = j.jobid and d.status = 'failed'
                                          and d.start_time > now() - interval '1 day' order by d.start_time desc limit 1),
                         'failed_24h', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.status = 'failed' and d.start_time > now() - interval '1 day'))
                       order by j.jobname) from cron.job j where j.jobname like 'b2b-%'), '[]'));
end $$;

revoke execute on function b2b.route_to_partners_core(bigint, text) from public, anon, authenticated;
grant execute on function b2b.route_to_partners_core(bigint, text) to service_role;
revoke execute on function b2b.api_route_to_partners(text, bigint, text), b2b.api_b2c_handoffs(text, timestamptz, bigint, int),
                           b2b.b2ccrm_event_ingest(text, text, text) from public;
grant execute on function b2b.api_route_to_partners(text, bigint, text), b2b.api_b2c_handoffs(text, timestamptz, bigint, int),
                          b2b.b2ccrm_event_ingest(text, text, text) to anon, authenticated, service_role;
revoke execute on function b2b.webhook_endpoint_save(jsonb), b2b.webhook_endpoint_rotate_secret(bigint), b2b.webhook_endpoint_set_active(bigint, boolean, text),
                           b2b.webhook_test(bigint), b2b.outbox_retry(bigint), b2b.system_overview() from public, anon;
grant execute on function b2b.webhook_endpoint_save(jsonb), b2b.webhook_endpoint_rotate_secret(bigint), b2b.webhook_endpoint_set_active(bigint, boolean, text),
                          b2b.webhook_test(bigint), b2b.outbox_retry(bigint), b2b.system_overview() to authenticated, service_role;
