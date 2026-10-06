-- M7d: reads for Addenda 1 and 2: decisions and allocations carry the B2C lane; the routing overview shows nurture,
-- sales, not passed and the review queue; the Master Lead Table hides not-passed leads by default and gets a
-- "Not passed" view (destination = not_passed) with the reason on each row.

create or replace function b2b.decision_json(d b2b.engine_decisions)
returns jsonb language sql stable set search_path = '' as $$
  select to_jsonb(d) || jsonb_build_object(
    'lead_name', (select l.student_name from public.student_leads l where l.id = d.lead_id),
    'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = d.winner_partner_id),
    'allocation', (select jsonb_build_object('id', a.id, 'reference', a.reference, 'status', a.status, 'cpe_net_inr', a.cpe_net_inr, 'b2c_lane', a.b2c_lane, 'outcome', a.outcome)
                     from b2b.allocations a where a.engine_decision_id = d.id limit 1));
$$;

create or replace function b2b.routing_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_today timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'switch', coalesce((select jsonb_build_object('live', s.live, 'reason', s.reason, 'switched_at', s.switched_at) from b2b.live_switches s where s.scope = 'routing'),
                       jsonb_build_object('live', false)),
    'engine', (select jsonb_build_object('value', s.value, 'version', s.version, 'updated_at', s.updated_at) from b2b.settings s where s.key = 'engine'),
    'live_partners', (select count(*) from b2b.partners p where p.status = 'active' and b2b.is_live('partner:' || p.id)),
    'partners', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.name), 'status', p.status,
                                  'live', b2b.is_live('partner:' || p.id), 'test_endpoint', p.test_endpoint is not null,
                                  'offers', (select count(*) from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active),
                                  'proposed', (select count(*) from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active
                                                  and o.commission ->> 'type' in ('percent', 'fixed')
                                                  and not exists (select 1 from b2b.rates r where r.scope = 'partner_programme' and r.partner_id = p.id
                                                                    and r.programme_id = o.programme_id and r.valid_to is null
                                                                    and r.rate_type = o.commission ->> 'type' and r.value = (o.commission ->> 'value')::numeric)))
                                order by p.status = 'closed', coalesce(p.display_name, p.name)) from b2b.partners p), '[]'),
    'today', jsonb_build_object(
      'to_partners', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.destination_type = 'partner' and not a.is_test),
      'to_b2c', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.destination_type = 'in_house' and not a.is_test),
      'tests', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.is_test),
      'b2c_reasons', coalesce((select jsonb_object_agg(reason, n) from (select a.reason, count(*) n from b2b.allocations a
                                where a.created_at >= v_today and a.destination_type = 'in_house' and not a.is_test group by 1) x), '{}'),
      'errors', (select count(*) from b2b.events e where e.type = 'routing.error' and e.occurred_at >= v_today),
      'nurture', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.b2c_lane = 'nurture' and not a.is_test),
      'sales', (select count(*) from b2b.allocations a where a.created_at >= v_today and a.b2c_lane = 'sales' and not a.is_test),
      'not_passed', (select count(*) from b2b.not_passed n where n.decided_at >= v_today and n.passed_at is null)),
    'not_passed_open', (select count(*) from b2b.not_passed n where n.passed_at is null),
    'flags_open', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'lead_id', f.lead_id, 'lead_name', l.student_name, 'lead_status', f.lead_status,
                              'destination_type', f.destination_type, 'reference', a.reference,
                              'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = a.partner_id),
                              'created_at', f.created_at) order by f.created_at desc)
                            from b2b.review_flags f join b2b.allocations a on a.id = f.allocation_id
                            left join public.student_leads l on l.id = f.lead_id where f.resolved_at is null), '[]'),
    'decisions', coalesce((select jsonb_agg(b2b.decision_json(d) - 'candidates' - 'excluded' - 'rules' - 'interest' order by d.created_at desc)
                             from (select * from b2b.engine_decisions order by created_at desc limit 50) d), '[]'),
    'rules', coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object('partner_names',
                              (select jsonb_agg(coalesce(p.display_name, p.name)) from b2b.partners p where p.id = any (r.partner_ids)))
                            order by r.active desc, r.priority, r.id) from b2b.routing_rules r), '[]'),
    'rates', coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object(
                              'partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = r.partner_id),
                              'programme', b2b.programme_label(r.programme_id))
                            order by r.partner_id, r.programme_id nulls first, r.valid_from desc)
                         from b2b.rates r where r.valid_to is null or r.valid_to >= current_date - 90), '[]'));
end $$;

