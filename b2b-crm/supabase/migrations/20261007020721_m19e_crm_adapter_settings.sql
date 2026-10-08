-- M19e: partner CRM adapters, part 5: the Admin's functions (partner page → Connection).
--   partner_adapter_save    settings and secrets per environment (secrets: one JSON secret in Vault; empty keeps)
--   partner_adapter_status  what the Admin sees (never a secret)
--   partner_adapter_action  fetch the schema or poll now
--   partner_adapter_preview the create call a lead would make, credentials masked

/* p: {env: live|sandbox, settings: {...}, secrets: {...}, reference_field?, status_field?, fixed?: {field: value}, poll?, poll_minutes?}.
   Secret values left empty keep the stored ones. */
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
    cfg := cfg || jsonb_build_object(k, t);
  end loop;
  foreach k in array array['reference_field', 'status_field'] loop
    if p ? k then
      t := nullif(trim(p ->> k), '');
      if t is not null and t !~ '^[A-Za-z_][A-Za-z0-9_]{0,79}$' then raise exception 'a CRM field name uses letters, digits and underscores' using errcode = '22023'; end if;
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
    if nullif(v_new ->> k, '') is null then raise exception 'the % is required', replace(k, '_', ' ') using errcode = '22023'; end if;
  end loop;
  for k in select jsonb_array_elements_text(spec -> 'settings') loop
    if k not in ('api_version', 'source', 'base_url', 'accounts_domain', 'api_domain', 'login_url') and nullif(cfg ->> k, '') is null then
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
    when 'meritto' then coalesce(cfg ->> 'base_url', 'https://api.nopaperforms.io') end;
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

