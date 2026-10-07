-- M23b: production sync cadence, part 2 (follows m23a).
--   b2c_link_settings_save  also takes delivery ('realtime' | 'batched'); switching to batched starts the batches from now
--   sync_settings_save      the production interval (5 to 60 minutes), versioned with a reason
--   sync_cadence            what runs when: the interval, B2C delivery and its next batch, each partner's live polling
--   api_b2c_schema          also tells the B2C CRM how it is being fed (delivery, interval)
--   api_b2c_batch           the B2C CRM sends up to 200 updates and activities in one call (its own every-15-minutes sync)

create or replace function b2b.b2c_link_settings_save(p jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  v_scope text := coalesce(p ->> 'scope', cfg ->> 'scope', 'held');
  v_delivery text := coalesce(p ->> 'delivery', cfg ->> 'delivery', 'realtime');
  v_writable jsonb := coalesce(p -> 'writable', cfg -> 'writable', '[]');
  v_bad text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'give a reason (it goes in the settings history)' using errcode = '22023'; end if;
  if v_scope not in ('held', 'all') then raise exception 'scope is held or all' using errcode = '22023'; end if;
  if v_delivery not in ('realtime', 'batched') then raise exception 'delivery is realtime or batched' using errcode = '22023'; end if;
  if jsonb_typeof(v_writable) <> 'array' then raise exception 'writable must be a list of fields' using errcode = '22023'; end if;
  select string_agg(x, ', ') into v_bad from jsonb_array_elements_text(v_writable) x
   where not exists (select 1 from jsonb_array_elements(b2b.b2c_fields()) f where f ->> 'field' = x and f ->> 'write' = 'b2c');
  if v_bad is not null then raise exception 'these fields cannot be written by the B2C CRM: %', v_bad using errcode = '22023'; end if;
  -- switching to batches: everything so far went out in real time, so the first batch starts now
  if v_delivery = 'batched' and cfg ->> 'delivery' is distinct from 'batched' then
    update b2b.b2c_link_state set value = jsonb_build_object('seq', coalesce((select max(seq) from b2b.b2c_sync), 0), 'at', now()), updated_at = now()
     where key = 'batch';
  end if;
  perform b2b.set_setting('b2c_link', jsonb_build_object('enabled', coalesce((p ->> 'enabled')::boolean, (cfg ->> 'enabled')::boolean, true), 'scope', v_scope,
                                                         'delivery', v_delivery,
                                                         'writable', (select coalesce(jsonb_agg(distinct x), '[]') from jsonb_array_elements_text(v_writable) x)),
                          trim(p_reason));
  return b2b.b2c_link_cfg();
end $fn$;

create or replace function b2b.sync_settings_save(p_minutes int, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_minutes is null or p_minutes not between 5 and 60 then raise exception 'the sync interval is 5 to 60 minutes' using errcode = '22023'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'give a reason (it goes in the settings history)' using errcode = '22023'; end if;
  perform b2b.set_setting('sync', jsonb_build_object('interval_minutes', p_minutes), trim(p_reason));
  return b2b.sync_cadence();
end $fn$;

/* What syncs when, for the Admin: the interval, the B2C CRM's delivery and its batches, and every partner whose CRM is
   polled (its own minutes, else the interval when live, 2 when testing in the sandbox). */
create or replace function b2b.sync_cadence()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
  b jsonb := coalesce((select value from b2b.b2c_link_state where key = 'batch'), '{}');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'interval_minutes', b2b.sync_minutes(),
    'b2c', jsonb_build_object('delivery', coalesce(cfg ->> 'delivery', 'realtime'), 'last_batch_at', b ->> 'at', 'last_batch_leads', b -> 'leads',
                              'last_batch_parts', b -> 'batches',
                              'next_batch_at', case when cfg ->> 'delivery' = 'batched' then (b ->> 'at')::timestamptz + make_interval(mins => b2b.sync_minutes()) end,
                              'waiting', case when cfg ->> 'delivery' = 'batched' then (select count(*) from b2b.b2c_sync s where s.seq > coalesce((b ->> 'seq')::bigint, 0)) end),
    'partners', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', coalesce(p.display_name, p.name), 'adapter', p.adapter_type, 'live', b2b.is_live('partner:' || p.id),
        'poll', coalesce((p.outbound_auth -> 'live' ->> 'poll')::boolean, true),
        'live_minutes', coalesce((p.outbound_auth -> 'live' ->> 'poll_minutes')::int, b2b.sync_minutes()),
        'sandbox_minutes', coalesce((p.outbound_auth -> 'sandbox' ->> 'poll_minutes')::int, 2),
        'own_minutes', (p.outbound_auth -> 'live' ->> 'poll_minutes') is not null,
        'last_poll_at', (select s.last_poll_at from b2b.partner_adapter_state s where s.partner_id = p.id and s.env = 'live')) order by p.id)
      from b2b.partners p
     where coalesce((b2b.adapter_spec(p.adapter_type) ->> 'poll')::boolean, false) and p.status <> 'closed'), '[]'));
