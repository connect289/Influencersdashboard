-- M15b: the mapping engine (spec B8.3.2, B8.3.4, B8.3.7). Pure read functions, used by the runtime (m15c), the
-- studio's test panel and the publish checks (m15d):
--   mapping_transform  one value through a transform chain
--   mapping_in         a partner payload → Eduwit stage, sub-stage, lost reason, canonical fields, activity, and
--                      everything that could not be mapped (never dropped: unmapped fields are returned as custom)
--   lead_canonical     an allocation's lead as canonical outbound values (the same data the standard push sends)
--   mapping_out        canonical values → the partner's fields, with required items still missing
--   mapping_coverage   the go-live coverage gates, item by item, with a score
--   mapping_golden_run the partner's golden files against a profile

/* Transforms: trim, lower, upper, title, phone_e164, date, datetime, amount, cgpa_to_pct, boolean, constant, default,
   split {sep, part: first|last|rest|<index>}, replace {from, to}, join {with: <key in ctx>, sep}. Unknown ops are refused on save. */
create or replace function b2b.mapping_transform(p_value text, p_chain jsonb, p_ctx jsonb default '{}')
returns text language plpgsql immutable set search_path = '' as $fn$
declare
  v text := p_value;
  t jsonb;
  d text;
  parts text[];
  n numeric;
  m text[];
begin
  for t in select x from jsonb_array_elements(coalesce(p_chain, '[]')) x loop
    case t ->> 'op'
      when 'trim' then v := nullif(trim(regexp_replace(v, '\s+', ' ', 'g')), '');
      when 'lower' then v := lower(v);
      when 'upper' then v := upper(v);
      when 'title' then v := initcap(v);
      when 'constant' then v := t ->> 'value';
      when 'default' then v := coalesce(nullif(trim(v), ''), t ->> 'value');
      when 'replace' then v := replace(v, coalesce(t ->> 'from', ''), coalesce(t ->> 'to', ''));
      when 'join' then v := nullif(concat_ws(coalesce(t ->> 'sep', ' '), nullif(trim(v), ''), nullif(trim(p_ctx ->> (t ->> 'with')), '')), '');
      when 'split' then
        if v is not null then
          parts := array_remove(string_to_array(v, coalesce(nullif(t ->> 'sep', ''), ' ')), '');
          v := case coalesce(t ->> 'part', 'first')
                 when 'first' then trim(parts[1])
                 when 'last' then trim(parts[cardinality(parts)])
                 when 'rest' then nullif(trim(array_to_string(parts[2:], coalesce(nullif(t ->> 'sep', ''), ' '))), '')
                 else trim(parts[(t ->> 'part')::int + 1]) end;
        end if;
      when 'phone_e164' then
        d := regexp_replace(coalesce(v, ''), '\D', '', 'g');
        v := case when d = '' then null
                  when length(d) = 10 then '+91' || d
                  when length(d) = 11 and left(d, 1) = '0' then '+91' || right(d, 10)
                  when length(d) = 12 and left(d, 2) = '91' then '+' || d
                  else '+' || d end;
      when 'date' then
        v := nullif(trim(v), '');
        if v is not null then
          if v ~ '^\d{4}-\d{2}-\d{2}' then v := left(v, 10);
          elsif v ~ '^\d{1,2}[/.-]\d{1,2}[/.-]\d{4}' then
            m := regexp_match(v, '^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})');   -- Indian order: day, month, year
            v := m[3] || '-' || lpad(m[2], 2, '0') || '-' || lpad(m[1], 2, '0');
          else v := to_char(v::date, 'YYYY-MM-DD');
          end if;
          perform v::date;
        end if;
      when 'datetime' then
        v := nullif(trim(v), '');
        if v is not null then
          if v ~ '^\d{1,2}[/.-]\d{1,2}[/.-]\d{4}' then
            m := regexp_match(v, '^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})(.*)$');
            v := m[3] || '-' || lpad(m[2], 2, '0') || '-' || lpad(m[1], 2, '0') || coalesce(m[4], '');
          end if;
          -- no zone given: India time
          if v !~ '(Z|[+-]\d{2}:?\d{2})$' then v := v || '+05:30'; end if;
          v := to_char(v::timestamptz at time zone 'Asia/Kolkata', 'YYYY-MM-DD"T"HH24:MI:SS') || '+05:30';
        end if;
      when 'amount' then
        d := lower(replace(replace(coalesce(v, ''), ',', ''), '₹', ''));
        d := trim(regexp_replace(d, '^(rs\.?|inr)\s*', ''));
        m := regexp_match(d, '^(\d+(?:\.\d+)?)\s*(l|lac|lakh|lakhs|lacs|cr|crore|crores|k|thousand)?\.?$');
        if m is null then v := case when d = '' then null else v end;
          if v is not null then raise exception 'not an amount: %', v using errcode = '22023'; end if;
        else
          n := m[1]::numeric * case when m[2] in ('l', 'lac', 'lakh', 'lakhs', 'lacs') then 100000 when m[2] in ('cr', 'crore', 'crores') then 10000000
                                    when m[2] in ('k', 'thousand') then 1000 else 1 end;
          v := trim_scale(n)::text;
        end if;
      when 'cgpa_to_pct' then
        if nullif(trim(v), '') is not null then
          n := trim(replace(v, '%', ''))::numeric;
          if n <= coalesce((t ->> 'scale')::numeric, 10) then n := round(n * coalesce((t ->> 'factor')::numeric, 9.5), 2); end if;
          v := trim_scale(n)::text;
        end if;
      when 'boolean' then
        v := case when lower(trim(coalesce(v, ''))) in ('yes', 'y', 'true', 't', '1', 'done', 'completed', 'haan', 'ha') then 'true'
                  when lower(trim(coalesce(v, ''))) in ('no', 'n', 'false', 'f', '0', 'not done', 'pending', 'nahi') then 'false' end;
      else raise exception 'unknown transform: %', t ->> 'op' using errcode = '22023';
    end case;
  end loop;
  return v;
