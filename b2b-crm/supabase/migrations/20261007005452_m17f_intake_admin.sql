-- M17f: intake, part 2: the Meta fetch loop (pg_net, every 10 seconds), the Admin's "New lead" form, form mappings,
-- connection settings (secrets to Vault), retry and discard of failed requests, and the Intake screen's overview.

-- ---------- the Meta fetch loop ----------
create or replace function b2b.intake_tick()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'intake'), '{}');
  v_token text := b2b.intake_secret('meta.page_token_id');
  r record;
  h record;
  g jsonb;
  n_sent int := 0;
  n_done int := 0;
begin
  perform set_config('b2b.actor', 'system', true);
  -- answers that came back
  for r in select q.id, q.net_request_id, q.attempts from b2b.intake_requests q
            where q.source = 'meta' and q.status = 'fetching' and q.net_request_id is not null order by q.id limit 200 loop
    select x.status_code, x.content, x.timed_out, x.error_msg into h from net._http_response x where x.id = r.net_request_id;
    continue when not found;
    begin
      if h.status_code between 200 and 299 then
        g := h.content::jsonb;
        perform b2b.meta_lead_apply(r.id, g);
        n_done := n_done + 1;
      else
        update b2b.intake_requests set status = case when r.attempts >= 3 then 'error' else 'received' end, net_request_id = null,
               error = left(coalesce('Graph API ' || h.status_code || ': ' || left(h.content, 200), h.error_msg, 'timed out'), 300)
         where id = r.id;
        if r.attempts >= 3 then perform b2b.log_event('alert.intake_failed', null, null, null, jsonb_build_object('source', 'meta', 'request_id', r.id)); end if;
      end if;
    exception when others then
      update b2b.intake_requests set status = 'error', error = left(sqlerrm, 300), net_request_id = null where id = r.id;
      perform b2b.log_event('alert.intake_failed', null, null, null, jsonb_build_object('source', 'meta', 'request_id', r.id, 'error', left(sqlerrm, 200)));
    end;
  end loop;
  -- new leadgen ids: fetch the lead (needs the page token)
  if v_token is not null then
    for r in select q.id, q.idempotency_key from b2b.intake_requests q
              where q.source = 'meta' and q.status = 'received' and q.attempts < 4 order by q.id limit 50 loop
      update b2b.intake_requests
         set status = 'fetching', attempts = attempts + 1,
             net_request_id = net.http_get(
               url := 'https://graph.facebook.com/' || coalesce(s -> 'meta' ->> 'api_version', 'v21.0') || '/' || r.idempotency_key,
               params := jsonb_build_object('fields', 'created_time,field_data,ad_id,ad_name,adset_id,campaign_id,campaign_name,form_id,platform,is_organic'),
               headers := jsonb_build_object('Authorization', 'Bearer ' || v_token),
               timeout_milliseconds := 10000)
       where id = r.id;
      n_sent := n_sent + 1;
    end loop;
  end if;
  return jsonb_build_object('fetching', n_sent, 'done', n_done);
end $fn$;

