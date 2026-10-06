-- M15c: the mapping layer at runtime (spec B8.3.5).
-- Partner events now go through the partner's active mapping profile:
--   stage     → the status rules move the lead's Eduwit stage (never backwards unless the rule is a reopen),
--               'lost' hands the lead to B2C nurture, 'duplicate_at_partner' is a duplicate claim
--   update    → field rules write the sales columns B2B owns while the partner holds the lead
--   activity  → activity rules; calls roll up as contact attempts
-- Raw first: the event is stored before anything is applied. A stage, activity or picklist value the profile does not
-- know is stored, never moves the lead, enters the mapping queue, and the event waits (held_unmapped) until a new
-- profile version is published, when held events are re-applied in order. Partner fields nobody mapped are kept on the
-- allocation (partner_custom). Witty-owned fields are only filled when empty and the rule marks the partner as trusted.
-- Outbound: pushes carry the mapped `fields` and the `mapping_version` that produced them; each push request records it.

-- ---------- outbound ----------
/* The standard payload (unchanged from m8b, renamed so mapping can extend it). */
create or replace function b2b.push_payload_base(a b2b.allocations)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  l public.student_leads;
  c record;
  v_prev text;
begin
  select * into l from public.student_leads where id = a.lead_id;
  select u.name as university, cp.course, cp.specialization, cp.level, cp.mode, o.partner_course_code
    into c from public.catalog_programs cp
    left join public.catalog_universities u on u.id = cp.university_id
    left join b2b.partner_programmes o on o.partner_id = a.partner_id and o.programme_id = cp.id and o.valid_to is null
   where cp.id = a.programme_id;
  select p.reference into v_prev from b2b.allocations p
   where p.lead_id = a.lead_id and p.partner_id = a.partner_id and p.id <> a.id and p.status in ('accepted', 'closed') order by p.created_at desc limit 1;
  return jsonb_strip_nulls(jsonb_build_object(
    'reference', a.reference,
    'test', a.is_test,
    'student', jsonb_build_object(
      'name', nullif(trim(l.student_name), ''), 'phone', '+' || regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'),
      'email', nullif(trim(l.email_id), ''), 'city', coalesce(nullif(l.city, ''), nullif(l.current_city_country, '')), 'state', nullif(l.state, ''),
      'preferred_language', nullif(l.preferred_language, '')),
    'programme', jsonb_build_object(
      'university', c.university, 'course', coalesce(c.course, nullif(l.interested_course, '')),
      'specialization', coalesce(c.specialization, nullif(l.interested_specialization, '')),
      'level', coalesce(c.level, nullif(l.program_level, '')), 'mode', coalesce(c.mode, nullif(l.study_mode_preference, '')),
      'partner_course_code', c.partner_course_code),
    'profile', jsonb_build_object(
      'highest_qualification', nullif(l.highest_qualification, ''), 'academic_score_pct', l.academic_score_pct,
      'work_experience_years', l.work_experience_years_num, 'enrollment_timeline', nullif(l.enrollment_timeline, '')),
    'note', left(concat_ws('. ',
              'Interested in ' || coalesce(c.course, l.interested_course) || coalesce(' (' || coalesce(c.specialization, l.interested_specialization) || ')', ''),
              case when coalesce(c.mode, l.study_mode_preference) is not null then 'Mode: ' || coalesce(c.mode, l.study_mode_preference) end,
              case when nullif(l.enrollment_timeline, '') is not null then 'Wants to start: ' || l.enrollment_timeline end), 300),
    'returning_lead', v_prev is not null,
    'previous_reference', v_prev,
    'sent_at', now()));
end $fn$;

/* The partner's active profile, if it has outbound rules. */
create or replace function b2b.mapping_active_out(p_partner_id bigint)
returns b2b.mapping_profiles language sql stable set search_path = '' as $fn$
  select pr.* from b2b.mapping_profiles pr
   where pr.partner_id = p_partner_id and pr.status = 'active'
     and exists (select 1 from b2b.field_rules x where x.profile_id = pr.id and not x.not_available and x.direction in ('out', 'both'));
$fn$;

/* What a partner receives: the standard payload, plus its own field names when its mapping has outbound rules. */
create or replace function b2b.push_payload(a b2b.allocations)
returns jsonb language plpgsql stable set search_path = '' as $fn$
declare
  v jsonb := b2b.push_payload_base(a);
  pr b2b.mapping_profiles := b2b.mapping_active_out(a.partner_id);