create or replace function b2b.lead_routing(p_lead_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  l public.student_leads;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into l from public.student_leads where id = p_lead_id;
  if l.id is null then return null; end if;
  return jsonb_build_object(
    'readiness', b2b.lead_readiness(l), 'interest', b2b.lead_interest(l),
    'consent', l.consent_partner_share_at is not null, 'routing_live', b2b.is_live('routing'),
    'not_passed', (select to_jsonb(n) from b2b.not_passed n where n.lead_id = l.id),
    'flags', coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at desc) from b2b.review_flags f where f.lead_id = l.id), '[]'),
    'decisions', coalesce((select jsonb_agg(b2b.decision_json(d) order by d.created_at desc) from b2b.engine_decisions d where d.lead_id = l.id), '[]'),
    'allocations', coalesce((select jsonb_agg(to_jsonb(a) || jsonb_build_object('partner_name', (select coalesce(p.display_name, p.name) from b2b.partners p where p.id = a.partner_id))
                                              order by a.created_at desc) from b2b.allocations a where a.lead_id = l.id), '[]'));
end $$;

create or replace function b2b.lead_filter_sql(p jsonb)
returns text language plpgsql immutable set search_path = '' as $$
declare
  w      text[] := array['l.merged_into_id is null'];
  q      text := left(trim(coalesce(p ->> 'q', '')), 100);
  digits text;
  pat    text;
  arr    text[];