end $fn$;

create or replace function b2b.api_b2c_schema(p_key text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  cfg jsonb := b2b.b2c_link_cfg();
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object(
    'scope', cfg ->> 'scope', 'enabled', coalesce((cfg ->> 'enabled')::boolean, true),
    'delivery', coalesce(cfg ->> 'delivery', 'realtime'), 'interval_minutes', b2b.sync_minutes(),
    'fields', (select jsonb_agg(jsonb_build_object('field', f ->> 'field', 'group', f ->> 'group', 'kind', f ->> 'kind', 'max', f -> 'max',
                                                   'writable', f ->> 'write' = 'b2c' and (cfg -> 'writable') ? (f ->> 'field')))
                 from jsonb_array_elements(b2b.b2c_fields()) f),
    'stages', (select jsonb_agg(jsonb_build_object('key', e ->> 'key', 'rank', e -> 'rank', 'group', e ->> 'group'))
                 from b2b.settings s, jsonb_array_elements(s.value) e where s.key = 'stages' and e ->> 'key' is not null),
    'activity_kinds', jsonb_build_array('call', 'whatsapp', 'sms', 'email', 'meeting', 'note')));
end $fn$;

/* Up to 200 updates and activities in one call: p = {items: [{op: 'update' | 'activity', lead_id, …the body of the
   single call}]}. Each item is applied on its own (one refused item does not stop the others) and answered in order. */
create or replace function b2b.api_b2c_batch(p_key text, p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  it jsonb;
  res jsonb;
  v_out jsonb := '[]';
  v_ok int := 0;
  v_lead bigint;
begin
  if not (b2b.b2c_key(p_key) ->> 'ok')::boolean then return jsonb_build_object('ok', false, 'status', 401, 'error', 'invalid key'); end if;
  if jsonb_typeof(p -> 'items') is distinct from 'array' or jsonb_array_length(p -> 'items') not between 1 and 200 then
    return jsonb_build_object('ok', false, 'status', 400, 'error', 'items must be a list of 1 to 200 updates or activities');
  end if;
  for it in select x from jsonb_array_elements(p -> 'items') x loop
    v_lead := case when (it ->> 'lead_id') ~ '^\d{1,18}$' then (it ->> 'lead_id')::bigint end;
    res := case
      when jsonb_typeof(it) <> 'object' or v_lead is null then jsonb_build_object('ok', false, 'status', 400, 'error', 'each item needs op and lead_id')
      when it ->> 'op' = 'update' then b2b.api_b2c_lead_update(p_key, v_lead, it - 'op' - 'lead_id')
      when it ->> 'op' = 'activity' then b2b.api_b2c_activity(p_key, v_lead, it - 'op' - 'lead_id')
      else jsonb_build_object('ok', false, 'status', 400, 'error', 'op must be update or activity') end;
    if (res ->> 'ok')::boolean then v_ok := v_ok + 1; end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('lead_id', v_lead, 'request_id', it ->> 'request_id', 'op', it ->> 'op') || (res - 'result')
                                        || case when res ? 'result' then jsonb_build_object('version', res -> 'result' -> 'version', 'changed', res -> 'result' -> 'changed') else '{}' end);
  end loop;
  return jsonb_build_object('ok', true, 'status', 200, 'result', jsonb_build_object('applied', v_ok, 'items', v_out));
end $fn$;

revoke execute on function b2b.b2c_link_settings_save(jsonb, text), b2b.sync_settings_save(int, text), b2b.sync_cadence() from public, anon;
grant execute on function b2b.b2c_link_settings_save(jsonb, text), b2b.sync_settings_save(int, text), b2b.sync_cadence() to authenticated, service_role;
revoke execute on function b2b.api_b2c_schema(text), b2b.api_b2c_batch(text, jsonb) from public;
grant execute on function b2b.api_b2c_schema(text), b2b.api_b2c_batch(text, jsonb) to anon, authenticated, service_role;
