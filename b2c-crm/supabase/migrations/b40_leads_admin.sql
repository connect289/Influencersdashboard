-- B2C CRM b40: completing the leads table and the Admin's tools (docs/completion-gaps.md, section B, plus A9, D1, D2).
-- Staging first. Idempotent.
--   leads_wide_v           every lead property and sales activity in one row: the table's columns, filters, segments
--   lead_list()            any of those fields as a filter or sort; relative dates; group-by with totals; all ids of a view
--   views                  shared with the same role by link; each person's default view per interface
--   bulk                   journeys (Marketing too) and stage changes in bulk; bulk delete as a background job with typed
--                          confirmation and undo for 30 days
--   lead_erase()           the DPDP erasure request: personal fields anonymised, message bodies and documents removed,
--                          money rows kept, the B2B CRM told
--   exports                large exports in the background with an expiring link
--   events_feed()          the reconciliation feed of what Spark sent the B2B CRM (GET /v1/events?since=)
--   b2c_lead_status_v      the published read-only status of each B2C lead, for the B2B CRM

create index if not exists enrollments_lead on b2c.enrollments (lead_id);
create index if not exists emails_lead_dir on b2c.emails (lead_id, direction, created_at desc);
alter table b2c.leads_state add column if not exists erase_reference text;

-- ---------- one wide row per lead ----------
create or replace view b2c.leads_wide_v with (security_invoker = true) as
select v.*,
       coalesce(nullif(v.lead_created_at #>> '{}', '')::timestamptz, v.handed_off_at) as created_at,
       r.record -> 'interest' ->> 'enrollment_timeline' as timeline,
       nullif(regexp_replace(coalesce(r.record -> 'interest' ->> 'annual_budget_inr', ''), '[^0-9.]', '', 'g'), '')::numeric as budget,
       r.record -> 'education' ->> 'work_experience_years' as work_experience,
       s.partner_lost ->> 'partner_name' as partner,
       s.partner_lost ->> 'lost_reason' as partner_lost_reason,
       jsonb_array_length(coalesce(s.partners_tried, '[]')) as partners_tried_count,
       s.engagement_points, s.fit_points, s.delete_reason,
       c.calls_logged, c.calls_connected, c.last_call_outcome, c.last_call_at,
       w.wa_sent, w.wa_received, w.last_wa_in_at,
       m.emails_sent, m.emails_opened, m.last_email_at,
       rp.last_reply_at, rp.last_reply_class,
       floor(extract(epoch from now() - v.stage_changed_at) / 86400)::int as days_in_stage,
       floor(extract(epoch from now() - coalesce(v.last_activity_at, v.assigned_at, v.handed_off_at)) / 86400)::int as days_untouched,
       case when v.sla_breached_at is not null and v.sla_met_at is null then 'breached'
            when v.sla_met_at is not null then 'met'
            when v.sla_due_at is not null and v.sla_due_at < now() + interval '15 minutes' then 'at_risk'
            when v.sla_due_at is not null then 'running' end as sla_status,
       ap.application_status, ap.application_ref, ap.documents_pending,
       en.enrollment_status, en.enrolled_on, en.fee,
       mo.university_gross, mo.university_net, mo.university_gst, mo.university_status, mo.counsellor_commission
  from b2c.leads_v v
  join b2c.leads_state s on s.lead_id = v.lead_id
  left join b2c.lead_records r on r.lead_id = v.lead_id
  left join lateral (select count(*) filter (where k.logged_at is not null)::int calls_logged, count(*) filter (where k.outcome = 'connected')::int calls_connected,
                            (array_agg(k.outcome order by k.logged_at desc nulls last) filter (where k.logged_at is not null))[1] last_call_outcome,
                            max(k.logged_at) last_call_at
                       from b2c.calls k where k.lead_id = v.lead_id) c on true
  left join lateral (select count(*) filter (where x.direction = 'out')::int wa_sent, count(*) filter (where x.direction = 'in')::int wa_received,
                            max(x.created_at) filter (where x.direction = 'in') last_wa_in_at
                       from b2c.wa_messages x where x.lead_id = v.lead_id) w on true
  left join lateral (select count(*) filter (where x.direction = 'out')::int emails_sent, count(*) filter (where x.opened_at is not null)::int emails_opened,
                            max(x.created_at) last_email_at
                       from b2c.emails x where x.lead_id = v.lead_id) m on true
  left join lateral (select x.created_at last_reply_at, coalesce(x.corrected_class, x.class) last_reply_class
                       from b2c.replies x where x.lead_id = v.lead_id order by x.created_at desc limit 1) rp on true
  left join lateral (select a.status application_status, a.application_ref,
                            (select count(*) from jsonb_each_text(a.checklist) ck where ck.value <> 'received')::int documents_pending
                       from b2c.applications a where a.lead_id = v.lead_id order by a.created_at desc limit 1) ap on true
  left join lateral (select e.status enrollment_status, e.enrolled_on, e.fee from b2c.enrollments e where e.lead_id = v.lead_id order by e.created_at desc limit 1) en on true
  left join lateral (select sum(g.gross) university_gross, sum(g.net) university_net, sum(g.gst) university_gst,
                            case when count(g.id) = 0 then null when bool_and(g.invoice_id is not null) then 'invoiced' when bool_or(g.realised_at is not null) then 'realised' else 'expected' end university_status,
                            (select sum(l.amount) from b2c.commission_lines l where l.lead_id = v.lead_id and l.status <> 'void') counsellor_commission
                       from b2c.enrollments e2 join b2c.earnings g on g.enrollment_id = e2.id where e2.lead_id = v.lead_id) mo on true;
revoke all on b2c.leads_wide_v from public, anon, authenticated;
grant select on b2c.leads_wide_v to service_role;

/* Every field a view, a filter, a segment or a sort may use (B8.2, B9.1, B10.1). */
create or replace function b2c.lead_fields() returns text[] language sql immutable set search_path = '' as $f$
  select array['lead_id','name','phone','email','city','state','language','course','specialization','university','programme_level','study_mode',
    'qualification','source','campaign','lead_status','partner_consent_state','marketing_consent','opted_out','lane','status','handoff_reason','cause',
    'partner_bar_reason','owner_id','owner_name','assigned_at','stage_id','stage','canonical_stage','sub_stage','stage_changed_at','hot','temperature','score',
    'next_task_due_at','first_contacted_at','last_contacted_at','contact_attempts','last_activity_at','sla_due_at','sla_met_at','sla_breached_at',
    'pool_entered_at','pool_reason','journey','lost_by','reengaged_at','flagged','reenquired_at','tags','is_test','handed_off_at','updated_at','closed_at',
    'created_at','timeline','budget','work_experience','partner','partner_lost_reason','partners_tried_count','engagement_points','fit_points',
    'calls_logged','calls_connected','last_call_outcome','last_call_at','wa_sent','wa_received','last_wa_in_at','emails_sent','emails_opened','last_email_at',
    'last_reply_at','last_reply_class','days_in_stage','days_untouched','sla_status','application_status','application_ref','documents_pending',
    'enrollment_status','enrolled_on','fee','university_gross','university_net','university_gst','university_status','counsellor_commission']
$f$;

/* The money columns: Admin and Marketing only (B10.1, B11). */
create or replace function b2c.money_fields() returns text[] language sql immutable set search_path = '' as $f$
  select array['university_gross','university_net','university_gst','university_status','counsellor_commission']
$f$;

create or replace function b2c.segment_fields() returns text[] language sql immutable set search_path = '' as $f$
  select b2c.lead_fields()
$f$;

/* One condition as SQL. Fields and operators are whitelisted; values are quoted. Relative dates in India time. */
create or replace function b2c.filter_sql(c jsonb, allowed text[]) returns text language plpgsql stable set search_path = '' as $f$
declare fld text := c ->> 'field'; op text := c ->> 'op'; val jsonb := c -> 'value'; d0 text := '(date_trunc(''day'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata'')';
begin
  if not fld = any (allowed) then raise exception 'cannot filter on %', fld; end if;
  return case op
    when 'eq' then format('%I::text = %L', fld, val #>> '{}')
    when 'neq' then format('%I::text is distinct from %L', fld, val #>> '{}')
    when 'in' then format('%I::text = any (%L::text[])', fld, (select array_agg(x) from jsonb_array_elements_text(val) x))
    when 'not_in' then format('not coalesce(%I::text = any (%L::text[]), false)', fld, (select array_agg(x) from jsonb_array_elements_text(val) x))
    when 'contains' then format('%I::text ilike %L', fld, '%' || (val #>> '{}') || '%')
    when 'gte' then format('%I >= %L', fld, val #>> '{}')
    when 'lte' then format('%I <= %L', fld, val #>> '{}')
    when 'gt' then format('%I > %L', fld, val #>> '{}')
    when 'lt' then format('%I < %L', fld, val #>> '{}')
    when 'between' then format('%I between %L and %L', fld, val ->> 0, val ->> 1)
    when 'is_null' then format('%I is null', fld)
    when 'not_null' then format('%I is not null', fld)
    when 'is_true' then format('%I is true', fld)
    when 'is_false' then format('%I is not true', fld)
    when 'lte_now' then format('%I <= now()', fld)
    when 'older_than_days' then format('%I < now() - make_interval(days => %s)', fld, (val #>> '{}')::int)
    when 'within_days' then format('%I >= now() - make_interval(days => %s)', fld, (val #>> '{}')::int)
    when 'next_days' then format('%I >= now() and %I < now() + make_interval(days => %s)', fld, fld, (val #>> '{}')::int)
    when 'today' then format('%I >= %s and %I < %s + interval ''1 day''', fld, d0, fld, d0)
    when 'this_week' then format('%I >= date_trunc(''week'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld)
    when 'this_month' then format('%I >= date_trunc(''month'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld)
    when 'last_month' then format('%I >= (date_trunc(''month'', now() at time zone ''Asia/Kolkata'') - interval ''1 month'') at time zone ''Asia/Kolkata'' and %I < date_trunc(''month'', now() at time zone ''Asia/Kolkata'') at time zone ''Asia/Kolkata''', fld, fld)
    when 'has_tag' then format('%L = any (tags)', val #>> '{}')
    when 'not_tag' then format('not (%L = any (coalesce(tags, ''{}'')))', val #>> '{}')
    else 'false' end;
end $f$;

/* Segments, journey conditions and filters read the wide row too. */
create or replace function b2c.segment_leads(p_segment bigint, p_filters jsonb default null, p_test boolean default false) returns setof bigint
language plpgsql stable security definer set search_path = '' as $f$
declare g b2c.segments;
begin
  if p_segment is not null then select * into g from b2c.segments where id = p_segment; end if;
  if g.kind = 'static' then
    return query select m.lead_id from b2c.segment_members m join b2c.leads_state s on s.lead_id = m.lead_id
                  where m.segment_id = g.id and m.removed_at is null and s.deleted_at is null and s.is_test = p_test;
  else
    return query execute format('select v.lead_id from b2c.leads_wide_v v where v.deleted_at is null and v.is_test = %L and %s',
                                p_test, b2c.filters_where(coalesce(p_filters, g.filters, '{}')));
  end if;
end $f$;

create or replace function b2c.lead_matches(p_lead bigint, p_filters jsonb) returns boolean language plpgsql stable security definer set search_path = '' as $f$
declare v boolean;
begin
  execute format('select exists (select 1 from b2c.leads_wide_v v where v.lead_id = %s and %s)', p_lead, b2c.filters_where(p_filters)) into v;
  return v;
end $f$;

create or replace function b2c.filter_leads(p_filters jsonb, p_test boolean default false) returns setof bigint
language plpgsql stable security definer set search_path = '' as $f$
begin
  return query execute format('select v.lead_id from b2c.leads_wide_v v where v.deleted_at is null and v.is_test = %L and %s', p_test, b2c.filters_where(coalesce(p_filters, '{}')));
end $f$;

/* Who sees which leads in lists: a counsellor their own; the sales head their team (b42 narrows it); everyone else all. */
create or replace function b2c.lead_scope_sql(p_user uuid, p_role text) returns text language plpgsql stable security definer set search_path = '' as $f$
begin
  return case p_role when 'counsellor' then format('owner_id = %L', p_user) else 'true' end;
end $f$;

/* Filtered, sorted, paged lead list for a view (B8.2, B10.1), on the wide row. Also: p.ids (selected rows only),
   p.mode = 'ids' (every id of the view, for "select all"), p.group_by (counts and totals over the whole view).
   lead_list_as() is the same list for a named person: the background export runs it for the Admin who asked. */
create or replace function b2c.lead_list(p jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  return b2c.lead_list_as(p, b2c.uid(), b2c.my_role());
end $f$;

create or replace function b2c.lead_list_as(p jsonb, p_user uuid, p_role text) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare
  v_role text := p_role; me uuid := p_user; w text;
  v_test_user boolean := coalesce((select u.is_test_user from b2c.users u where u.user_id = p_user), false); c jsonb; v_sql text; v_rows jsonb; v_total int;
  v_any text; f jsonb := coalesce(p -> 'filters', '{}'); v_sort text; v_dir text; v_limit int := least(coalesce((p ->> 'limit')::int, 50), 500); v_offset int := greatest(coalesce((p ->> 'offset')::int, 0), 0);
  allowed text[] := b2c.lead_fields(); v_drill bigint[]; v_group text; v_groups jsonb; v_ids bigint[]; v_strip text[];
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_role not in ('admin', 'marketing') then allowed := array(select x from unnest(allowed) x where not x = any (b2c.money_fields())); end if;
  w := b2c.lead_scope_sql(me, v_role);
  if nullif(p ->> 'drill', '') is not null then
    select lead_ids into v_drill from b2c.analytics_drills where id = (p ->> 'drill')::uuid and user_id = me;
    w := w || format(' and lead_id = any (%L::bigint[])', coalesce(v_drill, '{}'));
  end if;
  if jsonb_typeof(p -> 'ids') = 'array' then
    w := w || format(' and lead_id = any (%L::bigint[])', (select coalesce(array_agg(x::bigint), '{}') from jsonb_array_elements_text(p -> 'ids') x));
  end if;
  w := w || case when coalesce((p ->> 'deleted')::boolean, false)
                 then ' and deleted_at is not null and not exists (select 1 from b2c.leads_state z where z.lead_id = v.lead_id and z.erased_at is not null)'
                 else ' and deleted_at is null' end;
  if not coalesce((p ->> 'include_test')::boolean, v_role = 'admin' or v_drill is not null or v_test_user) then w := w || ' and not is_test'; end if;
  for c in select * from jsonb_array_elements(coalesce(f -> 'all', '[]')) loop
    w := w || ' and ' || b2c.filter_sql(c, allowed);
  end loop;
  if jsonb_array_length(coalesce(f -> 'any', '[]')) > 0 then
    select string_agg(b2c.filter_sql(x, allowed), ' or ') into v_any from jsonb_array_elements(f -> 'any') x;
    w := w || ' and (' || v_any || ')';
  end if;
  -- AND/OR groups: {"groups": [{"any": [...]}, {"all": [...]}]} each group is one bracket
  for c in select * from jsonb_array_elements(coalesce(f -> 'groups', '[]')) loop
    if jsonb_array_length(coalesce(c -> 'any', '[]')) > 0 then
      select string_agg(b2c.filter_sql(x, allowed), ' or ') into v_any from jsonb_array_elements(c -> 'any') x;
      w := w || ' and (' || v_any || ')';
    end if;
    if jsonb_array_length(coalesce(c -> 'all', '[]')) > 0 then
      select string_agg(b2c.filter_sql(x, allowed), ' and ') into v_any from jsonb_array_elements(c -> 'all') x;
      w := w || ' and (' || v_any || ')';
    end if;
  end loop;
  if coalesce(trim(p ->> 'search'), '') <> '' then
    w := w || format(' and (name ilike %1$L or email ilike %1$L or b2c.norm_phone(phone) like %2$L or lead_id::text = %3$L
                       or exists (select 1 from b2c.lead_contacts lc where lc.lead_id = v.lead_id and lc.value_norm like %2$L)
                       or exists (select 1 from b2c.applications ap where ap.lead_id = v.lead_id and ap.application_ref ilike %1$L))',
                     '%' || trim(p ->> 'search') || '%', '%' || coalesce(nullif(regexp_replace(p ->> 'search', '\D', '', 'g'), ''), '~none~') || '%', trim(p ->> 'search'));
  end if;
  if p ->> 'mode' = 'ids' then
    execute format('select array_agg(lead_id order by lead_id) from (select lead_id from b2c.leads_wide_v v where %s limit 20001) q', w) into v_ids;
    if coalesce(array_length(v_ids, 1), 0) > 20000 then raise exception 'more than 20,000 leads: narrow the view first'; end if;
    return jsonb_build_object('total', coalesce(array_length(v_ids, 1), 0), 'ids', coalesce(to_jsonb(v_ids), '[]'));
  end if;
  v_sort := coalesce(p -> 'sort' ->> 'field', 'next_task_due_at');
  if not v_sort = any (allowed) then v_sort := 'next_task_due_at'; end if;
  v_dir := case when lower(coalesce(p -> 'sort' ->> 'dir', 'asc')) = 'desc' then 'desc' else 'asc' end;
  v_strip := case when v_role in ('admin', 'marketing') then '{}'::text[] else b2c.money_fields() end;
  v_sql := format('select count(*) over () total, to_jsonb(v) - ''providers'' - ''handling'' - %L::text[] as row from b2c.leads_wide_v v where %s order by %I %s nulls last, lead_id desc limit %s offset %s',
                  v_strip, w, v_sort, v_dir, v_limit, v_offset);
  execute format('select coalesce(max(total), 0), coalesce(jsonb_agg(row), ''[]'') from (%s) q', v_sql) into v_total, v_rows;
  v_group := nullif(p ->> 'group_by', '');
  if v_group is not null then
    if not v_group = any (allowed) then raise exception 'cannot group by %', v_group; end if;
    execute format('select coalesce(jsonb_agg(jsonb_build_object(''key'', k, ''count'', n, ''expected'', x, ''commission'', y) order by n desc), ''[]'') from (
                      select %I::text k, count(*) n, sum(coalesce(university_gross, 0)) x, sum(coalesce(counsellor_commission, 0)) y
                        from b2c.leads_wide_v v where %s group by 1 order by 2 desc limit 100) g', v_group, w) into v_groups;
    if v_role not in ('admin', 'marketing') then
      select coalesce(jsonb_agg(gx - 'expected' - 'commission'), '[]') into v_groups from jsonb_array_elements(v_groups) gx;
    end if;
  end if;
  return jsonb_build_object('total', v_total, 'rows', v_rows) || case when v_group is not null then jsonb_build_object('groups', v_groups, 'group_by', v_group) else '{}'::jsonb end;
end $f$;

-- ---------- views: shared by link, a default per person (B8.2) ----------
create table if not exists b2c.view_defaults (
  user_id uuid not null references b2c.users (user_id),
  role text not null check (role in ('sales', 'workspace')),
  view_id bigint not null references b2c.saved_views (id),
  set_at timestamptz not null default now(),
  primary key (user_id, role)
);
alter table b2c.view_defaults enable row level security;

/* The views a person may open on an interface: their own, the standard ones, and those shared with their role. */
create or replace function b2c.views_list(p_role text) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v_role text := b2c.my_role();
begin
  if v_role is null then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'default', (select view_id from b2c.view_defaults where user_id = me and role = p_role),
    'views', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'filters', v.filters, 'columns', v.columns, 'sort', v.sort, 'group_by', v.group_by,
                     'layout', v.layout, 'is_standard', v.is_standard, 'shared_with_role', v.shared_with_role, 'mine', v.owner_id = me,
                     'owner', (select full_name from b2c.users u where u.user_id = v.owner_id)) order by v.is_standard desc, v.position, v.name), '[]')
                from b2c.saved_views v
               where v.hidden_at is null and coalesce(v.role, 'sales') = p_role
                 and (v.owner_id = me or v.is_standard or (v.shared_with_role is not null and v.shared_with_role = v_role))));
end $f$;

/* Opening a view by link: only if it is the person's, standard, or shared with their role. */
create or replace function b2c.view_get(p_id bigint) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v b2c.saved_views;
begin
  select * into v from b2c.saved_views where id = p_id and hidden_at is null;
  if v.id is null or not (v.owner_id = me or v.is_standard or (v.shared_with_role is not null and v.shared_with_role = b2c.my_role())) then
    raise exception 'this view is not shared with you' using errcode = '42501';
  end if;
  return to_jsonb(v) || jsonb_build_object('mine', v.owner_id = me);
end $f$;

create or replace function b2c.view_pin(p_role text, p_view bigint) returns void language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid();
begin
  if b2c.my_role() is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_view is null then delete from b2c.view_defaults where user_id = me and role = p_role; return; end if;
  perform b2c.view_get(p_view);
  insert into b2c.view_defaults (user_id, role, view_id) values (me, p_role, p_view)
  on conflict (user_id, role) do update set view_id = excluded.view_id, set_at = now();
end $f$;

/* view_save (b13): a view can be shared with a role (the owner's own role only) and carries its columns and group-by. */
create or replace function b2c.view_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v bigint := nullif(p ->> 'id', '')::bigint; v_std boolean := coalesce((p ->> 'is_standard')::boolean, false);
        v_name text := nullif(trim(p ->> 'name'), ''); v_cols jsonb := p -> 'columns';
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_std and b2c.my_role() <> 'admin' then raise exception 'only the Admin publishes standard views'; end if;
  if v is null and (v_name is null or length(v_name) > 60) then raise exception 'name the view (at most 60 characters)'; end if;
  if coalesce(p ->> 'role', 'sales') not in ('sales', 'workspace') then raise exception 'unknown interface'; end if;
  if nullif(p ->> 'shared_with_role', '') is not null and p ->> 'shared_with_role' <> b2c.my_role() then raise exception 'a view can be shared with your own role only'; end if;
  if v_cols is not null and (jsonb_typeof(v_cols) <> 'array' or exists (select 1 from jsonb_array_elements_text(v_cols) x where not x = any (b2c.lead_fields()))) then
    raise exception 'unknown column';
  end if;
  if p ? 'filters' or p ? 'sort' or p ? 'group_by' then
    perform b2c.lead_list(jsonb_build_object('filters', coalesce(p -> 'filters', '{}'), 'sort', p -> 'sort', 'limit', 1, 'group_by', p ->> 'group_by'));
  end if;
  if v is null then
    insert into b2c.saved_views (owner_id, role, name, filters, columns, sort, group_by, layout, is_standard, is_default, shared_with_role, position)
    values (case when v_std then null else me end, coalesce(p ->> 'role', 'sales'), v_name, coalesce(p -> 'filters', '{}'), coalesce(v_cols, '[]'),
            coalesce(p -> 'sort', '{"field":"next_task_due_at","dir":"asc"}'), nullif(p ->> 'group_by', ''), coalesce(p ->> 'layout', 'list'), v_std,
            coalesce((p ->> 'is_default')::boolean, false), nullif(p ->> 'shared_with_role', ''), case when v_std then 50 else 100 end)
    returning id into v;
  else
    update b2c.saved_views set name = coalesce(v_name, name), filters = coalesce(p -> 'filters', filters), columns = coalesce(v_cols, columns),
           sort = coalesce(p -> 'sort', sort), group_by = case when p ? 'group_by' then nullif(p ->> 'group_by', '') else group_by end, layout = coalesce(p ->> 'layout', layout),
           is_default = coalesce((p ->> 'is_default')::boolean, is_default),
           shared_with_role = case when p ? 'shared_with_role' then nullif(p ->> 'shared_with_role', '') else shared_with_role end,
           hidden_at = case when p ? 'hidden' then case when (p ->> 'hidden')::boolean then now() end else hidden_at end, updated_at = now()
     where id = v and (owner_id = me or (is_standard and b2c.my_role() = 'admin'));
    if not found then raise exception 'only your own views can be changed'; end if;
  end if;
  return v;
end $f$;

-- ---------- bulk actions (B10.3) ----------
/* Add to a journey or take out of one (Marketing too). Each lead is checked as if done alone. */
create or replace function b2c.bulk_journey(p_leads bigint[], p_action text, p_journey bigint default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare l bigint; n int := 0; refused jsonb := '[]'::jsonb; me uuid := b2c.require('journey_membership');
begin
  if p_action not in ('add', 'remove') then raise exception 'add or remove'; end if;
  if coalesce(cardinality(p_leads), 0) = 0 then raise exception 'tick at least one lead'; end if;
  if cardinality(p_leads) > 5000 then raise exception 'at most 5,000 leads at a time'; end if;
  if p_action = 'add' and not exists (select 1 from b2c.journeys where id = p_journey and current_version > 0 and status <> 'archived') then raise exception 'choose a published journey'; end if;
  foreach l in array p_leads loop
    begin
      if p_action = 'add' then
        if exists (select 1 from b2c.leads_state s where s.lead_id = l and s.status = 'active' and s.owner_id is not null)
           and not (select allow_active_sales from b2c.journeys where id = p_journey) then
          raise exception 'in active sales';
        end if;
        perform b2c.journey_lead(l, 'start', p_journey);
      else
        if b2c.journey_exit(l, 'removed by ' || coalesce(b2c.my_role(), 'staff')) = 0 then raise exception 'not in a journey'; end if;
      end if;
      n := n + 1;
    exception when others then
      refused := refused || jsonb_build_object('lead_id', l, 'why', sqlerrm);
    end;
  end loop;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'bulk_journey', jsonb_build_object('action', p_action, 'journey', p_journey, 'done', n, 'refused', jsonb_array_length(refused)));
  return jsonb_build_object('done', n, 'refused', refused);
end $f$;

/* Change stage for many (Admin), under the stage rules; the sub-stage and comment apply to all. */
create or replace function b2c.bulk_stage(p_leads bigint[], p_stage smallint, p_sub text, p_comment text default null, p_next_due timestamptz default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare l bigint; n int := 0; refused jsonb := '[]'::jsonb; me uuid := b2c.require('settings');
begin
  if coalesce(cardinality(p_leads), 0) = 0 then raise exception 'tick at least one lead'; end if;
  if cardinality(p_leads) > 1000 then raise exception 'at most 1,000 leads at a time'; end if;
  foreach l in array p_leads loop
    begin
      perform b2c.set_stage(l, p_stage, p_sub, p_comment, coalesce(p_next_due, case when p_stage not in (9, 10) then now() + interval '1 day' end));
      n := n + 1;
    exception when others then
      refused := refused || jsonb_build_object('lead_id', l, 'why', sqlerrm);
    end;
  end loop;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'bulk_stage', jsonb_build_object('stage', p_stage, 'sub_stage', p_sub, 'done', n, 'refused', jsonb_array_length(refused)));
  return jsonb_build_object('done', n, 'refused', refused);
end $f$;

/* Bulk delete as a background job (B10.4): typed confirmation, then the minute timer works through it; undo for 30 days. */
create table if not exists b2c.bulk_jobs (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('delete')),
  lead_ids bigint[] not null,
  params jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued', 'running', 'done', 'undone', 'failed')),
  done_count int not null default 0,
  result jsonb not null default '{}'::jsonb,
  created_by uuid,
  created_at timestamptz not null default now(),
  done_at timestamptz,
  undone_at timestamptz
);
alter table b2c.bulk_jobs enable row level security;

create or replace function b2c.lead_delete_request(p_leads bigint[], p_reason text, p_confirm text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v bigint; n int := coalesce(cardinality(p_leads), 0);
begin
  if n = 0 then raise exception 'tick at least one lead'; end if;
  if n > 20000 then raise exception 'at most 20,000 leads at a time'; end if;
  if p_reason not in ('junk', 'test', 'duplicate entry', 'spam', 'student request') then raise exception 'choose a reason: junk, test, duplicate entry, spam or student request'; end if;
  if coalesce(trim(p_confirm), '') <> 'DELETE ' || n then raise exception 'type DELETE % to confirm', n; end if;
  insert into b2c.bulk_jobs (kind, lead_ids, params, created_by) values ('delete', p_leads, jsonb_build_object('reason', p_reason), me) returning id into v;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'bulk_delete_requested', jsonb_build_object('job', v, 'leads', n, 'reason', p_reason));
  return jsonb_build_object('job_id', v, 'leads', n);
end $f$;

create or replace function b2c.bulk_jobs_tick(p_batch int default 500) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare j b2c.bulk_jobs; v_part bigint[]; r jsonb; n int := 0;
begin
  for j in select * from b2c.bulk_jobs where status in ('queued', 'running') order by id limit 5 for update skip locked loop
    v_part := j.lead_ids[j.done_count + 1 : j.done_count + p_batch];
    if coalesce(cardinality(v_part), 0) = 0 then
      update b2c.bulk_jobs set status = 'done', done_at = now() where id = j.id;
      perform b2c.notify(j.created_by, 'bulk_job', 'Bulk delete finished', (j.result ->> 'deleted') || ' deleted, ' || coalesce(j.result ->> 'kept', '0') || ' kept',
                         '/w/leads?deleted=1', null, 'bulkjob:' || j.id);
      continue;
    end if;
    r := b2c.lead_delete_job_part(v_part, j.params ->> 'reason', j.created_by, j.id);
    update b2c.bulk_jobs set status = 'running', done_count = done_count + cardinality(v_part),
           result = jsonb_build_object('deleted', coalesce((result ->> 'deleted')::int, 0) + (r ->> 'deleted')::int,
                                       'kept', coalesce((result ->> 'kept')::int, 0) + jsonb_array_length(r -> 'kept'),
                                       'kept_leads', coalesce(result -> 'kept_leads', '[]'::jsonb) || (r -> 'kept'))
     where id = j.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('jobs', n);
end $f$;

/* One part of a delete job (the same rules as lead_delete: leads with an enrolment are kept). */
create or replace function b2c.lead_delete_job_part(p_leads bigint[], p_reason text, p_actor uuid, p_job bigint) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v bigint; n int := 0; v_kept jsonb := '[]'::jsonb;
begin
  foreach v in array p_leads loop
    if exists (select 1 from b2c.enrollments e where e.lead_id = v and e.status in ('reported', 'verified')) then
      v_kept := v_kept || jsonb_build_object('lead_id', v, 'why', 'has an enrolment: close it instead'); continue;
    end if;
    update b2c.leads_state set deleted_at = now(), delete_reason = p_reason, journey = null, updated_at = now() where lead_id = v and deleted_at is null;
    if found then
      perform b2c.journey_exit(v, 'deleted');
      update b2c.tasks set status = 'cancelled', done_at = now(), outcome = 'deleted' where lead_id = v and status = 'open';
      update b2c.send_queue set status = 'cancelled' where lead_id = v and status = 'queued';
      insert into b2c.audit_log (actor_id, action, lead_id, detail) values (p_actor, 'delete', v, jsonb_build_object('reason', p_reason, 'job', p_job));
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('deleted', n, 'kept', v_kept);
end $f$;

create or replace function b2c.bulk_job_undo(p_job bigint) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); j b2c.bulk_jobs; n int;
begin
  select * into j from b2c.bulk_jobs where id = p_job for update;
  if j.id is null or j.kind <> 'delete' or j.status not in ('done', 'running') then raise exception 'this job cannot be undone'; end if;
  if j.created_at < now() - interval '30 days' then raise exception 'undo is possible for 30 days'; end if;
  update b2c.leads_state set deleted_at = null, delete_reason = null, updated_at = now()
   where lead_id = any (j.lead_ids) and deleted_at is not null and erased_at is null;
  get diagnostics n = row_count;
  update b2c.bulk_jobs set status = 'undone', undone_at = now() where id = p_job;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'restore', jsonb_build_object('job', p_job, 'restored', n));
  return n;
end $f$;

create or replace function b2c.bulk_jobs_list() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  perform b2c.require('settings');
  return (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'kind', j.kind, 'leads', cardinality(j.lead_ids), 'reason', j.params ->> 'reason', 'status', j.status,
            'done_count', j.done_count, 'result', j.result - 'kept_leads', 'by', u.full_name, 'created_at', j.created_at, 'done_at', j.done_at,
            'undo_until', case when j.status in ('done', 'running') then j.created_at + interval '30 days' end) order by j.id desc), '[]')
            from (select * from b2c.bulk_jobs order by id desc limit 50) j left join b2c.users u on u.user_id = j.created_by);
end $f$;

-- ---------- student erasure (B10.4, B18) ----------
create table if not exists b2c.erase_files (
  id bigint generated always as identity primary key,
  lead_id bigint not null,
  bucket text not null,
  path text not null,
  created_at timestamptz not null default now(),
  attempts int not null default 0,
  removed_at timestamptz,
  error text
);
alter table b2c.erase_files enable row level security;

/* The Admin erases a student on request: personal fields anonymised, message bodies and documents removed, money rows
   kept by id, the B2B CRM told (b2ccrm.erasure_requested), logged with the request reference. Cannot be undone. */
create or replace function b2c.lead_erase(p_lead bigint, p_reference text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); s b2c.leads_state; n_msg int; n_doc int;
begin
  if b2c.my_role() is distinct from 'admin' then raise exception 'not allowed' using errcode = '42501'; end if;
  if length(coalesce(trim(p_reference), '')) < 3 then raise exception 'give the request reference (the email or ticket the student used)'; end if;
  select * into s from b2c.leads_state where lead_id = p_lead for update;
  if s.lead_id is null then raise exception 'unknown lead'; end if;
  if s.erased_at is not null then raise exception 'this lead was already erased'; end if;
  -- the record: identity and contact gone; programme interest and source kept for the numbers
  update b2c.lead_records set record = jsonb_strip_nulls(jsonb_build_object(
           'id', record -> 'id', 'is_test', record -> 'is_test', 'held_by_b2c', record -> 'held_by_b2c', 'contract_version', record -> 'contract_version',
           'student', jsonb_build_object('name', 'Erased student', 'erased', true),
           'interest', (record -> 'interest') - 'notes', 'source', record -> 'source', 'created_at', record -> 'created_at',
           'consent', jsonb_build_object('state', record -> 'consent' ->> 'state', 'opted_out', true))), received_at = now()
   where lead_id = p_lead;
  perform set_config('b2c.trusted', 'on', true);
  update b2c.lead_contacts set value = 'erased', value_norm = 'erased:' || id, removed_at = coalesce(removed_at, now()) where lead_id = p_lead;
  perform set_config('b2c.trusted', 'off', true);
  update b2c.wa_messages set body = null, media = null where lead_id = p_lead;
  get diagnostics n_msg = row_count;
  update b2c.emails set subject = '[erased]', snippet = null, from_address = case when direction = 'in' then 'erased' else from_address end,
         to_address = case when direction = 'out' then 'erased' else to_address end where lead_id = p_lead;
  update b2c.activities set body = '[erased]' where lead_id = p_lead and kind in ('whatsapp', 'email', 'note', 'call', 'reenquiry', 'partner_history', 'correction');
  update b2c.calls set note = null, number = 'erased', from_number = null where lead_id = p_lead;
  update b2c.replies set text = null where lead_id = p_lead;
  update b2c.field_history set old_value = null, new_value = null where lead_id = p_lead;
  update b2c.wa_conversations set phone = 'erased:' || p_lead where lead_id = p_lead;
  delete from b2c.lead_briefs where lead_id = p_lead;
  update b2c.fact_leads set city = null, state = null, deleted = true where lead_id = p_lead;
  -- files go through the storage API (the app's erase job), never by deleting rows
  insert into b2c.erase_files (lead_id, bucket, path)
  select p_lead, 'b2c-documents', d.storage_path from b2c.documents d where d.lead_id = p_lead and d.removed_at is null
  union all select p_lead, 'b2c-recordings', c.recording_path from b2c.calls c where c.lead_id = p_lead and c.recording_path is not null;
  get diagnostics n_doc = row_count;
  update b2c.documents set removed_at = now(), file_name = null where lead_id = p_lead;
  update b2c.calls set recording_path = null, recording_url = null, recording_status = case when recording_status = 'stored' then 'deleted' else recording_status end where lead_id = p_lead;
  update b2c.send_queue set status = 'cancelled' where lead_id = p_lead and status = 'queued';
  perform b2c.journey_exit(p_lead, 'erased');
  update b2c.tasks set status = 'cancelled', done_at = now(), outcome = 'erased' where lead_id = p_lead and status = 'open';
  update b2c.leads_state set erased_at = now(), erase_reference = left(trim(p_reference), 200), deleted_at = coalesce(deleted_at, now()),
         delete_reason = 'student request', tags = '{}', stage_comment = null, missing = '[]', partner_lost = null, partners_tried = '[]', updated_at = now()
   where lead_id = p_lead;
  perform b2c.queue_event('b2ccrm.erasure_requested', p_lead, jsonb_build_object('reference', left(trim(p_reference), 200), 'note', left(p_note, 300)), true);
  insert into b2c.audit_log (actor_id, action, lead_id, detail) values (me, 'erase', p_lead, jsonb_build_object('reference', p_reference, 'note', p_note, 'messages', n_msg, 'files', n_doc));
  insert into b2c.activities (lead_id, kind, body, actor_id) values (p_lead, 'system', 'Erased on the student''s request (' || left(trim(p_reference), 100) || ')', me);
  return jsonb_build_object('erased', true, 'messages', n_msg, 'files', n_doc);
end $f$;

create or replace function b2c.erase_files_take(p_limit int default 20) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  with t as (select id from b2c.erase_files where removed_at is null and attempts < 6 order by id limit p_limit for update skip locked),
       m as (update b2c.erase_files f set attempts = f.attempts + 1 from t where f.id = t.id returning f.id, f.bucket, f.path)
  select coalesce(jsonb_agg(to_jsonb(m)), '[]') into v from m;
  return v;
end $f$;

create or replace function b2c.erase_file_done(p_id bigint, p_error text default null) returns void language sql security definer set search_path = '' as $f$
  update b2c.erase_files set removed_at = case when p_error is null then now() end, error = left(p_error, 300) where id = p_id
$f$;

/* The record cache (b3): an erased lead's record is never filled again from the B2B CRM. */
create or replace function b2c.apply_record(p_lead bigint, p_version int, p_seq bigint, p_record jsonb, p_origin text default null)
returns boolean language plpgsql security definer set search_path = '' as $f$
declare v_cur int; v_phone text; v_email text; v_test boolean;
begin
  if p_record is null or p_lead is null then return false; end if;
  if exists (select 1 from b2c.leads_state z where z.lead_id = p_lead and z.erased_at is not null) then
    update b2c.lead_records set version = greatest(version, coalesce(p_version, 0)), seq = p_seq where lead_id = p_lead;
    return false;
  end if;
  select version into v_cur from b2c.lead_records where lead_id = p_lead for update;
  if v_cur is not null and v_cur >= coalesce(p_version, 0) then return false; end if;
  v_phone := p_record -> 'student' ->> 'phone';
  v_email := lower(nullif(trim(p_record -> 'student' ->> 'email'), ''));
  v_test := coalesce((p_record ->> 'is_test')::boolean, false) or b2c.is_test_phone(v_phone);
  insert into b2c.lead_records (lead_id, version, seq, record, held_by_b2c, is_test, deleted, merged_into_id, origin, received_at)
  values (p_lead, coalesce(p_version, 0), p_seq, p_record, coalesce((p_record ->> 'held_by_b2c')::boolean, false), v_test,
          coalesce((p_record ->> 'deleted')::boolean, false), nullif(p_record ->> 'merged_into_id', '')::bigint, p_origin, now())
  on conflict (lead_id) do update set version = excluded.version, seq = excluded.seq, record = excluded.record,
         held_by_b2c = excluded.held_by_b2c, is_test = excluded.is_test, deleted = excluded.deleted,
         merged_into_id = excluded.merged_into_id, origin = excluded.origin, received_at = now();
  perform set_config('b2c.trusted', 'on', true);
  if v_phone is not null and b2c.norm_phone(v_phone) is not null then
    insert into b2c.lead_contacts (lead_id, kind, value, value_norm, label, origin, primary_call, primary_wa)
    select p_lead, 'phone', v_phone, b2c.norm_phone(v_phone), 'intake', 'intake',
           not exists (select 1 from b2c.lead_contacts c where c.lead_id = p_lead and c.primary_call and c.removed_at is null),
           not exists (select 1 from b2c.lead_contacts c where c.lead_id = p_lead and c.primary_wa and c.removed_at is null)
    on conflict (lead_id, kind, value_norm) do update set origin = 'intake', label = 'intake';
  end if;
  if v_email is not null then
    insert into b2c.lead_contacts (lead_id, kind, value, value_norm, label, origin, primary_email)
    select p_lead, 'email', v_email, v_email, 'intake', 'intake',
           not exists (select 1 from b2c.lead_contacts c where c.lead_id = p_lead and c.primary_email and c.removed_at is null)
    on conflict (lead_id, kind, value_norm) do update set origin = 'intake', label = 'intake';
  end if;
  perform set_config('b2c.trusted', 'off', true);
  update b2c.leads_state set is_test = v_test, updated_at = now() where lead_id = p_lead and is_test is distinct from v_test;
  return true;
end $f$;

/* Restoring never brings an erased lead back. */
create or replace function b2c.lead_restore(p_leads bigint[]) returns int language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); n int;
begin
  update b2c.leads_state set deleted_at = null, delete_reason = null, updated_at = now()
   where lead_id = any (p_leads) and deleted_at > now() - interval '30 days' and erased_at is null;
  get diagnostics n = row_count;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'restore', jsonb_build_object('leads', p_leads));
  return n;
end $f$;

-- ---------- exports (B10.5) ----------
create table if not exists b2c.exports (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  params jsonb not null,                     -- {filters, sort, search, columns, ids, include_test}
  format text not null default 'csv' check (format in ('csv', 'xlsx')),
  status text not null default 'queued' check (status in ('queued', 'running', 'ready', 'failed', 'expired')),
  rows int,
  path text,
  error text,
  attempts int not null default 0,
  created_at timestamptz not null default now(),
  done_at timestamptz,
  expires_at timestamptz
);
alter table b2c.exports enable row level security;

/* The Admin asks for an export: how many rows it holds, and a background job when it is over 10,000 rows. */
create or replace function b2c.export_request(p jsonb) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.require('settings'); v_n int; v bigint; v_fmt text := coalesce(p ->> 'format', 'csv');
begin
  if v_fmt not in ('csv', 'xlsx') then raise exception 'CSV or Excel'; end if;
  v_n := (b2c.lead_list(jsonb_build_object('filters', coalesce(p -> 'filters', '{}'), 'search', p ->> 'search', 'ids', p -> 'ids',
                                           'include_test', p -> 'include_test', 'limit', 1)) ->> 'total')::int;
  if v_n <= 10000 then return jsonb_build_object('inline', true, 'rows', v_n); end if;
  insert into b2c.exports (user_id, params, format) values (me, p - 'format', v_fmt) returning id into v;
  insert into b2c.audit_log (actor_id, action, detail) values (me, 'export', jsonb_build_object('job', v, 'rows', v_n, 'format', v_fmt, 'filters', p -> 'filters', 'columns', p -> 'columns'));
  return jsonb_build_object('inline', false, 'job_id', v, 'rows', v_n);
end $f$;

create or replace function b2c.export_take(p_limit int default 2) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v jsonb;
begin
  update b2c.exports set status = 'expired', path = null where status = 'ready' and expires_at < now();
  with t as (select id from b2c.exports where status = 'queued' and attempts < 3 order by id limit p_limit for update skip locked),
       m as (update b2c.exports e set status = 'running', attempts = e.attempts + 1 from t where e.id = t.id returning e.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'user_id', m.user_id, 'params', m.params, 'format', m.format)), '[]') into v from m;
  return v;
end $f$;

/* The export job runs the view as the person who asked for it (so the same scope and columns apply). */
create or replace function b2c.export_page(p_export bigint, p_offset int, p_limit int default 1000) returns jsonb language plpgsql security definer set search_path = '' as $f$
declare x b2c.exports; v_role text;
begin
  select * into x from b2c.exports where id = p_export and status = 'running';
  if x.id is null then raise exception 'unknown export'; end if;
  select role into v_role from b2c.users where user_id = x.user_id and is_active;
  if v_role is distinct from 'admin' then raise exception 'the person who asked can no longer export'; end if;
  return b2c.lead_list_as(x.params || jsonb_build_object('limit', least(p_limit, 500), 'offset', p_offset), x.user_id, v_role);
end $f$;

create or replace function b2c.export_done(p_export bigint, p_rows int, p_path text, p_error text default null) returns void language plpgsql security definer set search_path = '' as $f$
declare x b2c.exports;
begin
  update b2c.exports set status = case when p_error is null then 'ready' when attempts >= 3 then 'failed' else 'queued' end, rows = p_rows, path = p_path,
         error = left(p_error, 300), done_at = now(), expires_at = case when p_error is null then now() + interval '7 days' end
   where id = p_export returning * into x;
  if p_error is null then
    perform b2c.notify(x.user_id, 'export', 'Your export is ready', p_rows || ' rows. The link works for 7 days.', '/w/leads?exports=1', null, 'export:' || p_export);
  end if;
end $f$;

create or replace function b2c.exports_mine() returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'format', format, 'status', status, 'rows', rows, 'created_at', created_at, 'expires_at', expires_at, 'error', error) order by id desc), '[]')
    from (select * from b2c.exports where user_id = b2c.uid() order by id desc limit 20) x