-- ---------- the Admin ----------
/* "New lead": the Admin types a lead in. route: route (as soon as it is ready), hold (until the Admin routes it) or b2c. */
create or replace function b2b.intake_manual(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_res jsonb; v_purposes jsonb := coalesce(p -> 'consent_purposes', '[]');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(p ->> 'route', '') not in ('route', 'hold', 'b2c') then raise exception 'choose what happens to the lead' using errcode = '22023'; end if;
  if p ->> 'route' = 'b2c' and coalesce(p ->> 'b2c_lane', '') not in ('sales', 'nurture') then raise exception 'choose the B2C lane' using errcode = '22023'; end if;
  if not v_purposes ? 'sales' then raise exception 'record that the student agreed to be contacted' using errcode = '22023'; end if;
  if length(trim(coalesce(p ->> 'consent_where', ''))) < 3 then raise exception 'say how the student agreed (call, walk-in, event…)' using errcode = '22023'; end if;
  if length(trim(coalesce(p -> 'lead' ->> 'full_name', ''))) < 2 then raise exception 'give the student''s name' using errcode = '22023'; end if;
  if b2b.phone_problem(public.crm_norm_phone(p -> 'lead' ->> 'phone')) is not null and not b2b.is_test_phone(public.crm_norm_phone(p -> 'lead' ->> 'phone')) then
    raise exception 'the phone number is not valid' using errcode = '22023';
  end if;
  v_res := b2b.intake_lead(p -> 'lead', jsonb_build_object(
    'source_system', 'manual', 'lead_source', coalesce(nullif(trim(p ->> 'source'), ''), 'manual_entry'), 'channel', 'manual', 'campaign', p ->> 'campaign',
    'consent', jsonb_build_object('sales_at', now(), 'partner_share_at', case when v_purposes ? 'partner_share' then now() end,
                                  'marketing_at', case when v_purposes ? 'marketing' then now() end, 'text_version', 'manual:' || left(trim(p ->> 'consent_where'), 80)),
    'idempotency_key', 'manual:' || gen_random_uuid(), 'directive_source', 'manual',
    'directive', jsonb_build_object('directive', p ->> 'route', 'b2c_lane', p ->> 'b2c_lane', 'phone_trusted', true),
    'attribution', jsonb_build_object('entered_by', b2b.actor() ->> 'id', 'note', p ->> 'note')));
  insert into b2b.intake_requests (source, idempotency_key, raw, status, result, lead_id, done_at)
  values ('manual', 'manual:' || (v_res ->> 'lead_id') || ':' || extract(epoch from clock_timestamp()), p, 'done', v_res, (v_res ->> 'lead_id')::bigint, now());
  perform b2b.log_event('lead.entered', (v_res ->> 'lead_id')::bigint, null, null, jsonb_build_object('action', v_res ->> 'action', 'route', p ->> 'route'));
  return v_res;
end $fn$;

create or replace function b2b.lead_form_save(p jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint; v_fields jsonb := b2b.import_fields(); k text; v text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(p ->> 'platform', '') not in ('meta', 'google') then raise exception 'choose Meta or Google' using errcode = '22023'; end if;
  if coalesce(p ->> 'form_ref', '') !~ '^[A-Za-z0-9_.:-]{1,80}$' then raise exception 'the form ID is the number or ID the platform shows' using errcode = '22023'; end if;
  if length(trim(coalesce(p ->> 'name', ''))) < 2 then raise exception 'give the form a name' using errcode = '22023'; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(coalesce(p -> 'field_map', '{}')) loop
    if v <> 'ignore' and not (v_fields ? v) then raise exception 'unknown lead field: %', v using errcode = '22023'; end if;
  end loop;
  for k in select jsonb_object_keys(coalesce(p -> 'defaults', '{}')) loop
    if k not in ('course', 'specialization', 'university', 'programme_level', 'study_mode', 'campaign') then
      raise exception 'a form default can set course, specialization, university, level, mode or campaign' using errcode = '22023';
    end if;
  end loop;
  if exists (select 1 from jsonb_array_elements_text(coalesce(p -> 'consent_purposes', '["sales"]')) x where x not in ('sales', 'partner_share', 'marketing')) then
    raise exception 'unknown consent purpose' using errcode = '22023';
  end if;
  insert into b2b.lead_forms (platform, form_ref, name, page_ref, field_map, defaults, campaign, consent_text, consent_version, consent_purposes, active, updated_by)
  values (p ->> 'platform', p ->> 'form_ref', trim(p ->> 'name'), nullif(trim(p ->> 'page_ref'), ''), coalesce(p -> 'field_map', '{}'), coalesce(p -> 'defaults', '{}'),
          nullif(trim(p ->> 'campaign'), ''), nullif(trim(p ->> 'consent_text'), ''), nullif(trim(p ->> 'consent_version'), ''),
          array(select jsonb_array_elements_text(coalesce(p -> 'consent_purposes', '["sales"]'))), coalesce((p ->> 'active')::boolean, true), b2b.actor() ->> 'id')
  on conflict (platform, form_ref) do update
    set name = excluded.name, page_ref = excluded.page_ref, field_map = excluded.field_map, defaults = excluded.defaults, campaign = excluded.campaign,
        consent_text = excluded.consent_text, consent_version = excluded.consent_version, consent_purposes = excluded.consent_purposes,
        active = excluded.active, updated_at = now(), updated_by = excluded.updated_by
  returning id into v_id;
  perform b2b.log_event('intake.form_saved', null, null, null, jsonb_build_object('form_id', v_id, 'platform', p ->> 'platform', 'form_ref', p ->> 'form_ref'));
  return v_id;
end $fn$;

/* Secrets are written to Vault and never read back. Empty values leave a secret unchanged. */
create or replace function b2b.intake_settings_save(p jsonb)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  s jsonb := coalesce((select value from b2b.settings where key = 'intake'), '{}');
  m jsonb := coalesce(s -> 'meta', '{}');
  g jsonb := coalesce(s -> 'google', '{}');
  v_id uuid;
  r record;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if nullif(p -> 'meta' ->> 'api_version', '') is not null and p -> 'meta' ->> 'api_version' !~ '^v\d{1,2}\.\d$' then
    raise exception 'the Graph API version looks like v21.0' using errcode = '22023';
  end if;
  for r in select * from (values ('meta', 'verify_token', 'verify_token_id', 'Meta Lead Ads webhook verify token'),
                                 ('meta', 'app_secret', 'app_secret_id', 'Meta app secret (webhook signatures)'),
                                 ('meta', 'page_token', 'page_token_id', 'Meta page access token (Lead Ads)'),
                                 ('google', 'key', 'key_id', 'Google Ads lead form key')) x(grp, field, id_key, label) loop
    continue when coalesce(p -> r.grp ->> r.field, '') = '';
    if length(p -> r.grp ->> r.field) < 8 then raise exception '% is too short', r.label using errcode = '22023'; end if;
    v_id := (case r.grp when 'meta' then m else g end ->> r.id_key)::uuid;
    if v_id is null then v_id := vault.create_secret(p -> r.grp ->> r.field, 'b2b_intake_' || r.grp || '_' || r.field, r.label);
    else perform vault.update_secret(v_id, p -> r.grp ->> r.field); end if;
    if r.grp = 'meta' then m := m || jsonb_build_object(r.id_key, v_id); else g := g || jsonb_build_object(r.id_key, v_id); end if;
  end loop;
  m := m || jsonb_build_object('api_version', coalesce(nullif(p -> 'meta' ->> 'api_version', ''), m ->> 'api_version', 'v21.0'));
  update b2b.settings set value = s || jsonb_build_object('meta', m, 'google', g) where key = 'intake';
  perform b2b.log_event('settings.changed', null, null, null, jsonb_build_object('key', 'intake',
          'changed', (select coalesce(jsonb_agg(r2.grp || '.' || r2.field), '[]') from (values ('meta', 'verify_token'), ('meta', 'app_secret'), ('meta', 'page_token'), ('google', 'key')) r2(grp, field)
                       where coalesce(p -> r2.grp ->> r2.field, '') <> '')));
end $fn$;

create or replace function b2b.intake_request_retry(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare q b2b.intake_requests;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into q from b2b.intake_requests where id = p_id for update;
  if q.id is null or q.status not in ('error', 'held') then raise exception 'only a failed or held request can be retried' using errcode = '22023'; end if;
  if q.source = 'meta' then
    if q.raw ? 'graph' then return b2b.meta_lead_apply(q.id, q.raw -> 'graph'); end if;
    update b2b.intake_requests set status = 'received', attempts = 0, net_request_id = null, error = null where id = q.id;
    return jsonb_build_object('status', 'queued');
  end if;
  raise exception 'only Meta requests can be retried here; ask the sender to resend the others' using errcode = '22023';
end $fn$;

create or replace function b2b.intake_request_discard(p_id bigint, p_reason text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  update b2b.intake_requests set status = 'discarded', error = left('discarded: ' || trim(p_reason), 300), done_at = now()
   where id = p_id and status in ('error', 'held', 'received');
  if not found then raise exception 'open request not found' using errcode = 'P0002'; end if;
  perform b2b.log_event('intake.discarded', null, null, null, jsonb_build_object('request_id', p_id, 'reason', trim(p_reason)));
end $fn$;

/* The Intake screen. Volumes come from touchpoints (every source writes one through lead_intake). */
create or replace function b2b.intake_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare s jsonb := coalesce((select value from b2b.settings where key = 'intake'), '{}');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'sources', coalesce((
      select jsonb_agg(jsonb_build_object('source', src, 'today', today, 'week', week, 'created', created, 'last_at', last_at) order by week desc)
        from (select t.source_system src,
                     count(*) filter (where t.occurred_at >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata') today,
                     count(*) week, count(*) filter (where t.event_type = 'lead.created') created, max(t.occurred_at) last_at
                from public.touchpoints t where t.occurred_at > now() - interval '7 days' group by 1) x), '[]'),
    'requests', coalesce((select jsonb_object_agg(src || '.' || st, n) from (select source src, status st, count(*) n from b2b.intake_requests
                                                                            where received_at > now() - interval '7 days' group by 1, 2) x), '{}'),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'source', q.source, 'key', q.idempotency_key, 'form_ref', q.form_ref, 'status', q.status,
                                                            'error', q.error, 'lead_id', q.lead_id, 'action', q.result ->> 'action', 'routing', q.result -> 'routing',
                                                            'received_at', q.received_at, 'is_test', q.is_test, 'name', l.student_name) order by q.id desc)
                          from (select * from b2b.intake_requests order by id desc limit 60) q left join public.student_leads l on l.id = q.lead_id), '[]'),
    'problems', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'source', q.source, 'key', q.idempotency_key, 'form_ref', q.form_ref, 'status', q.status,
                                                              'error', q.error, 'received_at', q.received_at, 'attempts', q.attempts) order by q.id desc)
                            from (select * from b2b.intake_requests where status in ('error', 'held') order by id desc limit 100) q), '[]'),
    'forms', coalesce((select jsonb_agg(to_jsonb(f) || jsonb_build_object(
                                 'leads_7d', (select count(*) from b2b.intake_requests q where q.source = f.platform and q.form_ref = f.form_ref and q.received_at > now() - interval '7 days'),
                                 'last_at', (select max(q.received_at) from b2b.intake_requests q where q.source = f.platform and q.form_ref = f.form_ref)) order by f.platform, f.name)
                         from b2b.lead_forms f), '[]'),
    'imports', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'file_name', i.file_name, 'status', i.status, 'total_rows', i.total_rows, 'counts', i.counts,
                                                             'source_label', i.source_label, 'routing_choice', i.routing_choice, 'b2c_lane', i.b2c_lane,
                                                             'created_at', i.created_at, 'finished_at', i.finished_at, 'rolled_back_at', i.rolled_back_at,
                                                             'held', (select count(*) from b2b.intake_directives d where d.import_id = i.id and d.directive = 'hold' and d.released_at is null),
                                                             'can_rollback', i.status = 'done' and i.finished_at > now() - make_interval(hours => coalesce((s ->> 'rollback_hours')::int, 24)))
                                           order by i.id desc)
                           from (select * from b2b.imports order by id desc limit 30) i), '[]'),
    'templates', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'mapping', mapping, 'used_at', used_at) order by used_at desc nulls last) from b2b.import_templates), '[]'),
    'held_manual', (select count(*) from b2b.intake_directives where source = 'manual' and directive = 'hold' and released_at is null),
    'fields', b2b.import_fields(),
    'connections', jsonb_build_object(
      'meta', jsonb_build_object('verify_token', s -> 'meta' ? 'verify_token_id', 'app_secret', s -> 'meta' ? 'app_secret_id',
                                 'page_token', s -> 'meta' ? 'page_token_id', 'api_version', coalesce(s -> 'meta' ->> 'api_version', 'v21.0')),
      'google', jsonb_build_object('key', s -> 'google' ? 'key_id'),
      'api_keys', (select count(*) from b2b.api_keys where revoked_at is null and 'intake' = any (scopes))));
end $fn$;

revoke execute on function b2b.intake_tick(), b2b.intake_manual(jsonb), b2b.lead_form_save(jsonb), b2b.intake_settings_save(jsonb),
                           b2b.intake_request_retry(bigint), b2b.intake_request_discard(bigint, text), b2b.intake_overview()
  from public, anon, authenticated;
grant execute on function b2b.intake_tick() to service_role;
grant execute on function b2b.intake_manual(jsonb), b2b.lead_form_save(jsonb), b2b.intake_settings_save(jsonb), b2b.intake_request_retry(bigint),
                          b2b.intake_request_discard(bigint, text), b2b.intake_overview()
  to authenticated, service_role;

select cron.schedule('b2b-intake-tick', '10 seconds', 'select b2b.intake_tick()');
