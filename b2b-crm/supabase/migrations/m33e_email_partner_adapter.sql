-- M33e (15 Oct): leads by email for partners without any API (go-live limitation 'Partners without an API cannot be
-- routed to automatically', docs/go-live-setup.md 15).
--   adapter_type 'email'      The partner gets each allocated lead as an email through Eduwit's own email provider (the
--                             Notifications settings: Resend or Brevo), to the address(es) in the adapter settings
--                             (to_email, cc_email, subject_prefix; live and sandbox kept apart). The provider's 2xx answer
--                             is the push's 'created' (record id = the provider's message id); the hold window then runs
--                             as for any partner. There is nothing to map and no signing secret: the go-live checklist
--                             counts both as done. Outcomes come back by hand: allocation_outcome_manual records what the
--                             partner reported (a stage, a sub-stage, lost with a reason) as a partner activity and
--                             applies it through the same path as a CRM event.
--   Replaced: adapter_spec (m21c), adapter_env (m19a), partner_adapter_status (m19e), partner_adapter_save (m31i),
--             push_request (m19b), push_collect (m21c), partner_checklist (m31p). New: email_push_request,
--             allocation_outcome_manual. The partners.adapter_type check gains 'email'.
-- Nothing on student_leads' structure, nothing on Witty. Re-appliable.

alter table b2b.partners drop constraint if exists partners_adapter_type_check;
alter table b2b.partners add constraint partners_adapter_type_check
  check (adapter_type in ('leadsquared', 'salesforce', 'zoho', 'meritto', 'hubspot', 'inhouse', 'generic_rest', 'webhook', 'email'));

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
    -- M33e: a partner without any API gets each lead by email (settings only; the message goes through Eduwit's email provider)
    when 'email' then '{
      "label": "Email (no CRM API)", "settings": ["to_email", "cc_email", "subject_prefix"], "secrets": [], "oauth": false, "poll": false, "schema": false,
      "status_field": "status", "reference_field": "reference", "record_field": "message_id", "defaults": {}}'::jsonb
    end;
$fn$;

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
  return (cfg - 'secret_id') || jsonb_build_object('secrets', coalesce(v_secrets, '{}'),
         'configured', v_secret_id is not null or (p.adapter_type = 'email' and nullif(cfg ->> 'to_email', '') is not null),
         'api_version', coalesce(nullif(cfg ->> 'api_version', ''), nullif(p.outbound_auth -> 'live' ->> 'api_version', ''), 'v60.0'));
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
               'configured', nullif(pt.outbound_auth -> env ->> 'secret_id', '') is not null or (pt.adapter_type = 'email' and nullif(pt.outbound_auth -> env ->> 'to_email', '') is not null),
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
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_hold_sync int := round(coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'hold_minutes_sync'), 0))::int;
  v_hold_async int := round(coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'hold_minutes_async'), 30))::int;
  v_conf boolean;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into pt from b2b.partners where id = p_partner_id for update;
  if pt.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
  spec := b2b.adapter_spec(pt.adapter_type);
  if spec is null then raise exception 'this partner uses the generic contract; set its API credential instead' using errcode = '22023'; end if;
  if v_env not in ('live', 'sandbox') then raise exception 'environment must be live or sandbox' using errcode = '22023'; end if;
  if p ? 'dedupe_confirmed' and jsonb_typeof(p -> 'dedupe_confirmed') not in ('boolean', 'null') then
    raise exception 'dedupe_confirmed: true or false' using errcode = '22023';
  end if;
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
    -- M33e: the email adapter's addresses
    if k in ('to_email', 'cc_email') and t is not null then
      t := lower(t);
      if exists (select 1 from regexp_split_to_table(t, '\s*,\s*') x where x !~ '^[a-z0-9._%+''-]+@[a-z0-9.-]+\.[a-z]{2,}$') or length(t) > 500 then
        raise exception '% must be one or more email addresses, separated by commas', replace(k, '_', ' ') using errcode = '22023';
      end if;
    end if;
    if k = 'subject_prefix' and t is not null and length(t) > 60 then raise exception 'the subject prefix is at most 60 characters' using errcode = '22023'; end if;
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
                 'duplicate_status', 'poll_url', 'since_param', 'cc_email', 'subject_prefix') and nullif(cfg ->> k, '') is null then
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
    when 'inhouse' then cfg ->> 'create_url'
    when 'email' then null end;
  -- an in-house CRM without a changes address reports by webhook only
  if pt.adapter_type = 'inhouse' and nullif(cfg ->> 'poll_url', '') is null then cfg := cfg || jsonb_build_object('poll', false); end if;
  -- D37: the hold window follows the Admin's confirmation that this CRM blocks duplicates on create
  v_conf := case when p ? 'dedupe_confirmed' and jsonb_typeof(p -> 'dedupe_confirmed') = 'boolean' then (p ->> 'dedupe_confirmed')::boolean
                 else pt.dedupe_confirmed_at is not null end;
  update b2b.partners
     set outbound_auth = coalesce(pt.outbound_auth, '{}') - 'type' - 'header' || jsonb_build_object(v_env, cfg),
         api_base_url = case when v_env = 'live' then v_url else api_base_url end,
         test_endpoint = case when v_env = 'sandbox' then v_url else test_endpoint end,
         outbound_secret_id = coalesce(outbound_secret_id, case when v_env = 'live' then v_secret_id end),
         dedupe_mode = case when v_conf then 'sync' when pt.dedupe_mode = 'none' then 'none' else 'async' end,
         hold_minutes = case when v_conf then v_hold_sync else v_hold_async end,
         duplicate_window_hours = 24,
         dedupe_confirmed_at = case when v_conf then coalesce(pt.dedupe_confirmed_at, now()) end,
         updated_at = now(), updated_by = auth.uid()::text
   where id = pt.id;
  perform b2b.log_event('partner.adapter_saved', null, null, pt.id, jsonb_build_object('env', v_env, 'adapter', pt.adapter_type,
                        'secrets_changed', v_new is distinct from v_old, 'dedupe_confirmed', v_conf));
  return b2b.partner_adapter_status(pt.id);