$f$;

/* The path of a ready export, for a signed link (the app), logged. */
create or replace function b2c.export_open(p_export bigint) returns text language plpgsql security definer set search_path = '' as $f$
declare x b2c.exports;
begin
  perform b2c.require('settings');
  select * into x from b2c.exports where id = p_export and user_id = b2c.uid();
  if x.id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  if x.status <> 'ready' or x.expires_at < now() then raise exception 'this export is no longer available'; end if;
  insert into b2c.audit_log (actor_id, action, detail) values (b2c.uid(), 'export_download', jsonb_build_object('export', p_export, 'rows', x.rows));
  return x.path;
end $f$;

-- ---------- what Spark sent the B2B CRM, for its reconciliation (B17: GET /v1/events?since=) ----------
create or replace function b2c.events_feed(p_after bigint default 0, p_limit int default 200) returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v jsonb; v_last bigint;
begin
  select coalesce(jsonb_agg(jsonb_build_object('seq', o.id, 'event_id', o.body ->> 'event_id', 'type', o.body ->> 'type', 'lead_id', o.lead_id,
           'occurred_at', o.occurred_at, 'data', o.body -> 'data', 'delivery', o.status) order by o.id), '[]'), max(o.id)
    into v, v_last
    from (select * from b2c.outbox where kind = 'event' and id > coalesce(p_after, 0) order by id limit least(greatest(coalesce(p_limit, 200), 1), 1000)) o;
  return jsonb_build_object('events', v, 'next_after', coalesce(v_last, p_after));
