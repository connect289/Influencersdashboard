-- M34e (31 Oct 2026, audit B2B-S1): the database calls only addresses on the public internet.
--   b2b.url_allowed(url)   NEW, pure: true for an https:// address whose host is a public name or a public IPv4 dotted quad;
--                          false for loopback, private, link-local and metadata ranges, carrier-grade NAT, multicast and
--                          reserved ranges, any other numeric or hex host form, IPv6 literals, single-label names,
--                          internal names (localhost, .local, .internal, .lan, .svc, cluster.local …), names that resolve
--                          to the address written in them (nip.io, sslip.io …), user:password@, whitespace or backslashes.
--   Saving: partner_save (API base URL, test endpoint), partner_adapter_save (login, base, create-lead and changed-leads
--           addresses) and webhook_endpoint_save refuse such an address (22023). The AI worker address: m34f.
--   Sending, where pg_net is called: push_dispatch fails the push for good (like a partner with no address),
--           adapter_issue answers an error, adapter_token_request records a failed sign-in, notify_tick and
--           admin_send_tick fail the message, outbox_tick marks the delivery dead with an alert.
--   Each replaced function is its production definition with only those lines added.
-- Re-appliable. Checked by supabase/tests/test_m34e_outbound_urls.sql.

create or replace function b2b.url_allowed(p_url text)
returns boolean language plpgsql immutable set search_path = '' as $fn$
declare
  v_auth text;
  v_host text;
  v_port text;
  o int[];
begin
  if p_url is null or p_url !~* '^https://' or length(p_url) > 2000 or p_url ~ '[[:space:][:cntrl:]\\]' then return false; end if;
  v_auth := substring(p_url from '^[Hh][Tt][Tt][Pp][Ss]://([^/?#]*)');
  if coalesce(v_auth, '') = '' or position('@' in v_auth) > 0 or left(v_auth, 1) = '[' then return false; end if;
  v_host := lower(v_auth);
  v_port := substring(v_host from ':([0-9]{1,5})$');
  if v_port is not null then
    if v_port::int not between 1 and 65535 then return false; end if;
    v_host := regexp_replace(v_host, ':[0-9]{1,5}$', '');
  end if;
  v_host := rtrim(v_host, '.');
  if v_host !~ '^[a-z0-9.-]+$' or v_host ~ '\.\.' or v_host ~ '(^|\.)-' or v_host ~ '-(\.|$)' or position('.' in v_host) = 0 then
    return false;
  end if;
  -- an address written with digits: only a plain dotted quad is read, and only a public one passes
  if v_host ~ '^[0-9.]+$' or v_host ~ '(^|\.)0x' then
    if v_host !~ '^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$' then return false; end if;
    o := string_to_array(v_host, '.')::int[];
    return o[1] <= 255 and o[2] <= 255 and o[3] <= 255 and o[4] <= 255
       and not (o[1] in (0, 10, 127) or o[1] >= 224
                or (o[1] = 100 and o[2] between 64 and 127)
                or (o[1] = 169 and o[2] = 254)
                or (o[1] = 172 and o[2] between 16 and 31)
                or (o[1] = 192 and o[2] = 168)
                or (o[1] = 192 and o[2] = 0 and o[3] in (0, 2))
                or (o[1] = 198 and o[2] in (18, 19))
                or (o[1] = 198 and o[2] = 51 and o[3] = 100)
                or (o[1] = 203 and o[2] = 0 and o[3] = 113));
  end if;
  -- names that stay inside a network, and services that resolve a name to the address written in it
  if v_host ~ '(^|\.)(localhost|localdomain|local|internal|intranet|private|lan|home|corp|svc|cluster\.local|arpa)$'
     or v_host ~ '(^|\.)(nip\.io|sslip\.io|xip\.io|rbndr\.us|localtest\.me|lvh\.me|vcap\.me|lacolhost\.com|traefik\.me|localhost\.direct)$'
     or v_host ~ '^[0-9]{1,3}[.-][0-9]{1,3}[.-][0-9]{1,3}[.-][0-9]{1,3}[.-]' then
    return false;
  end if;
  return true;
end $fn$;
revoke execute on function b2b.url_allowed(text) from public, anon, authenticated;
grant execute on function b2b.url_allowed(text) to service_role;

