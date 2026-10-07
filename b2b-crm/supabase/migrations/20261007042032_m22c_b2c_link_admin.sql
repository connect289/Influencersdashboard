-- M22c: the B2C CRM link, part 3 (follows m22b): what the Admin sees and controls on the B2C CRM link screen.
--   b2c_link_overview       the connection checklist, live sync numbers, deliveries, writes from B2C and the activity log
--   b2c_link_settings_save  link on or off, scope (held / all), which fields B2C may write (versioned, reason required)
--   b2c_link_resync         re-sends one lead, or every lead in scope
--   b2c_link_lead           one lead as the B2C CRM sees it, with its versions, deliveries and B2C's writes
--   webhook_endpoint_save   accepts the new event types (b2c.lead_upserted, b2c.lead_released)

create or replace function b2b.webhook_endpoint_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_events text[];
  v_bad text;
  w b2b.webhook_endpoints;
  v_known text[] := array['lead.allocated', 'lead.accepted', 'lead.status_changed', 'lead.enrolled', 'b2c.lead_handed_off', 'b2c.lead_reenquired',
                          'b2c.lead_flagged', 'b2c.lead_close_agreed', 'b2c.lead_upserted', 'b2c.lead_released', 'b2b.lead_routed_to_partner',
                          'lead.*', 'b2c.*', 'b2b.*', '*'];
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
end $fn$;

create or replace function b2b.b2c_link_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  w b2b.webhook_endpoints;
  v_keys jsonb;
  v_snap text[] := array['b2c.lead_upserted', 'b2c.lead_released'];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into w from b2b.webhook_endpoints where consumer = 'b2c_crm';
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'prefix', key_prefix, 'scopes', scopes, 'last_used_at', last_used_at) order by id), '[]')
    into v_keys from b2b.api_keys where revoked_at is null and 'b2c' = any (scopes);
  return jsonb_build_object(
    'settings', cfg,
    'fields', b2b.b2c_fields(),
    'endpoint', case when w.id is not null then jsonb_build_object('id', w.id, 'name', w.name, 'url', w.url, 'active', w.active, 'events', w.events,
                       'has_secret', w.secret_id is not null, 'last_success_at', w.last_success_at, 'last_failure_at', w.last_failure_at, 'last_error', w.last_error,
                       'subscribed', b2b.event_subscribed(w.events, 'b2c.lead_upserted') and b2b.event_subscribed(w.events, 'b2c.lead_released')) end,
    'keys', v_keys,
    'checks', jsonb_build_object(
      'endpoint', w.id is not null,
      'secret', w.secret_id is not null,
      'subscribed', coalesce(b2b.event_subscribed(w.events, 'b2c.lead_upserted'), false),
      'ping', exists (select 1 from b2b.integration_outbox o where o.endpoint_id = w.id and o.event_type = 'ping' and o.status = 'delivered'),
      'active', coalesce(w.active, false),
      'key', jsonb_array_length(v_keys) > 0,
      'key_used', exists (select 1 from b2b.api_keys where revoked_at is null and 'b2c' = any (scopes) and last_used_at is not null),
      'first_delivery', exists (select 1 from b2b.integration_outbox o where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.status = 'delivered'),
      'first_write', exists (select 1 from b2b.b2c_writes where status in ('applied', 'unchanged'))),
    'sync', jsonb_build_object(
      'in_scope', (select count(*) from b2b.b2c_sync where in_scope),
      'held_now', (select count(*) from public.student_leads l where b2b.b2c_holds(l)),
      'changes_24h', (select count(*) from b2b.b2c_sync where changed_at > now() - interval '24 hours'),
      'last_change_at', (select max(changed_at) from b2b.b2c_sync),
      'last_seq', (select max(seq) from b2b.b2c_sync),
      'tick', (select value from b2b.b2c_link_state where key = 'cursor')),
    'deliveries', jsonb_build_object(
      'by_status', coalesce((select jsonb_object_agg(status, n) from (select o.status, count(*) n from b2b.integration_outbox o
                               where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.created_at > now() - interval '24 hours' group by 1) x), '{}'),
      'waiting', (select count(*) from b2b.integration_outbox o where o.endpoint_id = w.id and o.status in ('pending', 'failed', 'sending')),
      'lag_seconds_avg', (select round(avg(extract(epoch from o.delivered_at - o.created_at))::numeric, 1) from b2b.integration_outbox o
                            where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.delivered_at > now() - interval '1 hour'),
      'lag_seconds_max', (select round(max(extract(epoch from o.delivered_at - o.created_at))::numeric, 1) from b2b.integration_outbox o
                            where o.endpoint_id = w.id and o.event_type = any (v_snap) and o.delivered_at > now() - interval '1 hour')),
    'writes', jsonb_build_object(
      'by_status', coalesce((select jsonb_object_agg(kind || '.' || status, n) from (select kind, status, count(*) n from b2b.b2c_writes
                               where created_at > now() - interval '24 hours' group by 1, 2) x), '{}'),
      'last_at', (select max(created_at) from b2b.b2c_writes)),
    'log', coalesce((select jsonb_agg(x order by x ->> 'at' desc) from (
      (select jsonb_build_object('dir', 'out', 'at', s.changed_at, 'lead_id', s.lead_id, 'name', l.student_name, 'type', case when s.in_scope then 'upserted' else 'released' end,
                                 'version', s.version, 'origin', s.origin,
                                 'delivery', (select jsonb_build_object('status', o.status, 'error', o.last_error, 'attempts', o.attempts) from b2b.integration_outbox o
                                               where o.endpoint_id = w.id and o.idempotency_key = w.id || ':lead_' || s.lead_id || '_v' || s.version)) x
         from b2b.b2c_sync s left join public.student_leads l on l.id = s.lead_id order by s.changed_at desc limit 40)
      union all
      (select jsonb_build_object('dir', 'in', 'at', b.created_at, 'lead_id', b.lead_id, 'name', l.student_name, 'type', b.kind, 'status', b.status,
                                 'http_status', b.http_status, 'error', b.error, 'actor', b.actor, 'changes', b.changes, 'request_id', b.request_id,
                                 'version', b.version_after) x
         from b2b.b2c_writes b left join public.student_leads l on l.id = b.lead_id order by b.created_at desc limit 40)) y), '[]'));