create or replace function b2b.partner_adapter_status(p_partner_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare pt b2b.partners; spec jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into pt from b2b.partners where id = p_partner_id;
  if pt.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  spec := b2b.adapter_spec(pt.adapter_type);
  if spec is null then return null; end if;
  return jsonb_build_object('adapter', pt.adapter_type, 'spec', spec - 'defaults' || jsonb_build_object('default_fields', spec -> 'defaults'),
    'envs', (select jsonb_object_agg(env, jsonb_build_object(
               'configured', nullif(pt.outbound_auth -> env ->> 'secret_id', '') is not null,
               'settings', coalesce(pt.outbound_auth -> env, '{}') - 'secret_id',
               'secrets_set', (select coalesce(jsonb_agg(k), '[]') from jsonb_array_elements_text(spec -> 'secrets') k
                                where nullif(pt.outbound_auth -> env ->> 'secret_id', '') is not null
                                  and nullif((b2b.adapter_env(pt, env) -> 'secrets') ->> k, '') is not null),
               'state', (select jsonb_build_object('token_valid', s.token_expires_at > now(), 'token_expires_at', s.token_expires_at, 'token_error', s.token_error,
                                                   'token_failed_at', s.token_failed_at, 'instance_url', s.instance_url, 'last_poll_at', s.last_poll_at,
                                                   'last_poll_result', s.last_poll_result, 'last_poll_error', s.last_poll_error, 'poll_since', s.poll_since,
                                                   'polling', s.poll_request_id is not null, 'last_schema_at', s.last_schema_at, 'last_schema_error', s.last_schema_error,
                                                   'fetching_schema', s.schema_request_id is not null)
                           from b2b.partner_adapter_state s where s.partner_id = pt.id and s.env = e.env)))
             from (values ('live'), ('sandbox')) e(env)),
    'polled_events_7d', (select count(*) from b2b.partner_events pe where pe.partner_id = pt.id and pe.event_id like 'poll:%' and pe.received_at > now() - interval '7 days'));
end $fn$;

/* action: schema | poll. */
create or replace function b2b.partner_adapter_action(p_partner_id bigint, p_env text, p_action text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare pt b2b.partners; v jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_env not in ('live', 'sandbox') or p_action not in ('schema', 'poll') then raise exception 'unknown action' using errcode = '22023'; end if;
  select * into pt from b2b.partners where id = p_partner_id;
  if pt.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  v := b2b.adapter_issue(pt, p_env, p_action);
  if v ? 'error' then raise exception '%', v ->> 'error' using errcode = '22023'; end if;
  perform b2b.log_event('partner.adapter_' || p_action, null, null, pt.id, jsonb_build_object('env', p_env));
  return v;
end $fn$;

/* The create call a lead would make, credentials masked. With no lead, a sample student is used. */
create or replace function b2b.partner_adapter_preview(p_partner_id bigint, p_env text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  pt b2b.partners;
  a b2b.allocations;
  v jsonb;
  req jsonb;
  h jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into pt from b2b.partners where id = p_partner_id;
  if pt.id is null or b2b.adapter_spec(pt.adapter_type) is null then raise exception 'not a CRM adapter partner' using errcode = '22023'; end if;
  select * into a from b2b.allocations where partner_id = pt.id and is_test = (p_env = 'sandbox') order by id desc limit 1;
  if a.id is not null then v := b2b.push_payload(a);
  else
    a.id := 0; a.reference := 'EDW-SAMPLE'; a.is_test := p_env = 'sandbox'; a.partner_id := pt.id;
    v := jsonb_build_object('reference', 'EDW-SAMPLE', 'test', p_env = 'sandbox',
      'student', jsonb_build_object('name', 'Asha Verma', 'phone', '+919876543210', 'email', 'asha@example.com', 'city', 'Delhi', 'state', 'Delhi'),
      'programme', jsonb_build_object('university', 'Example University', 'course', 'MBA', 'specialization', 'Finance', 'level', 'PG', 'mode', 'Online'),
      'note', 'Interested in MBA (Finance). Mode: Online');
  end if;
  -- the token is not needed to see the shape: preview as if one were present
  req := case when pt.adapter_type in ('zoho', 'salesforce')
              then jsonb_build_object('note', 'sent with an OAuth access token renewed automatically')
              else '{}' end
         || coalesce((select b2b.adapter_push_request(a, pt, v) where pt.adapter_type not in ('zoho', 'salesforce')), '{}');
  if pt.adapter_type in ('zoho', 'salesforce') then
    req := req || jsonb_build_object('body', case pt.adapter_type
             when 'zoho' then jsonb_build_object('data', jsonb_build_array(b2b.adapter_record(pt.adapter_type, b2b.adapter_env(pt, p_env), v)), 'trigger', jsonb_build_array('workflow'))
             else b2b.adapter_record(pt.adapter_type, b2b.adapter_env(pt, p_env), v) end,
           'url', case pt.adapter_type when 'zoho' then '…/crm/v5/Leads' else '…/services/data/' || (b2b.adapter_env(pt, p_env) ->> 'api_version') || '/sobjects/Lead/' end);
  end if;
  h := coalesce(req -> 'headers', '{}');
  h := (select coalesce(jsonb_object_agg(key, case when key ilike any (array['authorization', '%key%', '%secret%', '%token%']) then to_jsonb('••••'::text) else value end), '{}')
          from jsonb_each(h));
  return jsonb_build_object('reference', a.reference, 'sample', a.id = 0, 'url', req ->> 'url', 'headers', h, 'body', req -> 'body',
                            'error', coalesce(req ->> 'error', req ->> 'token_error'));
end $fn$;

revoke execute on function b2b.partner_adapter_save(bigint, jsonb), b2b.partner_adapter_status(bigint), b2b.partner_adapter_action(bigint, text, text),
                           b2b.partner_adapter_preview(bigint, text)
  from public, anon, authenticated;
grant execute on function b2b.partner_adapter_save(bigint, jsonb), b2b.partner_adapter_status(bigint), b2b.partner_adapter_action(bigint, text, text),
                          b2b.partner_adapter_preview(bigint, text)
  to authenticated, service_role;