end $fn$;

create or replace function b2b.mapping_transform_ops()
returns text[] language sql immutable set search_path = '' as $fn$
  select array['trim', 'lower', 'upper', 'title', 'constant', 'default', 'replace', 'join', 'split', 'phone_e164', 'date', 'datetime', 'amount', 'cgpa_to_pct', 'boolean'];
$fn$;

/* Is this text a valid value of a canonical type? */
create or replace function b2b.mapping_type_ok(p_type text, p_value text)
returns boolean language plpgsql immutable set search_path = '' as $fn$
begin
  if p_value is null then return true; end if;
  case p_type
    when 'number' then perform p_value::numeric;
    when 'date' then perform p_value::date;
    when 'datetime' then perform p_value::timestamptz;
    when 'boolean' then return p_value in ('true', 'false');
    when 'email' then return p_value ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
    when 'phone' then return regexp_replace(p_value, '\D', '', 'g') ~ '^\d{8,15}$';
    else null;
  end case;
  return true;
exception when others then return false;
end $fn$;

/* The allowed values of a picklist (lost reasons live in settings). */
create or replace function b2b.mapping_allowed(c b2b.canonical_fields)
returns text[] language sql stable set search_path = '' as $fn$
  select case when c.key = 'lost_reason' then (select array_agg(x) from jsonb_array_elements_text((select value from b2b.settings where key = 'lost_reasons')) x)
              else c.allowed end;
$fn$;

