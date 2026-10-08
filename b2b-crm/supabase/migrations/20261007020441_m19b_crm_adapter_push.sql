-- M19b: partner CRM adapters, part 2: reading each CRM's answer to the create call, and the push engine using adapters.
--   adapter_push_result  created (with the CRM's record ID), duplicate (with the existing record when the CRM says),
--                        auth (credentials refused: the token is renewed and the push retried) or error (retried)
--   push_request         as m8b, but a CRM adapter builds its own request
--   push_dispatch        as m8b; a push waiting for an OAuth token asks for one and tries again shortly
--   push_collect         as m8b; CRM answers are read by adapter_push_result

create or replace function b2b.adapter_push_result(p_adapter text, p_status int, p_content text)
returns jsonb language plpgsql immutable set search_path = '' as $fn$
declare
  j jsonb;
  d jsonb;
  m text;
begin
  begin j := p_content::jsonb; exception when others then j := null; end;
  if p_adapter = 'leadsquared' then
    m := coalesce(j ->> 'ExceptionMessage', j -> 'Message' ->> 'Message', j ->> 'Message', left(p_content, 300));
    return case
      when p_status between 200 and 299 and j ->> 'Status' = 'Success' then jsonb_build_object('outcome', 'created', 'record_id', j -> 'Message' ->> 'Id')
      when coalesce(j ->> 'ExceptionType', '') ilike '%Duplicate%' or m ilike '%already exists%' then jsonb_build_object('outcome', 'duplicate', 'reason', m, 'crm_message', m)
      when p_status in (401, 403) or coalesce(j ->> 'ExceptionType', '') ilike '%Authentication%' then jsonb_build_object('outcome', 'auth', 'reason', m)
      else jsonb_build_object('outcome', 'error', 'reason', m) end;
  elsif p_adapter = 'zoho' then
    d := j -> 'data' -> 0;
    m := coalesce(d ->> 'message', j ->> 'message', left(p_content, 300));
    return case
      when coalesce(d ->> 'code', '') = 'SUCCESS' then jsonb_build_object('outcome', 'created', 'record_id', d -> 'details' ->> 'id')
      when coalesce(d ->> 'code', '') = 'DUPLICATE_DATA' then jsonb_build_object('outcome', 'duplicate', 'reason', m, 'crm_message', m,
             'existing_record_id', coalesce(d -> 'details' -> 'duplicate_record' ->> 'id', d -> 'details' ->> 'id'), 'duplicate_field', d -> 'details' ->> 'api_name')
      when p_status = 401 or coalesce(j ->> 'code', '') in ('INVALID_TOKEN', 'AUTHENTICATION_FAILURE', 'OAUTH_SCOPE_MISMATCH') then jsonb_build_object('outcome', 'auth', 'reason', m)
      else jsonb_build_object('outcome', 'error', 'reason', m) end;
  elsif p_adapter = 'salesforce' then
    d := case when jsonb_typeof(j) = 'array' then j -> 0 else j end;
    m := coalesce(d ->> 'message', left(p_content, 300));
    return case
      when p_status between 200 and 299 and d ->> 'id' is not null then jsonb_build_object('outcome', 'created', 'record_id', d ->> 'id')
      when coalesce(d ->> 'errorCode', '') = 'DUPLICATES_DETECTED' then jsonb_build_object('outcome', 'duplicate', 'reason', m, 'crm_message', m,
             'existing_record_id', d -> 'duplicateResult' -> 'matchResults' -> 0 -> 'matchRecords' -> 0 -> 'record' ->> 'Id')
      when p_status = 401 or coalesce(d ->> 'errorCode', '') = 'INVALID_SESSION_ID' then jsonb_build_object('outcome', 'auth', 'reason', m)
      else jsonb_build_object('outcome', 'error', 'reason', coalesce(d ->> 'errorCode' || ': ', '') || m) end;
  elsif p_adapter = 'hubspot' then
    m := coalesce(j ->> 'message', left(p_content, 300));
    return case
      when p_status between 200 and 299 and j ->> 'id' is not null then jsonb_build_object('outcome', 'created', 'record_id', j ->> 'id')
      when p_status = 409 then jsonb_build_object('outcome', 'duplicate', 'reason', m, 'crm_message', m,
             'existing_record_id', substring(m from 'Existing ID: ?(\d+)'))
      when p_status = 401 or coalesce(j ->> 'category', '') = 'INVALID_AUTHENTICATION' then jsonb_build_object('outcome', 'auth', 'reason', m)
      else jsonb_build_object('outcome', 'error', 'reason', coalesce(j ->> 'category' || ': ', '') || m) end;
  elsif p_adapter = 'meritto' then
    m := coalesce(j ->> 'message', j -> 'error' ->> 'message', left(p_content, 300));
    return case
      when coalesce(m, '') ~* '(already exist|duplicate)' then jsonb_build_object('outcome', 'duplicate', 'reason', m, 'crm_message', m,
             'existing_record_id', coalesce(j -> 'data' ->> 'lead_id', j ->> 'lead_id'))
      when p_status between 200 and 299 and (coalesce((j ->> 'status')::text, '') in ('true', 'success', '1') or coalesce(j -> 'data' ->> 'lead_id', j ->> 'lead_id') is not null)
        then jsonb_build_object('outcome', 'created', 'record_id', coalesce(j -> 'data' ->> 'lead_id', j ->> 'lead_id'))
      when p_status in (401, 403) then jsonb_build_object('outcome', 'auth', 'reason', m)
      else jsonb_build_object('outcome', 'error', 'reason', m) end;
  end if;
  return jsonb_build_object('outcome', 'error', 'reason', 'unknown adapter');
end $fn$;

/* The HTTP request for one allocation. CRM adapters build their own; generic REST and webhook are as in m8b. */
create or replace function b2b.push_request(a b2b.allocations)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  p b2b.partners;
  v_url text;
  v_body jsonb := b2b.push_payload(a);
  v_auth jsonb;
  v_secret text;
  v_headers jsonb := jsonb_build_object('Content-Type', 'application/json', 'Idempotency-Key', a.reference, 'X-Eduwit-Reference', a.reference,
                                        'User-Agent', 'Eduwit-B2B-CRM/1');
  v_ts text := extract(epoch from now())::bigint::text;
begin
  select * into p from b2b.partners where id = a.partner_id;
  if b2b.adapter_spec(p.adapter_type) is not null then return b2b.adapter_push_request(a, p, v_body); end if;
  v_url := case when a.is_test then p.test_endpoint else p.api_base_url end;
  v_auth := coalesce(p.outbound_auth, '{}');
  v_secret := case when p.outbound_secret_id is not null then b2b.partner_secret(p.outbound_secret_id) end;
  if v_secret is not null then
    v_headers := v_headers || case coalesce(v_auth ->> 'type', 'bearer')
      when 'bearer' then jsonb_build_object('Authorization', 'Bearer ' || v_secret)
      when 'header' then jsonb_build_object(v_auth ->> 'header', v_secret)
      when 'basic'  then jsonb_build_object('Authorization', 'Basic ' || translate(encode(convert_to(v_secret, 'UTF8'), 'base64'), E'\n', ''))
      else '{}'::jsonb end;
  end if;
  if p.inbound_secret_id is not null then
    v_headers := v_headers || jsonb_build_object('X-Eduwit-Timestamp', v_ts, 'X-Eduwit-Signature',
      'sha256=' || encode(extensions.hmac(convert_to(v_ts || '.' || v_body::text, 'UTF8'), convert_to(b2b.partner_secret(p.inbound_secret_id), 'UTF8'), 'sha256'), 'hex'));
  end if;
  return jsonb_build_object('url', v_url, 'headers', v_headers, 'body', v_body, 'adapter', p.adapter_type);
end $fn$;

/* As m8b. A CRM push waiting for an OAuth token asks for one (m19c) and tries again in 20 seconds without using an
   attempt; a CRM without credentials for the environment fails the attempt like a missing URL. */
create or replace function b2b.push_dispatch(p_limit int default 20)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  a b2b.allocations;
  p b2b.partners;
  req jsonb;
  v_net bigint;
  n int := 0;
begin
  for a in
    select * from b2b.allocations
     where destination_type = 'partner' and push_request_id is null
       and ((status = 'queued' and (next_push_at is null or next_push_at <= now())) or (status = 'pushing' and next_push_at <= now()))
     order by coalesce(next_push_at, created_at)
     limit least(greatest(p_limit, 1), 100)
     for update skip locked
  loop
    begin
      if not a.is_test and not b2b.is_live('partner:' || a.partner_id) then
        if a.status = 'queued' then update b2b.allocations set status = 'pushing' where id = a.id; end if;
        update b2b.allocations set push_attempts = 99 where id = a.id;
        perform b2b.apply_push_error(a.id, 'partner is switched off');
        continue;
      end if;
      if a.programme_id is null then
        select (c -> 'programmes' ->> 0)::bigint into a.programme_id
          from b2b.engine_decisions d, jsonb_array_elements(d.candidates) c
         where d.id = a.engine_decision_id and (c ->> 'partner_id')::bigint = a.partner_id;
        update b2b.allocations set programme_id = a.programme_id where id = a.id;
      end if;
      req := b2b.push_request(a);
      if coalesce((req ->> 'needs_token')::boolean, false) then
        select * into p from b2b.partners where id = a.partner_id;
        perform b2b.adapter_token_request(p, req ->> 'env');
        update b2b.allocations set status = 'pushing', next_push_at = now() + interval '20 seconds' where id = a.id;
        continue;
      end if;
      if req ->> 'token_error' is not null then
        -- the CRM sign-in failed: a failed attempt on the normal retry schedule
        update b2b.allocations set status = 'pushing', push_attempts = push_attempts + 1 where id = a.id;
        perform b2b.apply_push_error(a.id, req ->> 'token_error');
        continue;
      end if;
      if req ->> 'url' is null then
        if a.status = 'queued' then update b2b.allocations set status = 'pushing' where id = a.id; end if;
        update b2b.allocations set push_attempts = 99 where id = a.id;
        perform b2b.apply_push_error(a.id, coalesce(req ->> 'error', case when a.is_test then 'partner has no test endpoint' else 'partner has no API URL' end));
        continue;
      end if;
      v_net := net.http_post(url := req ->> 'url', body := req -> 'body', headers := req -> 'headers',
                             timeout_milliseconds := coalesce((e ->> 'push_timeout_ms')::int, 10000));
      update b2b.allocations set status = 'pushing', push_attempts = push_attempts + 1, push_request_id = v_net, next_push_at = null where id = a.id;
      insert into b2b.push_requests (allocation_id, attempt, net_request_id, url, sandbox)
      values (a.id, a.push_attempts + 1, v_net, req ->> 'url', a.is_test);
      n := n + 1;
    exception when others then
      update b2b.allocations set next_push_at = now() + interval '5 minutes', last_error = left(sqlerrm, 500) where id = a.id;
      perform b2b.log_event('alert.push_error', a.lead_id, a.id, a.partner_id, jsonb_build_object('error', left(sqlerrm, 300)));
    end;
  end loop;
  return n;
end $fn$;

/* As m8b; a CRM adapter's answer is read by adapter_push_result. Refused credentials drop the cached OAuth token. */
create or replace function b2b.push_collect()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  r record;
  j jsonb;
  res jsonb;
  v_outcome text;
  v_rid text;
  v_reason text;
  n int := 0;
begin
  for r in
    select a.id, a.partner_id, a.is_test, p.adapter_type, q.id as req_id, q.sent_at, x.status_code, x.content, x.timed_out, x.error_msg, x.id is not null as done
      from b2b.allocations a
      join b2b.partners p on p.id = a.partner_id
      join b2b.push_requests q on q.net_request_id = a.push_request_id and q.allocation_id = a.id
      left join net._http_response x on x.id = a.push_request_id
     where a.status = 'pushing' and a.push_request_id is not null
     order by a.id
     limit 200
  loop
    if not r.done then
      if r.sent_at < now() - interval '2 minutes' then
        update b2b.push_requests set outcome = 'timeout', error = 'no response within 2 minutes', completed_at = now() where id = r.req_id;
        perform b2b.apply_push_error(r.id, 'no response within 2 minutes');
        n := n + 1;
      end if;
      continue;
    end if;
    begin j := r.content::jsonb; exception when others then j := null; end;
    res := null; v_rid := null; v_reason := null;
    if r.timed_out or r.error_msg is not null then
      v_outcome := 'error';
    elsif b2b.adapter_spec(r.adapter_type) is not null then
      res := b2b.adapter_push_result(r.adapter_type, r.status_code, r.content);
      v_outcome := res ->> 'outcome';
      v_rid := res ->> 'record_id';
      v_reason := res ->> 'reason';
      if v_outcome = 'auth' then
        update b2b.partner_adapter_state set token_expires_at = null, updated_at = now()
         where partner_id = r.partner_id and env = case when r.is_test then 'sandbox' else 'live' end;
        perform b2b.log_event('alert.push_error', null, r.id, r.partner_id, jsonb_build_object('error', 'the CRM refused the credentials: ' || left(coalesce(v_reason, ''), 200)));
        v_outcome := 'error';
      end if;
    else
      v_rid := coalesce(j ->> 'record_id', j ->> 'id', j ->> 'lead_id', j -> 'data' ->> 'id');
      v_outcome := case
        when r.status_code = 409 or coalesce((j ->> 'duplicate')::boolean, false) then 'duplicate'
        when r.status_code in (422, 403) and (coalesce((j ->> 'rejected')::boolean, false) or j ? 'reason') then 'rejected'
        when r.status_code between 200 and 299 then 'created'
        else 'error' end;
      v_reason := j ->> 'reason';
    end if;
    update b2b.push_requests set status_code = r.status_code, response = left(r.content, 2000), outcome = case when r.timed_out then 'timeout' else v_outcome end,
           error = coalesce(r.error_msg, case when v_outcome = 'error' then 'HTTP ' || coalesce(r.status_code::text, '?') || coalesce(': ' || left(v_reason, 200), '') end),
           completed_at = now()
     where id = r.req_id;
    case v_outcome
      when 'created' then perform b2b.apply_created(r.id, v_rid);
      when 'duplicate' then perform b2b.apply_duplicate(r.id, coalesce(res, j, '{}') || jsonb_build_object('status_code', r.status_code, 'source', 'push_response'));
      when 'rejected' then perform b2b.apply_rejection(r.id, coalesce(v_reason, 'rejected'));
      else perform b2b.apply_push_error(r.id, coalesce(r.error_msg, case when r.timed_out then 'timeout' end,
                                                       'HTTP ' || coalesce(r.status_code::text, '?') || ': ' || left(coalesce(v_reason, r.content, ''), 200)));
    end case;
    n := n + 1;
  end loop;
  return n;
end $fn$;

revoke execute on function b2b.adapter_push_result(text, int, text) from public, anon, authenticated;
grant execute on function b2b.adapter_push_result(text, int, text) to service_role;
