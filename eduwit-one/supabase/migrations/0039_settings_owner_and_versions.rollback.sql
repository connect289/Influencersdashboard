-- Rollback of 0039: engineers change the thresholds again, a setting is saved without comparing versions, and a schema's
-- functions are acknowledged on the count alone, as after 0038 (the functions as 0010, 0037 and 0038 left them, with
-- their api_grants rows). What was saved or acknowledged under 0039 stays, with its versions and audit rows.

create or replace function one.setting_owner_only(p_key text) returns boolean
language sql immutable set search_path = '' as $$
  select p_key not in ('thresholds', 'checks', 'tests', 'witty', 'analytics')
$$;

delete from one.api_grants where fn = 'one.ui_settings_put(text,jsonb,text,text,integer)';
drop function if exists one.ui_settings_put(text, jsonb, text, text, integer);
create or replace function one.ui_settings_put(p_key text, p_value jsonb, p_reason text, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('operate');
  v_reason text := one.ui_reason(p_reason);
  v_before jsonb;
  v_version integer;
  v_value jsonb := p_value;
begin
  select value into v_before from one.settings where key = p_key for update;
  if v_before is null or p_key in ('setup', 'setup_catalog') then
    raise exception 'setting % cannot be changed here', p_key using errcode = '22023';
  end if;
  if one.setting_owner_only(p_key)
     or (p_key = 'alerts' and one.alert_recipients(v_before) is distinct from one.alert_recipients(p_value)) then
    perform one.ui_require('owner');
  end if;
  -- The observation window's start is the first tick's to write, never a page's (security review m1): the stored
  -- value is kept whatever the form sends, so the window cannot be backdated before it starts.
  if p_key = 'fixes' then
    v_value := v_value || jsonb_build_object('observation_started_at', v_before -> 'observation_started_at');
  end if;
  if v_value = v_before then
    raise exception 'nothing changed: the value is the current version' using errcode = '22023';
  end if;
  v_version := one.settings_put(p_key, v_value, v_actor, v_reason);
  perform one.ui_audit_write(v_actor, 'settings.put', 'settings:' || p_key, v_before, v_value, p_request_id);
  return jsonb_build_object('ok', true, 'version', v_version);
end $$;
insert into one.api_grants (fn, role, why) values ('one.ui_settings_put(text,jsonb,text,text)', 'authenticated', 'page write (0011)')
on conflict do nothing;

delete from one.api_grants where fn = 'one.ui_privilege_ack_schema(text,integer,text,text)';
drop function if exists one.ui_privilege_ack_schema(text, integer, text, text);
create or replace function one.ui_privilege_ack_schema(p_schema text, p_expected integer, p_request_id text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_actor text := one.ui_require('owner');
  v_fns text[];
  f text;
begin
  select coalesce(array_agg(b.fn order by b.fn), '{}') into v_fns
    from one.privilege_baseline b where b.schema = p_schema and not b.acknowledged;
  if cardinality(v_fns) = 0 then
    raise exception 'nothing to acknowledge in schema %', left(coalesce(p_schema, ''), 60) using errcode = '22023';
  end if;
  if cardinality(v_fns) is distinct from p_expected then
    raise exception 'the list changed: % function(s) to acknowledge in %, not %; reload the page and read it again',
      cardinality(v_fns), left(p_schema, 60), coalesce(p_expected::text, 'none') using errcode = '22023';
  end if;
  update one.privilege_baseline set acknowledged = true, acknowledged_by = v_actor where fn = any (v_fns) and not acknowledged;
  foreach f in array v_fns loop
    perform one.ui_audit_write(v_actor, 'privilege.acknowledge', 'function:' || left(f, 180), null, null, p_request_id);
  end loop;
  return jsonb_build_object('ok', true, 'acknowledged', cardinality(v_fns));
end $$;
insert into one.api_grants (fn, role, why)
values ('one.ui_privilege_ack_schema(text,integer,text)', 'authenticated', 'page write (0038): the owner acknowledges a schema''s new functions')
on conflict do nothing;

call one.apply_grants();
