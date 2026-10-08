-- M19a: partner CRM adapters (spec B8.1, B8.2, B8.3.2): LeadSquared, Zoho CRM, Salesforce, HubSpot and Meritto, beside
-- the generic REST / webhook contract. Part 1: what each CRM needs, credentials, and the push request.
--   adapter_spec          per CRM: settings, secrets, default field names, status and reference fields, OAuth, polling
--   partner_adapter_state one row per partner and environment (live, sandbox): OAuth token, polling and schema fetches
--   adapter_env           the partner's settings and decrypted secrets for live or sandbox (secrets never leave the database)
--   adapter_values        the push payload flattened (name, first/last name, phone formats, programme…)
--   adapter_record        the lead in the CRM's own field names: defaults, then Mapping studio's outbound fields on top
--   adapter_push_request  URL, headers and body of the create call for one allocation
-- Responses, dispatch and collection are m19b; OAuth, schema discovery and polling m19c–m19d; the Admin's functions m19e.

create table if not exists b2b.partner_adapter_state (
  partner_id          bigint not null references b2b.partners (id) on delete cascade,
  env                 text not null check (env in ('live', 'sandbox')),
  token_secret_id     uuid,
  token_expires_at    timestamptz,
  token_request_id    bigint,
  token_requested_at  timestamptz,
  token_failed_at     timestamptz,
  token_error         text,
  instance_url        text,
  poll_since          timestamptz,
  poll_request_id     bigint,
  poll_requested_at   timestamptz,
  last_poll_at        timestamptz,
  last_poll_result    jsonb,
  last_poll_error     text,
  schema_request_id   bigint,
  schema_requested_at timestamptz,
  last_schema_at      timestamptz,
  last_schema_error   text,
  updated_at          timestamptz not null default now(),
  primary key (partner_id, env)
);
alter table b2b.partner_adapter_state enable row level security;
revoke all on b2b.partner_adapter_state from public, anon, authenticated;
grant all on b2b.partner_adapter_state to service_role;

/* What each CRM needs. settings: non-secret, per environment; secrets: stored together as one JSON secret in Vault.
   defaults: CRM field → value from adapter_values (a key) or a fixed text ('=Eduwit'). */
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
    end;
$fn$;

/* The partner's settings and secrets for one environment. Sandbox settings and secrets are separate; a sandbox setting
   left empty falls back to live only for non-secret, non-URL values (api_version). */
create or replace function b2b.adapter_env(p b2b.partners, p_env text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  cfg jsonb := coalesce(p.outbound_auth -> case when p_env = 'sandbox' then 'sandbox' else 'live' end, '{}');
  v_secret_id uuid := nullif(cfg ->> 'secret_id', '')::uuid;
  v_secrets jsonb := '{}';
  t text;
begin
  if v_secret_id is not null then
    t := b2b.partner_secret(v_secret_id);
    begin v_secrets := t::jsonb; exception when others then v_secrets := jsonb_build_object('token', t); end;
  end if;
  return (cfg - 'secret_id') || jsonb_build_object('secrets', coalesce(v_secrets, '{}'), 'configured', v_secret_id is not null,
         'api_version', coalesce(nullif(cfg ->> 'api_version', ''), nullif(p.outbound_auth -> 'live' ->> 'api_version', ''), 'v60.0'));
end $fn$;

/* The push payload flattened, in the formats CRMs ask for. */
create or replace function b2b.adapter_values(v jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $fn$
declare
  v_name text := nullif(trim(v -> 'student' ->> 'name'), '');
  v_first text := nullif(split_part(coalesce(v_name, ''), ' ', 1), '');
  v_last text := nullif(trim(substr(coalesce(v_name, ''), length(coalesce(v_first, '')) + 1)), '');
  d text := regexp_replace(coalesce(v -> 'student' ->> 'phone', ''), '\D', '', 'g');
begin
  return jsonb_strip_nulls(jsonb_build_object(
    'reference', v ->> 'reference', 'name', v_name, 'first_name', v_first, 'last_name', v_last,
    'last_name_required', coalesce(v_last, v_first, 'Student'),
    'phone', case when d <> '' then '+' || d end, 'phone_digits', nullif(d, ''), 'phone10', nullif(right(d, 10), ''),
    'phone_dash', case when length(d) > 10 then '+' || left(d, length(d) - 10) || '-' || right(d, 10) when d <> '' then d end,
    'email', v -> 'student' ->> 'email', 'city', v -> 'student' ->> 'city', 'state', v -> 'student' ->> 'state',
    'language', v -> 'student' ->> 'preferred_language',
    'university', v -> 'programme' ->> 'university', 'course', v -> 'programme' ->> 'course', 'specialization', v -> 'programme' ->> 'specialization',
    'level', v -> 'programme' ->> 'level', 'mode', v -> 'programme' ->> 'mode', 'partner_course_code', v -> 'programme' ->> 'partner_course_code',
    'qualification', v -> 'profile' ->> 'highest_qualification', 'timeline', v -> 'profile' ->> 'enrollment_timeline',
    'note', v ->> 'note', 'test', case when (v ->> 'test')::boolean then 'true' end));
end $fn$;

/* The lead in the CRM's field names: adapter defaults (the partner's own reference / status field names from its
   settings), then the outbound fields Mapping studio produced, which win. */
create or replace function b2b.adapter_record(p_adapter text, p_env jsonb, v jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  spec jsonb := b2b.adapter_spec(p_adapter);
  vals jsonb := b2b.adapter_values(v);
  o jsonb := '{}';
  k text;
  src text;
  v_ref text := coalesce(nullif(p_env ->> 'reference_field', ''), spec ->> 'reference_field');
begin
  for k, src in select key, value #>> '{}' from jsonb_each(spec -> 'defaults') loop
    if k = spec ->> 'reference_field' then k := v_ref; end if;
    if left(src, 1) = '=' then o := o || jsonb_build_object(k, substr(src, 2));
    elsif vals ? src then o := o || jsonb_build_object(k, vals ->> src); end if;
  end loop;
  if p_adapter = 'meritto' and nullif(p_env ->> 'source', '') is not null then o := o || jsonb_build_object('source', p_env ->> 'source'); end if;
  o := o || coalesce(p_env -> 'fixed', '{}') || coalesce(v -> 'fields', '{}');
  return jsonb_strip_nulls(o);
end $fn$;

/* The create call for one allocation. needs_token: the request waits for an OAuth access token (m19c). */
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
    when 'meritto' then jsonb_build_object(
      'url', rtrim(coalesce(nullif(e ->> 'base_url', ''), 'https://api.nopaperforms.io'), '/') || '/lead/v1/create',
      'headers', h || jsonb_build_object('access-key', s ->> 'access_key', 'secret-key', s ->> 'secret_key'),
      'body', rec)
    end || jsonb_build_object('adapter', p.adapter_type, 'env', v_env);
end $fn$;

revoke execute on function b2b.adapter_spec(text), b2b.adapter_env(b2b.partners, text), b2b.adapter_values(jsonb), b2b.adapter_record(text, jsonb, jsonb),
                           b2b.adapter_push_request(b2b.allocations, b2b.partners, jsonb)
  from public, anon, authenticated;
grant execute on function b2b.adapter_spec(text), b2b.adapter_env(b2b.partners, text), b2b.adapter_values(jsonb), b2b.adapter_record(text, jsonb, jsonb),
                          b2b.adapter_push_request(b2b.allocations, b2b.partners, jsonb)
  to service_role;
