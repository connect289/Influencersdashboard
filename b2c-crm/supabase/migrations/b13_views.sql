-- B2C CRM b13: the custom view builder (spec B8.4). A person's own view can be hidden (their "remove"); standard views
-- are the Admin's. Views are checked by running them once, so a view that cannot run is never saved.
alter table b2c.saved_views add column if not exists hidden_at timestamptz;

create or replace function b2c.view_save(p jsonb) returns bigint language plpgsql security definer set search_path = '' as $f$
declare me uuid := b2c.uid(); v bigint := nullif(p ->> 'id', '')::bigint; v_std boolean := coalesce((p ->> 'is_standard')::boolean, false);
        v_name text := nullif(trim(p ->> 'name'), '');
begin
  if not b2c.is_staff() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_std and b2c.my_role() <> 'admin' then raise exception 'only the Admin publishes standard views'; end if;
  if v is null and (v_name is null or length(v_name) > 60) then raise exception 'name the view (at most 60 characters)'; end if;
  if coalesce(p ->> 'role', 'sales') not in ('sales', 'workspace') then raise exception 'unknown interface'; end if;
  if p ? 'filters' or p ? 'sort' then
    perform b2c.lead_list(jsonb_build_object('filters', coalesce(p -> 'filters', '{}'), 'sort', p -> 'sort', 'limit', 1));
  end if;
  if v is null then
    insert into b2c.saved_views (owner_id, role, name, filters, columns, sort, group_by, layout, is_standard, is_default, shared_with_role, position)
    values (case when v_std then null else me end, coalesce(p ->> 'role', 'sales'), v_name, coalesce(p -> 'filters', '{}'), coalesce(p -> 'columns', '[]'),
            coalesce(p -> 'sort', '{"field":"next_task_due_at","dir":"asc"}'), p ->> 'group_by', coalesce(p ->> 'layout', 'list'), v_std,
            coalesce((p ->> 'is_default')::boolean, false), p ->> 'shared_with_role', case when v_std then 50 else 100 end)
    returning id into v;
  else
    update b2c.saved_views set name = coalesce(v_name, name), filters = coalesce(p -> 'filters', filters), columns = coalesce(p -> 'columns', columns),
           sort = coalesce(p -> 'sort', sort), group_by = case when p ? 'group_by' then p ->> 'group_by' else group_by end, layout = coalesce(p ->> 'layout', layout),
           is_default = coalesce((p ->> 'is_default')::boolean, is_default),
           shared_with_role = case when p ? 'shared_with_role' then p ->> 'shared_with_role' else shared_with_role end,
           hidden_at = case when p ? 'hidden' then case when (p ->> 'hidden')::boolean then now() end else hidden_at end, updated_at = now()
     where id = v and (owner_id = me or (is_standard and b2c.my_role() = 'admin'));
    if not found then raise exception 'only your own views can be changed'; end if;
  end if;
  return v;
end $f$;
grant execute on function b2c.view_save(jsonb) to authenticated;
revoke execute on all functions in schema b2c from public, anon;
