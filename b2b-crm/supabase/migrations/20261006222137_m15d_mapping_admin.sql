-- M15d: editing and publishing mappings (spec B8.3.3).
-- Editing happens on a partner's draft (a copy of the active version). Publishing numbers the draft, runs the golden
-- files, retires the previous version, resolves the queue items the new version now covers and re-applies held events.
-- Any earlier version can be restored in one step. No row is erased: removing a rule replaces the draft with a copy
-- that leaves the rule out, a discarded draft is retired without a version number, golden files are archived.
-- The test panel, discovery, schema snapshots with drift, the queue, golden files and the studio reads are in m15e.

/* Partner stages a mapping may produce. Money stages and B2C stages are never set by a partner. */
create or replace function b2b.mapping_target_stages()
returns text[] language sql immutable set search_path = '' as $fn$
  select array['contacted', 'counselled', 'applied', 'enrolled', 'lost', 'duplicate_at_partner'];
$fn$;

create or replace function b2b.mapping_draft_of(p_profile_id bigint)
returns b2b.mapping_profiles language plpgsql stable security definer set search_path = '' as $fn$
declare pr b2b.mapping_profiles;
begin
  select * into pr from b2b.mapping_profiles where id = p_profile_id;
  if pr.id is null then raise exception 'mapping version not found' using errcode = 'P0002'; end if;
  if pr.status <> 'draft' then raise exception 'only a draft can be changed; start a draft first' using errcode = '22023'; end if;
  return pr;
end $fn$;

/* Copies every rule of one profile into another, optionally leaving one rule out (that is how a rule is removed). */
create or replace function b2b.mapping_copy_rules(p_from bigint, p_to bigint, p_skip_kind text default null, p_skip_id bigint default null)
returns void language sql volatile security definer set search_path = '' as $fn$
  insert into b2b.mapping_pipelines (profile_id, key, label) select p_to, key, label from b2b.mapping_pipelines
   where profile_id = p_from and not (coalesce(p_skip_kind, '') = 'pipeline' and id = p_skip_id);
  insert into b2b.status_rules (profile_id, pipeline_key, partner_stage, partner_sub_stage, conditions, stage, sub_stage, lost_reason, is_reopen, ignore, ignore_reason, priority)
    select p_to, pipeline_key, partner_stage, partner_sub_stage, conditions, stage, sub_stage, lost_reason, is_reopen, ignore, ignore_reason, priority
      from b2b.status_rules where profile_id = p_from and not (coalesce(p_skip_kind, '') = 'status' and id = p_skip_id) order by id;
  insert into b2b.field_rules (profile_id, partner_field, canonical_key, direction, transforms, out_transforms, trusted, required, not_available, note)
    select p_to, partner_field, canonical_key, direction, transforms, out_transforms, trusted, required, not_available, note
      from b2b.field_rules where profile_id = p_from and not (coalesce(p_skip_kind, '') = 'field' and id = p_skip_id) order by id;
  insert into b2b.value_rules (profile_id, canonical_key, partner_value, canonical_value, direction)
    select p_to, canonical_key, partner_value, canonical_value, direction from b2b.value_rules
     where profile_id = p_from and not (coalesce(p_skip_kind, '') = 'value' and id = p_skip_id) order by id;
  insert into b2b.activity_rules (profile_id, partner_type, partner_outcome, kind, outcome)
    select p_to, partner_type, partner_outcome, kind, outcome from b2b.activity_rules
     where profile_id = p_from and not (coalesce(p_skip_kind, '') = 'activity' and id = p_skip_id) order by id;
$fn$;

create or replace function b2b.mapping_draft_start(p_partner_id bigint)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint; act b2b.mapping_profiles;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partners where id = p_partner_id) then raise exception 'partner not found' using errcode = 'P0002'; end if;
  select id into v_id from b2b.mapping_profiles where partner_id = p_partner_id and status = 'draft';
  if v_id is not null then return v_id; end if;
  select * into act from b2b.mapping_profiles where partner_id = p_partner_id and status = 'active';
  insert into b2b.mapping_profiles (partner_id, status, pipeline_field, based_on, created_by)
  values (p_partner_id, 'draft', coalesce(act.pipeline_field, 'pipeline'), act.id, b2b.actor() ->> 'id') returning id into v_id;
  if act.id is not null then perform b2b.mapping_copy_rules(act.id, v_id); end if;
  return v_id;