CREATE OR REPLACE FUNCTION b2b.partner_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id    bigint := nullif(p ->> 'id', '')::bigint;
  v_old   b2b.partners;
  v_new   b2b.partners;
  v_slug  text := lower(trim(p ->> 'slug'));
  v_dedupe text := coalesce(nullif(p ->> 'dedupe_mode', ''), 'async');
  v_wh    jsonb := coalesce(p -> 'working_hours', 'null'::jsonb);
  v_changed text[];
  v_who   text := coalesce(auth.uid()::text, 'system');
  e jsonb := coalesce((select value from b2b.settings where key = 'engine'), '{}');
  v_hold_sync int := round(coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'hold_minutes_sync'), 0))::int;
  v_hold_async int := round(coalesce(b2b.stats_num(e -> 'a3_fixed' -> 'hold_minutes_async'), 30))::int;
  v_crit jsonb;
  v_push jsonb;
  v_conf boolean;
  v_adapter text;
  k text;
  v_num numeric;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_slug is null or v_slug !~ '^[a-z0-9][a-z0-9-]{1,39}$' then
    raise exception 'slug: 2 to 40 lowercase letters, digits or hyphens' using errcode = '22023';
  end if;
  if coalesce(trim(p ->> 'name'), '') = '' then raise exception 'name is required' using errcode = '22023'; end if;
  -- M34e: pushes leave only for the public internet
  if nullif(trim(p ->> 'api_base_url'), '') is not null and not b2b.url_allowed(trim(p ->> 'api_base_url')) then
    raise exception 'API base URL: an https address on the public internet, not a private, loopback, link-local or metadata address' using errcode = '22023';
  end if;
  if nullif(trim(p ->> 'test_endpoint'), '') is not null and not b2b.url_allowed(trim(p ->> 'test_endpoint')) then
    raise exception 'test endpoint: an https address on the public internet, not a private, loopback, link-local or metadata address' using errcode = '22023';
  end if;
  if jsonb_typeof(v_wh) = 'object' and not b2b.valid_working_hours(v_wh) then
    raise exception 'working hours: each day closed or open < close (HH:MM)' using errcode = '22023';
  end if;
  if v_dedupe not in ('sync', 'async', 'none') then raise exception 'duplicate handling is sync, async or none' using errcode = '22023'; end if;
  if p ? 'sla' and jsonb_typeof(p -> 'sla') <> 'object' then raise exception 'sla must be an object' using errcode = '22023'; end if;
  if p ? 'sla' then
    -- PART 4 and PART 6.4: the SLAs the engine measures are the rulebook's; a partner may promise more, never less
    for k in select key from jsonb_object_keys(p -> 'sla') key loop
      if jsonb_typeof(p -> 'sla' -> k) = 'null' then continue; end if;
      begin v_num := (p -> 'sla' ->> k)::numeric; exception when others then raise exception 'sla %: a number of hours or days', k using errcode = '22023'; end;
      if v_num is null or v_num < 0 then raise exception 'sla %: a number of hours or days', k using errcode = '22023'; end if;
      if k = 'first_contact_hours' and v_num > 2 then raise exception 'the first-contact SLA is 2 working hours at most (Addendum 3)' using errcode = '22023'; end if;
      if k = 'status_update_days' and v_num > 7 then raise exception 'the status-update SLA is every 7 days at most (Addendum 3)' using errcode = '22023'; end if;
      if k = 'proof_days' and v_num > 7 then raise exception 'enrolment proof is due within 7 days at most (Addendum 3)' using errcode = '22023'; end if;
    end loop;
  end if;
  if p ? 'lead_criteria' then
    v_crit := p -> 'lead_criteria';
    if jsonb_typeof(v_crit) <> 'object' then raise exception 'lead criteria must be an object' using errcode = '22023'; end if;
    for k in select key from jsonb_object_keys(v_crit) key loop
      if k not in ('states_include', 'states_exclude', 'cities_include', 'cities_exclude', 'sources_exclude', 'qualifications_include',
                   'min_academic_pct', 'min_work_experience_years', 'unknown', 'other') then
        raise exception 'unknown lead criterion: %', k using errcode = '22023';
      end if;
      if k in ('states_include', 'states_exclude', 'cities_include', 'cities_exclude', 'sources_exclude', 'qualifications_include') then
        if jsonb_typeof(v_crit -> k) <> 'array'
           or exists (select 1 from jsonb_array_elements(v_crit -> k) x where jsonb_typeof(x) <> 'string' or length(trim(x #>> '{}')) not between 1 and 80)
           or jsonb_array_length(v_crit -> k) > 100 then
          raise exception 'lead criteria %: a list of up to 100 names', replace(k, '_', ' ') using errcode = '22023';
        end if;
      elsif k = 'min_academic_pct' and jsonb_typeof(v_crit -> k) <> 'null' then
        if b2b.stats_num(v_crit -> k) is null or b2b.stats_num(v_crit -> k) not between 0 and 100 then
          raise exception 'minimum academic score: 0 to 100 percent' using errcode = '22023';
        end if;
      elsif k = 'min_work_experience_years' and jsonb_typeof(v_crit -> k) <> 'null' then
        if b2b.stats_num(v_crit -> k) is null or b2b.stats_num(v_crit -> k) not between 0 and 40 then
          raise exception 'minimum work experience: 0 to 40 years' using errcode = '22023';
        end if;
      elsif k = 'unknown' and jsonb_typeof(v_crit -> k) <> 'null' then
        if (v_crit ->> k) not in ('pass', 'fail') then raise exception 'unknown lead data: ''pass'' or ''fail''' using errcode = '22023'; end if;
      elsif k = 'other' and jsonb_typeof(v_crit -> k) not in ('null', 'string') then
        raise exception 'lead criteria other: a short text' using errcode = '22023';
      end if;
    end loop;
  end if;
  if p ? 'push_options' then
    if jsonb_typeof(p -> 'push_options') <> 'object' then raise exception 'push options must be an object' using errcode = '22023'; end if;
    if p -> 'push_options' ? 'interests_array' and jsonb_typeof(p -> 'push_options' -> 'interests_array') not in ('boolean', 'null') then
      raise exception 'push options interests_array: true or false' using errcode = '22023';
    end if;
    v_push := jsonb_build_object('interests_array', coalesce((p -> 'push_options' ->> 'interests_array')::boolean, false));
  end if;

  if v_id is not null then
    select * into v_old from b2b.partners where id = v_id for update;
    if v_old.id is null then raise exception 'partner not found' using errcode = 'P0002'; end if;
    if v_slug <> v_old.slug and (v_old.status <> 'onboarding' or b2b.is_live('partner:' || v_id)) then
      raise exception 'the slug is fixed once a partner leaves onboarding' using errcode = '22023';
    end if;
  end if;
  if exists (select 1 from b2b.partners where slug = v_slug and id is distinct from v_id) then
    raise exception 'slug already used by another partner' using errcode = '23505';
  end if;

  if v_id is null then
    insert into b2b.partners (slug, name, created_by, updated_by) values (v_slug, trim(p ->> 'name'), auth.uid(), v_who)
    returning * into v_old;
    v_id := v_old.id;
  end if;

  -- D37: a CRM adapter blocks duplicates on create only when the Admin confirmed it; 'sync' without that confirmation is refused
  v_conf := case when p ? 'dedupe_confirmed' and jsonb_typeof(p -> 'dedupe_confirmed') = 'boolean' then (p ->> 'dedupe_confirmed')::boolean
                 else v_old.dedupe_confirmed_at is not null end;
  v_adapter := coalesce(nullif(p ->> 'adapter_type', ''), v_old.adapter_type);
  if v_dedupe = 'sync' and not v_conf and b2b.adapter_spec(v_adapter) is not null then
    raise exception 'confirm that the CRM rejects duplicates on create (dedupe_confirmed) before choosing a 0-minute hold' using errcode = '22023';
  end if;

  update b2b.partners t set
    slug                   = v_slug,
    name                   = trim(p ->> 'name'),
    display_name           = nullif(trim(p ->> 'display_name'), ''),
    logo_url               = nullif(trim(p ->> 'logo_url'), ''),
    brand_color            = nullif(trim(p ->> 'brand_color'), ''),
    adapter_type           = coalesce(nullif(p ->> 'adapter_type', ''), t.adapter_type),
    api_base_url           = nullif(trim(p ->> 'api_base_url'), ''),
    test_endpoint          = nullif(trim(p ->> 'test_endpoint'), ''),
    dedupe_mode            = v_dedupe,
    hold_minutes           = case when v_dedupe = 'sync' then v_hold_sync else v_hold_async end,
    duplicate_window_hours = 24,
    dedupe_confirmed_at    = case when v_conf then coalesce(t.dedupe_confirmed_at, now()) end,
    push_options           = coalesce(v_push, t.push_options, '{}'::jsonb),
    notify_enabled         = coalesce((p ->> 'notify_enabled')::boolean, false),
    daily_cap              = (p ->> 'daily_cap')::int,
    monthly_cap            = (p ->> 'monthly_cap')::int,
    contract_min_monthly   = (p ->> 'contract_min_monthly')::int,
    working_hours          = case when jsonb_typeof(v_wh) = 'object' then v_wh else t.working_hours end,
    holidays               = coalesce((select array_agg(distinct d::date order by d::date) from jsonb_array_elements_text(p -> 'holidays') d), '{}'),
    sla                    = case when p ? 'sla' then t.sla || (p -> 'sla') else t.sla end,
    lead_criteria          = case when p ? 'lead_criteria' then p -> 'lead_criteria' else t.lead_criteria end,
    notes                  = nullif(trim(p ->> 'notes'), ''),
    updated_at             = now(),
    updated_by             = v_who
  where t.id = v_id
  returning * into v_new;

  select coalesce(array_agg(n.key order by n.key), '{}') into v_changed
    from jsonb_each(to_jsonb(v_new)) n
   where n.key not in ('updated_at', 'updated_by', 'created_at', 'created_by')
     and n.value is distinct from (to_jsonb(v_old) -> n.key);

  if p ->> 'id' is null or p ->> 'id' = '' then
    perform b2b.log_event('partner.created', null, null, v_id, jsonb_build_object('slug', v_slug));
  elsif cardinality(v_changed) > 0 then
    perform b2b.log_event('partner.updated', null, null, v_id, jsonb_build_object('fields', to_jsonb(v_changed)));
  end if;
  return jsonb_build_object('id', v_id, 'changed', to_jsonb(v_changed));
end $function$;

CREATE OR REPLACE FUNCTION b2b.partner_adapter_save(p_partner_id bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    -- M34e: the CRM is called only on the public internet
    if k in ('login_url', 'base_url', 'create_url', 'poll_url') and t is not null and not b2b.url_allowed(t) then
      raise exception '% must be an https address on the public internet, not a private, loopback, link-local or metadata address', replace(k, '_', ' ') using errcode = '22023';
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
end $function$;

CREATE OR REPLACE FUNCTION b2b.webhook_endpoint_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_events text[];
  v_bad text;
  w b2b.webhook_endpoints;
  v_known text[] := array['lead.allocated', 'lead.accepted', 'lead.status_changed', 'lead.enrolled', 'b2c.lead_handed_off', 'b2c.lead_reenquired',
                          'b2c.lead_flagged', 'b2c.lead_close_agreed', 'b2c.lead_upserted', 'b2c.lead_released', 'b2c.leads_batch',
                          'b2c.lead_requalified', 'b2c.lead_reengaged', 'b2c.consent_requested', 'b2c.consent_closed',
                          'b2b.lead_routed_to_partner', 'lead.*', 'b2c.*', 'b2b.*', '*'];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select array_agg(distinct trim(x)) into v_events from jsonb_array_elements_text(coalesce(p -> 'events', '[]')) x where trim(x) <> '';
  if coalesce(cardinality(v_events), 0) = 0 then raise exception 'choose at least one event' using errcode = '22023'; end if;
  select string_agg(x, ', ') into v_bad from unnest(v_events) x where not x = any (v_known);
  if v_bad is not null then raise exception 'unknown event: %', v_bad using errcode = '22023'; end if;
  if coalesce(p ->> 'url', '') !~ '^https://[^\s]+$' then raise exception 'the URL must start with https://' using errcode = '22023'; end if;
  -- M34e: deliveries leave only for the public internet
  if not b2b.url_allowed(p ->> 'url') then raise exception 'the URL must be an https address on the public internet, not a private, loopback, link-local or metadata address' using errcode = '22023'; end if;
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
end $function$;

CREATE OR REPLACE FUNCTION b2b.push_dispatch(p_limit integer DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      if not a.is_test then
        select * into p from b2b.partners where id = a.partner_id;
        if p.status is distinct from 'active' then
          update b2b.allocations set status = 'failed', outcome = 'failed', outcome_at = now(), next_push_at = null,
                 last_error = left('partner paused: ' || coalesce(p.status, 'unknown'), 500) where id = a.id;
          perform b2b.log_event('lead.push_failed', a.lead_id, a.id, a.partner_id,
                                jsonb_build_object('error', 'partner paused', 'why', coalesce(p.status, 'unknown'), 'partner_paused', true, 'attempts', a.push_attempts));
          perform b2b.reroute_after(a.id, 'partner paused');
          continue;
        end if;
      end if;
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
      -- M34e: a private or internal address fails the push for good, like a partner with no address
      if not b2b.url_allowed(req ->> 'url') then
        if a.status = 'queued' then update b2b.allocations set status = 'pushing' where id = a.id; end if;
        update b2b.allocations set push_attempts = 99 where id = a.id;
        perform b2b.apply_push_error(a.id, 'the partner address is not allowed (a private, loopback, link-local or metadata address)');
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
end $function$;

CREATE OR REPLACE FUNCTION b2b.adapter_issue(p b2b.partners, p_env text, p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if not b2b.url_allowed(c ->> 'url') then return jsonb_build_object('error', 'the partner CRM address is not allowed (a private, loopback, link-local or metadata address)'); end if;   -- M34e
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
end $function$;

CREATE OR REPLACE FUNCTION b2b.adapter_token_request(p b2b.partners, p_env text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- M34e: the sign-in address must be on the public internet
  if not b2b.url_allowed(v_url) then
    update b2b.partner_adapter_state set token_failed_at = now(), token_error = 'the sign-in address is not allowed (a private, loopback, link-local or metadata address)', updated_at = now()
     where partner_id = p.id and env = p_env;
    return null;
  end if;
  v_net := net.http_post(url := v_url, body := '{}'::jsonb,
    params := jsonb_build_object('grant_type', 'refresh_token', 'client_id', e ->> 'client_id', 'client_secret', e -> 'secrets' ->> 'client_secret',
                                 'refresh_token', e -> 'secrets' ->> 'refresh_token'),
    headers := jsonb_build_object('Content-Type', 'application/json'), timeout_milliseconds := 10000);   -- pg_net posts JSON only; the grant travels in the query string
  update b2b.partner_adapter_state set token_request_id = v_net, token_requested_at = now(), updated_at = now() where partner_id = p.id and env = p_env;
  return v_net;
end $function$;

CREATE OR REPLACE FUNCTION b2b.admin_send_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  al jsonb := coalesce((select value from b2b.settings where key = 'admin_alerts'), '{}');
  m b2b.admin_messages;
  req jsonb;
  b jsonb;
  v_net bigint;
  r record;
  v_sent int := 0;
begin
  -- answers
  for r in select x.id, x.attempts, x.updated, h.status_code, h.content, h.timed_out, h.error_msg, h.id is not null done
             from (select id, attempts, net_request_id, coalesce(sent_at, created_at) updated from b2b.admin_messages where status = 'sending' limit 100) x
             left join net._http_response h on h.id = x.net_request_id
  loop
    if not r.done then
      if r.updated < now() - interval '10 minutes' then update b2b.admin_messages set status = 'failed', error = 'no answer from the provider' where id = r.id; end if;
      continue;
    end if;
    if not coalesce(r.timed_out, false) and r.error_msg is null and r.status_code between 200 and 299 then
      update b2b.admin_messages set status = 'sent', sent_at = now(), error = null where id = r.id;
    elsif r.attempts < 3 then
      update b2b.admin_messages set status = 'queued', error = left(coalesce(r.error_msg, 'HTTP ' || r.status_code || ': ' || left(r.content, 200)), 300) where id = r.id;
    else
      update b2b.admin_messages set status = 'failed', error = left(coalesce(r.error_msg, 'HTTP ' || r.status_code || ': ' || left(r.content, 200)), 300) where id = r.id;
    end if;
  end loop;
  update b2b.admin_messages set status = 'skipped', error = 'not sent within 2 days (alerts were off or the provider kept failing)'
   where status = 'queued' and created_at <= now() - interval '2 days';
  if not coalesce((al ->> 'enabled')::boolean, false) then return jsonb_build_object('sent', 0, 'why', 'admin alerts are off'); end if;
  for m in select * from b2b.admin_messages where status = 'queued' and created_at > now() - interval '2 days'
             and (attempts = 0 or sent_at < now() - make_interval(mins => 5 * attempts))
           order by id limit 20 for update skip locked loop
    req := b2b.admin_message_request(m);
    if req ? 'error' then
      update b2b.admin_messages set status = 'failed', error = req ->> 'error' where id = m.id;
      continue;
    end if;
    -- M34e: the provider must be on the public internet
    if not b2b.url_allowed(req ->> 'url') then
      update b2b.admin_messages set status = 'failed', error = 'the provider address is not allowed (a private, loopback, link-local or metadata address)' where id = m.id;
      continue;
    end if;
    if coalesce((req ->> 'many')::boolean, false) then
      for b in select * from jsonb_array_elements(req -> 'bodies') loop
        v_net := net.http_post(url := req ->> 'url', body := b, headers := req -> 'headers', timeout_milliseconds := 15000);
      end loop;
    else
      v_net := net.http_post(url := req ->> 'url', body := req -> 'body', headers := req -> 'headers', timeout_milliseconds := 20000);
    end if;
    update b2b.admin_messages set status = 'sending', attempts = attempts + 1, net_request_id = v_net, provider = req ->> 'provider', sent_at = now() where id = m.id;
    v_sent := v_sent + 1;
  end loop;
  return jsonb_build_object('sent', v_sent);
end $function$;

CREATE OR REPLACE FUNCTION b2b.notify_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'notifications'), '{}');
  v_retry int := coalesce((s ->> 'retry_after_minutes')::int, 5);
  r record;
  n b2b.student_notifications;
  j jsonb;
  req jsonb;
  v_net bigint;
  v_sent int := 0;
  v_done int := 0;
  v_why text;
begin
  perform set_config('b2b.actor', 'engine', true);
  -- 1. answers
  for r in
    select x.id, x.attempts, x.lead_id, x.allocation_id, x.partner_id, x.channel, x.updated_at, h.status_code, h.content, h.timed_out, h.error_msg, h.id is not null as done
      from b2b.student_notifications x left join net._http_response h on h.id = x.net_request_id
     where x.status = 'sending' limit 200
  loop
    if not r.done and r.updated_at > now() - interval '2 minutes' then continue; end if;
    begin j := r.content::jsonb; exception when others then j := null; end;
    if r.done and not coalesce(r.timed_out, false) and r.error_msg is null and r.status_code between 200 and 299 then
      update b2b.student_notifications set status = 'sent', sent_at = now(), updated_at = now(), net_request_id = null, error = null,
             provider_message_id = left(coalesce(j -> 'messages' -> 0 ->> 'id', j ->> 'id', j ->> 'messageId'), 200)
       where id = r.id;
      perform b2b.log_event('notification.sent', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('channel', r.channel, 'notification_id', r.id));
    else
      v_why := left(coalesce(r.error_msg, case when not r.done or r.timed_out then 'no answer from the provider' end,
                             'HTTP ' || r.status_code || ': ' || coalesce(j -> 'error' ->> 'message', j ->> 'message', left(r.content, 200))), 300);
      if r.attempts < 2 then
        update b2b.student_notifications set status = 'scheduled', scheduled_for = now() + make_interval(mins => v_retry), net_request_id = null,
               error = v_why, updated_at = now() where id = r.id;
      else
        update b2b.student_notifications set status = 'failed', net_request_id = null, error = v_why, updated_at = now() where id = r.id;
        perform b2b.log_event('alert.notification_failed', r.lead_id, r.allocation_id, r.partner_id, jsonb_build_object('channel', r.channel, 'error', v_why));
      end if;
    end if;
    v_done := v_done + 1;
  end loop;

  -- 2. due messages
  for n in
    select * from b2b.student_notifications where status = 'scheduled' and scheduled_for <= now()
     order by scheduled_for limit 50 for update skip locked
  loop
    begin
      v_why := case
        when not exists (select 1 from b2b.allocations a where a.id = n.allocation_id and a.status = 'accepted') then 'the allocation is no longer accepted'
        when exists (select 1 from b2b.allocations a where a.id = n.allocation_id and a.lost_at is not null and a.lost_revived_at is null) then 'lost, in grace'
        when exists (select 1 from b2b.commission_disputes d where d.allocation_id = n.allocation_id and d.kind = 'duplicate_after_acceptance'
                        and d.status in ('open', 'upheld')) then 'duplicate claimed after acceptance'
        when exists (select 1 from public.student_leads l where l.id = n.lead_id and (coalesce(l.is_opted_out, false) or coalesce(l.is_test, false)
                                                                                       or b2b.is_test_phone(l.whatsapp_number))) then 'student opted out or is a test lead'
        when not b2b.is_live(n.channel) then n.channel || ' is switched off'
      end;
      if v_why is not null then
        update b2b.student_notifications set status = 'cancelled', error = v_why, updated_at = now() where id = n.id;
        continue;
      end if;
      req := b2b.notify_request(n);
      if req ? 'error' then
        update b2b.student_notifications set status = 'failed', error = req ->> 'error', updated_at = now() where id = n.id;
        perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id, jsonb_build_object('channel', n.channel, 'error', req ->> 'error'));
        continue;
      end if;
      -- M34e: the provider must be on the public internet
      if not b2b.url_allowed(req ->> 'url') then
        update b2b.student_notifications set status = 'failed', error = 'the provider address is not allowed (a private, loopback, link-local or metadata address)', updated_at = now() where id = n.id;
        perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id,
                              jsonb_build_object('channel', n.channel, 'error', 'the provider address is not allowed'));
        continue;
      end if;
      v_net := net.http_post(url := req ->> 'url', body := req -> 'body', headers := req -> 'headers', timeout_milliseconds := 15000);
      update b2b.student_notifications set status = 'sending', attempts = attempts + 1, net_request_id = v_net, provider = req ->> 'provider',
             updated_at = now() where id = n.id;
      v_sent := v_sent + 1;
    exception when others then
      update b2b.student_notifications set status = 'failed', error = left(sqlerrm, 300), updated_at = now() where id = n.id;
      perform b2b.log_event('alert.notification_failed', n.lead_id, n.allocation_id, n.partner_id, jsonb_build_object('channel', n.channel, 'error', left(sqlerrm, 300)));
    end;
  end loop;
  return jsonb_build_object('answers', v_done, 'sent', v_sent);
end $function$;

CREATE OR REPLACE FUNCTION b2b.outbox_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_backoff int[] := array[30, 120, 600, 1800, 3600, 10800, 21600];
  v_max int := 8;
  r record;
  o b2b.integration_outbox;
  w b2b.webhook_endpoints;
  v_ts text;
  v_secret text;
  v_net bigint;
  v_why text;
  v_sent int := 0;
  v_done int := 0;
begin
  perform set_config('b2b.actor', 'engine', true);
  -- 1. answers
  for r in
    -- while sending, next_attempt_at holds the time the request went out
    select x.id, x.attempts, x.endpoint_id, x.event_type, x.next_attempt_at as sent_at, h.status_code, h.content, h.timed_out, h.error_msg,
           h.id is not null as done
      from b2b.integration_outbox x left join net._http_response h on h.id = x.net_request_id
     where x.status = 'sending' limit 300
  loop
    if not r.done and r.sent_at > now() - interval '2 minutes' then continue; end if;
    if r.done and not coalesce(r.timed_out, false) and r.error_msg is null and r.status_code between 200 and 299 then
      update b2b.integration_outbox set status = 'delivered', delivered_at = now(), response_status = r.status_code, net_request_id = null, last_error = null
       where id = r.id;
      update b2b.webhook_endpoints set last_success_at = now() where id = r.endpoint_id;
    else
      v_why := left(coalesce(r.error_msg, case when not r.done or r.timed_out then 'no answer within the timeout' end,
                             'HTTP ' || r.status_code || ': ' || left(coalesce(r.content, ''), 200)), 300);
      if r.attempts >= v_max then
        update b2b.integration_outbox set status = 'dead', response_status = r.status_code, net_request_id = null, last_error = v_why where id = r.id;
        perform b2b.log_event('alert.webhook_dead', null, null, null,
                              jsonb_build_object('outbox_id', r.id, 'endpoint_id', r.endpoint_id, 'event_type', r.event_type, 'error', v_why));
      else
        update b2b.integration_outbox set status = 'failed', response_status = r.status_code, net_request_id = null, last_error = v_why,
               next_attempt_at = now() + make_interval(secs => v_backoff[least(r.attempts, array_length(v_backoff, 1))])
         where id = r.id;
      end if;
      update b2b.webhook_endpoints set last_failure_at = now(), last_error = v_why where id = r.endpoint_id;
    end if;
    v_done := v_done + 1;
  end loop;

  -- 2. due deliveries, oldest first, only to active endpoints (a test ping goes out before activation)
  for o in
    select x.* from b2b.integration_outbox x join b2b.webhook_endpoints e on e.id = x.endpoint_id
     where x.status in ('pending', 'failed') and x.next_attempt_at <= now() and (e.active or x.event_type = 'ping') and e.secret_id is not null
     order by x.id limit 100 for update of x skip locked
  loop
    begin
      select * into w from b2b.webhook_endpoints where id = o.endpoint_id;
      -- M34e: deliveries leave only for the public internet
      if not b2b.url_allowed(w.url) then
        update b2b.integration_outbox set status = 'dead', last_error = 'the endpoint address is not allowed (a private, loopback, link-local or metadata address)' where id = o.id;
        update b2b.webhook_endpoints set last_failure_at = now(), last_error = 'the endpoint address is not allowed' where id = w.id;
        perform b2b.log_event('alert.webhook_dead', null, null, null,
                              jsonb_build_object('outbox_id', o.id, 'endpoint_id', w.id, 'event_type', o.event_type, 'error', 'the endpoint address is not allowed'));
        continue;
      end if;
      v_secret := b2b.partner_secret(w.secret_id);
      v_ts := floor(extract(epoch from now()))::bigint::text;
      v_net := net.http_post(
        url := w.url,
        body := o.payload,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'X-Eduwit-Event', o.event_type,
          'X-Eduwit-Delivery', o.id::text,
          'X-Eduwit-Timestamp', v_ts,
          'X-Eduwit-Signature', 'sha256=' || encode(extensions.hmac(convert_to(v_ts || '.' || o.payload::text, 'UTF8'), convert_to(v_secret, 'UTF8'), 'sha256'), 'hex'),
          'Idempotency-Key', o.idempotency_key),
        timeout_milliseconds := 10000);
      update b2b.integration_outbox set status = 'sending', attempts = attempts + 1, net_request_id = v_net, next_attempt_at = now() where id = o.id;
      v_sent := v_sent + 1;
    exception when others then
      update b2b.integration_outbox set status = 'failed', attempts = attempts + 1, last_error = left(sqlerrm, 300),
             next_attempt_at = now() + interval '5 minutes' where id = o.id;
    end;
  end loop;
  return jsonb_build_object('answers', v_done, 'sent', v_sent);
end $function$;

-- the replaced functions keep their grants (create or replace); restated
revoke execute on function b2b.partner_save(jsonb), b2b.partner_adapter_save(bigint, jsonb), b2b.webhook_endpoint_save(jsonb) from public, anon;
grant execute on function b2b.partner_save(jsonb), b2b.partner_adapter_save(bigint, jsonb), b2b.webhook_endpoint_save(jsonb) to authenticated, service_role;
revoke execute on function b2b.push_dispatch(integer), b2b.adapter_issue(b2b.partners, text, text), b2b.adapter_token_request(b2b.partners, text),
                           b2b.admin_send_tick(), b2b.notify_tick(), b2b.outbox_tick() from public, anon, authenticated;
grant execute on function b2b.push_dispatch(integer), b2b.adapter_issue(b2b.partners, text, text), b2b.adapter_token_request(b2b.partners, text),
                          b2b.admin_send_tick(), b2b.notify_tick(), b2b.outbox_tick() to service_role;

-- rollback: re-run the previous definitions, which are production's as of 30 Oct 2026 (these without their "M34e" lines):
--   partner_save, push_dispatch, notify_tick: m31i_a3_after_push.sql; partner_adapter_save: m33e_email_partner_adapter.sql;
--   webhook_endpoint_save: m31b_a3_helpers.sql; adapter_issue: 20261007020636_m19d_crm_adapter_poll.sql;
--   adapter_token_request: 20261007020546_m19c_crm_adapter_sync.sql; admin_send_tick: m28b_alerts_schedules.sql;
--   outbox_tick: 20261006194015_m14a_integration_outbox.sql. b2b.url_allowed can stay (unused).