end $f$;

-- ---------- the published lead status (B14, B17), for the B2B CRM ----------
create or replace view public.b2c_lead_status_v as
select 1 as view_version,
       s.lead_id, s.lane, s.status, st.name as stage, s.sub_stage, st.canon as canonical_stage, s.stage_changed_at,
       u.full_name as counsellor, u.email as counsellor_email, s.assigned_at, s.pool_reason, s.journey, s.reengaged_at, s.reengage_trigger,
       s.closed_at, s.closed_reason, s.routing_requested_at, s.is_test, s.updated_at
  from b2c.leads_state s
  left join b2c.stages st on st.id = s.stage_id
  left join b2c.users u on u.user_id = s.owner_id
 where s.deleted_at is null;
revoke all on public.b2c_lead_status_v from public, anon, authenticated;
grant select on public.b2c_lead_status_v to service_role;

-- ---------- timers ----------
do $d$
begin
  if not exists (select 1 from cron.job where jobname = 'b2c-jobs') then
    perform cron.schedule('b2c-jobs', '* * * * *', 'select b2c.bulk_jobs_tick()');
  end if;
end $d$;

-- ---------- grants ----------
grant execute on function b2c.views_list(text), b2c.view_get(bigint), b2c.view_pin(text, bigint), b2c.bulk_journey(bigint[], text, bigint),
  b2c.bulk_stage(bigint[], smallint, text, text, timestamptz), b2c.lead_delete_request(bigint[], text, text), b2c.bulk_job_undo(bigint), b2c.bulk_jobs_list(),
  b2c.lead_erase(bigint, text, text), b2c.export_request(jsonb), b2c.exports_mine(), b2c.export_open(bigint) to authenticated;
grant execute on function b2c.erase_files_take(integer), b2c.erase_file_done(bigint, text), b2c.export_take(integer), b2c.export_page(bigint, integer, integer),
  b2c.export_done(bigint, integer, text, text), b2c.events_feed(bigint, integer), b2c.bulk_jobs_tick(integer) to service_role;
revoke execute on function b2c.erase_files_take(integer), b2c.erase_file_done(bigint, text), b2c.export_take(integer), b2c.export_page(bigint, integer, integer),
  b2c.export_done(bigint, integer, text, text), b2c.events_feed(bigint, integer), b2c.bulk_jobs_tick(integer), b2c.lead_delete_job_part(bigint[], text, uuid, bigint),
  b2c.lead_fields(), b2c.money_fields(), b2c.lead_scope_sql(uuid, text), b2c.lead_list_as(jsonb, uuid, text), b2c.lead_matches(bigint, jsonb), b2c.filter_leads(jsonb, boolean) from public, authenticated;
grant all on all tables in schema b2c to service_role;
revoke execute on all functions in schema b2c from public, anon;
