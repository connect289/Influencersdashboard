-- M3 (6 Oct 2026): the Leads page (spec B6.1): list with search, filters, sort and keyset paging; lead detail with
-- the Witty conversation and timeline; soft delete, restore and the recycle bin; CSV export with an audit log.
--
-- Reads go through SECURITY DEFINER functions that check b2b.is_admin(), so RLS on student_leads and Witty's tables
-- stays untouched (guardrail A3). The only student_leads column written is deleted_at (B2B-owned for soft delete).
-- No DROP statements (the Supabase connector holds those for confirmation).

-- ---------- audit tables ----------
create table if not exists b2b.lead_deletions (
  id         bigint generated always as identity primary key,
  lead_id    bigint not null,
  action     text not null check (action in ('delete', 'restore')),
  reason     text,
  batch_id   uuid not null,
  actor_type text not null,
  actor_id   text,
  at         timestamptz not null default now()
);
create index if not exists lead_deletions_lead_idx on b2b.lead_deletions (lead_id, at desc);

create table if not exists b2b.lead_exports (
  id         bigint generated always as identity primary key,
  actor_id   text,
  filters    jsonb not null,
  row_count  int not null,
  masked     boolean not null,
  at         timestamptz not null default now()
);

do $rls$
declare t text;
begin
  foreach t in array array['lead_deletions', 'lead_exports'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- ---------- helpers ----------
-- Witty's test harness (910000xxxxxx) and the Hermes test agent (9190000000NN), matched on digits.
create or replace function b2b.is_test_phone(p text)
returns boolean language sql immutable set search_path = '' as $$
  select regexp_replace(coalesce(p, ''), '\D', '', 'g') ~ '^(910000[0-9]{6}|9190000000[0-9]{2})$';
$$;

-- WHERE clause for the lead filters. Every value is embedded with %L (quote_literal), so no input reaches SQL unquoted.
-- p: { q, stage[], source[], status[], destination, include_test, bin }
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
    else null;
  end case;

  return array_to_string(w, ' and ');
end $$;

-- ---------- list (keyset paging) ----------
-- p: filters + { sort: created_at | last_activity | name, dir: asc | desc, after: { v, id }, limit }
-- Returns { rows, next, total } — total only on the first page (no cursor), so paging stays cheap.
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
               l.is_bot_paused
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

-- ---------- facets for the filter bar ----------
create or replace function b2b.leads_facets(p jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_where text;
  v_out   jsonb;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  -- facet counts ignore the facet filters themselves, so every option stays visible
  v_where := b2b.lead_filter_sql(jsonb_build_object('include_test', p -> 'include_test', 'bin', p -> 'bin', 'q', p -> 'q'));
  execute format($q$
    select jsonb_build_object(
      'stage',       (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(l.stage, '(none)') k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'source',      (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(l.lead_source, '(none)') k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'status',      (select coalesce(jsonb_object_agg(k, n), '{}') from (select upper(coalesce(nullif(l.lead_status, ''), 'NONE')) k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'destination', (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(l.destination_type, 'unrouted') k, count(*) n from public.student_leads l where %1$s group by 1) s),
      'bin',         (select count(*) from public.student_leads l where l.deleted_at is not null and l.merged_into_id is null),
      'tests',       (select count(*) from public.student_leads l where l.deleted_at is null and l.merged_into_id is null and (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)))
    )
  $q$, v_where) into v_out;
  return v_out;
end $$;

-- ---------- one lead, with its history ----------
create or replace function b2b.lead_detail(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  l public.student_leads;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into l from public.student_leads where id = p_id;
  if l.id is null then return null; end if;
  return jsonb_build_object(
    'lead', to_jsonb(l) || jsonb_build_object('is_test', coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)),
    'touchpoints', coalesce((select jsonb_agg(jsonb_build_object('at', t.occurred_at, 'system', t.source_system, 'event', t.event_type,
                                                                'source', t.source, 'campaign', t.campaign) order by t.occurred_at desc)
                               from (select * from public.touchpoints where lead_id = l.id order by occurred_at desc limit 50) t), '[]'),
    'messages', coalesce((select jsonb_agg(jsonb_build_object('at', m.created_at, 'direction', m.direction, 'kind', m.kind,
                                                             'content', left(m.content, 4000)) order by m.created_at)
                            from (select * from public.w2_messages
                                   where phone = regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g')
                                   order by created_at desc limit 200) m), '[]'),
    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.occurred_at, 'type', e.type, 'actor', e.actor_type, 'payload', e.payload)
                                         order by e.occurred_at desc)
                          from (select * from b2b.events where lead_id = l.id order by occurred_at desc limit 50) e), '[]'),
    'deletions', coalesce((select jsonb_agg(jsonb_build_object('at', d.at, 'action', d.action, 'reason', d.reason) order by d.at desc)
                             from b2b.lead_deletions d where d.lead_id = l.id), '[]'),
    'has_enrollment', exists (select 1 from public.enrollments e where e.lead_id = l.id)
  );