/* A partner payload through a profile. p_kind: stage | update | activity. */
create or replace function b2b.mapping_in(p_profile_id bigint, p_kind text, p_data jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  pr b2b.mapping_profiles;
  v_fields jsonb;
  v_stage text := nullif(trim(p_data ->> 'stage'), '');
  v_sub text := nullif(trim(p_data ->> 'sub_stage'), '');
  v_pipe text;
  s b2b.status_rules;
  v_status jsonb;
  v_out jsonb := '{}';
  v_custom jsonb := '{}';
  v_unmapped jsonb := '[]';
  v_used text[] := '{}';
  v_activity jsonb;
  f record;
  r record;
  c b2b.canonical_fields;
  v text;
  v_raw text;
  v_mapped text;
  v_hit boolean;
  a b2b.activity_rules;
  v_type text;
  v_outcome text;
begin
  select * into pr from b2b.mapping_profiles where id = p_profile_id;
  if pr.id is null then raise exception 'mapping profile not found' using errcode = 'P0002'; end if;
  v_fields := case when jsonb_typeof(p_data -> 'fields') = 'object' then p_data -> 'fields'
                   else coalesce(p_data, '{}') - array['stage', 'sub_stage', 'type', 'outcome', 'occurred_at', 'activity_type', 'connected', 'reason'] end;
  v_pipe := nullif(trim(coalesce(p_data ->> pr.pipeline_field, v_fields ->> pr.pipeline_field)), '');

  -- 1. stage: the most specific rule wins (pipeline, sub-stage, conditions), then priority
  if v_stage is not null and p_kind = 'stage' then
    for s in
      select * from b2b.status_rules x
       where x.profile_id = pr.id and lower(trim(x.partner_stage)) = lower(v_stage)
         and (x.partner_sub_stage is null or lower(trim(x.partner_sub_stage)) = lower(coalesce(v_sub, '')))
         and (x.pipeline_key is null or x.pipeline_key = v_pipe)
       order by (x.pipeline_key is not null) desc, (x.partner_sub_stage is not null) desc, (jsonb_array_length(x.conditions) > 0) desc, x.priority, x.id
    loop
      v_hit := true;
      for r in select e from jsonb_array_elements(s.conditions) e loop
        v := v_fields ->> (r.e ->> 'field');
        v_hit := v_hit and case r.e ->> 'op'
          when 'eq' then lower(trim(coalesce(v, ''))) = lower(trim(coalesce(r.e ->> 'value', '')))
          when 'neq' then lower(trim(coalesce(v, ''))) <> lower(trim(coalesce(r.e ->> 'value', '')))
          when 'in' then lower(trim(coalesce(v, ''))) in (select lower(trim(y)) from jsonb_array_elements_text(r.e -> 'value') y)
          when 'empty' then nullif(trim(coalesce(v, '')), '') is null
          when 'not_empty' then nullif(trim(coalesce(v, '')), '') is not null
          else false end;
      end loop;
      if v_hit then
        v_status := jsonb_build_object('matched', true, 'rule_id', s.id, 'ignored', s.ignore, 'ignore_reason', s.ignore_reason, 'stage', s.stage,
                                       'sub_stage', s.sub_stage, 'lost_reason', s.lost_reason, 'is_reopen', s.is_reopen);
        exit;
      end if;
    end loop;
    if v_status is null then
      v_status := jsonb_build_object('matched', false);
      v_unmapped := v_unmapped || jsonb_build_object('kind', 'stage', 'item', v_stage || coalesce(' / ' || v_sub, ''));
    end if;
  end if;

  -- 2. fields (inbound rules), values (picklists) and types
  for f in select key, value from jsonb_each(v_fields) where key <> pr.pipeline_field loop
    v_raw := f.value #>> '{}';
    if nullif(trim(coalesce(v_raw, '')), '') is null then continue; end if;
    v_hit := false;
    for r in select x.* from b2b.field_rules x where x.profile_id = pr.id and not x.not_available and x.direction in ('in', 'both')
                and lower(x.partner_field) = lower(f.key) order by x.id loop
      v_hit := true;
      select * into c from b2b.canonical_fields where key = r.canonical_key;
      if not c.inbound then continue; end if;
      begin
        v_mapped := b2b.mapping_transform(v_raw, r.transforms, v_fields);
      exception when others then
        v_unmapped := v_unmapped || jsonb_build_object('kind', 'value', 'item', c.key || ' = ' || left(v_raw, 80), 'value', v_raw, 'error', sqlerrm);
        v_custom := v_custom || jsonb_build_object(f.key, f.value);
        continue;
      end;
      if v_mapped is null then continue; end if;
      if c.data_type = 'picklist' then
        v := v_mapped;
        select x.canonical_value into v_mapped from b2b.value_rules x
         where x.profile_id = pr.id and x.canonical_key = c.key and x.direction in ('in', 'both') and lower(trim(x.partner_value)) = lower(trim(v))
         order by x.id limit 1;
        if v_mapped is null then
          select a1 into v_mapped from unnest(b2b.mapping_allowed(c)) a1 where lower(a1) = lower(trim(v)) limit 1;
        end if;
        if v_mapped is null then
          v_unmapped := v_unmapped || jsonb_build_object('kind', 'value', 'item', c.key || ' = ' || left(v, 80), 'value', v);
          v_custom := v_custom || jsonb_build_object(f.key, f.value);
          continue;
        end if;
      elsif not b2b.mapping_type_ok(c.data_type, v_mapped) then
        v_unmapped := v_unmapped || jsonb_build_object('kind', 'value', 'item', c.key || ' = ' || left(v_mapped, 80), 'value', v_mapped,
                                                       'error', 'not a valid ' || c.data_type);
        v_custom := v_custom || jsonb_build_object(f.key, f.value);
        continue;
      end if;
      v_out := v_out || jsonb_build_object(c.key, v_mapped);
      v_used := v_used || c.key;
    end loop;
    if not v_hit then
      v_custom := v_custom || jsonb_build_object(f.key, f.value);
      v_unmapped := v_unmapped || jsonb_build_object('kind', 'field', 'item', f.key, 'value', left(v_raw, 200));
    end if;
  end loop;

  -- 3. activity
  if p_kind = 'activity' then
    v_type := nullif(trim(coalesce(p_data ->> 'type', p_data ->> 'activity_type')), '');
    v_outcome := nullif(trim(p_data ->> 'outcome'), '');
    if v_type is not null then
      select * into a from b2b.activity_rules x
       where x.profile_id = pr.id and lower(trim(x.partner_type)) = lower(v_type)
         and (x.partner_outcome is null or lower(trim(x.partner_outcome)) = lower(coalesce(v_outcome, '')))
       order by (x.partner_outcome is not null) desc, x.id limit 1;
      if a.id is null then
        v_unmapped := v_unmapped || jsonb_build_object('kind', 'activity', 'item', v_type || coalesce(' / ' || v_outcome, ''));
      else
        v_activity := jsonb_build_object('kind', a.kind, 'outcome', coalesce(a.outcome, v_outcome), 'rule_id', a.id);
      end if;
    end if;
  end if;

  return jsonb_strip_nulls(jsonb_build_object('version', pr.version, 'status', v_status, 'fields', v_out, 'custom', v_custom, 'activity', v_activity,
                                              'pipeline', v_pipe, 'unmapped', v_unmapped));
end $fn$;

/* An allocation's lead as canonical outbound values: the standard push payload plus the other permitted columns. */
create or replace function b2b.lead_canonical(a b2b.allocations)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  p jsonb := b2b.push_payload_base(a);
  l jsonb;
  v jsonb;
begin
  select to_jsonb(x) into l from public.student_leads x where x.id = a.lead_id;
  v := jsonb_build_object(
    'reference', p ->> 'reference', 'full_name', p #>> '{student,name}', 'phone', p #>> '{student,phone}', 'email', p #>> '{student,email}',
    'city', p #>> '{student,city}', 'state', p #>> '{student,state}', 'preferred_language', p #>> '{student,preferred_language}',
    'university', p #>> '{programme,university}', 'course', p #>> '{programme,course}', 'specialization', p #>> '{programme,specialization}',
    'programme_level', p #>> '{programme,level}', 'study_mode', p #>> '{programme,mode}', 'partner_course_code', p #>> '{programme,partner_course_code}',
    'highest_qualification', p #>> '{profile,highest_qualification}', 'academic_score_pct', p #>> '{profile,academic_score_pct}',
    'work_experience_years', p #>> '{profile,work_experience_years}', 'enrollment_timeline', p #>> '{profile,enrollment_timeline}');
  -- the other outbound fields straight from their columns
  select v || coalesce(jsonb_object_agg(c.key, l ->> c.lead_column), '{}') into v
    from b2b.canonical_fields c where c.outbound and c.lead_column is not null and not (v ? c.key);
  return jsonb_strip_nulls(v);
end $fn$;

/* Canonical values → the partner's fields (outbound rules, value maps, transforms). */
create or replace function b2b.mapping_out(p_profile_id bigint, p_canonical jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  r record;
  c b2b.canonical_fields;
  v text;
  v_out jsonb := '{}';
  v_missing text[] := '{}';
  v_unmapped jsonb := '[]';
  v_map text;
begin
  for r in select x.* from b2b.field_rules x where x.profile_id = p_profile_id and not x.not_available and x.direction in ('out', 'both') order by x.id loop
    select * into c from b2b.canonical_fields where key = r.canonical_key;
    if not c.outbound then continue; end if;
    v := p_canonical ->> c.key;
    if v is not null and c.data_type = 'picklist' then
      select x.partner_value into v_map from b2b.value_rules x
       where x.profile_id = p_profile_id and x.canonical_key = c.key and x.direction in ('out', 'both') and lower(trim(x.canonical_value)) = lower(trim(v))
       order by x.id limit 1;
      if v_map is null then v_unmapped := v_unmapped || jsonb_build_object('kind', 'value', 'item', c.key || ' = ' || v); else v := v_map; end if;
      v_map := null;
    end if;
    begin
      v := b2b.mapping_transform(v, r.out_transforms, p_canonical);
    exception when others then
      v_unmapped := v_unmapped || jsonb_build_object('kind', 'value', 'item', c.key || ' = ' || coalesce(v, ''), 'error', sqlerrm);
      v := null;
    end;
    if v is null and (r.required or c.required_out) then v_missing := v_missing || c.key; end if;
    if v is not null then v_out := v_out || jsonb_build_object(r.partner_field, v); end if;
  end loop;
  return jsonb_build_object('fields', v_out, 'missing_required', to_jsonb(v_missing), 'unmapped', v_unmapped);
end $fn$;

/* Coverage gates (B8.3.4). Each item: {group, item, required, done, detail}. */
create or replace function b2b.mapping_coverage(p_profile_id bigint)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  pr b2b.mapping_profiles;
  p b2b.partners;
  snap jsonb;
  v_items jsonb := '[]';
  v_standard boolean;
  r record;
  m jsonb;
begin
  select * into pr from b2b.mapping_profiles where id = p_profile_id;
  select * into p from b2b.partners where id = pr.partner_id;
  select schema into snap from b2b.partner_schema_snapshots where partner_id = p.id order by id desc limit 1;
  v_standard := p.adapter_type in ('generic_rest', 'webhook');

  -- stages and sub-stages: from the latest schema snapshot and every stage event received
  for r in
    with seen as (
      select nullif(trim(s ->> 'stage'), '') st, null::text sub from jsonb_array_elements(coalesce(snap -> 'stages', '[]')) s
      union select nullif(trim(s ->> 'stage'), ''), nullif(trim(x), '') from jsonb_array_elements(coalesce(snap -> 'stages', '[]')) s
                   cross join lateral jsonb_array_elements_text(coalesce(s -> 'sub_stages', '[]')) x
      union select nullif(trim(e.raw -> 'data' ->> 'stage'), ''), nullif(trim(e.raw -> 'data' ->> 'sub_stage'), '')
              from b2b.partner_events e where e.partner_id = p.id and e.event_type = 'stage')
    select distinct st, sub from seen where st is not null order by 1, 2 nulls first
  loop
    m := b2b.mapping_in(pr.id, 'stage', jsonb_build_object('stage', r.st, 'sub_stage', r.sub));
    v_items := v_items || jsonb_build_object('group', 'stage', 'item', r.st || coalesce(' / ' || r.sub, ''), 'required', true,
      'done', coalesce((m -> 'status' ->> 'matched')::boolean, false),
      'detail', case when (m -> 'status' ->> 'ignored')::boolean then 'ignored: ' || (m -> 'status' ->> 'ignore_reason')
                     else concat_ws(' / ', m -> 'status' ->> 'stage', m -> 'status' ->> 'sub_stage') end);
  end loop;

  -- required outbound fields (a standard-payload partner receives them in the Eduwit format)
  for r in select c.* from b2b.canonical_fields c where c.required_out order by c.sort loop
    v_items := v_items || jsonb_build_object('group', 'out', 'item', r.label, 'key', r.key, 'required', true,
      'done', v_standard or exists (select 1 from b2b.field_rules x where x.profile_id = pr.id and not x.not_available and x.direction in ('out', 'both')
                                     and (x.canonical_key = r.key or (r.key = 'course' and x.canonical_key = 'partner_course_code'))),
      'detail', case when v_standard then 'standard Eduwit payload' end);
  end loop;
  for r in select x.* from b2b.field_rules x where x.profile_id = pr.id and x.required and x.direction in ('out', 'both') loop
    v_items := v_items || jsonb_build_object('group', 'out', 'item', r.partner_field || ' (required by the partner)', 'key', r.canonical_key, 'required', true,
      'done', true, 'detail', 'from ' || r.canonical_key);
  end loop;

  -- required inbound sales fields: mapped, or marked as not available at this partner
  for r in select c.* from b2b.canonical_fields c where c.required_in order by c.sort loop
    v_items := v_items || jsonb_build_object('group', 'in', 'item', r.label, 'key', r.key, 'required', true,
      'done', exists (select 1 from b2b.field_rules x where x.profile_id = pr.id and x.canonical_key = r.key and (x.not_available or x.direction in ('in', 'both')))
              or (r.key = 'lost_reason' and exists (select 1 from b2b.status_rules s where s.profile_id = pr.id and s.lost_reason is not null)),
      'detail', (select case when x.not_available then 'not available at this partner' else 'from ' || x.partner_field end
                   from b2b.field_rules x where x.profile_id = pr.id and x.canonical_key = r.key order by x.not_available, x.id limit 1));
  end loop;

  -- picklist values seen on test leads: mapped inbound (and outbound for two-way fields)
  for r in
    select distinct x.id rule_id, x.canonical_key, x.direction, x.partner_field, f.value #>> '{}' val
      from b2b.partner_events e join b2b.allocations al on al.id = e.allocation_id and al.is_test
      cross join lateral jsonb_each(case when jsonb_typeof(e.raw -> 'data' -> 'fields') = 'object' then e.raw -> 'data' -> 'fields' else coalesce(e.raw -> 'data', '{}') end) f
      join b2b.field_rules x on x.profile_id = pr.id and lower(x.partner_field) = lower(f.key) and x.direction in ('in', 'both') and not x.not_available
      join b2b.canonical_fields c on c.key = x.canonical_key and c.data_type = 'picklist'
     where e.partner_id = p.id and nullif(trim(f.value #>> '{}'), '') is not null
  loop
    m := b2b.mapping_in(pr.id, 'update', jsonb_build_object('fields', jsonb_build_object(r.partner_field, r.val)));
    v_items := v_items || jsonb_build_object('group', 'values', 'item', r.canonical_key || ' = ' || r.val, 'required', true,
      'done', (m -> 'fields') ? r.canonical_key
              and (r.direction = 'in' or exists (select 1 from b2b.value_rules v where v.profile_id = pr.id and v.canonical_key = r.canonical_key
                                                   and v.direction = 'both' and lower(trim(v.partner_value)) = lower(trim(r.val)))
                   or lower(trim(r.val)) = lower(m -> 'fields' ->> r.canonical_key)),
      'detail', m -> 'fields' ->> r.canonical_key);
  end loop;

  -- informational: partner fields in the schema snapshot that are mapped or knowingly kept as custom
  for r in select distinct f ->> 'name' nm from jsonb_array_elements(coalesce(snap -> 'fields', '[]')) f where nullif(f ->> 'name', '') is not null loop
    v_items := v_items || jsonb_build_object('group', 'fields', 'item', r.nm, 'required', false,
      'done', exists (select 1 from b2b.field_rules x where x.profile_id = pr.id and lower(x.partner_field) = lower(r.nm))
              or exists (select 1 from b2b.mapping_queue q where q.partner_id = p.id and q.kind = 'field' and lower(q.item) = lower(r.nm) and q.status = 'ignored'));
  end loop;

  return jsonb_build_object(
    'items', v_items,
    'required_total', (select count(*) from jsonb_array_elements(v_items) i where (i ->> 'required')::boolean),
    'required_done', (select count(*) from jsonb_array_elements(v_items) i where (i ->> 'required')::boolean and (i ->> 'done')::boolean),
    'total', jsonb_array_length(v_items),
    'done', (select count(*) from jsonb_array_elements(v_items) i where (i ->> 'done')::boolean),
    'stages_seen', (select count(*) from jsonb_array_elements(v_items) i where i ->> 'group' = 'stage'));
end $fn$;

/* Golden files against a profile: the mapping result must contain each expected value. */
create or replace function b2b.mapping_golden_run(p_profile_id bigint)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  pr b2b.mapping_profiles;
  g b2b.mapping_goldens;
  m jsonb;
  v_rows jsonb := '[]';
begin
  select * into pr from b2b.mapping_profiles where id = p_profile_id;
  for g in select * from b2b.mapping_goldens where partner_id = pr.partner_id and archived_at is null order by name loop
    begin
      m := b2b.mapping_in(pr.id, coalesce(g.input ->> 'kind', 'stage'), coalesce(g.input -> 'data', '{}'));
      v_rows := v_rows || jsonb_build_object('id', g.id, 'name', g.name, 'pass', (m - 'unmapped' - 'version') @> g.expected, 'actual', m - 'version');
    exception when others then
      v_rows := v_rows || jsonb_build_object('id', g.id, 'name', g.name, 'pass', false, 'error', sqlerrm);
    end;
  end loop;
  return v_rows;
end $fn$;

/* Round trip (B8.3.7): Eduwit → partner → Eduwit returns the same value for every two-way field. */
create or replace function b2b.mapping_roundtrip(p_profile_id bigint, p_canonical jsonb)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  o jsonb := b2b.mapping_out(p_profile_id, p_canonical);
  i jsonb := b2b.mapping_in(p_profile_id, 'update', jsonb_build_object('fields', o -> 'fields'));
  r record;
  v_rows jsonb := '[]';
begin
  for r in select distinct x.canonical_key k from b2b.field_rules x join b2b.canonical_fields c on c.key = x.canonical_key and c.outbound and c.inbound
            where x.profile_id = p_profile_id and x.direction = 'both' and not x.not_available and p_canonical ? x.canonical_key loop
    v_rows := v_rows || jsonb_build_object('key', r.k, 'sent', p_canonical ->> r.k, 'back', i -> 'fields' ->> r.k,
                                           'pass', lower(coalesce(p_canonical ->> r.k, '')) = lower(coalesce(i -> 'fields' ->> r.k, '')));
  end loop;
  return jsonb_build_object('out', o, 'in', i, 'checks', v_rows);
end $fn$;

revoke execute on function b2b.mapping_transform(text, jsonb, jsonb), b2b.mapping_transform_ops(), b2b.mapping_type_ok(text, text),
                           b2b.mapping_allowed(b2b.canonical_fields), b2b.mapping_in(bigint, text, jsonb), b2b.lead_canonical(b2b.allocations),
                           b2b.mapping_out(bigint, jsonb), b2b.mapping_coverage(bigint), b2b.mapping_golden_run(bigint), b2b.mapping_roundtrip(bigint, jsonb)
  from public, anon, authenticated;
grant execute on function b2b.mapping_transform(text, jsonb, jsonb), b2b.mapping_transform_ops(), b2b.mapping_type_ok(text, text),
                          b2b.mapping_allowed(b2b.canonical_fields), b2b.mapping_in(bigint, text, jsonb), b2b.lead_canonical(b2b.allocations),
                          b2b.mapping_out(bigint, jsonb), b2b.mapping_coverage(bigint), b2b.mapping_golden_run(bigint), b2b.mapping_roundtrip(bigint, jsonb)
  to service_role;