end $fn$;

/* The provider request that emails one lead to an email partner. Settings come from the Notifications screen (email
   provider, from address, API key); the recipients from the partner's adapter settings for the lead's environment. */
create or replace function b2b.email_push_request(a b2b.allocations, p b2b.partners, v jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_env text := case when a.is_test then 'sandbox' else 'live' end;
  e jsonb := b2b.adapter_env(p, v_env);
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  m jsonb := coalesce(s -> 'email', '{}');
  v_secret text;
  v_to text[];
  v_cc text[];
  v_subject text;
  v_text text;
  v_html text;
  lead jsonb := coalesce(v -> 'lead', v -> 'student', v);
  r record;
  rows text := '';
  plain text := '';
begin
  if nullif(e ->> 'to_email', '') is null then return jsonb_build_object('url', null, 'error', 'no ' || v_env || ' email address for this partner', 'env', v_env); end if;
  v_secret := case when m ->> 'api_key_secret_id' is not null then b2b.partner_secret((m ->> 'api_key_secret_id')::uuid) end;
  if v_secret is null or m ->> 'from_email' is null then return jsonb_build_object('url', null, 'error', 'the email provider is not set up (Notifications)', 'env', v_env); end if;
  v_to := array(select trim(x) from regexp_split_to_table(lower(e ->> 'to_email'), ',') x where trim(x) <> '');
  v_cc := array(select trim(x) from regexp_split_to_table(lower(coalesce(e ->> 'cc_email', '')), ',') x where trim(x) <> '');
  v_subject := coalesce(nullif(e ->> 'subject_prefix', ''), 'Eduwit lead') || ' ' || a.reference || ': '
               || coalesce(lead ->> 'name', lead ->> 'full_name', 'student') || coalesce(' · ' || coalesce(lead ->> 'course', lead ->> 'interested_course'), '')
               || case when a.is_test then ' (TEST)' else '' end;
  for r in select key, value from jsonb_each(lead) where jsonb_typeof(value) <> 'null' and jsonb_typeof(value) <> 'object' and jsonb_typeof(value) <> 'array' order by key loop
    rows := rows || '<tr><td style="padding:4px 10px 4px 0;color:#666">' || b2b.html_escape(replace(r.key, '_', ' ')) || '</td><td style="padding:4px 0">' || b2b.html_escape(r.value #>> '{}') || '</td></tr>';
    plain := plain || replace(r.key, '_', ' ') || ': ' || (r.value #>> '{}') || E'\n';
  end loop;
  v_text := 'New lead from Eduwit, reference ' || a.reference || E'.\n\n' || plain
            || E'\nPlease record your outcome with your Eduwit contact. This email was sent by the Eduwit Partner CRM.';
  v_html := '<div style="font-family:Arial,sans-serif;font-size:14px;color:#222"><p>New lead from <b>Eduwit</b>, reference <b>' || b2b.html_escape(a.reference) || '</b>'
            || case when a.is_test then ' <span style="color:#b45309">(test)</span>' else '' end || '.</p><table style="border-collapse:collapse">' || rows || '</table>'
            || '<p style="color:#666;font-size:12px">Please record your outcome with your Eduwit contact. Sent by the Eduwit Partner CRM.</p></div>';
  if coalesce(m ->> 'provider', 'resend') = 'brevo' then
    return jsonb_build_object('provider', 'brevo', 'adapter', 'email', 'env', v_env,
      'url', coalesce(m ->> 'base_url', 'https://api.brevo.com') || '/v3/smtp/email',
      'headers', jsonb_build_object('Content-Type', 'application/json', 'api-key', v_secret),
      'body', jsonb_strip_nulls(jsonb_build_object(
        'sender', jsonb_build_object('name', coalesce(m ->> 'from_name', 'Eduwit Partner CRM'), 'email', m ->> 'from_email'),
        'to', (select jsonb_agg(jsonb_build_object('email', x)) from unnest(v_to) x),
        'cc', case when cardinality(v_cc) > 0 then (select jsonb_agg(jsonb_build_object('email', x)) from unnest(v_cc) x) end,
        'subject', v_subject, 'textContent', v_text, 'htmlContent', v_html,
        'replyTo', case when m ->> 'reply_to' is not null then jsonb_build_object('email', m ->> 'reply_to') end,
        'headers', jsonb_build_object('X-Eduwit-Reference', a.reference))));
  end if;
  return jsonb_build_object('provider', 'resend', 'adapter', 'email', 'env', v_env,
    'url', coalesce(m ->> 'base_url', 'https://api.resend.com') || '/emails',
    'headers', jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret, 'Idempotency-Key', 'push-' || a.id || '-' || (a.push_attempts + 1)),
    'body', jsonb_strip_nulls(jsonb_build_object(
      'from', coalesce(m ->> 'from_name', 'Eduwit Partner CRM') || ' <' || (m ->> 'from_email') || '>', 'to', to_jsonb(v_to),
      'cc', case when cardinality(v_cc) > 0 then to_jsonb(v_cc) end,
      'subject', v_subject, 'text', v_text, 'html', v_html, 'reply_to', m ->> 'reply_to',
      'headers', jsonb_build_object('X-Eduwit-Reference', a.reference))));
end $fn$;

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
  if p.adapter_type = 'email' then return b2b.email_push_request(a, p, v_body); end if;
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
    elsif r.adapter_type = 'email' then
      -- M33e: the email provider's answer (Resend: 200 {id}; Brevo: 201 {messageId}); a refused key is the Admin's problem, not the partner's
      v_rid := coalesce(j ->> 'id', j ->> 'messageId', j -> 'data' ->> 'id');
      v_reason := coalesce(j ->> 'message', j ->> 'error', j -> 'error' ->> 'message', left(r.content, 300));
      v_outcome := case when r.status_code between 200 and 299 then 'created' else 'error' end;
      if r.status_code in (401, 403) then
        perform b2b.log_event('alert.push_error', null, r.id, r.partner_id, jsonb_build_object('error', 'the email provider refused Eduwit''s key: ' || left(coalesce(v_reason, ''), 200)));
      end if;
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

create or replace function b2b.partner_checklist(p b2b.partners)
returns jsonb language sql stable set search_path = '' as $fn$
  select jsonb_build_array(
    jsonb_build_object('key', 'agreement',   'done', p.agreement_confirmed_at is not null, 'available', true),
    jsonb_build_object('key', 'programmes',  'done', exists (select 1 from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active), 'available', true),
    -- M33e: an email partner needs a live address, no API credential and no signing secret
    jsonb_build_object('key', 'credentials', 'done', case when p.adapter_type = 'email' then nullif(p.outbound_auth -> 'live' ->> 'to_email', '') is not null
                                                          else p.api_base_url is not null and (p.outbound_secret_id is not null or p.outbound_auth ->> 'type' = 'none')
                                                               and p.inbound_secret_id is not null end, 'available', true),
    jsonb_build_object('key', 'dedupe',      'done', p.dedupe_mode <> 'sync' or p.dedupe_confirmed_at is not null, 'available', true),
    jsonb_build_object('key', 'mapping',     'done', p.adapter_type = 'email' or b2b.mapping_ready(p.id), 'available', p.adapter_type <> 'email'),
    jsonb_build_object('key', 'sla_hours',   'done', exists (select 1 from jsonb_each(p.working_hours) d where jsonb_typeof(d.value) = 'object'), 'available', true),
    jsonb_build_object('key', 'branding',    'done', p.display_name is not null and p.brand_color is not null and p.logo_url is not null, 'available', true),
    jsonb_build_object('key', 'test_leads',  'done', exists (select 1 from b2b.allocations a where a.partner_id = p.id and a.is_test and a.status in ('accepted', 'closed')), 'available', true)
  );
$fn$;

/* The Admin records what a partner reported outside any API (an email partner, a phone call): a stage with an optional
   sub-stage and note, or 'lost' with a reason. Stored as a partner activity (kind stage_change) and applied through the
   same path as a mapped CRM event (forward only; lost goes to the lost grace; duplicate claims use the Sync & SLAs screen). */
create or replace function b2b.allocation_outcome_manual(p_allocation_id bigint, p_stage text, p_sub_stage text default null, p_note text default null, p_lost_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  v_stage text := lower(trim(coalesce(p_stage, '')));
  v_res text;
  v_act bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into a from b2b.allocations where id = p_allocation_id for update;
  if a.id is null then raise exception 'allocation not found' using errcode = 'P0002'; end if;
  if a.destination_type <> 'partner' or a.status not in ('pushed', 'accepted') then raise exception 'the partner does not hold this lead' using errcode = '22023'; end if;
  if v_stage <> 'lost' and not exists (select 1 from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages' and e ->> 'key' = v_stage) then
    raise exception 'unknown stage %', v_stage using errcode = '22023';
  end if;
  if v_stage = 'lost' and length(trim(coalesce(p_lost_reason, ''))) < 2 then raise exception 'give the reason the partner lost the lead' using errcode = '22023'; end if;
  insert into b2b.partner_activities (allocation_id, lead_id, partner_id, kind, direction, outcome, occurred_at, raw, mapped)
  values (a.id, a.lead_id, a.partner_id, 'stage_change', 'inbound', v_stage, now(),
          jsonb_strip_nulls(jsonb_build_object('source', 'admin', 'stage', v_stage, 'sub_stage', p_sub_stage, 'note', left(p_note, 1000), 'lost_reason', p_lost_reason, 'by', auth.jwt() ->> 'email')),
          jsonb_strip_nulls(jsonb_build_object('stage', v_stage, 'sub_stage', p_sub_stage, 'lost_reason', p_lost_reason)))
  returning id into v_act;
  perform set_config('b2b.actor', 'admin', true);
  v_res := b2b.apply_partner_mapped_stage(a.id, jsonb_strip_nulls(jsonb_build_object('stage', v_stage, 'sub_stage', left(p_sub_stage, 120), 'lost_reason', p_lost_reason)),
                                          jsonb_strip_nulls(jsonb_build_object('stage', v_stage, 'sub_stage', p_sub_stage, 'occurred_at', now(), 'note', left(p_note, 1000))));
  perform b2b.log_event('partner.outcome_manual', a.lead_id, a.id, a.partner_id, jsonb_strip_nulls(jsonb_build_object('stage', v_stage, 'sub_stage', p_sub_stage,
                        'lost_reason', p_lost_reason, 'note', left(p_note, 1000), 'result', v_res, 'activity_id', v_act)));
  return jsonb_build_object('allocation_id', a.id, 'result', v_res, 'activity_id', v_act);
end $fn$;

revoke execute on function b2b.email_push_request(b2b.allocations, b2b.partners, jsonb), b2b.push_request(b2b.allocations), b2b.push_collect() from public, anon, authenticated;
grant execute on function b2b.email_push_request(b2b.allocations, b2b.partners, jsonb), b2b.push_request(b2b.allocations), b2b.push_collect() to service_role;
revoke execute on function b2b.allocation_outcome_manual(bigint, text, text, text, text), b2b.partner_adapter_save(bigint, jsonb), b2b.partner_adapter_status(bigint) from public, anon;
grant execute on function b2b.allocation_outcome_manual(bigint, text, text, text, text), b2b.partner_adapter_save(bigint, jsonb), b2b.partner_adapter_status(bigint) to authenticated, service_role;
