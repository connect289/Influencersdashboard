-- Fixes found in the Step 1 walkthrough (16 Oct 2026), every screen opened as each role against staging with test data.
--   lead_list         test users (users.is_test_user) see test leads by default: they only ever hold test leads, so their
--                     Leads and Pipeline pages were empty while Today showed the leads. Real users still see none unless asked.
--   pool_list         'total' counted the one aggregated row (always 1): now the number of matching leads before the page limit.
--                     Its search also matched every lead when the words had no digits (an empty phone pattern).
--   inbox_list        the Inbox search had the same empty phone pattern: a name that matched nobody showed every chat.
--   programme_search  the same count bug ("1 programmes" over three rows).

create or replace function b2c.lead_list(p jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_role text := b2c.my_role(); me uuid := b2c.uid(); w text := 'true';
  v_test_user boolean := coalesce((select u.is_test_user from b2c.users u where u.user_id = b2c.uid()), false); c jsonb; v_field text; v_op text; v_sql text; v_rows jsonb; v_total int;
  v_any text; f jsonb := coalesce(p -> 'filters', '{}'); v_sort text; v_dir text; v_limit int := least(coalesce((p ->> 'limit')::int, 50), 500); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0);
  allowed text[] := array['lead_id','name','phone','email','city','state','language','course','specialization','university','programme_level','study_mode',
    'qualification','source','campaign','lead_status','partner_consent_state','marketing_consent','opted_out','lane','status','handoff_reason','cause',
    'partner_bar_reason','owner_id','owner_name','assigned_at','stage_id','stage','canonical_stage','sub_stage','stage_changed_at','hot','temperature','score',
    'next_task_due_at','first_contacted_at','last_contacted_at','contact_attempts','last_activity_at','sla_due_at','sla_met_at','sla_breached_at',
    'pool_entered_at','pool_reason','journey','lost_by','reengaged_at','flagged','reenquired_at','tags','is_test','handed_off_at','updated_at','closed_at'];
  v_drill bigint[];
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_role = 'counsellor' then w := format('owner_id = %L', me); end if;
  if nullif(p ->> 'drill', '') is not null then
    select lead_ids into v_drill from b2c.analytics_drills where id = (p ->> 'drill')::uuid and user_id = me;
    w := w || format(' and lead_id = any (%L::bigint[])', coalesce(v_drill, '{}'));
  end if;
  w := w || case when coalesce((p ->> 'deleted')::boolean, false) then ' and deleted_at is not null' else ' and deleted_at is null' end;
  if not coalesce((p ->> 'include_test')::boolean, v_role = 'admin' or v_drill is not null or v_test_user) then w := w || ' and not is_test'; end if;
  for c in select * from jsonb_array_elements(coalesce(f -> 'all', '[]')) loop
    w := w || ' and ' || b2c.filter_sql(c, allowed);
  end loop;
  if jsonb_array_length(coalesce(f -> 'any', '[]')) > 0 then
    select string_agg(b2c.filter_sql(x, allowed), ' or ') into v_any from jsonb_array_elements(f -> 'any') x;
    w := w || ' and (' || v_any || ')';
  end if;
  if coalesce(trim(p ->> 'search'), '') <> '' then
    w := w || format(' and (name ilike %1$L or email ilike %1$L or b2c.norm_phone(phone) like %2$L or lead_id::text = %3$L
                       or exists (select 1 from b2c.lead_contacts lc where lc.lead_id = v.lead_id and lc.value_norm like %2$L)
                       or exists (select 1 from b2c.applications ap where ap.lead_id = v.lead_id and ap.application_ref ilike %1$L))',
                     '%' || trim(p ->> 'search') || '%', '%' || coalesce(nullif(regexp_replace(p ->> 'search', '\D', '', 'g'), ''), '~none~') || '%', trim(p ->> 'search'));
  end if;
  v_sort := coalesce(p -> 'sort' ->> 'field', 'next_task_due_at');
  if not v_sort = any (allowed) then v_sort := 'next_task_due_at'; end if;
  v_dir := case when lower(coalesce(p -> 'sort' ->> 'dir', 'asc')) = 'desc' then 'desc' else 'asc' end;
  v_sql := format('select count(*) over () total, to_jsonb(v) - ''providers'' - ''handling'' as row from b2c.leads_v v where %s order by %I %s nulls last, lead_id desc limit %s offset %s',
                  w, v_sort, v_dir, v_limit, v_offset);
  execute format('select coalesce(max(total), 0), coalesce(jsonb_agg(row), ''[]'') from (%s) q', v_sql) into v_total, v_rows;
  return jsonb_build_object('total', v_total, 'rows', v_rows);
end $f$;