end $$;

-- ---------- soft delete and restore ----------
create or replace function b2b.leads_soft_delete(p_ids bigint[], p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_batch   uuid := gen_random_uuid();
  v_a       jsonb := b2b.actor();
  v_blocked jsonb;
  v_done    bigint[];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_reason is null or p_reason not in ('junk', 'test', 'duplicate entry', 'spam', 'student request', 'other') then
    raise exception 'choose a reason';
  end if;
  if cardinality(p_ids) is null or cardinality(p_ids) = 0 then return jsonb_build_object('deleted', '[]'::jsonb, 'blocked', '[]'::jsonb); end if;
  if cardinality(p_ids) > 500 then raise exception 'at most 500 leads per delete'; end if;

  -- Money rows must survive: a lead with an enrollment can only be closed, never deleted (B6.1.4).
  -- A lead with a partner may be deleted only as junk, spam or a student request.
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'why',
           case when exists (select 1 from public.enrollments e where e.lead_id = l.id) then 'has an enrollment'
                else 'with a partner: use junk, spam or student request' end)), '[]')
    into v_blocked
    from public.student_leads l
   where l.id = any (p_ids) and l.deleted_at is null
     and (exists (select 1 from public.enrollments e where e.lead_id = l.id)
          or (l.destination_type = 'partner' and p_reason not in ('junk', 'spam', 'student request')));

  with upd as (
    update public.student_leads l
       set deleted_at = now(), updated_by = 'b2b'
     where l.id = any (p_ids) and l.deleted_at is null
       and not exists (select 1 from public.enrollments e where e.lead_id = l.id)
       and not (l.destination_type = 'partner' and p_reason not in ('junk', 'spam', 'student request'))
    returning l.id
  )
  select coalesce(array_agg(id), '{}') into v_done from upd;

  insert into b2b.lead_deletions (lead_id, action, reason, batch_id, actor_type, actor_id)
  select id, 'delete', p_reason, v_batch, v_a ->> 'type', v_a ->> 'id' from unnest(v_done) id;
  insert into b2b.events (type, lead_id, actor_type, actor_id, payload)
  select 'lead.deleted', id, v_a ->> 'type', v_a ->> 'id', jsonb_build_object('reason', p_reason, 'batch_id', v_batch) from unnest(v_done) id;

  return jsonb_build_object('deleted', to_jsonb(v_done), 'blocked', v_blocked, 'batch_id', v_batch);
end $$;