end $fn$;

/* Discarding a draft retires it without a version number; it never appears in the history. */
create or replace function b2b.mapping_draft_discard(p_profile_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare pr b2b.mapping_profiles;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  pr := b2b.mapping_draft_of(p_profile_id);
  update b2b.mapping_profiles set status = 'retired', note = 'discarded draft' where id = pr.id;
end $fn$;

/* Removes one rule from a draft by replacing the draft with a copy that leaves it out. Returns the new draft's id. */
create or replace function b2b.mapping_rule_remove(p_kind text, p_id bigint)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_profile bigint;
  pr b2b.mapping_profiles;
  v_new bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_kind is null or p_kind not in ('status', 'field', 'value', 'activity', 'pipeline') then raise exception 'unknown rule kind' using errcode = '22023'; end if;
  execute format('select profile_id from b2b.%I where id = $1', case p_kind when 'status' then 'status_rules' when 'field' then 'field_rules'
                   when 'value' then 'value_rules' when 'activity' then 'activity_rules' else 'mapping_pipelines' end) into v_profile using p_id;
  if v_profile is null then raise exception 'rule not found' using errcode = 'P0002'; end if;
  pr := b2b.mapping_draft_of(v_profile);
  if p_kind = 'pipeline' and exists (select 1 from b2b.status_rules s join b2b.mapping_pipelines m on m.id = p_id
                                      where s.profile_id = pr.id and s.pipeline_key = m.key) then
    raise exception 'stage rules still use this pipeline' using errcode = '22023';
  end if;
  update b2b.mapping_profiles set status = 'retired', note = 'replaced draft' where id = pr.id;
  insert into b2b.mapping_profiles (partner_id, status, pipeline_field, based_on, created_by)
  values (pr.partner_id, 'draft', pr.pipeline_field, pr.based_on, b2b.actor() ->> 'id') returning id into v_new;
  perform b2b.mapping_copy_rules(pr.id, v_new, p_kind, p_id);
  return v_new;
end $fn$;

create or replace function b2b.mapping_profile_settings(p_profile_id bigint, p_pipeline_field text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare pr b2b.mapping_profiles;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  pr := b2b.mapping_draft_of(p_profile_id);
  if coalesce(trim(p_pipeline_field), '') !~ '^[A-Za-z0-9_.\- ]{1,80}$' then raise exception 'name the field that carries the pipeline' using errcode = '22023'; end if;
  update b2b.mapping_profiles set pipeline_field = trim(p_pipeline_field) where id = pr.id;
end $fn$;

create or replace function b2b.mapping_chain_ok(p_chain jsonb)
returns boolean language sql immutable set search_path = '' as $fn$
  select jsonb_typeof(coalesce(p_chain, '[]')) = 'array' and jsonb_array_length(coalesce(p_chain, '[]')) <= 8
     and not exists (select 1 from jsonb_array_elements(coalesce(p_chain, '[]')) t
                      where jsonb_typeof(t) <> 'object' or not ((t ->> 'op') = any (b2b.mapping_transform_ops())));
$fn$;

/* Saves one rule on a draft. p_kind: status | field | value | activity | pipeline. p.id updates, otherwise inserts. */
create or replace function b2b.mapping_rule_save(p_kind text, p jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare
  pr b2b.mapping_profiles;
  c b2b.canonical_fields;
  v_id bigint := nullif(p ->> 'id', '')::bigint;
  v_val text;
  v_dir text := coalesce(nullif(p ->> 'direction', ''), 'both');
  cnd jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  pr := b2b.mapping_draft_of((p ->> 'profile_id')::bigint);
  case p_kind
    when 'pipeline' then
      if coalesce(trim(p ->> 'key'), '') = '' or length(p ->> 'key') > 120 then raise exception 'give the pipeline''s value' using errcode = '22023'; end if;
      insert into b2b.mapping_pipelines (profile_id, key, label) values (pr.id, trim(p ->> 'key'), nullif(trim(p ->> 'label'), ''))
      on conflict (profile_id, key) do update set label = excluded.label returning id into v_id;
    when 'status' then
      if coalesce(trim(p ->> 'partner_stage'), '') = '' or length(p ->> 'partner_stage') > 200 then raise exception 'give the partner''s stage' using errcode = '22023'; end if;
      if coalesce((p ->> 'ignore')::boolean, false) then
        if length(trim(coalesce(p ->> 'ignore_reason', ''))) < 3 then raise exception 'say why this stage is ignored' using errcode = '22023'; end if;
      else
        if not coalesce(p ->> 'stage', '') = any (b2b.mapping_target_stages()) then raise exception 'choose an Eduwit stage' using errcode = '22023'; end if;
        if nullif(p ->> 'lost_reason', '') is not null and not exists (select 1 from jsonb_array_elements_text((select value from b2b.settings where key = 'lost_reasons')) x
                                                                         where x = p ->> 'lost_reason') then
          raise exception 'unknown lost reason' using errcode = '22023';
        end if;
        if nullif(p ->> 'lost_reason', '') is not null and p ->> 'stage' <> 'lost' then raise exception 'a lost reason needs the stage lost' using errcode = '22023'; end if;
      end if;
      if nullif(p ->> 'pipeline_key', '') is not null and not exists (select 1 from b2b.mapping_pipelines where profile_id = pr.id and key = p ->> 'pipeline_key') then
        raise exception 'add the pipeline first' using errcode = '22023';
      end if;
      for cnd in select x from jsonb_array_elements(coalesce(p -> 'conditions', '[]')) x loop
        if coalesce(cnd ->> 'field', '') = '' or not (cnd ->> 'op') = any (array['eq', 'neq', 'in', 'empty', 'not_empty'])
           or ((cnd ->> 'op') = 'in' and jsonb_typeof(cnd -> 'value') <> 'array') then
          raise exception 'each condition needs a field, an operator (eq, neq, in, empty, not_empty) and a value' using errcode = '22023';
        end if;
      end loop;
      if v_id is null then
        insert into b2b.status_rules (profile_id, pipeline_key, partner_stage, partner_sub_stage, conditions, stage, sub_stage, lost_reason, is_reopen, ignore, ignore_reason, priority)
        values (pr.id, nullif(p ->> 'pipeline_key', ''), trim(p ->> 'partner_stage'), nullif(trim(p ->> 'partner_sub_stage'), ''), coalesce(p -> 'conditions', '[]'),
                case when coalesce((p ->> 'ignore')::boolean, false) then null else p ->> 'stage' end, nullif(left(trim(p ->> 'sub_stage'), 80), ''),
                nullif(p ->> 'lost_reason', ''), coalesce((p ->> 'is_reopen')::boolean, false), coalesce((p ->> 'ignore')::boolean, false),
                nullif(trim(p ->> 'ignore_reason'), ''), coalesce((p ->> 'priority')::int, 100))
        returning id into v_id;
      else
        update b2b.status_rules set pipeline_key = nullif(p ->> 'pipeline_key', ''), partner_stage = trim(p ->> 'partner_stage'),
               partner_sub_stage = nullif(trim(p ->> 'partner_sub_stage'), ''), conditions = coalesce(p -> 'conditions', '[]'),
               stage = case when coalesce((p ->> 'ignore')::boolean, false) then null else p ->> 'stage' end, sub_stage = nullif(left(trim(p ->> 'sub_stage'), 80), ''),
               lost_reason = nullif(p ->> 'lost_reason', ''), is_reopen = coalesce((p ->> 'is_reopen')::boolean, false), ignore = coalesce((p ->> 'ignore')::boolean, false),
               ignore_reason = nullif(trim(p ->> 'ignore_reason'), ''), priority = coalesce((p ->> 'priority')::int, 100)
         where id = v_id and profile_id = pr.id;
        if not found then raise exception 'rule not found' using errcode = 'P0002'; end if;
      end if;
    when 'field' then
      select * into c from b2b.canonical_fields where key = p ->> 'canonical_key';
      if c.key is null then raise exception 'choose an Eduwit field' using errcode = '22023'; end if;
      if v_dir not in ('in', 'out', 'both') then raise exception 'direction must be in, out or both' using errcode = '22023'; end if;
      if v_dir in ('out', 'both') and not c.outbound then raise exception '% is never sent to partners', c.label using errcode = '22023'; end if;
      if v_dir in ('in', 'both') and not c.inbound then raise exception '% is not taken from partners', c.label using errcode = '22023'; end if;
      if not coalesce((p ->> 'not_available')::boolean, false) and (coalesce(trim(p ->> 'partner_field'), '') = '' or length(p ->> 'partner_field') > 200) then
        raise exception 'give the partner''s field name' using errcode = '22023';
      end if;
      if not b2b.mapping_chain_ok(p -> 'transforms') or not b2b.mapping_chain_ok(p -> 'out_transforms') then
        raise exception 'unknown transform (allowed: %)', array_to_string(b2b.mapping_transform_ops(), ', ') using errcode = '22023';
      end if;
      if coalesce((p ->> 'trusted')::boolean, false) and c.owner = 'b2b' then raise exception 'trusted applies only to Witty-owned fields' using errcode = '22023'; end if;
      if v_id is null then
        insert into b2b.field_rules (profile_id, partner_field, canonical_key, direction, transforms, out_transforms, trusted, required, not_available, note)
        values (pr.id, case when coalesce((p ->> 'not_available')::boolean, false) then null else trim(p ->> 'partner_field') end, c.key, v_dir,
                coalesce(p -> 'transforms', '[]'), coalesce(p -> 'out_transforms', '[]'), coalesce((p ->> 'trusted')::boolean, false),
                coalesce((p ->> 'required')::boolean, false), coalesce((p ->> 'not_available')::boolean, false), nullif(left(trim(p ->> 'note'), 300), ''))
        returning id into v_id;
      else
        update b2b.field_rules set partner_field = case when coalesce((p ->> 'not_available')::boolean, false) then null else trim(p ->> 'partner_field') end,
               canonical_key = c.key, direction = v_dir, transforms = coalesce(p -> 'transforms', '[]'), out_transforms = coalesce(p -> 'out_transforms', '[]'),
               trusted = coalesce((p ->> 'trusted')::boolean, false), required = coalesce((p ->> 'required')::boolean, false),
               not_available = coalesce((p ->> 'not_available')::boolean, false), note = nullif(left(trim(p ->> 'note'), 300), '')
         where id = v_id and profile_id = pr.id;
        if not found then raise exception 'rule not found' using errcode = 'P0002'; end if;
      end if;
    when 'value' then
      select * into c from b2b.canonical_fields where key = p ->> 'canonical_key';
      if c.key is null or c.data_type <> 'picklist' then raise exception 'choose a picklist field' using errcode = '22023'; end if;
      if v_dir not in ('in', 'out', 'both') then raise exception 'direction must be in, out or both' using errcode = '22023'; end if;
      select x into v_val from unnest(b2b.mapping_allowed(c)) x where lower(x) = lower(trim(coalesce(p ->> 'canonical_value', ''))) limit 1;
      if v_val is null then raise exception 'choose one of the Eduwit values for %', c.label using errcode = '22023'; end if;
      if coalesce(trim(p ->> 'partner_value'), '') = '' or length(p ->> 'partner_value') > 200 then raise exception 'give the partner''s value' using errcode = '22023'; end if;
      if v_id is null then
        insert into b2b.value_rules (profile_id, canonical_key, partner_value, canonical_value, direction)
        values (pr.id, c.key, trim(p ->> 'partner_value'), v_val, v_dir) returning id into v_id;
      else
        update b2b.value_rules set canonical_key = c.key, partner_value = trim(p ->> 'partner_value'), canonical_value = v_val, direction = v_dir
         where id = v_id and profile_id = pr.id;
        if not found then raise exception 'rule not found' using errcode = 'P0002'; end if;
      end if;
    when 'activity' then
      if coalesce(trim(p ->> 'partner_type'), '') = '' then raise exception 'give the partner''s activity type' using errcode = '22023'; end if;
      if not coalesce(p ->> 'kind', '') = any (array['call', 'whatsapp', 'email', 'sms', 'meeting', 'note', 'task', 'stage_change']) then
        raise exception 'choose an Eduwit activity kind' using errcode = '22023';
      end if;
      if p ->> 'kind' = 'call' and nullif(p ->> 'outcome', '') is not null
         and not exists (select 1 from b2b.canonical_fields c2 cross join lateral unnest(c2.allowed) o where c2.key = 'call_outcome' and o = p ->> 'outcome') then
        raise exception 'choose a call outcome' using errcode = '22023';
      end if;
      if v_id is null then
        insert into b2b.activity_rules (profile_id, partner_type, partner_outcome, kind, outcome)
        values (pr.id, trim(p ->> 'partner_type'), nullif(trim(p ->> 'partner_outcome'), ''), p ->> 'kind', nullif(trim(p ->> 'outcome'), '')) returning id into v_id;
      else
        update b2b.activity_rules set partner_type = trim(p ->> 'partner_type'), partner_outcome = nullif(trim(p ->> 'partner_outcome'), ''), kind = p ->> 'kind',
               outcome = nullif(trim(p ->> 'outcome'), '')
         where id = v_id and profile_id = pr.id;
        if not found then raise exception 'rule not found' using errcode = 'P0002'; end if;
      end if;
    else raise exception 'unknown rule kind' using errcode = '22023';
  end case;
  return v_id;
end $fn$;

/* Queue items a profile now covers. */
create or replace function b2b.mapping_queue_covered(p_profile_id bigint, q b2b.mapping_queue)
returns boolean language plpgsql stable set search_path = '' as $fn$
declare m jsonb; v_parts text[];
begin
  case q.kind
    when 'stage' then
      v_parts := regexp_split_to_array(q.item, ' / ');
      m := b2b.mapping_in(p_profile_id, 'stage', jsonb_build_object('stage', v_parts[1], 'sub_stage', v_parts[2]));
      return coalesce((m -> 'status' ->> 'matched')::boolean, false);
    when 'field' then
      return exists (select 1 from b2b.field_rules x where x.profile_id = p_profile_id and lower(x.partner_field) = lower(q.item) and x.direction in ('in', 'both'));
    when 'value' then
      v_parts := regexp_split_to_array(q.item, ' = ');
      return exists (select 1 from b2b.field_rules x where x.profile_id = p_profile_id and x.canonical_key = v_parts[1] and x.direction in ('in', 'both')
                      and not x.not_available
                      and b2b.mapping_in(p_profile_id, 'update', jsonb_build_object('fields', jsonb_build_object(x.partner_field, coalesce(q.sample ->> 'value', v_parts[2]))))
                          -> 'fields' ? v_parts[1]);
    when 'activity' then
      v_parts := regexp_split_to_array(q.item, ' / ');
      m := b2b.mapping_in(p_profile_id, 'activity', jsonb_build_object('type', v_parts[1], 'outcome', v_parts[2]));
      return m -> 'activity' is not null;
    else return false;
  end case;
end $fn$;

/* Publishes a draft: golden files must pass. Returns the new version, re-processing and queue results. */
create or replace function b2b.mapping_publish(p_profile_id bigint, p_note text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  pr b2b.mapping_profiles;
  v_version int;
  v_failed text;
  v_resolved int := 0;
  q b2b.mapping_queue;
  v_re jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'say what changed (for the version history)' using errcode = '22023'; end if;
  pr := b2b.mapping_draft_of(p_profile_id);
  perform 1 from b2b.mapping_profiles where partner_id = pr.partner_id for update;
  select string_agg(g ->> 'name', ', ') into v_failed from jsonb_array_elements(b2b.mapping_golden_run(pr.id)) g where not (g ->> 'pass')::boolean;
  if v_failed is not null then raise exception 'golden files fail: %', v_failed using errcode = '22023'; end if;
  select coalesce(max(version), 0) + 1 into v_version from b2b.mapping_profiles where partner_id = pr.partner_id;
  update b2b.mapping_profiles set status = 'retired' where partner_id = pr.partner_id and status = 'active';
  update b2b.mapping_profiles set status = 'active', version = v_version, note = left(trim(p_note), 500), activated_at = now(), activated_by = b2b.actor() ->> 'id'
   where id = pr.id;
  for q in select * from b2b.mapping_queue where partner_id = pr.partner_id and status = 'open' loop
    if b2b.mapping_queue_covered(pr.id, q) then
      update b2b.mapping_queue set status = 'mapped', resolution = 'mapped in version ' || v_version, resolved_at = now() where id = q.id;
      v_resolved := v_resolved + 1;
    end if;
  end loop;
  perform b2b.log_event('mapping.published', null, null, pr.partner_id, jsonb_build_object('version', v_version, 'profile_id', pr.id, 'note', left(trim(p_note), 300)));
  v_re := b2b.mapping_reprocess(pr.partner_id);
  return jsonb_build_object('version', v_version, 'queue_resolved', v_resolved, 'reprocess', v_re);
end $fn$;

/* Makes an earlier version active again, as a new version number (history is never rewritten). */
create or replace function b2b.mapping_restore(p_profile_id bigint, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  old b2b.mapping_profiles;
  v_id bigint;
  v_version int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into old from b2b.mapping_profiles where id = p_profile_id;
  if old.id is null or old.status <> 'retired' or old.version is null then raise exception 'only an earlier version can be restored' using errcode = '22023'; end if;
  perform 1 from b2b.mapping_profiles where partner_id = old.partner_id for update;
  select coalesce(max(version), 0) + 1 into v_version from b2b.mapping_profiles where partner_id = old.partner_id;
  update b2b.mapping_profiles set status = 'retired' where partner_id = old.partner_id and status = 'active';
  insert into b2b.mapping_profiles (partner_id, version, status, pipeline_field, note, based_on, created_by, activated_at, activated_by)
  values (old.partner_id, v_version, 'active', old.pipeline_field, 'Restored version ' || old.version || ': ' || left(trim(p_reason), 400), old.id,
          b2b.actor() ->> 'id', now(), b2b.actor() ->> 'id')
  returning id into v_id;
  perform b2b.mapping_copy_rules(old.id, v_id);
  perform b2b.log_event('mapping.restored', null, null, old.partner_id, jsonb_build_object('version', v_version, 'from_version', old.version, 'reason', left(trim(p_reason), 300)));
  return jsonb_build_object('version', v_version, 'reprocess', b2b.mapping_reprocess(old.partner_id));
end $fn$;

revoke execute on function b2b.mapping_target_stages(), b2b.mapping_draft_of(bigint), b2b.mapping_copy_rules(bigint, bigint, text, bigint), b2b.mapping_chain_ok(jsonb), b2b.mapping_queue_covered(bigint, b2b.mapping_queue)
  from public, anon, authenticated;
grant execute on function b2b.mapping_target_stages(), b2b.mapping_draft_of(bigint), b2b.mapping_copy_rules(bigint, bigint, text, bigint), b2b.mapping_chain_ok(jsonb), b2b.mapping_queue_covered(bigint, b2b.mapping_queue)
  to service_role;
revoke execute on function b2b.mapping_draft_start(bigint), b2b.mapping_draft_discard(bigint), b2b.mapping_rule_remove(text, bigint), b2b.mapping_profile_settings(bigint, text), b2b.mapping_rule_save(text, jsonb), b2b.mapping_publish(bigint, text), b2b.mapping_restore(bigint, text)
  from public, anon;
grant execute on function b2b.mapping_draft_start(bigint), b2b.mapping_draft_discard(bigint), b2b.mapping_rule_remove(text, bigint), b2b.mapping_profile_settings(bigint, text), b2b.mapping_rule_save(text, jsonb), b2b.mapping_publish(bigint, text), b2b.mapping_restore(bigint, text)
  to authenticated, service_role;