begin
  if pr.id is null then return v; end if;
  return v || jsonb_build_object('fields', b2b.mapping_out(pr.id, b2b.lead_canonical(a)) -> 'fields', 'mapping_version', pr.version);
end $fn$;

alter table b2b.push_requests add column if not exists mapping_version int;

create or replace function b2b.push_requests_mapping_version()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  select (b2b.mapping_active_out(a.partner_id)).version into new.mapping_version from b2b.allocations a where a.id = new.allocation_id;
  return new;
end $fn$;
create or replace trigger push_requests_mapping_version before insert on b2b.push_requests
  for each row execute function b2b.push_requests_mapping_version();

-- ---------- inbound ----------
/* Records unmapped items in the mapping queue (one row per partner and item; counts and affected leads). */
create or replace function b2b.mapping_queue_add(p_partner_id bigint, p_items jsonb, p_lead_id bigint)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare i jsonb; n int := 0; v_new boolean; v_fresh jsonb := '[]';
begin
  for i in select x from jsonb_array_elements(coalesce(p_items, '[]')) x loop
    insert into b2b.mapping_queue as q (partner_id, kind, item, sample, lead_ids)
    values (p_partner_id, i ->> 'kind', left(i ->> 'item', 300), i - 'kind' - 'item', case when p_lead_id is null then '{}' else array[p_lead_id] end)
    on conflict (partner_id, kind, item) do update
      set last_seen = now(), seen_count = q.seen_count + 1, sample = excluded.sample,
          lead_ids = case when p_lead_id is null or p_lead_id = any (q.lead_ids) or cardinality(q.lead_ids) >= 500 then q.lead_ids else q.lead_ids || p_lead_id end,
          status = case when q.status = 'mapped' then 'open' else q.status end,
          resolution = case when q.status = 'mapped' then null else q.resolution end,
          resolved_at = case when q.status = 'mapped' then null else q.resolved_at end
    returning (xmax = 0) into v_new;
    if v_new then v_fresh := v_fresh || i; end if;
    n := n + 1;
  end loop;
  -- an alert for values seen for the first time; repeats only raise the queue's counts
  if jsonb_array_length(v_fresh) > 0 then
    perform b2b.log_event('alert.mapping_unmapped', p_lead_id, null, p_partner_id, jsonb_build_object('items', v_fresh));
  end if;
  return n;
end $fn$;

/* Writes mapped fields: B2B-owned lead columns while the partner holds the lead; Witty-owned ones only when empty and
   the partner is trusted for them; every canonical value and every unmapped partner field on the allocation. */