end $fn$;

create or replace function b2b.b2c_link_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_scope text := coalesce(p ->> 'scope', 'held');
  v_writable jsonb := coalesce(p -> 'writable', '[]');
  v_bad text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'give a reason (it goes in the settings history)' using errcode = '22023'; end if;
  if v_scope not in ('held', 'all') then raise exception 'scope is held or all' using errcode = '22023'; end if;
  if jsonb_typeof(v_writable) <> 'array' then raise exception 'writable must be a list of fields' using errcode = '22023'; end if;
  select string_agg(x, ', ') into v_bad from jsonb_array_elements_text(v_writable) x
   where not exists (select 1 from jsonb_array_elements(b2b.b2c_fields()) f where f ->> 'field' = x and f ->> 'write' = 'b2c');
  if v_bad is not null then raise exception 'these fields cannot be written by the B2C CRM: %', v_bad using errcode = '22023'; end if;
  perform b2b.set_setting('b2c_link', jsonb_build_object('enabled', coalesce((p ->> 'enabled')::boolean, true), 'scope', v_scope,
                                                         'writable', (select coalesce(jsonb_agg(distinct x), '[]') from jsonb_array_elements_text(v_writable) x)),
                          trim(p_reason));
  return b2b.b2c_link_cfg();
end $fn$;

/* Re-sends one lead (p_lead_id) or every lead in scope (p_lead_id null). The B2C CRM applies a version only when it is
   newer than its copy, so a resend is always safe. */
create or replace function b2b.b2c_link_resync(p_lead_id bigint default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  r record;
  n int := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_lead_id is not null then
    if not exists (select 1 from public.student_leads where id = p_lead_id) then raise exception 'lead not found' using errcode = 'P0002'; end if;
    perform b2b.b2c_sync_lead(p_lead_id, true, 'resync');
    n := 1;
  else
    for r in select l.id from public.student_leads l
              where b2b.b2c_holds(l) or (cfg ->> 'scope' = 'all' and l.deleted_at is null and l.merged_into_id is null and l.anonymised_at is null)
              order by l.id limit 20000 loop
      perform b2b.b2c_sync_lead(r.id, true, 'resync');
      n := n + 1;
    end loop;
  end if;
  perform b2b.log_event('b2c.link_resync', p_lead_id, null, null, jsonb_build_object('leads', n));
  perform b2b.outbox_kick();
  return jsonb_build_object('leads', n);
end $fn$;

create or replace function b2b.b2c_link_lead(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  l public.student_leads;
  s b2b.b2c_sync;
  w b2b.webhook_endpoints;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then raise exception 'lead not found' using errcode = 'P0002'; end if;
  select * into s from b2b.b2c_sync where lead_id = l.id;
  select * into w from b2b.webhook_endpoints where consumer = 'b2c_crm';
  return jsonb_build_object(
    'lead_id', l.id, 'name', l.student_name, 'held_by_b2c', b2b.b2c_holds(l), 'shared', s.lead_id is not null and s.in_scope,
    'version', s.version, 'seq', s.seq, 'changed_at', s.changed_at, 'origin', s.origin,
    'record', b2b.b2c_record(l),
    'deliveries', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'type', o.event_type, 'version', o.payload -> 'data' -> 'version', 'status', o.status,
                                                                'attempts', o.attempts, 'error', o.last_error, 'created_at', o.created_at, 'delivered_at', o.delivered_at)
                                             order by o.id desc)
                              from (select * from b2b.integration_outbox o where o.endpoint_id = w.id and o.event_type in ('b2c.lead_upserted', 'b2c.lead_released')
                                       and (o.payload ->> 'lead_id')::bigint = l.id order by o.id desc limit 20) o), '[]'),
    'writes', coalesce((select jsonb_agg(jsonb_build_object('at', b.created_at, 'kind', b.kind, 'status', b.status, 'http_status', b.http_status, 'error', b.error,
                                                            'actor', b.actor, 'changes', b.changes, 'version', b.version_after) order by b.created_at desc)
                          from (select * from b2b.b2c_writes where lead_id = l.id order by created_at desc limit 30) b), '[]'));
end $fn$;

revoke execute on function b2b.webhook_endpoint_save(jsonb), b2b.b2c_link_overview(), b2b.b2c_link_settings_save(jsonb, text), b2b.b2c_link_resync(bigint),
                           b2b.b2c_link_lead(bigint) from public, anon;
grant execute on function b2b.webhook_endpoint_save(jsonb), b2b.b2c_link_overview(), b2b.b2c_link_settings_save(jsonb, text), b2b.b2c_link_resync(bigint),
                          b2b.b2c_link_lead(bigint) to authenticated, service_role;
