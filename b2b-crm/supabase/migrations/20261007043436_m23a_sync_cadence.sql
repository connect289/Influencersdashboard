-- M23a: production sync cadence (Vikas, 7 Oct): real-time syncing with partner CRMs and the B2C CRM makes too many paid
-- API calls, so once a connection is integrated and tested it syncs every 15 minutes (settings sync.interval_minutes).
--   sync_minutes       the production interval (5 to 60 minutes, default 15)
--   B2C CRM link       settings b2c_link.delivery: 'realtime' (integration and testing, the default) or 'batched' (production):
--                      versions are still computed every 5 seconds inside the database (no API call), but real students'
--                      changes go out as one b2c.leads_batch webhook per interval (b2c_batch_send), each lead once at its
--                      newest version; test leads stay real time so testing goes on. The change feed and reads are unchanged.
--   Partner CRMs       live polling defaults to the interval (was 10 minutes); sandboxes poll every 2 minutes while testing.
--                      A partner's own poll_minutes still wins.
-- Not batched, on purpose: pushing a new lead to its partner (one create call per lead either way; speed to lead and the
-- partner's SLA depend on it) and messages to students.

insert into b2b.settings (key, value) values ('sync', '{"interval_minutes": 15}') on conflict (key) do nothing;
insert into b2b.b2c_link_state (key, value) values ('batch', jsonb_build_object('seq', coalesce((select max(seq) from b2b.b2c_sync), 0), 'at', now()))
on conflict (key) do nothing;

create or replace function b2b.sync_minutes()
returns int language sql stable set search_path = '' as $fn$
  select least(greatest(coalesce((select (value ->> 'interval_minutes')::int from b2b.settings where key = 'sync'), 15), 5), 60);
$fn$;

/* Batched delivery to the B2C CRM: every lead whose version changed since the last batch, once, at its newest version,
   100 per webhook. Due every sync interval (p_force: now). Does nothing in real-time delivery. */
create or replace function b2b.b2c_batch_send(p_force boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  st jsonb := coalesce((select value from b2b.b2c_link_state where key = 'batch'), '{}');
  v_from bigint := coalesce((st ->> 'seq')::bigint, 0);
  v_to bigint;
  v_n int := 0;
  v_batches int := 0;
  v_items jsonb;
  env jsonb;
  w b2b.webhook_endpoints;
  r record;
begin
  if cfg ->> 'delivery' is distinct from 'batched' or not coalesce((cfg ->> 'enabled')::boolean, true) then return jsonb_build_object('batches', 0, 'why', 'real time'); end if;
  if not p_force and coalesce((st ->> 'at')::timestamptz, '-infinity') > now() - make_interval(mins => b2b.sync_minutes()) then
    return jsonb_build_object('batches', 0, 'next_at', (st ->> 'at')::timestamptz + make_interval(mins => b2b.sync_minutes()));
  end if;
  select max(seq) into v_to from b2b.b2c_sync;
  v_to := coalesce(v_to, v_from);
  if v_to > v_from then
    select * into w from b2b.webhook_endpoints where consumer = 'b2c_crm' and active and b2b.event_subscribed(events, 'b2c.leads_batch');
    if w.id is not null then
      for r in
        select (row_number() over (order by s.seq) - 1) / 100 grp,
               jsonb_build_object('type', case when s.in_scope then 'b2c.lead_upserted' else 'b2c.lead_released' end, 'lead_id', s.lead_id,
                                  'version', s.version, 'seq', s.seq, 'changed_at', s.changed_at, 'origin', s.origin,
                                  'record', case when s.in_scope then (select b2b.b2c_record(l) from public.student_leads l where l.id = s.lead_id)
                                                 else jsonb_build_object('id', s.lead_id, 'held_by_b2c', false) end) item
          from b2b.b2c_sync s where s.seq > v_from and s.seq <= v_to order by s.seq
      loop
        v_n := v_n + 1;
        insert into b2b.integration_outbox (event_type, target, payload, idempotency_key, endpoint_id)
        values ('b2c.leads_batch', w.consumer,
                jsonb_build_object('id', 'batch_' || v_from || '_' || v_to || '_' || r.grp, 'type', 'b2c.leads_batch', 'occurred_at', now(), 'lead_id', null, 'test', false,
                                   'data', jsonb_build_object('from_seq', v_from, 'to_seq', v_to, 'part', r.grp + 1, 'leads', jsonb_build_array(r.item))),
                w.id || ':batch_' || v_from || '_' || v_to || '_' || r.grp, w.id)
        on conflict (idempotency_key) do update
          set payload = jsonb_set(b2b.integration_outbox.payload, '{data,leads}', (b2b.integration_outbox.payload -> 'data' -> 'leads') || jsonb_build_array(r.item));
      end loop;
      select count(*) into v_batches from b2b.integration_outbox where endpoint_id = w.id and idempotency_key like w.id || ':batch_' || v_from || '_' || v_to || '_%';
    end if;
  end if;
  update b2b.b2c_link_state set value = jsonb_build_object('seq', v_to, 'at', now(), 'leads', v_n, 'batches', v_batches), updated_at = now() where key = 'batch';
  return jsonb_build_object('batches', v_batches, 'leads', v_n, 'from_seq', v_from, 'to_seq', v_to);
end $fn$;

create or replace function b2b.b2c_sync_lead(p_lead_id bigint, p_force boolean default false, p_origin text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  l public.student_leads;
  prev b2b.b2c_sync;
  v_scope boolean;
  rec jsonb;
  v_hash text;
  v_seq bigint;
  v_ver int;
  v_type text;
  env jsonb;
  w b2b.webhook_endpoints;
begin
  if not coalesce((cfg ->> 'enabled')::boolean, true) then return jsonb_build_object('changed', false, 'why', 'link off'); end if;
  select * into l from public.student_leads where id = p_lead_id;
  select * into prev from b2b.b2c_sync where lead_id = p_lead_id for update;
  if l.id is null then
    if prev.lead_id is null or not prev.in_scope then return jsonb_build_object('changed', false); end if;
    v_scope := false;
    rec := jsonb_build_object('id', p_lead_id, 'deleted', true, 'held_by_b2c', false);
  else
    v_scope := b2b.b2c_holds(l) or (cfg ->> 'scope' = 'all' and l.deleted_at is null and l.merged_into_id is null and l.anonymised_at is null);
    if not v_scope and (prev.lead_id is null or (not prev.in_scope and not p_force)) then return jsonb_build_object('changed', false); end if;
    rec := case when v_scope then b2b.b2c_record(l)
                else jsonb_build_object('id', l.id, 'held_by_b2c', false, 'deleted', l.deleted_at is not null or l.anonymised_at is not null,
                                        'merged_into_id', l.merged_into_id,
                                        'allocation', jsonb_build_object('destination', l.destination_type, 'reason', l.allocation_reason,
                                                                         'allocated_at', l.allocated_at)) end;
  end if;
  v_hash := md5((rec - 'updated_at')::text);
  if prev.lead_id is not null and prev.hash = v_hash and prev.in_scope = v_scope and not p_force then
    return jsonb_build_object('changed', false, 'version', prev.version);
  end if;
  v_seq := nextval('b2b.b2c_sync_seq');
  v_ver := coalesce(prev.version, 0) + 1;
  insert into b2b.b2c_sync (lead_id, seq, version, hash, in_scope, origin, changed_at)
  values (p_lead_id, v_seq, v_ver, v_hash, v_scope, p_origin, now())
  on conflict (lead_id) do update set seq = excluded.seq, version = excluded.version, hash = excluded.hash, in_scope = excluded.in_scope,
                                      origin = excluded.origin, changed_at = excluded.changed_at;
  v_type := case when v_scope then 'b2c.lead_upserted' else 'b2c.lead_released' end;
  env := jsonb_build_object('id', 'lead_' || p_lead_id || '_v' || v_ver, 'type', v_type, 'occurred_at', now(), 'lead_id', p_lead_id,
                            'test', coalesce((rec ->> 'is_test')::boolean, false),
                            'data', jsonb_build_object('version', v_ver, 'seq', v_seq, 'origin', p_origin, 'record', rec));
  -- production cadence: real students go out in the next batch (b2c_batch_send); test leads stay real time for testing
  if cfg ->> 'delivery' = 'batched' and not coalesce((rec ->> 'is_test')::boolean, false) then
    return jsonb_build_object('changed', true, 'version', v_ver, 'seq', v_seq, 'type', v_type, 'batched', true);
  end if;
  for w in select * from b2b.webhook_endpoints where consumer = 'b2c_crm' and active and b2b.event_subscribed(events, v_type) loop
    update b2b.integration_outbox set status = 'cancelled', last_error = 'superseded by version ' || v_ver
     where endpoint_id = w.id and status in ('pending', 'failed') and event_type in ('b2c.lead_upserted', 'b2c.lead_released')
       and (payload ->> 'lead_id')::bigint = p_lead_id;
    insert into b2b.integration_outbox (event_type, target, payload, idempotency_key, endpoint_id)
    values (v_type, w.consumer, env, w.id || ':' || (env ->> 'id'), w.id)
    on conflict (idempotency_key) do nothing;
  end loop;
  return jsonb_build_object('changed', true, 'version', v_ver, 'seq', v_seq, 'type', v_type);
end $fn$;


create or replace function b2b.b2c_sync_tick(p_limit int default 1000)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_start timestamptz := clock_timestamp();
  v_since timestamptz;
  v_last timestamptz;
  v_n int := 0;
  v_changed int := 0;
  r record;
  x jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtext('b2b.b2c_sync_tick')) then return jsonb_build_object('skipped', 'busy'); end if;
  perform set_config('b2b.actor', 'engine', true);
  select (value ->> 'at')::timestamptz into v_since from b2b.b2c_link_state where key = 'cursor';
  v_since := coalesce(v_since, now() - interval '1 day') - interval '10 seconds';
  for r in
    select lead_id, max(changed) changed from (
      select l.id lead_id, l.updated_at changed from public.student_leads l where l.updated_at > v_since
      union all select a.lead_id, greatest(a.created_at, a.updated_at) from b2b.allocations a where greatest(a.created_at, a.updated_at) > v_since
      union all select c.lead_id, c.updated_at from b2b.lead_campaigns c where c.updated_at > v_since) y
     group by lead_id order by 2 limit greatest(p_limit, 1)
  loop
    begin
      x := b2b.b2c_sync_lead(r.lead_id);
      if (x ->> 'changed')::boolean then v_changed := v_changed + 1; end if;
    exception when others then
      raise warning 'b2c_sync_lead(%) failed: %', r.lead_id, sqlerrm;
    end;
    v_n := v_n + 1;
    v_last := r.changed;
  end loop;
  update b2b.b2c_link_state set value = jsonb_build_object('at', case when v_n >= greatest(p_limit, 1) then v_last else v_start end,
                                                           'last_run', v_start, 'scanned', v_n, 'changed', v_changed), updated_at = now()
   where key = 'cursor';
  -- batched delivery: one webhook per batch of changed leads, every sync interval
  x := b2b.b2c_batch_send(false);
  if v_changed > 0 or coalesce((x ->> 'batches')::int, 0) > 0 then perform b2b.outbox_kick(); end if;
  return jsonb_build_object('scanned', v_n, 'changed', v_changed, 'batch', x);
end $fn$;


create or replace function b2b.partner_sync_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  h record;
  j jsonb;
  p b2b.partners;
  spec jsonb;
  e jsonb;
  recs jsonb;
  rec jsonb;
  res text;
  v_max timestamptz;
  v_counts jsonb;
  n_polls int := 0;
  n_issued int := 0;
begin
  perform set_config('b2b.actor', 'system', true);
  perform b2b.adapter_token_collect();

  -- answers to polls and schema fetches
  for r in select s.* from b2b.partner_adapter_state s where s.poll_request_id is not null or s.schema_request_id is not null loop
    select * into p from b2b.partners where id = r.partner_id;
    spec := b2b.adapter_spec(p.adapter_type);
    e := b2b.adapter_env(p, r.env);
    if r.poll_request_id is not null then
      select x.status_code, x.content, x.error_msg into h from net._http_response x where x.id = r.poll_request_id;
      if found then
        begin j := h.content::jsonb; exception when others then j := null; end;
        if h.status_code between 200 and 299 or h.status_code = 304 then
          recs := case when h.status_code = 304 or j is null then '[]' else b2b.adapter_poll_parse(p.adapter_type, j,
                    coalesce(nullif(e ->> 'status_field', ''), spec ->> 'status_field'), coalesce(nullif(e ->> 'reference_field', ''), spec ->> 'reference_field')) end;
          v_counts := '{}'; v_max := null;
          for rec in select x from jsonb_array_elements(recs) x loop
            begin res := b2b.adapter_poll_apply(p, r.env, rec); exception when others then res := 'error'; end;
            v_counts := v_counts || jsonb_build_object(res, coalesce((v_counts ->> res)::int, 0) + 1);
            v_max := greatest(v_max, b2b.try_timestamptz(rec ->> 'modified'));
          end loop;
          update b2b.partner_adapter_state
             set poll_request_id = null, last_poll_at = now(), last_poll_error = null,
                 last_poll_result = v_counts || jsonb_build_object('records', jsonb_array_length(recs)),
                 poll_since = coalesce(v_max, r.poll_requested_at - interval '2 minutes', poll_since), updated_at = now()
           where partner_id = r.partner_id and env = r.env;
          n_polls := n_polls + 1;
        else
          if h.status_code = 401 then update b2b.partner_adapter_state set token_expires_at = null where partner_id = r.partner_id and env = r.env; end if;
          update b2b.partner_adapter_state set poll_request_id = null, last_poll_at = now(), updated_at = now(),
                 last_poll_error = left(coalesce(h.error_msg, 'HTTP ' || h.status_code || ': ' || left(h.content, 200)), 300)
           where partner_id = r.partner_id and env = r.env;
        end if;
      elsif r.poll_requested_at < now() - interval '5 minutes' then
        update b2b.partner_adapter_state set poll_request_id = null, last_poll_error = 'no answer from the CRM' where partner_id = r.partner_id and env = r.env;
      end if;
    end if;
    if r.schema_request_id is not null then
      select x.status_code, x.content, x.error_msg into h from net._http_response x where x.id = r.schema_request_id;
      if found then
        begin j := h.content::jsonb; exception when others then j := null; end;
        if h.status_code between 200 and 299 and j is not null then
          begin
            perform b2b.mapping_snapshot_store(p.id, 'api', b2b.adapter_schema_parse(p.adapter_type, j, coalesce(nullif(e ->> 'status_field', ''), spec ->> 'status_field')));
            update b2b.partner_adapter_state set schema_request_id = null, last_schema_at = now(), last_schema_error = null, updated_at = now()
             where partner_id = r.partner_id and env = r.env;
          exception when others then
            update b2b.partner_adapter_state set schema_request_id = null, last_schema_error = left(sqlerrm, 300), updated_at = now()
             where partner_id = r.partner_id and env = r.env;
          end;
        else
          if h.status_code = 401 then update b2b.partner_adapter_state set token_expires_at = null where partner_id = r.partner_id and env = r.env; end if;
          update b2b.partner_adapter_state set schema_request_id = null, updated_at = now(),
                 last_schema_error = left(coalesce(h.error_msg, 'HTTP ' || h.status_code || ': ' || left(h.content, 200)), 300)
           where partner_id = r.partner_id and env = r.env;
        end if;
      elsif r.schema_requested_at < now() - interval '5 minutes' then
        update b2b.partner_adapter_state set schema_request_id = null, last_schema_error = 'no answer from the CRM' where partner_id = r.partner_id and env = r.env;
      end if;
    end if;
  end loop;

  -- due polls: live partners that are switched on, and sandboxes with recent test leads; daily schema check of live partners
  for r in
    select pt.id, env.env, s.last_poll_at, s.poll_request_id, s.last_schema_at, s.schema_request_id, s.token_request_id
      from b2b.partners pt
      cross join (values ('live'), ('sandbox')) env(env)
      left join b2b.partner_adapter_state s on s.partner_id = pt.id and s.env = env.env
     where coalesce((b2b.adapter_spec(pt.adapter_type) ->> 'poll')::boolean, false)
       and nullif(pt.outbound_auth -> env.env ->> 'secret_id', '') is not null
       and coalesce((pt.outbound_auth -> env.env ->> 'poll')::boolean, true)
       and case when env.env = 'live' then b2b.is_live('partner:' || pt.id)
                else exists (select 1 from b2b.allocations a where a.partner_id = pt.id and a.is_test and a.created_at > now() - interval '7 days') end
  loop
    select * into p from b2b.partners where id = r.id;
    if r.poll_request_id is null and r.token_request_id is null
       and coalesce(r.last_poll_at, '-infinity') < now() - make_interval(mins => greatest(coalesce((p.outbound_auth -> r.env ->> 'poll_minutes')::int, case when r.env = 'live' then b2b.sync_minutes() else 2 end), 2)) then
      begin
        perform b2b.adapter_issue(p, r.env, 'poll');
        n_issued := n_issued + 1;
      exception when others then
        update b2b.partner_adapter_state set last_poll_at = now(), last_poll_error = left(sqlerrm, 300) where partner_id = p.id and env = r.env;
      end;
    end if;
    if r.env = 'live' and r.schema_request_id is null and coalesce((b2b.adapter_spec(p.adapter_type) ->> 'schema')::boolean, false)
       and coalesce(r.last_schema_at, '-infinity') < now() - interval '1 day' then
      begin
        perform b2b.adapter_issue(p, 'live', 'schema');
      exception when others then
        update b2b.partner_adapter_state set last_schema_at = now(), last_schema_error = left(sqlerrm, 300) where partner_id = p.id and env = 'live';
      end;
    end if;
  end loop;
  return jsonb_build_object('polls_read', n_polls, 'polls_sent', n_issued);
end $fn$;


create or replace function b2b.webhook_endpoint_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_events text[];
  v_bad text;
  w b2b.webhook_endpoints;
  v_known text[] := array['lead.allocated', 'lead.accepted', 'lead.status_changed', 'lead.enrolled', 'b2c.lead_handed_off', 'b2c.lead_reenquired',
                          'b2c.lead_flagged', 'b2c.lead_close_agreed', 'b2c.lead_upserted', 'b2c.lead_released', 'b2c.leads_batch', 'b2b.lead_routed_to_partner',
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


revoke execute on function b2b.sync_minutes(), b2b.b2c_batch_send(boolean) from public, anon, authenticated;
grant execute on function b2b.sync_minutes(), b2b.b2c_batch_send(boolean) to service_role;
revoke execute on function b2b.webhook_endpoint_save(jsonb) from public, anon;
grant execute on function b2b.webhook_endpoint_save(jsonb) to authenticated, service_role;
