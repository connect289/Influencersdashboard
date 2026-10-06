-- M15e: the Mapping studio's reads and tools (spec B8.3.3, B8.3.5): the test panel (a payload in, a lead out and
-- back), discovery from raw events, schema snapshots with drift detection, the mapping queue, golden files, the stage
-- backfill after a correction, and the overview and studio reads. Split from m15d to keep each migration small.

/* The test panel: a partner payload through a profile, or a lead out to the partner and back. */
create or replace function b2b.mapping_test(p_profile_id bigint, p_kind text, p_data jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_kind not in ('stage', 'update', 'activity') then raise exception 'kind must be stage, update or activity' using errcode = '22023'; end if;
  if jsonb_typeof(p_data) <> 'object' then raise exception 'the sample must be a JSON object' using errcode = '22023'; end if;
  return b2b.mapping_in(p_profile_id, p_kind, p_data);
end $fn$;

create or replace function b2b.mapping_test_out(p_profile_id bigint, p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare pr b2b.mapping_profiles; a b2b.allocations; v jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into pr from b2b.mapping_profiles where id = p_profile_id;
  if pr.id is null then raise exception 'mapping version not found' using errcode = 'P0002'; end if;
  select * into a from b2b.allocations where lead_id = p_lead_id and partner_id = pr.partner_id order by id desc limit 1;
  if a.id is null then
    if not exists (select 1 from public.student_leads where id = p_lead_id) then raise exception 'lead not found' using errcode = 'P0002'; end if;
    a.lead_id := p_lead_id; a.partner_id := pr.partner_id; a.reference := 'EDW-PREVIEW'; a.is_test := true;
  end if;
  v := b2b.lead_canonical(a);
  return jsonb_build_object('canonical', v, 'roundtrip', b2b.mapping_roundtrip(pr.id, v));
end $fn$;

/* A partner schema built from its raw events: stages with sub-stages, fields with sample values, activities, pipelines. */
create or replace function b2b.mapping_discover(p_partner_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_pf text;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select coalesce((select pipeline_field from b2b.mapping_profiles where partner_id = p_partner_id and status in ('draft', 'active') order by status = 'draft' desc limit 1), 'pipeline')
    into v_pf;
  return jsonb_build_object(
    'stages', coalesce((select jsonb_agg(jsonb_build_object('stage', st, 'sub_stages', subs, 'count', n) order by n desc)
                          from (select e.raw -> 'data' ->> 'stage' st, count(*) n,
                                       coalesce(jsonb_agg(distinct e.raw -> 'data' ->> 'sub_stage') filter (where nullif(e.raw -> 'data' ->> 'sub_stage', '') is not null), '[]') subs
                                  from b2b.partner_events e where e.partner_id = p_partner_id and e.event_type = 'stage' and nullif(e.raw -> 'data' ->> 'stage', '') is not null
                                 group by 1) s), '[]'),
    'fields', coalesce((select jsonb_agg(jsonb_build_object('name', k, 'count', n, 'values', vals) order by n desc)
                          from (select f.key k, count(*) n, (array_agg(distinct left(f.value #>> '{}', 80)))[1:20] vals
                                  from b2b.partner_events e
                                  cross join lateral jsonb_each(case when jsonb_typeof(e.raw -> 'data' -> 'fields') = 'object' then e.raw -> 'data' -> 'fields'
                                                                     else coalesce(e.raw -> 'data', '{}') - array['stage', 'sub_stage', 'type', 'outcome', 'occurred_at', 'connected', 'reason'] end) f
                                 where e.partner_id = p_partner_id and e.event_type in ('stage', 'update', 'activity') and f.key <> v_pf
                                 group by 1) x), '[]'),
    'activities', coalesce((select jsonb_agg(jsonb_build_object('type', t, 'outcomes', outs, 'count', n) order by n desc)
                              from (select e.raw -> 'data' ->> 'type' t, count(*) n,
                                           coalesce(jsonb_agg(distinct e.raw -> 'data' ->> 'outcome') filter (where nullif(e.raw -> 'data' ->> 'outcome', '') is not null), '[]') outs
                                      from b2b.partner_events e where e.partner_id = p_partner_id and e.event_type = 'activity' and nullif(e.raw -> 'data' ->> 'type', '') is not null
                                     group by 1) a), '[]'),
    'pipelines', coalesce((select jsonb_agg(distinct coalesce(e.raw -> 'data' ->> v_pf, e.raw -> 'data' -> 'fields' ->> v_pf))
                             from b2b.partner_events e where e.partner_id = p_partner_id
                              and coalesce(e.raw -> 'data' ->> v_pf, e.raw -> 'data' -> 'fields' ->> v_pf) is not null), '[]'));
end $fn$;

/* Saves a schema snapshot and compares it with the previous one (drift: stages, fields, values, types). */
create or replace function b2b.mapping_snapshot_save(p_partner_id bigint, p_source text, p_schema jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  prev jsonb;
  v_drift jsonb := '[]';
  v_id bigint;
  act bigint;
  r record;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_source not in ('upload', 'api', 'events') then raise exception 'unknown source' using errcode = '22023'; end if;
  if jsonb_typeof(p_schema) <> 'object' or jsonb_typeof(coalesce(p_schema -> 'fields', '[]')) <> 'array' or jsonb_typeof(coalesce(p_schema -> 'stages', '[]')) <> 'array' then
    raise exception 'the schema needs fields and stages lists' using errcode = '22023';
  end if;
  if length(p_schema::text) > 500000 then raise exception 'the schema is too large' using errcode = '22023'; end if;
  if not exists (select 1 from b2b.partners where id = p_partner_id) then raise exception 'partner not found' using errcode = 'P0002'; end if;
  select schema into prev from b2b.partner_schema_snapshots where partner_id = p_partner_id order by id desc limit 1;
  select id into act from b2b.mapping_profiles where partner_id = p_partner_id and status = 'active';

  if prev is not null then
    for r in
      with ps as (select lower(trim(s ->> 'stage')) k, s ->> 'stage' st from jsonb_array_elements(coalesce(prev -> 'stages', '[]')) s),
           ns as (select lower(trim(s ->> 'stage')) k, s ->> 'stage' st from jsonb_array_elements(coalesce(p_schema -> 'stages', '[]')) s),
           pf as (select lower(trim(f ->> 'name')) k, f ->> 'name' nm, f ->> 'type' tp, f -> 'values' vals from jsonb_array_elements(coalesce(prev -> 'fields', '[]')) f),
           nf as (select lower(trim(f ->> 'name')) k, f ->> 'name' nm, f ->> 'type' tp, f -> 'values' vals from jsonb_array_elements(coalesce(p_schema -> 'fields', '[]')) f)
      select 'new_stage' what, ns.st item, null::text detail from ns where not exists (select 1 from ps where ps.k = ns.k)
      union all select 'removed_stage', ps.st, null from ps where not exists (select 1 from ns where ns.k = ps.k)
      union all select 'new_field', nf.nm, null from nf where not exists (select 1 from pf where pf.k = nf.k)
      union all select 'removed_field', pf.nm, null from pf where not exists (select 1 from nf where nf.k = pf.k)
      union all select 'type_changed', nf.nm, pf.tp || ' → ' || nf.tp from nf join pf on pf.k = nf.k where coalesce(pf.tp, '') <> coalesce(nf.tp, '') and pf.tp is not null
      union all select 'removed_value', nf.nm, v from nf join pf on pf.k = nf.k cross join lateral jsonb_array_elements_text(coalesce(pf.vals, '[]')) v
                 where jsonb_typeof(nf.vals) = 'array' and not exists (select 1 from jsonb_array_elements_text(nf.vals) w where lower(w) = lower(v))
    loop
      v_drift := v_drift || jsonb_build_object('what', r.what, 'item', r.item, 'detail', r.detail,
        'required', act is not null and r.what in ('removed_field', 'type_changed', 'removed_value')
                    and exists (select 1 from b2b.field_rules x join b2b.canonical_fields c on c.key = x.canonical_key
                                 where x.profile_id = act and lower(x.partner_field) = lower(r.item) and (x.required or c.required_out or c.required_in)));
    end loop;
  end if;

  insert into b2b.partner_schema_snapshots (partner_id, source, schema, drift, created_by)
  values (p_partner_id, p_source, p_schema, case when prev is null then null else v_drift end, b2b.actor() ->> 'id') returning id into v_id;
  if jsonb_array_length(v_drift) > 0 then
    perform b2b.mapping_queue_add(p_partner_id,
      (select jsonb_agg(jsonb_build_object('kind', 'drift', 'item', (d ->> 'what') || ': ' || (d ->> 'item') || coalesce(' (' || (d ->> 'detail') || ')', ''),
                                           'required', d -> 'required')) from jsonb_array_elements(v_drift) d), null);
    perform b2b.log_event('alert.mapping_drift', null, null, p_partner_id, jsonb_build_object('snapshot_id', v_id, 'changes', jsonb_array_length(v_drift),
      'required', exists (select 1 from jsonb_array_elements(v_drift) d where (d ->> 'required')::boolean)));
  end if;
  return jsonb_build_object('id', v_id, 'drift', v_drift);
end $fn$;

create or replace function b2b.mapping_queue_resolve(p_id bigint, p_status text, p_note text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status not in ('ignored', 'open') then raise exception 'status must be ignored or open' using errcode = '22023'; end if;
  if p_status = 'ignored' and length(trim(coalesce(p_note, ''))) < 3 then raise exception 'say why (for example: kept as a custom field)' using errcode = '22023'; end if;
  update b2b.mapping_queue set status = p_status, resolution = case when p_status = 'ignored' then left(trim(p_note), 300) end,
         resolved_at = case when p_status = 'ignored' then now() end
   where id = p_id;
  if not found then raise exception 'queue item not found' using errcode = 'P0002'; end if;
end $fn$;

create or replace function b2b.mapping_golden_save(p_partner_id bigint, p_name text, p_input jsonb, p_expected jsonb)
returns bigint language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_name, ''))) not between 2 and 80 then raise exception 'name the golden file (2 to 80 characters)' using errcode = '22023'; end if;
  if jsonb_typeof(p_input) <> 'object' or coalesce(p_input ->> 'kind', '') not in ('stage', 'update', 'activity') or jsonb_typeof(p_input -> 'data') <> 'object' then
    raise exception 'the input needs kind (stage, update or activity) and a data object' using errcode = '22023';
  end if;
  if jsonb_typeof(p_expected) <> 'object' or p_expected = '{}' then raise exception 'say what the result must contain' using errcode = '22023'; end if;
  insert into b2b.mapping_goldens (partner_id, name, input, expected) values (p_partner_id, trim(p_name), p_input, p_expected)
  on conflict (partner_id, name) do update set input = excluded.input, expected = excluded.expected, archived_at = null
  returning id into v_id;
  return v_id;
end $fn$;

create or replace function b2b.mapping_golden_archive(p_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.mapping_goldens set archived_at = now() where id = p_id and archived_at is null;
  if not found then raise exception 'golden file not found' using errcode = 'P0002'; end if;
end $fn$;

/* Leads the partner holds whose Eduwit stage would change under the active version (from their stored partner stage). */
create or replace function b2b.mapping_backfill_rows(p_partner_id bigint)
returns table (lead_id bigint, allocation_id bigint, current_stage text, new_stage text, new_sub_stage text, partner_stage text, partner_sub_stage text)
language plpgsql stable security definer set search_path = '' as $fn$
declare pr b2b.mapping_profiles;
begin
  select * into pr from b2b.mapping_profiles where partner_id = p_partner_id and status = 'active';
  if pr.id is null then return; end if;
  return query
    select l.id, a.id, l.stage, m -> 'status' ->> 'stage', m -> 'status' ->> 'sub_stage', l.partner_stage_raw, l.partner_sub_stage_raw
      from b2b.allocations a join public.student_leads l on l.allocation_id = a.id
      cross join lateral b2b.mapping_in(pr.id, 'stage', jsonb_build_object('stage', l.partner_stage_raw, 'sub_stage', l.partner_sub_stage_raw)) m
     where a.partner_id = p_partner_id and a.status in ('pushed', 'accepted') and l.partner_stage_raw is not null
       and (m -> 'status' ->> 'matched')::boolean and not coalesce((m -> 'status' ->> 'ignored')::boolean, false)
       and m -> 'status' ->> 'stage' not in ('lost', 'duplicate_at_partner')
       and (l.stage is distinct from m -> 'status' ->> 'stage' or l.sub_stage is distinct from m -> 'status' ->> 'sub_stage');
end $fn$;

create or replace function b2b.mapping_backfill_preview(p_partner_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object('count', (select count(*) from b2b.mapping_backfill_rows(p_partner_id)),
    'by_change', coalesce((select jsonb_agg(jsonb_build_object('from', f, 'to', t, 'n', n) order by n desc)
                             from (select coalesce(current_stage, '—') f, new_stage t, count(*) n from b2b.mapping_backfill_rows(p_partner_id) group by 1, 2) x), '[]'),
    'sample', coalesce((select jsonb_agg(to_jsonb(r)) from (select * from b2b.mapping_backfill_rows(p_partner_id) limit 20) r), '[]'));
end $fn$;

/* Applies the active version to the stored partner stage of every lead the partner holds. A correction may move a
   stage back (it is logged as such); lost and duplicate are left to their events. */
create or replace function b2b.mapping_backfill(p_partner_id bigint, p_reason text)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare r record; n int := 0;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'a reason is required' using errcode = '22023'; end if;
  for r in select * from b2b.mapping_backfill_rows(p_partner_id) loop
    update public.student_leads set stage = r.new_stage, sub_stage = r.new_sub_stage,
           stage_changed_at = case when stage is distinct from r.new_stage then now() else stage_changed_at end, updated_by = 'b2b'
     where id = r.lead_id and allocation_id = r.allocation_id;
    perform b2b.log_event('partner.stage_applied', r.lead_id, r.allocation_id, p_partner_id,
      jsonb_build_object('stage', r.new_stage, 'sub_stage', r.new_sub_stage, 'from', r.current_stage, 'partner_stage', r.partner_stage,
                         'partner_sub_stage', r.partner_sub_stage, 'backfill', true, 'reason', left(trim(p_reason), 300)));
    n := n + 1;
  end loop;
  perform b2b.log_event('mapping.backfill', null, null, p_partner_id, jsonb_build_object('leads', n, 'reason', left(trim(p_reason), 300)));
  return n;
end $fn$;

/* The Mapping studio's list: every partner with its versions, coverage and queue. */
create or replace function b2b.mapping_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(x.r order by x.r ->> 'name') from (
    select jsonb_build_object('id', p.id, 'name', p.name, 'slug', p.slug, 'adapter_type', p.adapter_type, 'status', p.status,
      'active_version', act.version, 'active_at', act.activated_at, 'has_draft', exists (select 1 from b2b.mapping_profiles d where d.partner_id = p.id and d.status = 'draft'),
      'coverage', case when act.id is not null then (select jsonb_build_object('required_done', c -> 'required_done', 'required_total', c -> 'required_total',
                                                                              'done', c -> 'done', 'total', c -> 'total') from (select b2b.mapping_coverage(act.id) c) z) end,
      'ready', b2b.mapping_ready(p.id),
      'queue_open', (select count(*) from b2b.mapping_queue q where q.partner_id = p.id and q.status = 'open'),
      'held_events', (select count(*) from b2b.partner_events e where e.partner_id = p.id and e.status = 'held_unmapped'),
      'last_snapshot_at', (select max(s.created_at) from b2b.partner_schema_snapshots s where s.partner_id = p.id)) r
      from b2b.partners p left join b2b.mapping_profiles act on act.partner_id = p.id and act.status = 'active'
     where p.status <> 'closed') x), '[]');
end $fn$;

/* Everything the studio shows for one partner. The editable profile is the draft; without one, the active version (read-only). */
create or replace function b2b.mapping_studio(p_partner_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  p b2b.partners;
  ed b2b.mapping_profiles;
  snap b2b.partner_schema_snapshots;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into p from b2b.partners where id = p_partner_id;
  if p.id is null then return null; end if;
  select * into ed from b2b.mapping_profiles where partner_id = p.id and status in ('draft', 'active') order by status = 'draft' desc limit 1;
  select * into snap from b2b.partner_schema_snapshots where partner_id = p.id order by id desc limit 1;
  return jsonb_build_object(
    'partner', jsonb_build_object('id', p.id, 'name', p.name, 'slug', p.slug, 'adapter_type', p.adapter_type, 'status', p.status),
    'profiles', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'version', x.version, 'status', x.status, 'note', x.note, 'created_at', x.created_at,
                            'activated_at', x.activated_at, 'activated_by', x.activated_by, 'based_on', x.based_on,
                            'rules', (select count(*) from b2b.status_rules s where s.profile_id = x.id) + (select count(*) from b2b.field_rules s where s.profile_id = x.id)
                                     + (select count(*) from b2b.value_rules s where s.profile_id = x.id) + (select count(*) from b2b.activity_rules s where s.profile_id = x.id))
                            order by x.status = 'draft' desc, x.version desc nulls first) from b2b.mapping_profiles x
                            where x.partner_id = p.id and (x.status <> 'retired' or x.version is not null)), '[]'),
    'editing', case when ed.id is null then null else jsonb_build_object(
      'id', ed.id, 'status', ed.status, 'version', ed.version, 'pipeline_field', ed.pipeline_field,
      'pipelines', coalesce((select jsonb_agg(to_jsonb(x) order by x.key) from b2b.mapping_pipelines x where x.profile_id = ed.id), '[]'),
      'status_rules', coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.partner_stage), x.partner_sub_stage nulls first, x.priority, x.id)
                                  from b2b.status_rules x where x.profile_id = ed.id), '[]'),
      'field_rules', coalesce((select jsonb_agg(to_jsonb(x) order by c.sort, x.id) from b2b.field_rules x join b2b.canonical_fields c on c.key = x.canonical_key
                                 where x.profile_id = ed.id), '[]'),
      'value_rules', coalesce((select jsonb_agg(to_jsonb(x) order by x.canonical_key, lower(x.partner_value)) from b2b.value_rules x where x.profile_id = ed.id), '[]'),
      'activity_rules', coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.partner_type), x.partner_outcome nulls first) from b2b.activity_rules x where x.profile_id = ed.id), '[]'),
      'coverage', b2b.mapping_coverage(ed.id),
      'goldens', b2b.mapping_golden_run(ed.id)) end,
    'canonical', (select jsonb_agg(to_jsonb(c) || jsonb_build_object('allowed', b2b.mapping_allowed(c)) order by c.sort) from b2b.canonical_fields c),
    'target_stages', to_jsonb(b2b.mapping_target_stages()),
    'sub_stages', (select value from b2b.settings where key = 'sub_stages'),
    'lost_reasons', (select value from b2b.settings where key = 'lost_reasons'),
    'transform_ops', to_jsonb(b2b.mapping_transform_ops()),
    'snapshot', case when snap.id is null then null else jsonb_build_object('id', snap.id, 'source', snap.source, 'created_at', snap.created_at, 'schema', snap.schema,
                                                                               'drift', snap.drift) end,
    'discovered', b2b.mapping_discover(p.id),
    'queue', coalesce((select jsonb_agg(to_jsonb(q) - 'lead_ids' || jsonb_build_object('leads', cardinality(q.lead_ids), 'lead_sample', to_jsonb(q.lead_ids[1:5]))
                                        order by q.status = 'open' desc, q.last_seen desc)
                         from (select * from b2b.mapping_queue where partner_id = p.id order by status = 'open' desc, last_seen desc limit 200) q), '[]'),
    'goldens', coalesce((select jsonb_agg(to_jsonb(g) order by g.name) from b2b.mapping_goldens g where g.partner_id = p.id and g.archived_at is null), '[]'),
    'samples', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'type', e.event_type, 'received_at', e.received_at, 'status', e.status, 'data', e.raw -> 'data')
                                          order by e.id desc)
                           from (select * from b2b.partner_events where partner_id = p.id and event_type in ('stage', 'update', 'activity') order by id desc limit 20) e), '[]'),
    'held_events', (select count(*) from b2b.partner_events e where e.partner_id = p.id and e.status = 'held_unmapped'),
    -- suggestions learned from other partners on the same CRM (their active versions)
    'learned', coalesce((select jsonb_agg(jsonb_build_object('partner_field', f, 'canonical_key', k, 'partners', n) order by n desc)
                           from (select x.partner_field f, x.canonical_key k, count(distinct pr.partner_id) n
                                   from b2b.field_rules x join b2b.mapping_profiles pr on pr.id = x.profile_id and pr.status = 'active'
                                   join b2b.partners op on op.id = pr.partner_id and op.adapter_type = p.adapter_type and op.id <> p.id
                                  where x.partner_field is not null group by 1, 2) z), '[]'),
    'backfill', case when exists (select 1 from b2b.mapping_profiles where partner_id = p.id and status = 'active') then b2b.mapping_backfill_preview(p.id) end);
