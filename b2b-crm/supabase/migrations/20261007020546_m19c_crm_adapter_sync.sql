-- M19c: partner CRM adapters, part 3: OAuth tokens (Zoho, Salesforce), schema discovery and polling.
--   adapter_token_request / adapter_token_collect   refresh-token grant through pg_net; the access token is kept in Vault
--   adapter_call             one read request (schema or poll) for a partner and environment
--   adapter_schema_parse     the CRM's field list as a schema snapshot {fields, stages} (drift is detected as in m15e)
--   adapter_poll_parse       records changed since the last poll: {record_id, reference, stage, modified, fields}
--   mapping_snapshot_store   mapping_snapshot_save without the Admin check, for the daily schema check (m19d)
-- Meritto has no polling or schema API here: it reports by webhook (docs/partner-api.md) and its schema is uploaded.

create or replace function b2b.mapping_snapshot_store(p_partner_id bigint, p_source text, p_schema jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  prev jsonb;
  v_drift jsonb := '[]';
  v_id bigint;
  act bigint;
  r record;
begin
  if p_source not in ('upload', 'api', 'events') then raise exception 'unknown source' using errcode = '22023'; end if;
  if jsonb_typeof(p_schema) <> 'object' or jsonb_typeof(coalesce(p_schema -> 'fields', '[]')) <> 'array' or jsonb_typeof(coalesce(p_schema -> 'stages', '[]')) <> 'array' then
    raise exception 'the schema needs fields and stages lists' using errcode = '22023';
  end if;
  if length(p_schema::text) > 500000 then raise exception 'the schema is too large' using errcode = '22023'; end if;
  if not exists (select 1 from b2b.partners where id = p_partner_id) then raise exception 'partner not found' using errcode = 'P0002'; end if;
  select schema into prev from b2b.partner_schema_snapshots where partner_id = p_partner_id order by id desc limit 1;
  select id into act from b2b.mapping_profiles where partner_id = p_partner_id and status = 'active';

  if prev is not null then
    for r in
      with ps as (select lower(trim(s ->> 'stage')) k, s ->> 'stage' st from jsonb_array_elements(coalesce(prev -> 'stages', '[]')) s),
           ns as (select lower(trim(s ->> 'stage')) k, s ->> 'stage' st from jsonb_array_elements(coalesce(p_schema -> 'stages', '[]')) s),
           pf as (select lower(trim(f ->> 'name')) k, f ->> 'name' nm, f ->> 'type' tp, f -> 'values' vals from jsonb_array_elements(coalesce(prev -> 'fields', '[]')) f),
           nf as (select lower(trim(f ->> 'name')) k, f ->> 'name' nm, f ->> 'type' tp, f -> 'values' vals from jsonb_array_elements(coalesce(p_schema -> 'fields', '[]')) f)
      select 'new_stage' what, ns.st item, null::text detail from ns where not exists (select 1 from ps where ps.k = ns.k)
      union all select 'removed_stage', ps.st, null from ps where not exists (select 1 from ns where ns.k = ps.k)
      union all select 'new_field', nf.nm, null from nf where not exists (select 1 from pf where pf.k = nf.k)
      union all select 'removed_field', pf.nm, null from pf where not exists (select 1 from nf where nf.k = pf.k)
      union all select 'type_changed', nf.nm, pf.tp || ' → ' || nf.tp from nf join pf on pf.k = nf.k where coalesce(pf.tp, '') <> coalesce(nf.tp, '') and pf.tp is not null
      union all select 'removed_value', nf.nm, v from nf join pf on pf.k = nf.k cross join lateral jsonb_array_elements_text(coalesce(pf.vals, '[]')) v
                 where jsonb_typeof(nf.vals) = 'array' and not exists (select 1 from jsonb_array_elements_text(nf.vals) w where lower(w) = lower(v))
    loop
      v_drift := v_drift || jsonb_build_object('what', r.what, 'item', r.item, 'detail', r.detail,
        'required', act is not null and r.what in ('removed_field', 'type_changed', 'removed_value')
                    and exists (select 1 from b2b.field_rules x join b2b.canonical_fields c on c.key = x.canonical_key
                                 where x.profile_id = act and lower(x.partner_field) = lower(r.item) and (x.required or c.required_out or c.required_in)));
    end loop;
  end if;

  insert into b2b.partner_schema_snapshots (partner_id, source, schema, drift, created_by)
  values (p_partner_id, p_source, p_schema, case when prev is null then null else v_drift end, b2b.actor() ->> 'id') returning id into v_id;
  if jsonb_array_length(v_drift) > 0 then
    perform b2b.mapping_queue_add(p_partner_id,
      (select jsonb_agg(jsonb_build_object('kind', 'drift', 'item', (d ->> 'what') || ': ' || (d ->> 'item') || coalesce(' (' || (d ->> 'detail') || ')', ''),
                                           'required', d -> 'required')) from jsonb_array_elements(v_drift) d), null);
    perform b2b.log_event('alert.mapping_drift', null, null, p_partner_id, jsonb_build_object('snapshot_id', v_id, 'changes', jsonb_array_length(v_drift),
      'required', exists (select 1 from jsonb_array_elements(v_drift) d where (d ->> 'required')::boolean)));
  end if;
  return jsonb_build_object('id', v_id, 'drift', v_drift);
end $fn$;

/* As m15e, through the store above. */
create or replace function b2b.mapping_snapshot_save(p_partner_id bigint, p_source text, p_schema jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.mapping_snapshot_store(p_partner_id, p_source, p_schema);
end $fn$;

-- ---------- OAuth ----------
create or replace function b2b.adapter_token_request(p b2b.partners, p_env text)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e jsonb := b2b.adapter_env(p, p_env);
  st b2b.partner_adapter_state;
  v_url text;
  v_net bigint;
begin
  if not coalesce((b2b.adapter_spec(p.adapter_type) ->> 'oauth')::boolean, false) or not (e ->> 'configured')::boolean then return null; end if;
  insert into b2b.partner_adapter_state (partner_id, env) values (p.id, p_env) on conflict do nothing;
  select * into st from b2b.partner_adapter_state where partner_id = p.id and env = p_env for update;
  if st.token_request_id is not null and st.token_requested_at > now() - interval '2 minutes' then return st.token_request_id; end if;
  if st.token_failed_at > now() - interval '5 minutes' then return null; end if;
  v_url := case p.adapter_type
    when 'zoho' then 'https://' || coalesce(nullif(e ->> 'accounts_domain', ''), 'accounts.zoho.in') || '/oauth/v2/token'
    when 'salesforce' then rtrim(coalesce(nullif(e ->> 'login_url', ''), case when p_env = 'sandbox' then 'https://test.salesforce.com' else 'https://login.salesforce.com' end), '/')
                           || '/services/oauth2/token' end;
  v_net := net.http_post(url := v_url, body := '{}'::jsonb,
    params := jsonb_build_object('grant_type', 'refresh_token', 'client_id', e ->> 'client_id', 'client_secret', e -> 'secrets' ->> 'client_secret',
                                 'refresh_token', e -> 'secrets' ->> 'refresh_token'),
    headers := jsonb_build_object('Content-Type', 'application/json'), timeout_milliseconds := 10000);   -- pg_net posts JSON only; the grant travels in the query string
  update b2b.partner_adapter_state set token_request_id = v_net, token_requested_at = now(), updated_at = now() where partner_id = p.id and env = p_env;
  return v_net;
end $fn$;

create or replace function b2b.adapter_token_collect()
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  st record;
  h record;
  j jsonb;
  v_secret uuid;
  v_name text;
  n int := 0;
begin
  for st in select s.*, p.adapter_type, p.slug from b2b.partner_adapter_state s join b2b.partners p on p.id = s.partner_id where s.token_request_id is not null loop
    select x.status_code, x.content, x.error_msg, x.timed_out into h from net._http_response x where x.id = st.token_request_id;
    if not found then
      if st.token_requested_at < now() - interval '5 minutes' then
        update b2b.partner_adapter_state set token_request_id = null, token_failed_at = now(), token_error = 'no answer from the sign-in service' where partner_id = st.partner_id and env = st.env;
      end if;
      continue;
    end if;
    begin j := h.content::jsonb; exception when others then j := null; end;
    if h.status_code = 200 and j ->> 'access_token' is not null then
      v_name := 'b2b_partner_' || st.partner_id || '_' || st.env || '_access_token';
      v_secret := coalesce(st.token_secret_id, (select vs.id from vault.secrets vs where vs.name = v_name));
      if v_secret is null then v_secret := vault.create_secret(j ->> 'access_token', v_name, 'CRM access token for partner ' || st.slug || ' (' || st.env || ', renewed automatically)');
      else perform vault.update_secret(v_secret, j ->> 'access_token'); end if;
      update b2b.partner_adapter_state
         set token_secret_id = v_secret, token_request_id = null, token_failed_at = null, token_error = null,
             token_expires_at = now() + make_interval(secs => coalesce((j ->> 'expires_in')::int, 3000) - 120),
             instance_url = coalesce(j ->> 'instance_url', j ->> 'api_domain', instance_url), updated_at = now()
       where partner_id = st.partner_id and env = st.env;
    else
      update b2b.partner_adapter_state
         set token_request_id = null, token_failed_at = now(), updated_at = now(),
             token_error = left('CRM sign-in failed: ' || coalesce(j ->> 'error_description', j ->> 'error', h.error_msg, 'HTTP ' || h.status_code), 300)
       where partner_id = st.partner_id and env = st.env;
      perform b2b.log_event('alert.partner_auth', null, null, st.partner_id, jsonb_build_object('env', st.env, 'error', left(coalesce(j ->> 'error', h.error_msg, 'HTTP ' || h.status_code), 200)));
    end if;
    n := n + 1;
  end loop;
  return n;
end $fn$;

-- ---------- reads: schema and polling ----------
/* Inbound partner field names from the active mapping (so polls ask for them), at most 60. */
create or replace function b2b.adapter_poll_fields(p_partner_id bigint)
returns text[] language sql stable set search_path = '' as $fn$
  select coalesce(array_agg(distinct x.partner_field), '{}') from (
    select r.partner_field from b2b.field_rules r join b2b.mapping_profiles pr on pr.id = r.profile_id
     where pr.partner_id = p_partner_id and pr.status = 'active' and r.direction in ('in', 'both') and not r.not_available
     limit 60) x;
$fn$;

/* One read request. kind: schema | poll. Returns {method, url, headers, params, body} or {error}. */
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

/* The CRM's field list as a schema snapshot. */
create or replace function b2b.adapter_schema_parse(p_adapter text, j jsonb, p_status_field text)
returns jsonb language plpgsql immutable set search_path = '' as $fn$
declare
  f jsonb;
begin
  f := case p_adapter
    when 'leadsquared' then (select coalesce(jsonb_agg(jsonb_build_object('name', x ->> 'SchemaName', 'label', x ->> 'DisplayName', 'type', x ->> 'DataType',
                               'values', (select jsonb_agg(coalesce(o ->> 'Value', o ->> 'Text')) from jsonb_array_elements(coalesce(x -> 'Options', '[]')) o))), '[]')
                               from jsonb_array_elements(case when jsonb_typeof(j) = 'array' then j else '[]' end) x)
    when 'zoho' then (select coalesce(jsonb_agg(jsonb_build_object('name', x ->> 'api_name', 'label', x ->> 'field_label', 'type', x ->> 'data_type',
                        'values', (select jsonb_agg(coalesce(o ->> 'actual_value', o ->> 'display_value')) from jsonb_array_elements(coalesce(x -> 'pick_list_values', '[]')) o))), '[]')
                        from jsonb_array_elements(coalesce(j -> 'fields', '[]')) x)
    when 'salesforce' then (select coalesce(jsonb_agg(jsonb_build_object('name', x ->> 'name', 'label', x ->> 'label', 'type', x ->> 'type',
                              'values', (select jsonb_agg(o ->> 'value') from jsonb_array_elements(coalesce(x -> 'picklistValues', '[]')) o where coalesce((o ->> 'active')::boolean, true)))), '[]')
                              from jsonb_array_elements(coalesce(j -> 'fields', '[]')) x)
    when 'hubspot' then (select coalesce(jsonb_agg(jsonb_build_object('name', x ->> 'name', 'label', x ->> 'label', 'type', x ->> 'type',
                           'values', (select jsonb_agg(o ->> 'value') from jsonb_array_elements(coalesce(x -> 'options', '[]')) o where not coalesce((o ->> 'hidden')::boolean, false)))), '[]')
                           from jsonb_array_elements(coalesce(j -> 'results', '[]')) x where not coalesce((x ->> 'hidden')::boolean, false))
    end;
  f := (select coalesce(jsonb_agg(jsonb_strip_nulls(x)), '[]') from jsonb_array_elements(coalesce(f, '[]')) x);
  return jsonb_build_object('fields', f,
    'stages', (select coalesce(jsonb_agg(jsonb_build_object('stage', v)), '[]') from jsonb_array_elements(f) x, jsonb_array_elements_text(coalesce(x -> 'values', '[]')) v
                where lower(x ->> 'name') = lower(p_status_field)));
end $fn$;

/* Records changed since the last poll. */
create or replace function b2b.adapter_poll_parse(p_adapter text, j jsonb, p_status_field text, p_ref_field text)
returns jsonb language sql immutable set search_path = '' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('record_id', r ->> 'rid', 'reference', r -> 'f' ->> p_ref_field, 'stage', r -> 'f' ->> p_status_field,
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
        from jsonb_array_elements(case when p_adapter = 'hubspot' then coalesce(j -> 'results', '[]') else '[]' end) l) y;
$fn$;
