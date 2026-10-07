-- M21c: in-house partner CRMs (Vikas, 7 Oct). Partners with their own CRM get three options:
--   1. "In-house CRM": Eduwit adapts to the CRM's existing API. The Admin enters the create address, the auth (bearer,
--      header, Basic, query parameter or none), an optional wrapper key, where the record ID is in the answer and the HTTP
--      status used for duplicates, and optionally a changes address to poll. Field names come from Mapping studio.
--   2. The partner builds Eduwit's contract (generic REST + signed events), docs/partner-api.md.
--   3. No API: the partner's export is reconciled (Sync & SLAs) and its statement in Commission & Finance.
-- This part: the adapter type, its spec and push request, and reading its answers. Polling and settings are m21d.

alter table b2b.partners drop constraint if exists partners_adapter_type_check;
alter table b2b.partners add constraint partners_adapter_type_check
  check (adapter_type in ('leadsquared', 'salesforce', 'zoho', 'meritto', 'hubspot', 'inhouse', 'generic_rest', 'webhook'));

create or replace function b2b.adapter_spec(p_adapter text)
returns jsonb language sql immutable set search_path = '' as $fn$
  select case p_adapter
    when 'leadsquared' then '{
      "label": "LeadSquared", "settings": ["host"], "secrets": ["access_key", "secret_key"], "oauth": false, "poll": true, "schema": true,
      "status_field": "ProspectStage", "reference_field": "mx_Eduwit_Reference", "record_field": "ProspectID",
      "defaults": {"FirstName": "first_name", "LastName": "last_name", "Phone": "phone_dash", "EmailAddress": "email", "mx_City": "city",
                   "mx_State": "state", "Source": "=Eduwit", "Notes": "note", "mx_Eduwit_Reference": "reference"}}'::jsonb
    when 'zoho' then '{
      "label": "Zoho CRM", "settings": ["api_domain", "accounts_domain", "client_id"], "secrets": ["client_secret", "refresh_token"], "oauth": true, "poll": true, "schema": true,
      "status_field": "Lead_Status", "reference_field": "Eduwit_Reference", "record_field": "id",
      "defaults": {"First_Name": "first_name", "Last_Name": "last_name_required", "Phone": "phone", "Email": "email", "City": "city", "State": "state",
                   "Lead_Source": "=Eduwit", "Description": "note", "Eduwit_Reference": "reference"}}'::jsonb
    when 'salesforce' then '{
      "label": "Salesforce", "settings": ["login_url", "client_id", "api_version"], "secrets": ["client_secret", "refresh_token"], "oauth": true, "poll": true, "schema": true,
      "status_field": "Status", "reference_field": "Eduwit_Reference__c", "record_field": "Id",
      "defaults": {"FirstName": "first_name", "LastName": "last_name_required", "Company": "=Individual", "Phone": "phone", "Email": "email", "City": "city",
                   "State": "state", "LeadSource": "=Eduwit", "Description": "note", "Eduwit_Reference__c": "reference"}}'::jsonb
    when 'hubspot' then '{
      "label": "HubSpot", "settings": [], "secrets": ["token"], "oauth": false, "poll": true, "schema": true,
      "status_field": "hs_lead_status", "reference_field": "eduwit_reference", "record_field": "id",
      "defaults": {"firstname": "first_name", "lastname": "last_name", "phone": "phone", "email": "email", "city": "city", "state": "state",
                   "lifecyclestage": "=lead", "eduwit_reference": "reference"}}'::jsonb
    when 'meritto' then '{
      "label": "Meritto (NoPaperForms)", "settings": ["base_url", "source"], "secrets": ["access_key", "secret_key"], "oauth": false, "poll": false, "schema": false,
      "status_field": "lead_stage", "reference_field": "eduwit_reference", "record_field": "lead_id",
      "defaults": {"name": "name", "email": "email", "mobile": "phone10", "country_dial_code": "=+91", "city": "city", "state": "state",
                   "course": "course", "specialization": "specialization", "eduwit_reference": "reference", "remarks": "note"}}'::jsonb
    when 'inhouse' then '{
      "label": "In-house CRM", "settings": ["create_url", "auth_type", "auth_name", "wrap_key", "record_id_path", "duplicate_status", "poll_url", "since_param"],
      "secrets": ["token"], "oauth": false, "poll": true, "schema": false,
      "status_field": "status", "reference_field": "eduwit_reference", "record_field": "id",
      "defaults": {"name": "name", "first_name": "first_name", "last_name": "last_name", "phone": "phone", "email": "email", "city": "city",
                   "state": "state", "course": "course", "specialization": "specialization", "university": "university", "level": "level",
                   "mode": "mode", "eduwit_reference": "reference", "source": "=Eduwit", "note": "note"}}'::jsonb
    end;
