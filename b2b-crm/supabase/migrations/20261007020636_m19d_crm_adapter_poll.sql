-- M19d: partner CRM adapters, part 4: applying polled records and the sync tick.
--   adapter_poll_apply      a polled record → partner events (a stage event when the stage differs from what Eduwit last
--                           saw; a field update), applied through partner_event_apply exactly like webhook events
--   adapter_issue           sends one read request (schema or poll) through pg_net
--   partner_sync_tick       pg_cron every minute
-- The Admin's functions are m19e.

create or replace function b2b.adapter_poll_apply(p b2b.partners, p_env text, rec jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  v_seen text;
  v_id bigint;
  v_mod text := coalesce(rec ->> 'modified', to_char(now(), 'YYYY-MM-DD HH24:MI:SS'));
  n int := 0;
begin
  select * into a from b2b.allocations x
   where x.partner_id = p.id and x.is_test = (p_env = 'sandbox')
     and ((rec ->> 'reference' is not null and x.reference = rec ->> 'reference') or (rec ->> 'record_id' is not null and x.partner_record_id = rec ->> 'record_id'))
   order by x.created_at desc limit 1;
  if a.id is null then return 'unmatched'; end if;
  if a.partner_record_id is null and rec ->> 'record_id' is not null then
    update b2b.allocations set partner_record_id = rec ->> 'record_id' where id = a.id;
  end if;
  select l.partner_stage_raw into v_seen from public.student_leads l where l.id = a.lead_id and l.allocation_id = a.id;
  if nullif(trim(rec ->> 'stage'), '') is not null and lower(trim(rec ->> 'stage')) is distinct from lower(trim(coalesce(v_seen, ''))) then
    insert into b2b.partner_events (partner_id, event_id, event_type, reference, record_id, allocation_id, lead_id, raw)
    values (p.id, left('poll:' || (rec ->> 'record_id') || ':stage:' || v_mod, 200), 'stage', a.reference, rec ->> 'record_id', a.id, a.lead_id,
            jsonb_build_object('event_id', left('poll:' || (rec ->> 'record_id') || ':stage:' || v_mod, 200), 'type', 'stage', 'source', 'poll',
                               'reference', a.reference, 'record_id', rec ->> 'record_id', 'occurred_at', rec ->> 'modified',
                               'data', jsonb_build_object('stage', trim(rec ->> 'stage'))))
    on conflict (partner_id, event_id) do nothing returning id into v_id;
    if v_id is not null then perform b2b.partner_event_apply(v_id); n := n + 1; end if;
  end if;
  v_id := null;
  if jsonb_typeof(rec -> 'fields') = 'object' and rec -> 'fields' <> '{}' then
    insert into b2b.partner_events (partner_id, event_id, event_type, reference, record_id, allocation_id, lead_id, raw)
    values (p.id, left('poll:' || (rec ->> 'record_id') || ':update:' || v_mod, 200), 'update', a.reference, rec ->> 'record_id', a.id, a.lead_id,
            jsonb_build_object('event_id', left('poll:' || (rec ->> 'record_id') || ':update:' || v_mod, 200), 'type', 'update', 'source', 'poll',
                               'reference', a.reference, 'record_id', rec ->> 'record_id', 'occurred_at', rec ->> 'modified',
                               'data', jsonb_build_object('fields', rec -> 'fields')))
    on conflict (partner_id, event_id) do nothing returning id into v_id;
    if v_id is not null then perform b2b.partner_event_apply(v_id); n := n + 1; end if;
  end if;
  return case when n > 0 then 'applied' else 'unchanged' end;
end $fn$;

/* Sends one read request. Returns the pg_net id, or null (asking for a token first when needed). */
create or replace function b2b.adapter_issue(p b2b.partners, p_env text, p_kind text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  st b2b.partner_adapter_state;
  c jsonb;
  v_net bigint;
  v_since timestamptz;
begin
  insert into b2b.partner_adapter_state (partner_id, env) values (p.id, p_env) on conflict do nothing;
  select * into st from b2b.partner_adapter_state where partner_id = p.id and env = p_env for update;
  v_since := coalesce(st.poll_since, now() - interval '1 day');
  c := b2b.adapter_call(p, p_env, p_kind, v_since);
  if coalesce((c ->> 'needs_token')::boolean, false) then
    perform b2b.adapter_token_request(p, p_env);
    return jsonb_build_object('waiting', 'sign-in');
  end if;
  if c ? 'error' then return c; end if;
  v_net := case c ->> 'method'
    when 'GET' then net.http_get(url := c ->> 'url', params := coalesce(c -> 'params', '{}'), headers := coalesce(c -> 'headers', '{}'), timeout_milliseconds := 20000)
    else net.http_post(url := c ->> 'url', body := coalesce(c -> 'body', '{}'), params := coalesce(c -> 'params', '{}'), headers := coalesce(c -> 'headers', '{}'),
                       timeout_milliseconds := 20000) end;
  if p_kind = 'poll' then
    update b2b.partner_adapter_state set poll_request_id = v_net, poll_requested_at = now(), poll_since = v_since, updated_at = now() where partner_id = p.id and env = p_env;
  else
    update b2b.partner_adapter_state set schema_request_id = v_net, schema_requested_at = now(), updated_at = now() where partner_id = p.id and env = p_env;
  end if;
  return jsonb_build_object('request_id', v_net);
end $fn$;

/* pg_cron, every minute: tokens, read answers, due polls, daily schema checks. */
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
       and coalesce(r.last_poll_at, '-infinity') < now() - make_interval(mins => greatest(coalesce((p.outbound_auth -> r.env ->> 'poll_minutes')::int, 10), 2)) then
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

revoke execute on function b2b.adapter_token_request(b2b.partners, text), b2b.adapter_token_collect(), b2b.adapter_poll_fields(bigint),
                           b2b.adapter_call(b2b.partners, text, text, timestamptz), b2b.adapter_schema_parse(text, jsonb, text),
                           b2b.adapter_poll_parse(text, jsonb, text, text), b2b.adapter_poll_apply(b2b.partners, text, jsonb), b2b.adapter_issue(b2b.partners, text, text),
                           b2b.partner_sync_tick(), b2b.mapping_snapshot_store(bigint, text, jsonb)
  from public, anon, authenticated;
grant execute on function b2b.adapter_token_request(b2b.partners, text), b2b.adapter_token_collect(), b2b.adapter_poll_fields(bigint),
                          b2b.adapter_call(b2b.partners, text, text, timestamptz), b2b.adapter_schema_parse(text, jsonb, text),
                          b2b.adapter_poll_parse(text, jsonb, text, text), b2b.adapter_poll_apply(b2b.partners, text, jsonb), b2b.adapter_issue(b2b.partners, text, text),
                          b2b.partner_sync_tick(), b2b.mapping_snapshot_store(bigint, text, jsonb)
  to service_role;

select cron.schedule('b2b-partner-sync-tick', '* * * * *', 'select b2b.partner_sync_tick()');