create or replace function b2c.pool_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_limit int := least(coalesce((p ->> 'limit')::int, 100), 500); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0); q text := nullif(trim(p ->> 'q'), '');
begin
  if not b2c.can('marketing') then raise exception 'not allowed' using errcode = '42501'; end if;
  return (select jsonb_build_object('total', coalesce(max(t.total), 0), 'rows', coalesce(jsonb_agg(t.x order by t.ord), '[]')) from (
    select count(*) over () as total, row_number() over (order by v.pool_entered_at desc nulls last, v.lead_id desc) as ord, jsonb_build_object('lead_id', v.lead_id, 'name', v.name, 'course', v.course, 'reason', v.pool_reason, 'sub_stage', v.sub_stage, 'lost_by', v.lost_by,
             'lost_detail', coalesce(s.partner_lost ->> 'partner_name', u.full_name), 'lost_reason', coalesce(s.partner_lost ->> 'lost_reason', v.sub_stage),
             'missing', s.missing, 'score', v.score, 'trend_7d', (select coalesce(sum(points), 0) from b2c.score_events e where e.lead_id = v.lead_id and e.at > now() - interval '7 days'),
             'marketing_consent', jsonb_build_object('whatsapp', b2c.has_marketing_consent(v.lead_id, 'whatsapp'), 'email', b2c.has_marketing_consent(v.lead_id, 'email')),
             'journey', (select jsonb_build_object('name', j.name, 'step', r.step_idx + 1, 'status', r.status, 'next_at', r.next_at) from b2c.journey_runs r join b2c.journeys j on j.id = r.journey_id
                          where r.lead_id = v.lead_id and r.status in ('running', 'paused') limit 1),
             'first_message_due_at', s.first_message_due_at, 'pool_entered_at', v.pool_entered_at,
             'last_message', (select jsonb_build_object('channel', 'whatsapp', 'status', m.status, 'at', m.created_at) from b2c.wa_messages m
                               where m.lead_id = v.lead_id and m.direction = 'out' and m.purpose in ('journey', 'campaign', 'marketing') order by m.created_at desc limit 1),
             'last_student_at', (select max(m.created_at) from b2c.wa_messages m where m.lead_id = v.lead_id and m.direction = 'in')) x
      from b2c.leads_v v join b2c.leads_state s on s.lead_id = v.lead_id left join b2c.users u on u.user_id = s.lost_by_user
     where v.status = 'pool' and v.deleted_at is null and s.dormant_at is null and v.is_test = coalesce((p ->> 'test')::boolean, false)
       and (p ->> 'reason' is null or v.pool_reason = p ->> 'reason')
       and (q is null or v.name ilike '%' || q || '%' or v.lead_id::text = q or (regexp_replace(q, '\D', '', 'g') <> '' and b2c.norm_phone(v.phone) like '%' || regexp_replace(q, '\D', '', 'g') || '%'))
     order by v.pool_entered_at desc nulls last, v.lead_id desc
     limit v_limit offset v_offset) t);
end $f$;

create or replace function b2c.programme_search(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare q text := nullif(trim(p ->> 'q'), '');
begin
  if not b2c.is_staff() then raise exception 'not allowed'; end if;
  return (select jsonb_build_object('total', coalesce(max(s.total), 0), 'rows', coalesce(jsonb_agg(s.x order by s.x ->> 'university', s.x ->> 'name'), '[]')) from (
    select count(*) over () as total, jsonb_build_object('id', pr.id, 'name', coalesce(pr.program_name, pr.course), 'course', pr.course, 'specialization', pr.specialization, 'level', pr.level,
             'mode', pr.mode, 'university', un.name, 'university_short', un.short_name, 'accreditation', un.accreditation_text, 'recognitions', to_jsonb(un.recognitions),
             'fee_yearly', pr.fee_yearly, 'fee_semester', pr.fee_semester, 'fee_total', pr.fee_total, 'fee_exam', pr.fee_exam, 'fee_registration', pr.fee_registration,
             'min_qualification', pr.min_qualification, 'min_pct', pr.min_pct_general, 'eligibility', pr.eligibility_text, 'brochure_url', pr.brochure_url) x
      from public.catalog_programs pr join public.catalog_universities un on un.id = pr.university_id
     where pr.active
       and (q is null or pr.search_doc @@ websearch_to_tsquery('simple', q) or coalesce(pr.program_name, pr.course) ilike '%' || q || '%' or un.name ilike '%' || q || '%')
       and (p ->> 'level' is null or pr.level ilike p ->> 'level')
       and (p ->> 'mode' is null or pr.mode ilike p ->> 'mode')
       and (p ->> 'university' is null or un.name ilike '%' || (p ->> 'university') || '%')
       and (p ->> 'fee_max' is null or coalesce(pr.fee_total, pr.fee_yearly) <= (p ->> 'fee_max')::numeric)
       and (p ->> 'fee_min' is null or coalesce(pr.fee_total, pr.fee_yearly) >= (p ->> 'fee_min')::numeric)
     limit least(coalesce((p ->> 'limit')::int, 100), 300)) s);
end $f$;

create or replace function b2c.inbox_list(p jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_role text := b2c.my_role(); me uuid := b2c.uid();
begin
  if v_role is null then raise exception 'not allowed'; end if;
  return (select coalesce(jsonb_agg(x order by x ->> 'last_at' desc nulls last), '[]') from (
    select jsonb_build_object('phone', c.phone, 'lead_id', c.lead_id, 'name', v.name, 'course', v.course, 'owner_name', v.owner_name, 'unread', c.unread,
                              'window_open', c.last_inbound_at > now() - interval '24 hours', 'window_closes_at', c.last_inbound_at + interval '24 hours',
                              'last_at', greatest(c.last_inbound_at, c.last_outbound_at),
                              'last', (select m.body from b2c.wa_messages m where m.phone = c.phone order by m.created_at desc limit 1)) x
      from b2c.wa_conversations c left join b2c.leads_v v on v.lead_id = c.lead_id
     where (v_role in ('admin', 'marketing') or v.owner_id = me)
       and (coalesce(p ->> 'search', '') = '' or v.name ilike '%' || (p ->> 'search') || '%' or (regexp_replace(p ->> 'search', '\D', '', 'g') <> '' and c.phone like '%' || regexp_replace(p ->> 'search', '\D', '', 'g') || '%'))
       and (not coalesce((p ->> 'unread')::boolean, false) or c.unread > 0)
     limit 200) q);
end $f$;
