-- Influencer Portal: typed settings (spec 2.9, 21). Definitions come from lib/settings/registry.ts through a
-- generated migration; every write is validated against the key's JSON Schema here, so a direct RPC call can't store
-- an invalid value. Each change keeps a version row and an audit entry, and shows who changed it and when.

create table inf.setting_definitions (
  key                 text primary key check (key ~ '^[a-z_]+\.[a-z_]+$'),
  grp                 text not null,
  label               text not null,
  description         text not null,
  json_schema         jsonb not null,
  default_value       jsonb not null,
  edit_permission     text not null references inf.permissions (key),
  needs_confirmation  text,
  updated_at          timestamptz not null default now(),
  constraint default_is_valid check (inf.json_matches_schema(default_value, json_schema))
);

create table inf.settings (
  key           text primary key references inf.setting_definitions (key) on delete cascade,
  value         jsonb not null,
  version       int not null default 1 check (version >= 1),
  confirmed_at  timestamptz,
  confirmed_by  uuid,
  updated_by    uuid,
  updated_at    timestamptz not null default now()
);

create table inf.settings_versions (
  id        bigint generated always as identity primary key,
  key       text not null,
  version   int not null,
  value     jsonb not null,
  actor_id  uuid,
  reason    text not null,
  at        timestamptz not null default now(),
  unique (key, version)
);
create trigger settings_versions_append_only before update or delete on inf.settings_versions
  for each row execute function inf.forbid_mutation();

-- Internal: the effective value (stored or default). Not granted to clients; used inside definer functions.
create or replace function inf.setting(p_key text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(s.value, d.default_value)
    from inf.setting_definitions d left join inf.settings s on s.key = d.key
   where d.key = p_key;
$$;

create or replace function inf.settings_list() returns table (
  key text, grp text, label text, description text, json_schema jsonb, default_value jsonb, value jsonb,
  version int, is_default boolean, can_edit boolean, needs_confirmation text, confirmed_at timestamptz,
  updated_by_name text, updated_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select d.key, d.grp, d.label, d.description, d.json_schema, d.default_value, coalesce(s.value, d.default_value),
         coalesce(s.version, 0), s.key is null, inf.has_perm(d.edit_permission), d.needs_confirmation, s.confirmed_at,
         (select p.full_name from inf.staff_profiles p where p.user_id = s.updated_by), s.updated_at
    from inf.setting_definitions d left join inf.settings s on s.key = d.key
   where inf.has_perm('settings.read') or inf.has_perm(d.edit_permission)
   order by d.grp, d.key;
$$;

create or replace function inf.setting_history(p_key text) returns table (version int, value jsonb, actor_name text, reason text, at timestamptz)
language sql stable security definer set search_path = '' as $$
  select v.version, v.value, (select p.full_name from inf.staff_profiles p where p.user_id = v.actor_id), v.reason, v.at
    from inf.settings_versions v
   where v.key = p_key
     and (inf.has_perm('settings.read') or inf.has_perm((select d.edit_permission from inf.setting_definitions d where d.key = p_key)))
   order by v.version desc
   limit 100;
$$;

-- Change a setting. p_expected_version guards against two people editing at once (0 = still the default).
create or replace function inf.setting_set(p_key text, p_value jsonb, p_reason text, p_expected_version int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_def  inf.setting_definitions;
  v_cur  inf.settings;
  v_errs text[];
  v_next int;
begin
  select * into v_def from inf.setting_definitions where key = p_key;
  if v_def.key is null then return jsonb_build_object('ok', false, 'error', 'unknown_setting'); end if;
  if not inf.has_perm(v_def.edit_permission) then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_reason), '') = '' or char_length(p_reason) > 500 then
    return jsonb_build_object('ok', false, 'error', 'reason_required');
  end if;
  v_errs := inf.json_schema_errors(p_value, v_def.json_schema);
  if cardinality(v_errs) > 0 then return jsonb_build_object('ok', false, 'error', 'invalid', 'details', to_jsonb(v_errs)); end if;
  select * into v_cur from inf.settings where key = p_key for update;
  if coalesce(v_cur.version, 0) <> coalesce(p_expected_version, -1) then
    return jsonb_build_object('ok', false, 'error', 'stale', 'version', coalesce(v_cur.version, 0));
  end if;
  if v_cur.key is not null and v_cur.value = p_value then return jsonb_build_object('ok', true, 'version', v_cur.version, 'unchanged', true); end if;
  v_next := coalesce(v_cur.version, 0) + 1;
  insert into inf.settings (key, value, version, updated_by, updated_at, confirmed_at, confirmed_by)
  values (p_key, p_value, v_next, auth.uid(), now(), null, null)
  on conflict (key) do update set value = excluded.value, version = excluded.version, updated_by = excluded.updated_by,
    updated_at = excluded.updated_at, confirmed_at = null, confirmed_by = null;
  insert into inf.settings_versions (key, version, value, actor_id, reason) values (p_key, v_next, p_value, auth.uid(), p_reason);
  perform inf.audit('setting', p_key, 'update', jsonb_build_object('value', coalesce(v_cur.value, v_def.default_value), 'version', coalesce(v_cur.version, 0)),
                    jsonb_build_object('value', p_value, 'version', v_next, 'reason', p_reason));
  return jsonb_build_object('ok', true, 'version', v_next);
end $$;

-- Records that a person (e.g. after the CA's advice) confirmed a value flagged "needs confirmation".
create or replace function inf.setting_confirm(p_key text, p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_def inf.setting_definitions;
begin
  select * into v_def from inf.setting_definitions where key = p_key;
  if v_def.key is null then raise exception 'unknown setting' using errcode = '22023'; end if;
  if not inf.has_perm(v_def.edit_permission) then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'a note is required' using errcode = '22023'; end if;
  insert into inf.settings (key, value, version, updated_by, confirmed_at, confirmed_by)
  values (p_key, v_def.default_value, 1, auth.uid(), now(), auth.uid())
  on conflict (key) do update set confirmed_at = now(), confirmed_by = auth.uid();
  if not exists (select 1 from inf.settings_versions where key = p_key) then
    insert into inf.settings_versions (key, version, value, actor_id, reason) values (p_key, 1, v_def.default_value, auth.uid(), 'confirmed default');
  end if;
  perform inf.audit('setting', p_key, 'confirm', null, jsonb_build_object('note', p_note));
end $$;

alter table inf.setting_definitions enable row level security;
alter table inf.settings enable row level security;
alter table inf.settings_versions enable row level security;
-- No direct table access for clients: reads through settings_list() / setting_history(), writes through setting_set().

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('function', 'inf.settings_list()', 'authenticated', 'execute'),
  ('function', 'inf.setting_history(text)', 'authenticated', 'execute'),
  ('function', 'inf.setting_set(text, jsonb, text, int)', 'authenticated', 'execute'),
  ('function', 'inf.setting_confirm(text, text)', 'authenticated', 'execute');
call inf.apply_client_grants();