create or replace function b2b.leads_restore(p_ids bigint[])
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_batch   uuid := gen_random_uuid();
  v_a       jsonb := b2b.actor();
  v_blocked jsonb;
  v_done    bigint[];
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if cardinality(p_ids) is null or cardinality(p_ids) = 0 then return jsonb_build_object('restored', '[]'::jsonb, 'blocked', '[]'::jsonb); end if;
  if cardinality(p_ids) > 500 then raise exception 'at most 500 leads per restore'; end if;

  -- One open lead per phone: if the student came back after the delete, a newer lead already exists.
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'why', 'a newer lead with this phone exists')), '[]')
    into v_blocked
    from public.student_leads l
   where l.id = any (p_ids) and l.deleted_at is not null
     and exists (select 1 from public.student_leads o
                  where o.id <> l.id and o.deleted_at is null and o.merged_into_id is null
                    and regexp_replace(coalesce(o.whatsapp_number, ''), '\D', '', 'g') = regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'));

  with upd as (
    update public.student_leads l
       set deleted_at = null, updated_by = 'b2b'
     where l.id = any (p_ids) and l.deleted_at is not null
       and not exists (select 1 from public.student_leads o
                        where o.id <> l.id and o.deleted_at is null and o.merged_into_id is null
                          and regexp_replace(coalesce(o.whatsapp_number, ''), '\D', '', 'g') = regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'))
    returning l.id
  )
  select coalesce(array_agg(id), '{}') into v_done from upd;

  insert into b2b.lead_deletions (lead_id, action, reason, batch_id, actor_type, actor_id)
  select id, 'restore', null, v_batch, v_a ->> 'type', v_a ->> 'id' from unnest(v_done) id;
  insert into b2b.events (type, lead_id, actor_type, actor_id, payload)
  select 'lead.restored', id, v_a ->> 'type', v_a ->> 'id', jsonb_build_object('batch_id', v_batch) from unnest(v_done) id;

  return jsonb_build_object('restored', to_jsonb(v_done), 'blocked', v_blocked);
end $$;

-- ---------- export (audited) ----------
-- Same filters as the list, up to 10,000 rows; phone and email optionally masked. Every export is logged.
create or replace function b2b.leads_export(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_where  text;
  v_masked boolean := coalesce((p ->> 'masked')::boolean, false);
  v_rows   jsonb;
  v_a      jsonb := b2b.actor();
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  v_where := b2b.lead_filter_sql(p);
  execute format($q$
    select coalesce(jsonb_agg(r order by r.created_at desc), '[]'::jsonb) from (
      select l.id, l.created_at, l.student_name,
             case when %2$L::boolean then '******' || right(regexp_replace(coalesce(l.whatsapp_number, ''), '\D', '', 'g'), 4) else l.whatsapp_number end as phone,
             case when %2$L::boolean and position('@' in coalesce(l.email_id, '')) > 0 then left(l.email_id, 1) || '***@' || split_part(l.email_id, '@', 2) else l.email_id end as email,
             l.city, l.state, l.interested_course, l.interested_specialization, l.program_level, l.study_mode_preference,
             l.highest_qualification, l.lead_status, l.stage, l.lead_source, l.channel, l.campaign, l.utm_source, l.utm_medium, l.utm_campaign,
             l.destination_type, l.partner_id, l.consent_partner_share_at, l.last_activity_at,
             (coalesce(l.is_test, false) or b2b.is_test_phone(l.whatsapp_number)) as is_test
        from public.student_leads l
       where %1$s
       order by l.created_at desc
       limit 10000
    ) r
  $q$, v_where, v_masked) into v_rows;

  insert into b2b.lead_exports (actor_id, filters, row_count, masked) values (v_a ->> 'id', p, jsonb_array_length(v_rows), v_masked);
  perform b2b.log_event('leads.exported', null, null, null, jsonb_build_object('rows', jsonb_array_length(v_rows), 'masked', v_masked));
  return v_rows;
end $$;

-- ---------- privileges ----------
revoke execute on function b2b.is_test_phone(text), b2b.lead_filter_sql(jsonb) from public, anon, authenticated;
grant execute on function b2b.is_test_phone(text), b2b.lead_filter_sql(jsonb) to service_role;
revoke execute on function b2b.leads_list(jsonb), b2b.leads_facets(jsonb), b2b.lead_detail(bigint),
                           b2b.leads_soft_delete(bigint[], text), b2b.leads_restore(bigint[]), b2b.leads_export(jsonb)
  from public, anon;
grant execute on function b2b.leads_list(jsonb), b2b.leads_facets(jsonb), b2b.lead_detail(bigint),
                          b2b.leads_soft_delete(bigint[], text), b2b.leads_restore(bigint[]), b2b.leads_export(jsonb)
  to authenticated, service_role;