begin
  if coalesce((p ->> 'bin')::boolean, false) then
    w := array_append(w, 'l.deleted_at is not null');
  else
    w := array_append(w, 'l.deleted_at is null');
  end if;

  if not coalesce((p ->> 'include_test')::boolean, false) then
    w := array_append(w, 'not (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number))');
  end if;

  if q <> '' then
    pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
    digits := regexp_replace(q, '\D', '', 'g');
    w := array_append(w, format('(l.student_name ilike %1$L or l.email_id ilike %1$L%2$s%3$s)',
      pat,
      case when length(digits) >= 4 then format(' or regexp_replace(coalesce(l.whatsapp_number, ''''), ''\D'', '''', ''g'') like %L', '%' || digits || '%') else '' end,
      case when q ~ '^\d{1,18}$' then format(' or l.id = %L::bigint', q) else '' end));
  end if;

  if jsonb_typeof(p -> 'stage') = 'array' and jsonb_array_length(p -> 'stage') > 0 then
    select array_agg(x) into arr from jsonb_array_elements_text(p -> 'stage') x;
    w := array_append(w, format('l.stage = any (%L::text[])', arr));
  end if;
  if jsonb_typeof(p -> 'source') = 'array' and jsonb_array_length(p -> 'source') > 0 then
    select array_agg(x) into arr from jsonb_array_elements_text(p -> 'source') x;
    w := array_append(w, format('coalesce(l.lead_source, ''(none)'') = any (%L::text[])', arr));
  end if;
  if jsonb_typeof(p -> 'status') = 'array' and jsonb_array_length(p -> 'status') > 0 then
    select array_agg(upper(x)) into arr from jsonb_array_elements_text(p -> 'status') x;
    w := array_append(w, format('upper(coalesce(nullif(l.lead_status, ''''), ''NONE'')) = any (%L::text[])', arr));
  end if;
  case p ->> 'destination'
    when 'unrouted' then w := array_append(w, 'l.destination_type is null');
    when 'partner'  then w := array_append(w, 'l.destination_type = ''partner''');
    when 'in_house' then w := array_append(w, 'l.destination_type = ''in_house''');
    when 'not_passed' then w := array_append(w, 'exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null)');
    else null;
  end case;
  -- Addendum 2: default views hide not-passed (junk / mismatch) leads; the "Not passed" view and the recycle bin show them
  if coalesce(p ->> 'destination', '') <> 'not_passed' and not coalesce((p ->> 'bin')::boolean, false)
     and not coalesce((p ->> 'with_not_passed')::boolean, false) then
    w := array_append(w, 'not exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null)');
  end if;

  return array_to_string(w, ' and ');
end $$;

create or replace function b2b.leads_list(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_where text;
  v_sort  text;
  v_dir   text := case when lower(coalesce(p ->> 'dir', 'desc')) = 'asc' then 'asc' else 'desc' end;
  v_cmp   text := case when lower(coalesce(p ->> 'dir', 'desc')) = 'asc' then '>' else '<' end;
  v_cast  text;
  v_limit int := least(greatest(coalesce((p ->> 'limit')::int, 50), 1), 200);
  v_keyset text := '';
  v_rows  jsonb;
  v_total bigint;
  v_next  jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;

  case coalesce(p ->> 'sort', 'created_at')
    when 'name'          then v_sort := 'lower(coalesce(nullif(l.student_name, ''''), ''~''))'; v_cast := 'text';
    when 'last_activity' then v_sort := 'coalesce(l.last_activity_at, l.created_at)';             v_cast := 'timestamptz';
    else                      v_sort := 'l.created_at';                                           v_cast := 'timestamptz';
  end case;

  v_where := b2b.lead_filter_sql(p);
  if p ? 'after' and p -> 'after' ->> 'id' is not null then
    v_keyset := format(' and (%s, l.id) %s (%L::%s, %L::bigint)', v_sort, v_cmp, p -> 'after' ->> 'v', v_cast, p -> 'after' ->> 'id');
  end if;

  execute format($q$
    select coalesce(jsonb_agg(to_jsonb(r) order by r.ord), '[]'::jsonb)
      from (
        select row_number() over (order by %1$s %4$s, l.id %4$s) as ord, %1$s::text as sort_key,
               l.id, l.created_at, l.student_name, l.whatsapp_number, l.email_id, l.city, l.state,
               l.interested_course, l.interested_specialization, l.program_level, l.study_mode_preference,
               l.lead_source, l.channel, l.campaign, l.lead_status, l.temperature, l.stage, l.sub_stage, l.lead_stage,
               l.destination_type, l.partner_id, l.last_activity_at, l.deleted_at, l.is_opted_out,
               (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)) as is_test,
               l.consent_partner_share_at is not null as partner_consent,
               l.is_bot_paused,
               (select jsonb_build_object('reason', np.reason, 'decided_at', np.decided_at) from b2b.not_passed np
                 where np.lead_id = l.id and np.passed_at is null) as not_passed
          from public.student_leads l
         where %2$s%3$s
         order by %1$s %4$s, l.id %4$s
         limit %5$s
      ) r
  $q$, v_sort, v_where, v_keyset, v_dir, v_limit + 1) into v_rows;

  if jsonb_array_length(v_rows) > v_limit then
    v_rows := v_rows - v_limit;   -- drop the probe row; its presence means there is a next page
    v_next := jsonb_build_object('v', v_rows -> (v_limit - 1) ->> 'sort_key', 'id', v_rows -> (v_limit - 1) ->> 'id');
  end if;
  select coalesce(jsonb_agg(e.value - 'sort_key' - 'ord' order by e.i), '[]'::jsonb)
    into v_rows from jsonb_array_elements(v_rows) with ordinality e(value, i);

  if not (p ? 'after') then
    execute format('select count(*) from public.student_leads l where %s', v_where) into v_total;
  end if;

  return jsonb_build_object('rows', v_rows, 'next', v_next, 'total', v_total);
end $$;

create or replace function b2b.leads_facets(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_where text;
  v_all   text;
  v_out   jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  -- facet counts ignore the facet filters themselves, so every option stays visible; only the routing facet counts
  -- not-passed leads (its "Not passed" option), the others follow the list, which hides them
  v_where := b2b.lead_filter_sql(jsonb_build_object('include_test', p -> 'include_test', 'bin', p -> 'bin', 'q', p -> 'q'));
  v_all := b2b.lead_filter_sql(jsonb_build_object('include_test', p -> 'include_test', 'bin', p -> 'bin', 'q', p -> 'q', 'with_not_passed', true));
  execute format($q$
    select jsonb_build_object(
      'stage',       (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(l.stage, '(none)') k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'source',      (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(l.lead_source, '(none)') k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'status',      (select coalesce(jsonb_object_agg(k, n), '{}') from (select upper(coalesce(nullif(l.lead_status, ''), 'NONE')) k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'destination', (select coalesce(jsonb_object_agg(k, n), '{}') from (select case when exists (select 1 from b2b.not_passed np where np.lead_id = l.id and np.passed_at is null) then 'not_passed' else coalesce(l.destination_type, 'unrouted') end k, count(*) n from public.student_leads l where %2$s group by 1) s),
      'bin',         (select count(*) from public.student_leads l where l.deleted_at is not null and l.merged_into_id is null),
      'tests',       (select count(*) from public.student_leads l where l.deleted_at is null and l.merged_into_id is null and (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)))
    )
  $q$, v_where, v_all) into v_out;
  return v_out;
end $$;

/* Not passed (Addendum 2): counts by reason and source, and the programmes students asked for that Eduwit does not offer. */
create or replace function b2b.not_passed_summary()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'by_reason', coalesce((select jsonb_object_agg(reason, n) from (select reason, count(*) n from b2b.not_passed where passed_at is null group by 1) x), '{}'),
    'by_source', coalesce((select jsonb_object_agg(coalesce(lead_source, '(none)'), n) from (select lead_source, count(*) n from b2b.not_passed where passed_at is null group by 1) x), '{}'),
    'mismatch_courses', coalesce((select jsonb_agg(jsonb_build_object('course', c, 'n', n) order by n desc, c) from (
        select initcap(lower(trim(requested_course))) c, count(*) n from b2b.not_passed
         where passed_at is null and reason = 'program_mismatch' and coalesce(trim(requested_course), '') <> '' group by 1 order by 2 desc limit 20) x), '[]'));
end $$;

revoke execute on function b2b.not_passed_summary() from public, anon;
grant execute on function b2b.not_passed_summary() to authenticated, service_role;