end $fn$;

revoke execute on function b2b.mapping_backfill_rows(bigint)
  from public, anon, authenticated;
grant execute on function b2b.mapping_backfill_rows(bigint)
  to service_role;
revoke execute on function b2b.mapping_test(bigint, text, jsonb), b2b.mapping_test_out(bigint, bigint), b2b.mapping_discover(bigint), b2b.mapping_snapshot_save(bigint, text, jsonb), b2b.mapping_queue_resolve(bigint, text, text), b2b.mapping_golden_save(bigint, text, jsonb, jsonb), b2b.mapping_golden_archive(bigint), b2b.mapping_backfill_preview(bigint), b2b.mapping_backfill(bigint, text), b2b.mapping_overview(), b2b.mapping_studio(bigint)
  from public, anon;
grant execute on function b2b.mapping_test(bigint, text, jsonb), b2b.mapping_test_out(bigint, bigint), b2b.mapping_discover(bigint), b2b.mapping_snapshot_save(bigint, text, jsonb), b2b.mapping_queue_resolve(bigint, text, text), b2b.mapping_golden_save(bigint, text, jsonb, jsonb), b2b.mapping_golden_archive(bigint), b2b.mapping_backfill_preview(bigint), b2b.mapping_backfill(bigint, text), b2b.mapping_overview(), b2b.mapping_studio(bigint)
  to authenticated, service_role;