$fn$;

/* In-house CRM auth from its settings: bearer, a header of the partner's choice, HTTP Basic (secret "user:password"),
   a query parameter, or none. */
create or replace function b2b.inhouse_header_auth(e jsonb)
returns jsonb language sql immutable set search_path = '' as $fn$
  select case e ->> 'auth_type'
    when 'bearer' then jsonb_build_object('Authorization', 'Bearer ' || coalesce(e -> 'secrets' ->> 'token', ''))
    when 'header' then jsonb_build_object(coalesce(nullif(e ->> 'auth_name', ''), 'x-api-key'), coalesce(e -> 'secrets' ->> 'token', ''))
    when 'basic' then jsonb_build_object('Authorization', 'Basic ' || replace(encode(convert_to(coalesce(e -> 'secrets' ->> 'token', ''), 'UTF8'), 'base64'), E'\n', ''))
    else '{}'::jsonb end;
$fn$;

create or replace function b2b.inhouse_query_auth(e jsonb, p_url text)
returns text language sql immutable set search_path = '' as $fn$
  select case when e ->> 'auth_type' = 'query'
              then case when position('?' in coalesce(p_url, '')) > 0 then '&' else '?' end
                   || coalesce(nullif(e ->> 'auth_name', ''), 'api_key') || '=' || coalesce(e -> 'secrets' ->> 'token', '')
              else '' end;
$fn$;

/* A dotted path ("data.lead.id") in a JSON answer. */
create or replace function b2b.json_path_text(j jsonb, p_path text)
returns text language sql immutable set search_path = '' as $fn$
  select case when nullif(trim(p_path), '') is null or j is null then null else j #>> string_to_array(trim(p_path), '.') end;
$fn$;

/* The answer to a create call, for any adapter. An in-house CRM is read with the partner's own settings (record ID path,
   the HTTP status it uses for duplicates); everything else is adapter_push_result. */
