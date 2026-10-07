-- M21d: in-house partner CRMs, part 2 (follows m21c): polling the CRM's changes address, reading any list it returns, and
-- the settings the Admin enters.
--   adapter_call          an in-house CRM's changes address, with {since} or a since parameter, and its auth
--   adapter_poll_parse    in-house answers: a list, or the first list under data / records / results / items / leads; the
--                         status and reference fields may be dotted paths (stage.name)
--   partner_adapter_save  in-house settings checked (https addresses, auth type, names and paths); a CRM without a changes
--                         address is not polled; status and reference fields may be paths

create or replace function b2b.adapter_call(p b2b.partners, p_env text, p_kind text, p_since timestamptz)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  spec jsonb := b2b.adapter_spec(p.adapter_type);
  e jsonb := b2b.adapter_env(p, p_env);
  s jsonb := e -> 'secrets';
  st b2b.partner_adapter_state;
  v_token text;
  v_status text := coalesce(nullif(e ->> 'status_field', ''), spec ->> 'status_field');
  v_ref text := coalesce(nullif(e ->> 'reference_field', ''), spec ->> 'reference_field');
  v_fields text[] := b2b.adapter_poll_fields(p.id);
  v_cols text;
begin
  if spec is null or not coalesce((spec ->> p_kind)::boolean, false) then return jsonb_build_object('error', 'not supported for ' || coalesce(spec ->> 'label', p.adapter_type)); end if;
  if not (e ->> 'configured')::boolean then return jsonb_build_object('error', 'no ' || p_env || ' credentials'); end if;
  select * into st from b2b.partner_adapter_state where partner_id = p.id and env = p_env;
  if (spec ->> 'oauth')::boolean then
    if st.token_expires_at is null or st.token_expires_at <= now() then return jsonb_build_object('needs_token', true); end if;
    v_token := b2b.partner_secret(st.token_secret_id);
  end if;
  v_cols := array_to_string(array(select distinct x from unnest(array[spec ->> 'record_field', v_status, v_ref] || v_fields) x where x is not null), ',');
  return case p.adapter_type
    when 'inhouse' then case when nullif(e ->> 'poll_url', '') is null then jsonb_build_object('error', 'no changes address is set')
      else jsonb_build_object('method', 'GET',
        'url', replace(e ->> 'poll_url', '{since}', to_char(p_since at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
        'params', case when position('{since}' in e ->> 'poll_url') = 0
                       then jsonb_build_object(coalesce(nullif(e ->> 'since_param', ''), 'updated_since'), to_char(p_since at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
                       else '{}'::jsonb end
                  || case when e ->> 'auth_type' = 'query' then jsonb_build_object(coalesce(nullif(e ->> 'auth_name', ''), 'api_key'), coalesce(e -> 'secrets' ->> 'token', ''))
                          else '{}'::jsonb end,
        'headers', jsonb_build_object('Accept', 'application/json') || b2b.inhouse_header_auth(e)) end
    when 'leadsquared' then case p_kind
      when 'schema' then jsonb_build_object('method', 'GET', 'url', 'https://' || (e ->> 'host') || '/v2/LeadManagement.svc/LeadsMetaData.Get')
      else jsonb_build_object('method', 'POST', 'url', 'https://' || (e ->> 'host') || '/v2/LeadManagement.svc/Leads.RecentlyModified',
        'body', jsonb_build_object('Parameter', jsonb_build_object('FromDate', to_char(p_since at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS'),
                                                                   'ToDate', to_char(now() at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS')),
                                   'Columns', jsonb_build_object('Include_CSV', v_cols || ',ModifiedOn'),
                                   'Paging', jsonb_build_object('PageIndex', 1, 'PageSize', 500))) end
      || jsonb_build_object('headers', jsonb_build_object('Content-Type', 'application/json', 'x-LSQ-AccessKey', s ->> 'access_key', 'x-LSQ-SecretKey', s ->> 'secret_key'))
    when 'zoho' then case p_kind
      when 'schema' then jsonb_build_object('method', 'GET', 'url', coalesce(st.instance_url, 'https://' || coalesce(nullif(e ->> 'api_domain', ''), 'www.zohoapis.in')) || '/crm/v5/settings/fields',
        'params', jsonb_build_object('module', 'Leads'), 'headers', jsonb_build_object('Authorization', 'Zoho-oauthtoken ' || v_token))
      else jsonb_build_object('method', 'GET', 'url', coalesce(st.instance_url, 'https://' || coalesce(nullif(e ->> 'api_domain', ''), 'www.zohoapis.in')) || '/crm/v5/Leads',
        'params', jsonb_build_object('fields', v_cols || ',Modified_Time', 'sort_by', 'Modified_Time', 'sort_order', 'asc', 'per_page', '200'),
        'headers', jsonb_build_object('Authorization', 'Zoho-oauthtoken ' || v_token,
                                      'If-Modified-Since', to_char(p_since at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') || '+00:00')) end
    when 'salesforce' then jsonb_build_object('method', 'GET', 'headers', jsonb_build_object('Authorization', 'Bearer ' || v_token)) || case p_kind
      when 'schema' then jsonb_build_object('url', st.instance_url || '/services/data/' || (e ->> 'api_version') || '/sobjects/Lead/describe')
      else jsonb_build_object('url', st.instance_url || '/services/data/' || (e ->> 'api_version') || '/query',
        'params', jsonb_build_object('q', 'SELECT ' || v_cols || ',LastModifiedDate FROM Lead WHERE LastModifiedDate > '
                                          || to_char(p_since at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || ' AND ' || v_ref || ' != null ORDER BY LastModifiedDate ASC LIMIT 200')) end
    when 'hubspot' then jsonb_build_object('headers', jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || coalesce(s ->> 'token', ''))) || case p_kind
      when 'schema' then jsonb_build_object('method', 'GET', 'url', 'https://api.hubapi.com/crm/v3/properties/contacts')
      else jsonb_build_object('method', 'POST', 'url', 'https://api.hubapi.com/crm/v3/objects/contacts/search',
        'body', jsonb_build_object(
          'filterGroups', jsonb_build_array(jsonb_build_object('filters', jsonb_build_array(
             jsonb_build_object('propertyName', 'lastmodifieddate', 'operator', 'GT', 'value', (floor(extract(epoch from p_since) * 1000))::bigint::text),
             jsonb_build_object('propertyName', v_ref, 'operator', 'HAS_PROPERTY')))),
          'properties', to_jsonb(array(select distinct x from unnest(array[v_status, v_ref, 'lastmodifieddate'] || v_fields) x)),
          'sorts', jsonb_build_array(jsonb_build_object('propertyName', 'lastmodifieddate', 'direction', 'ASCENDING')), 'limit', 100)) end
    end;
end $fn$;

create or replace function b2b.adapter_poll_parse(p_adapter text, j jsonb, p_status_field text, p_ref_field text)
returns jsonb language sql immutable set search_path = '' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('record_id', r ->> 'rid',
                                               'reference', coalesce(r -> 'f' ->> p_ref_field, b2b.json_path_text(r -> 'f', p_ref_field)),
                                               'stage', coalesce(r -> 'f' ->> p_status_field, b2b.json_path_text(r -> 'f', p_status_field)),
                                               'modified', r ->> 'modified', 'fields', r -> 'f')), '[]')
    from (
      select jsonb_build_object('rid', props ->> 'ProspectID', 'modified', props ->> 'ModifiedOn', 'f', props) r
        from jsonb_array_elements(case when p_adapter = 'leadsquared' then coalesce(j -> 'Leads', '[]') else '[]' end) l,
             lateral (select coalesce(jsonb_object_agg(a ->> 'Attribute', a -> 'Value'), '{}') props from jsonb_array_elements(coalesce(l -> 'LeadPropertyList', '[]')) a where a ->> 'Attribute' is not null) x
      union all
      select jsonb_build_object('rid', l ->> 'id', 'modified', l ->> 'Modified_Time', 'f', l - 'id')
        from jsonb_array_elements(case when p_adapter = 'zoho' then coalesce(j -> 'data', '[]') else '[]' end) l
      union all
      select jsonb_build_object('rid', l ->> 'Id', 'modified', l ->> 'LastModifiedDate', 'f', l - 'attributes' - 'Id')
        from jsonb_array_elements(case when p_adapter = 'salesforce' then coalesce(j -> 'records', '[]') else '[]' end) l
      union all
      select jsonb_build_object('rid', l ->> 'id', 'modified', coalesce(l ->> 'updatedAt', l -> 'properties' ->> 'lastmodifieddate'), 'f', coalesce(l -> 'properties', '{}'))
        from jsonb_array_elements(case when p_adapter = 'hubspot' then coalesce(j -> 'results', '[]') else '[]' end) l
      union all
      -- in-house: a list, or the first list under data / records / results / items / leads
      select jsonb_build_object('rid', coalesce(l ->> 'id', l ->> 'record_id', l ->> 'lead_id'),
                                'modified', coalesce(l ->> 'updated_at', l ->> 'modified_at', l ->> 'modified', l ->> 'last_modified', l ->> 'updatedAt'), 'f', l)
        from jsonb_array_elements(case when p_adapter <> 'inhouse' then '[]'::jsonb
                                       when jsonb_typeof(j) = 'array' then j
                                       else coalesce(case when jsonb_typeof(j -> 'data') = 'array' then j -> 'data' end, case when jsonb_typeof(j -> 'records') = 'array' then j -> 'records' end,
                                                     case when jsonb_typeof(j -> 'results') = 'array' then j -> 'results' end, case when jsonb_typeof(j -> 'items') = 'array' then j -> 'items' end,
                                                     case when jsonb_typeof(j -> 'leads') = 'array' then j -> 'leads' end, case when jsonb_typeof(j -> 'data' -> 'records') = 'array' then j -> 'data' -> 'records' end,
                                                     '[]') end) l
       where jsonb_typeof(l) = 'object') y;
$fn$;

create or replace function b2b.partner_adapter_save(p_partner_id bigint, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  pt b2b.partners;
  spec jsonb;
  v_env text := coalesce(p ->> 'env', 'live');
  cfg jsonb;
  v_old jsonb := '{}';
  v_new jsonb;
  v_secret_id uuid;
  v_url text;
  k text;
  t text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into pt from b2b.partners where id = p_partner_id for update;
  if pt.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  spec := b2b.adapter_spec(pt.adapter_type);
  if spec is null then raise exception 'this partner uses the generic contract; set its API credential instead' using errcode = '22023'; end if;
  if v_env not in ('live', 'sandbox') then raise exception 'environment must be live or sandbox' using errcode = '22023'; end if;
  cfg := coalesce(pt.outbound_auth -> v_env, '{}');
  if jsonb_typeof(pt.outbound_auth -> 'live') is null and jsonb_typeof(pt.outbound_auth -> 'sandbox') is null then
    -- first adapter save replaces a generic credential shape
    pt.outbound_auth := '{}';
  end if;

  for k in select jsonb_array_elements_text(spec -> 'settings') loop
    t := nullif(trim(coalesce(p -> 'settings' ->> k, cfg ->> k, '')), '');
    if k = 'host' and t is not null and t !~ '^[a-z0-9.-]+\.leadsquared\.com$' then raise exception 'the LeadSquared API host looks like api-in21.leadsquared.com' using errcode = '22023'; end if;
    if k in ('login_url', 'base_url') and t is not null and t !~ '^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._/-]*)?$' then raise exception '% must be an https address', k using errcode = '22023'; end if;
    if k in ('api_domain', 'accounts_domain') and t is not null and t !~ '^[a-z0-9.-]+\.zoho(apis)?\.(in|com|eu|com\.au|jp|com\.cn|ca|sa)$' then
      raise exception '% looks like www.zohoapis.in or accounts.zoho.in', k using errcode = '22023';
    end if;
    if k = 'api_version' and t is not null and t !~ '^v\d{2}\.\d$' then raise exception 'the Salesforce API version looks like v60.0' using errcode = '22023'; end if;
    if k = 'client_id' and t is not null and length(t) > 300 then raise exception 'the client ID is too long' using errcode = '22023'; end if;
    if k in ('create_url', 'poll_url') and t is not null and (t !~ '^https://[A-Za-z0-9.-]+(:\d+)?(/\S*)?$' or length(t) > 500) then
      raise exception '% must be an https address', replace(k, '_', ' ') using errcode = '22023';
    end if;
    if k = 'auth_type' and coalesce(t, '') not in ('bearer', 'header', 'basic', 'query', 'none') then raise exception 'choose how the CRM checks Eduwit''s key' using errcode = '22023'; end if;
    if k in ('auth_name', 'since_param') and t is not null and t !~ '^[A-Za-z][A-Za-z0-9_-]{0,59}$' then raise exception '% uses letters, digits, - and _', replace(k, '_', ' ') using errcode = '22023'; end if;
    if k in ('wrap_key', 'record_id_path') and t is not null and t !~ '^[A-Za-z_][A-Za-z0-9_]{0,59}(\.[A-Za-z0-9_]{1,60}){0,4}$' then
      raise exception '% looks like data or data.lead.id', replace(k, '_', ' ') using errcode = '22023';
    end if;
    if k = 'duplicate_status' and t is not null and (t !~ '^\d{3}$' or t::int not between 200 and 599) then raise exception 'the duplicate status is an HTTP code such as 409' using errcode = '22023'; end if;
    cfg := cfg || jsonb_build_object(k, t);
  end loop;
  foreach k in array array['reference_field', 'status_field'] loop
    if p ? k then
      t := nullif(trim(p ->> k), '');
      if t is not null and t !~ '^[A-Za-z_][A-Za-z0-9_]{0,79}(\.[A-Za-z0-9_]{1,60}){0,4}$' then
        raise exception 'a CRM field name uses letters, digits and underscores (an in-house CRM may use a path such as stage.name)' using errcode = '22023';
      end if;
      cfg := cfg || jsonb_build_object(k, t);
    end if;
  end loop;
  if p ? 'fixed' then
    if jsonb_typeof(p -> 'fixed') <> 'object' or (select count(*) from jsonb_object_keys(p -> 'fixed')) > 20 then raise exception 'fixed values must be at most 20 field: value pairs' using errcode = '22023'; end if;
    cfg := cfg || jsonb_build_object('fixed', p -> 'fixed');
  end if;
  if p ? 'poll' then cfg := cfg || jsonb_build_object('poll', coalesce((p ->> 'poll')::boolean, true)); end if;
  if p ? 'poll_minutes' then
    if coalesce((p ->> 'poll_minutes')::int, 0) not between 2 and 1440 then raise exception 'poll every 2 to 1,440 minutes' using errcode = '22023'; end if;
    cfg := cfg || jsonb_build_object('poll_minutes', (p ->> 'poll_minutes')::int);
  end if;

  -- secrets: merged with the stored JSON; every listed secret is required once
  v_secret_id := nullif(cfg ->> 'secret_id', '')::uuid;
  if v_secret_id is not null then begin v_old := b2b.partner_secret(v_secret_id)::jsonb; exception when others then v_old := '{}'; end; end if;
  v_new := v_old;
  for k in select jsonb_array_elements_text(spec -> 'secrets') loop
    t := nullif(p -> 'secrets' ->> k, '');
    if t is not null then
      if length(t) < 8 or length(t) > 4000 then raise exception '% looks wrong (8 to 4,000 characters)', replace(k, '_', ' ') using errcode = '22023'; end if;
      v_new := v_new || jsonb_build_object(k, t);
    end if;
    if nullif(v_new ->> k, '') is null and not (pt.adapter_type = 'inhouse' and cfg ->> 'auth_type' = 'none') then
      raise exception 'the % is required', replace(k, '_', ' ') using errcode = '22023';
    end if;
  end loop;
  for k in select jsonb_array_elements_text(spec -> 'settings') loop
    if k not in ('api_version', 'source', 'base_url', 'accounts_domain', 'api_domain', 'login_url', 'auth_name', 'wrap_key', 'record_id_path',
                 'duplicate_status', 'poll_url', 'since_param') and nullif(cfg ->> k, '') is null then
      raise exception 'the % is required', replace(k, '_', ' ') using errcode = '22023';
    end if;
  end loop;
  if v_new is distinct from v_old or v_secret_id is null then
    if v_secret_id is null then v_secret_id := vault.create_secret(v_new::text, 'b2b_partner_' || pt.id || '_' || v_env || '_crm', 'CRM credentials for partner ' || pt.slug || ' (' || v_env || ')');
    else perform vault.update_secret(v_secret_id, v_new::text); end if;
    -- new credentials: the cached access token is dropped
    update b2b.partner_adapter_state set token_expires_at = null, token_failed_at = null, token_error = null where partner_id = pt.id and env = v_env;
  end if;
  cfg := cfg || jsonb_build_object('secret_id', v_secret_id);
  -- the address shown as the partner's endpoint (pushes are built by the adapter)
  v_url := case pt.adapter_type
    when 'leadsquared' then 'https://' || (cfg ->> 'host')
    when 'zoho' then 'https://' || coalesce(cfg ->> 'api_domain', 'www.zohoapis.in')
    when 'salesforce' then coalesce(cfg ->> 'login_url', case when v_env = 'sandbox' then 'https://test.salesforce.com' else 'https://login.salesforce.com' end)
    when 'hubspot' then 'https://api.hubapi.com'
    when 'meritto' then coalesce(cfg ->> 'base_url', 'https://api.nopaperforms.io')
    when 'inhouse' then cfg ->> 'create_url' end;
  -- an in-house CRM without a changes address reports by webhook only
  if pt.adapter_type = 'inhouse' and nullif(cfg ->> 'poll_url', '') is null then cfg := cfg || jsonb_build_object('poll', false); end if;
  update b2b.partners
     set outbound_auth = coalesce(pt.outbound_auth, '{}') - 'type' - 'header' || jsonb_build_object(v_env, cfg),
         api_base_url = case when v_env = 'live' then v_url else api_base_url end,
         test_endpoint = case when v_env = 'sandbox' then v_url else test_endpoint end,
         outbound_secret_id = coalesce(outbound_secret_id, case when v_env = 'live' then v_secret_id end),
         updated_at = now(), updated_by = auth.uid()::text
   where id = pt.id;
  perform b2b.log_event('partner.adapter_saved', null, null, pt.id, jsonb_build_object('env', v_env, 'adapter', pt.adapter_type,
                        'secrets_changed', v_new is distinct from v_old));
  return b2b.partner_adapter_status(pt.id);
end $fn$;

revoke execute on function b2b.adapter_call(b2b.partners, text, text, timestamptz), b2b.adapter_poll_parse(text, jsonb, text, text) from public, anon, authenticated;
grant execute on function b2b.adapter_call(b2b.partners, text, text, timestamptz), b2b.adapter_poll_parse(text, jsonb, text, text) to service_role;
revoke execute on function b2b.partner_adapter_save(bigint, jsonb) from public, anon;
grant execute on function b2b.partner_adapter_save(bigint, jsonb) to authenticated, service_role;