create or replace function b2b.apply_partner_fields(p_allocation_id bigint, p_profile_id bigint, m jsonb)
returns int language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  l jsonb;
  v_b2b jsonb := '{}';
  v_witty jsonb := '{}';
  v_set text;
  r record;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  select to_jsonb(x) into l from public.student_leads x where x.id = a.lead_id;
  update b2b.allocations set partner_fields = partner_fields || coalesce(m -> 'fields', '{}'), partner_custom = partner_custom || coalesce(m -> 'custom', '{}'),
         mapping_version = coalesce((m ->> 'version')::int, mapping_version), updated_at = now()
   where id = a.id;
  if (l ->> 'allocation_id')::bigint is distinct from a.id then return 0; end if;   -- the partner no longer holds the lead

  for r in select c.key, c.lead_column, c.owner, f.value #>> '{}' val,
                  exists (select 1 from b2b.field_rules x where x.profile_id = p_profile_id and x.canonical_key = c.key and x.trusted) trusted
             from jsonb_each(coalesce(m -> 'fields', '{}')) f join b2b.canonical_fields c on c.key = f.key
            where c.lead_column is not null and c.inbound loop
    if r.owner = 'b2b' then
      v_b2b := v_b2b || jsonb_build_object(r.lead_column, case when r.lead_column = 'contact_attempts' then round(r.val::numeric)::text else r.val end);
    elsif r.trusted and nullif(trim(coalesce(l ->> r.lead_column, '')), '') is null then
      v_witty := v_witty || jsonb_build_object(r.lead_column, r.val);
    end if;
  end loop;

  if v_b2b <> '{}' then
    select string_agg(format('%I = r.%I', k, k), ', ') into v_set from jsonb_object_keys(v_b2b) k;
    execute format('update public.student_leads t set %s, partner_synced_at = now(), updated_by = %L
                      from jsonb_populate_record(null::public.student_leads, $1) r where t.id = $2 and t.allocation_id = $3', v_set, 'b2b')
      using v_b2b, a.lead_id, a.id;
  end if;
  if v_witty <> '{}' then
    perform public.lead_intake(jsonb_build_object('phone', l ->> 'whatsapp_number', 'source_system', 'partner', 'event_type', 'partner.fields',
                                                  'lead', v_witty));
  end if;
  return (select count(*) from jsonb_object_keys(v_b2b)) + (select count(*) from jsonb_object_keys(v_witty));
end $fn$;

/* A mapped stage on the lead: forward only (unless the rule is a reopen); lost and duplicate go through their own paths. */
create or replace function b2b.apply_partner_mapped_stage(p_allocation_id bigint, st jsonb, p_raw jsonb)
returns text language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a b2b.allocations;
  l public.student_leads;
  v_stages jsonb := (select value from b2b.settings where key = 'stages');
  v_new text := st ->> 'stage';
  v_rank_new int;
  v_rank_old int;
begin
  select * into a from b2b.allocations where id = p_allocation_id;
  if a.status not in ('pushed', 'accepted') then return 'ignored: allocation is ' || a.status; end if;
  if v_new = 'lost' then
    return 'lost: handed to B2C nurture as ' || (b2b.apply_partner_lost(a.id, jsonb_build_object('lost_reason', st ->> 'lost_reason',
             'status', p_raw ->> 'stage', 'sub_status', p_raw ->> 'sub_stage', 'last_activity_at', p_raw ->> 'occurred_at')) ->> 'reference');
  end if;
  if v_new = 'duplicate_at_partner' then
    return b2b.apply_partner_duplicate(a.id, coalesce(p_raw -> 'fields', '{}') || jsonb_build_object('source', 'mapped_stage'));
  end if;

  select * into l from public.student_leads where id = a.lead_id for update;
  if l.allocation_id is distinct from a.id then return 'stored: the partner no longer holds the lead'; end if;
  select (e ->> 'rank')::int into v_rank_new from jsonb_array_elements(v_stages) e where e ->> 'key' = v_new;
  select (e ->> 'rank')::int into v_rank_old from jsonb_array_elements(v_stages) e where e ->> 'key' = l.stage;
  if v_rank_new < coalesce(v_rank_old, 0) and not coalesce((st ->> 'is_reopen')::boolean, false) then
    perform b2b.log_event('partner.stage_backwards', a.lead_id, a.id, a.partner_id,
                          jsonb_build_object('from', l.stage, 'to', v_new, 'partner_stage', p_raw ->> 'stage', 'partner_sub_stage', p_raw ->> 'sub_stage'));
    return 'stored: not moved back from ' || l.stage || ' to ' || v_new;
  end if;
  if l.stage is not distinct from v_new and l.sub_stage is not distinct from (st ->> 'sub_stage') then return 'stage unchanged (' || v_new || ')'; end if;

  update public.student_leads
     set stage = v_new, sub_stage = st ->> 'sub_stage', stage_changed_at = case when stage is distinct from v_new then now() else stage_changed_at end,
         reopened_at = case when coalesce((st ->> 'is_reopen')::boolean, false) and v_rank_new < coalesce(v_rank_old, 0) then now() else reopened_at end,
         partner_synced_at = now(), updated_by = 'b2b'
   where id = l.id;
  perform b2b.log_event('partner.stage_applied', a.lead_id, a.id, a.partner_id,
                        jsonb_build_object('stage', v_new, 'sub_stage', st ->> 'sub_stage', 'from', l.stage, 'partner_stage', p_raw ->> 'stage',
                                           'partner_sub_stage', p_raw ->> 'sub_stage', 'reopen', coalesce((st ->> 'is_reopen')::boolean, false)));
  if v_new = 'enrolled' and l.stage is distinct from 'enrolled' then
    perform b2b.log_event('lead.enrolled', a.lead_id, a.id, a.partner_id, jsonb_build_object('source', 'partner_stage', 'partner_stage', p_raw ->> 'stage'));
  end if;
  return 'stage ' || v_new || coalesce(' / ' || (st ->> 'sub_stage'), '');
end $fn$;

/* Applies one stored partner event. Sets its status (applied, ignored, held_unmapped, error) and returns {status, result}. */
create or replace function b2b.partner_event_apply(p_event_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  e b2b.partner_events;
  a b2b.allocations;
  pr b2b.mapping_profiles;
  j jsonb;
  d jsonb;
  m jsonb;
  v_kind text;
  v_status text := 'applied';
  v_result text;
  v_unmapped jsonb;
  v_at timestamptz;
begin
  select * into e from b2b.partner_events where id = p_event_id for update;
  if e.id is null then raise exception 'event not found' using errcode = 'P0002'; end if;
  select * into a from b2b.allocations where id = e.allocation_id;
  if a.id is null then
    update b2b.partner_events set status = 'error', result = 'no allocation matches reference or record_id' where id = e.id;
    return jsonb_build_object('status', 'error', 'result', 'no allocation matches reference or record_id');
  end if;
  j := e.raw;
  d := coalesce(j -> 'data', '{}');
  select * into pr from b2b.mapping_profiles where partner_id = e.partner_id and status = 'active';

  begin
    case e.event_type
      when 'duplicate' then v_result := b2b.apply_partner_duplicate(a.id, d);
      when 'rejected' then v_result := case when a.status in ('pushing', 'pushed') then b2b.apply_rejection(a.id, coalesce(d ->> 'reason', 'rejected'))
                                            else 'ignored: rejection after acceptance' end;
      when 'lost' then v_result := case when a.status in ('pushed', 'accepted')
                                        then (b2b.apply_partner_lost(a.id, d || jsonb_build_object('lost_reason', d ->> 'reason'))) ->> 'reference'
                                        else 'ignored: allocation is ' || a.status end;
      when 'contacted' then v_result := b2b.apply_contacted(a.id, j);
      when 'stage', 'update', 'activity' then
        -- the partner's own wording is always kept on the lead
        if e.event_type = 'stage' and a.status in ('pushed', 'accepted') then
          update public.student_leads set partner_stage_raw = left(d ->> 'stage', 200), partner_sub_stage_raw = left(d ->> 'sub_stage', 200),
                 partner_synced_at = now(), updated_by = 'b2b'
           where id = a.lead_id and allocation_id = a.id;
        end if;
        if pr.id is null then
          v_status := 'held_unmapped';
          v_result := 'stored: no mapping published for this partner yet';
        else
          v_kind := e.event_type;
          m := b2b.mapping_in(pr.id, v_kind, d);
          v_unmapped := coalesce(m -> 'unmapped', '[]');
          perform b2b.mapping_queue_add(e.partner_id, v_unmapped, a.lead_id);
          if a.status in ('pushed', 'accepted', 'closed', 'duplicate') then perform b2b.apply_partner_fields(a.id, pr.id, m); end if;
          if v_kind = 'stage' then
            if not coalesce((m -> 'status' ->> 'matched')::boolean, false) then
              v_status := 'held_unmapped';
              v_result := 'stored: unmapped stage ' || (d ->> 'stage') || coalesce(' / ' || (d ->> 'sub_stage'), '');
            elsif (m -> 'status' ->> 'ignored')::boolean then
              v_status := 'ignored';
              v_result := 'ignored stage: ' || (m -> 'status' ->> 'ignore_reason');
            else
              v_result := b2b.apply_partner_mapped_stage(a.id, m -> 'status', d);
            end if;
          elsif v_kind = 'activity' then
            if m -> 'activity' is null then
              v_status := 'held_unmapped';
              v_result := 'stored: unmapped activity ' || coalesce(d ->> 'type', '?') || coalesce(' / ' || (d ->> 'outcome'), '');
            else
              begin v_at := least(coalesce((j ->> 'occurred_at')::timestamptz, now()), now()); exception when others then v_at := now(); end;
              perform b2b.log_event('partner.activity', a.lead_id, a.id, a.partner_id,
                                    (m -> 'activity') || jsonb_build_object('occurred_at', v_at, 'partner_type', d ->> 'type', 'partner_outcome', d ->> 'outcome'));
              if m -> 'activity' ->> 'kind' = 'call' then
                perform b2b.apply_contacted(a.id, jsonb_build_object('occurred_at', v_at, 'data', jsonb_build_object('connected', m -> 'activity' ->> 'outcome' = 'connected')));
              end if;
              v_result := 'activity ' || (m -> 'activity' ->> 'kind') || coalesce(' / ' || (m -> 'activity' ->> 'outcome'), '');
            end if;
          else
            v_result := 'fields updated';
          end if;
          if jsonb_array_length(v_unmapped) > 0 and v_status = 'applied' then
            v_result := v_result || '; ' || jsonb_array_length(v_unmapped) || ' unmapped item(s) queued';
          end if;
        end if;
      else
        v_status := 'held_unmapped';
        v_result := 'stored: unknown event type';
    end case;
    if v_status = 'applied' and v_result like 'ignored%' then v_status := 'ignored'; end if;
    update b2b.partner_events set status = v_status, result = left(v_result, 500), mapped = m, mapping_version = pr.version,
           applied_at = case when v_status in ('applied', 'ignored') then now() end
     where id = e.id;
  exception when others then
    update b2b.partner_events set status = 'error', result = left(sqlerrm, 300) where id = e.id;
    return jsonb_build_object('status', 'error', 'result', left(sqlerrm, 300));
  end;
  return jsonb_build_object('status', v_status, 'result', v_result);
end $fn$;

/* Re-applies a partner's held events in the order they arrived (after a mapping is published). */
create or replace function b2b.mapping_reprocess(p_partner_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare r record; x jsonb; n int := 0; ok int := 0;
begin
  for r in select id from b2b.partner_events where partner_id = p_partner_id and status = 'held_unmapped' and allocation_id is not null order by id loop
    x := b2b.partner_event_apply(r.id);
    n := n + 1;
    if x ->> 'status' in ('applied', 'ignored') then ok := ok + 1; end if;
  end loop;
  return jsonb_build_object('reprocessed', n, 'applied', ok);
end $fn$;

/* POST /v1/partners/{slug}/events: signature, raw storage, then b2b.partner_event_apply. */
create or replace function b2b.partner_event_ingest(p_slug text, p_body text, p_timestamp text, p_signature text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  p b2b.partners;
  j jsonb;
  a b2b.allocations;
  v_expected text;
  v_type text;
  v_event_id text;
  v_id bigint;
  v_ts bigint;
  x jsonb;
begin
  perform set_config('b2b.actor', 'partner', true);
  select * into p from b2b.partners where slug = lower(trim(p_slug));
  if p.id is null or p.inbound_secret_id is null then return jsonb_build_object('ok', false, 'status', 404, 'error', 'unknown partner'); end if;
  if length(coalesce(p_body, '')) > 200000 then return jsonb_build_object('ok', false, 'status', 413, 'error', 'body too large'); end if;
  begin v_ts := p_timestamp::bigint; exception when others then v_ts := null; end;
  if v_ts is null or abs(extract(epoch from now()) - v_ts) > 300 then
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'timestamp missing or more than 5 minutes off');
  end if;
  v_expected := 'sha256=' || encode(extensions.hmac(convert_to(p_timestamp || '.' || p_body, 'UTF8'),
                                                    convert_to(b2b.partner_secret(p.inbound_secret_id), 'UTF8'), 'sha256'), 'hex');
  if p_signature is distinct from v_expected then
    perform b2b.log_event('alert.partner_bad_signature', null, null, p.id, '{}');
    return jsonb_build_object('ok', false, 'status', 401, 'error', 'bad signature');
  end if;
  begin j := p_body::jsonb; exception when others then return jsonb_build_object('ok', false, 'status', 400, 'error', 'body is not JSON'); end;
  v_event_id := left(nullif(trim(j ->> 'event_id'), ''), 200);
  v_type := lower(coalesce(j ->> 'type', ''));
  if v_event_id is null or v_type = '' then return jsonb_build_object('ok', false, 'status', 400, 'error', 'event_id and type are required'); end if;

  -- find the allocation by our reference (EDW-<id>), else by the partner's record id
  select * into a from b2b.allocations x
   where x.partner_id = p.id and (x.reference = j ->> 'reference' or (j ->> 'record_id' is not null and x.partner_record_id = j ->> 'record_id'))
   order by x.created_at desc limit 1;

  insert into b2b.partner_events (partner_id, event_id, event_type, reference, record_id, allocation_id, lead_id, raw)
  values (p.id, v_event_id, v_type, j ->> 'reference', j ->> 'record_id', a.id, a.lead_id, j)
  on conflict (partner_id, event_id) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('ok', true, 'status', 200, 'result', 'already received'); end if;
  if a.id is null then
    update b2b.partner_events set status = 'error', result = 'no allocation matches reference or record_id' where id = v_id;
    return jsonb_build_object('ok', false, 'status', 404, 'error', 'no lead matches this reference');
  end if;

  x := b2b.partner_event_apply(v_id);
  if x ->> 'status' = 'error' then
    return jsonb_build_object('ok', false, 'status', 500, 'error', 'could not apply the event; it is stored and will be reviewed');
  end if;
  return jsonb_build_object('ok', true, 'status', 200, 'result', coalesce(x ->> 'result', 'stored'));
end $fn$;

-- ---------- go-live gate ----------
/* Mapping is ready when an active version covers every required item and every golden file passes. */
create or replace function b2b.mapping_ready(p_partner_id bigint)
returns boolean language plpgsql stable security definer set search_path = '' as $fn$
declare pr b2b.mapping_profiles; c jsonb;
begin
  select * into pr from b2b.mapping_profiles where partner_id = p_partner_id and status = 'active';
  if pr.id is null then return false; end if;
  c := b2b.mapping_coverage(pr.id);
  return (c ->> 'required_done')::int = (c ->> 'required_total')::int
     and not exists (select 1 from jsonb_array_elements(b2b.mapping_golden_run(pr.id)) g where not (g ->> 'pass')::boolean);
end $fn$;

create or replace function b2b.partner_checklist(p b2b.partners)
returns jsonb language sql stable set search_path = '' as $fn$
  select jsonb_build_array(
    jsonb_build_object('key', 'agreement',   'done', false, 'available', false),
    jsonb_build_object('key', 'programmes',  'done', exists (select 1 from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active), 'available', true),
    jsonb_build_object('key', 'credentials', 'done', p.api_base_url is not null and (p.outbound_secret_id is not null or p.outbound_auth ->> 'type' = 'none')
                                                     and p.inbound_secret_id is not null, 'available', true),
    jsonb_build_object('key', 'mapping',     'done', b2b.mapping_ready(p.id), 'available', true),
    jsonb_build_object('key', 'sla_hours',   'done', exists (select 1 from jsonb_each(p.working_hours) d where jsonb_typeof(d.value) = 'object'), 'available', true),
    jsonb_build_object('key', 'branding',    'done', p.display_name is not null and p.brand_color is not null and p.logo_url is not null, 'available', true),
    jsonb_build_object('key', 'test_leads',  'done', exists (select 1 from b2b.allocations a where a.partner_id = p.id and a.is_test and a.status in ('accepted', 'closed')), 'available', true)
  );
$fn$;

-- b2b.apply_partner_stage (m8c) is no longer called: stage events take the mapping path above. It stays (service_role
-- only) because the connector holds migrations that contain DROP.

revoke execute on function b2b.push_payload_base(b2b.allocations), b2b.mapping_active_out(bigint), b2b.push_payload(b2b.allocations),
                           b2b.push_requests_mapping_version(), b2b.mapping_queue_add(bigint, jsonb, bigint), b2b.apply_partner_fields(bigint, bigint, jsonb),
                           b2b.apply_partner_mapped_stage(bigint, jsonb, jsonb), b2b.partner_event_apply(bigint), b2b.mapping_reprocess(bigint),
                           b2b.mapping_ready(bigint)
  from public, anon, authenticated;
grant execute on function b2b.push_payload_base(b2b.allocations), b2b.mapping_active_out(bigint), b2b.push_payload(b2b.allocations),
                          b2b.mapping_queue_add(bigint, jsonb, bigint), b2b.apply_partner_fields(bigint, bigint, jsonb),
                          b2b.apply_partner_mapped_stage(bigint, jsonb, jsonb), b2b.partner_event_apply(bigint), b2b.mapping_reprocess(bigint),
                          b2b.mapping_ready(bigint)
  to service_role;
-- partner_checklist is read through partner_json by the signed-in Admin (it was granted to authenticated in m4b)
grant execute on function b2b.mapping_ready(bigint) to authenticated;
revoke execute on function b2b.partner_event_ingest(text, text, text, text) from public;
grant execute on function b2b.partner_event_ingest(text, text, text, text) to anon, authenticated, service_role;