create or replace function b2b.adapter_push_result_p(p_partner_id bigint, p_is_test boolean, p_adapter text, p_status int, p_content text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  e jsonb;
  j jsonb;
  m text;
  v_rid text;
  v_dup int;
begin
  if p_adapter <> 'inhouse' then return b2b.adapter_push_result(p_adapter, p_status, p_content); end if;
  select coalesce(p.outbound_auth -> case when p_is_test then 'sandbox' else 'live' end, '{}') into e from b2b.partners p where p.id = p_partner_id;
  begin j := p_content::jsonb; exception when others then j := null; end;
  m := coalesce(j ->> 'message', j ->> 'error', j -> 'error' ->> 'message', j ->> 'reason', left(p_content, 300));
  v_rid := coalesce(b2b.json_path_text(j, e ->> 'record_id_path'), j ->> 'id', j ->> 'record_id', j ->> 'lead_id', j -> 'data' ->> 'id',
                    j -> 'data' ->> 'record_id', j -> 'data' ->> 'lead_id', j -> 'result' ->> 'id', j -> 'lead' ->> 'id');
  v_dup := nullif(e ->> 'duplicate_status', '')::int;
  return case
    when p_status = v_dup or p_status = 409 or lower(coalesce(j ->> 'duplicate', '')) in ('true', '1') or coalesce(m, '') ~* '(duplicate|already exist)'
      then jsonb_build_object('outcome', 'duplicate', 'reason', m, 'crm_message', m,
                              'existing_record_id', coalesce(j ->> 'existing_record_id', j ->> 'existing_id', v_rid))
    when p_status in (401, 403) and lower(coalesce(j ->> 'rejected', '')) not in ('true', '1') then jsonb_build_object('outcome', 'auth', 'reason', m)
    when p_status in (403, 422) and (lower(coalesce(j ->> 'rejected', '')) in ('true', '1') or j ? 'reason') then jsonb_build_object('outcome', 'rejected', 'reason', m)
    when p_status between 200 and 299 then jsonb_build_object('outcome', 'created', 'record_id', v_rid)
    else jsonb_build_object('outcome', 'error', 'reason', m) end;
end $fn$;

create or replace function b2b.adapter_push_request(a b2b.allocations, p b2b.partners, v jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_env text := case when a.is_test then 'sandbox' else 'live' end;
  e jsonb := b2b.adapter_env(p, v_env);
  s jsonb := e -> 'secrets';
  st b2b.partner_adapter_state;
  rec jsonb := b2b.adapter_record(p.adapter_type, e, v);
  v_token text;
  h jsonb := jsonb_build_object('Content-Type', 'application/json', 'User-Agent', 'Eduwit-B2B-CRM/1', 'X-Eduwit-Reference', a.reference);
begin
  if not (e ->> 'configured')::boolean then return jsonb_build_object('url', null, 'error', 'no ' || v_env || ' credentials'); end if;
  select * into st from b2b.partner_adapter_state where partner_id = p.id and env = v_env;
  if (b2b.adapter_spec(p.adapter_type) ->> 'oauth')::boolean then
    if st.token_expires_at is null or st.token_expires_at <= now() then
      if st.token_failed_at > now() - interval '5 minutes' then
        return jsonb_build_object('url', null, 'token_error', coalesce(st.token_error, 'the CRM sign-in failed'), 'env', v_env);
      end if;
      return jsonb_build_object('url', null, 'needs_token', true, 'env', v_env);
    end if;
    v_token := b2b.partner_secret(st.token_secret_id);
  end if;
  return case p.adapter_type
    when 'leadsquared' then jsonb_build_object(
      'url', 'https://' || (e ->> 'host') || '/v2/LeadManagement.svc/Lead.Create',
      'headers', h || jsonb_build_object('x-LSQ-AccessKey', s ->> 'access_key', 'x-LSQ-SecretKey', s ->> 'secret_key'),
      'body', (select coalesce(jsonb_agg(jsonb_build_object('Attribute', key, 'Value', value #>> '{}')), '[]') from jsonb_each(rec)))
    when 'zoho' then jsonb_build_object(
      'url', 'https://' || coalesce(nullif(e ->> 'api_domain', ''), 'www.zohoapis.in') || '/crm/v5/Leads',
      'headers', h || jsonb_build_object('Authorization', 'Zoho-oauthtoken ' || v_token),
      'body', jsonb_build_object('data', jsonb_build_array(rec), 'trigger', jsonb_build_array('workflow')))
    when 'salesforce' then jsonb_build_object(
      'url', st.instance_url || '/services/data/' || (e ->> 'api_version') || '/sobjects/Lead/',
      'headers', h || jsonb_build_object('Authorization', 'Bearer ' || v_token, 'Sforce-Duplicate-Rule-Header', 'allowSave=false; includeRecordDetails=false; runAsCurrentUser=true'),
      'body', rec)
    when 'hubspot' then jsonb_build_object(
      'url', 'https://api.hubapi.com/crm/v3/objects/contacts',
      'headers', h || jsonb_build_object('Authorization', 'Bearer ' || coalesce(s ->> 'token', '')),
      'body', jsonb_build_object('properties', rec))
    when 'inhouse' then jsonb_build_object(
      'url', (e ->> 'create_url') || b2b.inhouse_query_auth(e, e ->> 'create_url'),
      'headers', h || b2b.inhouse_header_auth(e),
      'body', case when nullif(e ->> 'wrap_key', '') is not null then jsonb_build_object(e ->> 'wrap_key', rec) else rec end)
    when 'meritto' then jsonb_build_object(
      'url', rtrim(coalesce(nullif(e ->> 'base_url', ''), 'https://api.nopaperforms.io'), '/') || '/lead/v1/create',
      'headers', h || jsonb_build_object('access-key', s ->> 'access_key', 'secret-key', s ->> 'secret_key'),
      'body', rec)
    end || jsonb_build_object('adapter', p.adapter_type, 'env', v_env);
end $fn$;

/* As m19b; answers are read by adapter_push_result_p (in-house CRMs with the partner's settings). */
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
      res := b2b.adapter_push_result_p(r.partner_id, r.is_test, r.adapter_type, r.status_code, r.content);
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

revoke execute on function b2b.adapter_spec(text), b2b.adapter_push_request(b2b.allocations, b2b.partners, jsonb), b2b.inhouse_header_auth(jsonb),
                           b2b.inhouse_query_auth(jsonb, text), b2b.json_path_text(jsonb, text), b2b.adapter_push_result_p(bigint, boolean, text, int, text)
  from public, anon, authenticated;
grant execute on function b2b.adapter_spec(text), b2b.adapter_push_request(b2b.allocations, b2b.partners, jsonb), b2b.inhouse_header_auth(jsonb),
                          b2b.inhouse_query_auth(jsonb, text), b2b.json_path_text(jsonb, text), b2b.adapter_push_result_p(bigint, boolean, text, int, text)
  to service_role;
