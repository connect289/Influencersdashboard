-- Phase 2.3: admin creator CRM (spec 7). Staff create and edit creators, move them through the pipeline, log
-- outreach with follow-up dates, assign tasks, save filtered views, bulk-tag/assign/stage, and import prospects
-- from CSV with de-duplication. A nightly pass flags active creators dormant after N days without activity.

alter table inf.creators add column last_contacted_at timestamptz;
create index creators_search_trgm on inf.creators using gin ((display_name || ' ' || handle || ' ' || coalesce(email, '')) extensions.gin_trgm_ops);
create index creators_tags_idx on inf.creators using gin (tags);
create index creators_niches_idx on inf.creators using gin (niches);

-- ---------------------------------------------------------------------------------------------------------------
-- Outreach log
-- ---------------------------------------------------------------------------------------------------------------
create table inf.outreach_activities (
  id                 uuid primary key default gen_random_uuid(),
  creator_id         uuid not null references inf.creators (id) on delete cascade,
  channel            text not null check (channel in ('call', 'whatsapp', 'instagram_dm', 'email', 'meeting', 'note', 'other')),
  direction          text not null default 'outbound' check (direction in ('outbound', 'inbound')),
  outcome            text not null check (outcome in ('no_response', 'interested', 'not_interested', 'follow_up', 'negotiating', 'agreed', 'declined', 'info')),
  notes              text check (char_length(notes) <= 4000),
  next_follow_up_at  timestamptz,
  follow_up_done_at  timestamptz,
  created_by         uuid not null default auth.uid(),
  created_at         timestamptz not null default now()
);
create index outreach_creator_idx on inf.outreach_activities (creator_id, created_at desc);
create index outreach_follow_up_idx on inf.outreach_activities (next_follow_up_at) where next_follow_up_at is not null and follow_up_done_at is null;

-- ---------------------------------------------------------------------------------------------------------------
-- Tasks (staff work items, optionally about a creator or another record)
-- ---------------------------------------------------------------------------------------------------------------
create table inf.tasks (
  id            uuid primary key default gen_random_uuid(),
  title         text not null check (char_length(title) between 2 and 200),
  description   text check (char_length(description) <= 4000),
  assignee_id   uuid references inf.staff_profiles (user_id) on delete set null,
  due_at        timestamptz,
  priority      text not null default 'normal' check (priority in ('low', 'normal', 'high')),
  status        text not null default 'open' check (status in ('open', 'done', 'cancelled')),
  related_type  text check (related_type in ('creator', 'campaign', 'application', 'agency')),
  related_id    uuid,
  created_by    uuid not null default auth.uid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  completed_at  timestamptz,
  check ((related_type is null) = (related_id is null))
);
create index tasks_assignee_idx on inf.tasks (assignee_id, status, due_at);
create index tasks_related_idx on inf.tasks (related_type, related_id);

-- ---------------------------------------------------------------------------------------------------------------
-- Saved views (filters for the creators grid and kanban)
-- ---------------------------------------------------------------------------------------------------------------
create table inf.saved_views (
  id          uuid primary key default gen_random_uuid(),
  scope       text not null default 'creators' check (scope in ('creators')),
  name        text not null check (char_length(name) between 1 and 60),
  filters     jsonb not null check (jsonb_typeof(filters) = 'object' and pg_column_size(filters) < 4096),
  owner_id    uuid not null default auth.uid(),
  is_shared   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (owner_id, scope, name)
);

-- ---------------------------------------------------------------------------------------------------------------
-- CSV imports (summary and per-row report; rows themselves become creators)
-- ---------------------------------------------------------------------------------------------------------------
create table inf.creator_imports (
  id           uuid primary key default gen_random_uuid(),
  file_name    text not null check (char_length(file_name) <= 200),
  total        int not null,
  created      int not null,
  duplicates   int not null,
  errors       int not null,
  report       jsonb not null,
  created_by   uuid not null default auth.uid(),
  created_at   timestamptz not null default now()
);

create trigger tasks_touch before update on inf.tasks for each row execute function inf.touch_updated_at();
create trigger saved_views_touch before update on inf.saved_views for each row execute function inf.touch_updated_at();
create trigger outreach_audit after insert or update or delete on inf.outreach_activities for each row execute function inf.audit_row('outreach');
create trigger tasks_audit after insert or update or delete on inf.tasks for each row execute function inf.audit_row('task');
create trigger creator_imports_audit after insert on inf.creator_imports for each row execute function inf.audit_row('creator_import', 'report');

-- ---------------------------------------------------------------------------------------------------------------
-- Creator records (staff)
-- ---------------------------------------------------------------------------------------------------------------
-- Pipeline stage moves that also change the account status. Other stages leave status alone.
create or replace function inf.status_for_stage(p_stage text, p_status text) returns text
language sql immutable set search_path = '' as $$
  select case
    when p_stage = 'archived' then 'archived'
    when p_stage = 'paused' then case when p_status in ('active', 'paused') then 'paused' else p_status end
    when p_stage in ('active', 'dormant') and p_status = 'paused' then 'active'
    when p_status = 'archived' then 'prospect'
    else p_status end;
$$;

-- Create or update a creator (staff with creator.write). Returns the id. Handle, email and phone are unique.
create or replace function inf.creator_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id     uuid := nullif(p ->> 'id', '')::uuid;
  v_stage  text := coalesce(nullif(p ->> 'pipeline_stage', ''), 'prospect');
  v_tags   text[] := coalesce((select array_agg(distinct left(lower(trim(x)), 40)) from jsonb_array_elements_text(coalesce(p -> 'tags', '[]')) x where trim(x) <> ''), '{}');
  v_langs  text[] := coalesce((select array_agg(distinct left(trim(x), 40)) from jsonb_array_elements_text(coalesce(p -> 'languages', '[]')) x where trim(x) <> ''), '{}');
  v_niches text[] := coalesce((select array_agg(distinct left(lower(trim(x)), 40)) from jsonb_array_elements_text(coalesce(p -> 'niches', '[]')) x where trim(x) <> ''), '{}');
begin
  if not inf.has_perm('creator.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_id is null then
    insert into inf.creators (display_name, legal_name, handle, email, phone_e164, city, state, languages, niches, bio,
                              owner_id, tier_id, source, tags, pipeline_stage, status, created_by)
    values (trim(p ->> 'display_name'), nullif(trim(p ->> 'legal_name'), ''), lower(trim(p ->> 'handle')),
            nullif(lower(trim(p ->> 'email')), ''), nullif(trim(p ->> 'phone_e164'), ''), nullif(trim(p ->> 'city'), ''),
            nullif(trim(p ->> 'state'), ''), v_langs, v_niches, nullif(trim(p ->> 'bio'), ''),
            coalesce(nullif(p ->> 'owner_id', '')::uuid, auth.uid()), nullif(p ->> 'tier_id', '')::uuid,
            coalesce(nullif(trim(p ->> 'source'), ''), 'manual'), v_tags, v_stage, inf.status_for_stage(v_stage, 'prospect'), auth.uid())
    returning id into v_id;
  else
    update inf.creators set
      display_name = trim(p ->> 'display_name'), legal_name = nullif(trim(p ->> 'legal_name'), ''),
      handle = lower(trim(p ->> 'handle')), email = nullif(lower(trim(p ->> 'email')), ''),
      phone_e164 = nullif(trim(p ->> 'phone_e164'), ''), city = nullif(trim(p ->> 'city'), ''),
      state = nullif(trim(p ->> 'state'), ''), languages = v_langs, niches = v_niches, bio = nullif(trim(p ->> 'bio'), ''),
      owner_id = nullif(p ->> 'owner_id', '')::uuid, tier_id = nullif(p ->> 'tier_id', '')::uuid,
      source = nullif(trim(p ->> 'source'), ''), tags = v_tags
    where id = v_id;
    if not found then raise exception 'no such creator' using errcode = '22023'; end if;
  end if;
  return v_id;
end $$;

-- Move through the pipeline (kanban drag, bulk). Blocked creators can't move; "active" needs a linked account.
create or replace function inf.creator_set_stage(p_creator uuid, p_stage text) returns void
language plpgsql security definer set search_path = '' as $$
declare c inf.creators;
begin
  if not inf.has_perm('creator.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into c from inf.creators where id = p_creator for update;
  if c.id is null then raise exception 'no such creator' using errcode = '22023'; end if;
  if c.is_blocked then raise exception 'creator is blocked' using errcode = '22023'; end if;
  if p_stage in ('active', 'dormant', 'paused') and not exists (select 1 from inf.creator_accounts where creator_id = p_creator) then
    raise exception 'creator has not signed up yet' using errcode = '22023';
  end if;
  update inf.creators set pipeline_stage = p_stage, status = inf.status_for_stage(p_stage, c.status) where id = p_creator;
end $$;

create or replace function inf.creator_set_blocked(p_creator uuid, p_blocked boolean, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('creator.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_blocked and coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
  update inf.creators set is_blocked = p_blocked, blocked_reason = case when p_blocked then left(p_reason, 500) end,
         status = case when p_blocked then 'blocked' when status = 'blocked' then 'paused' else status end
   where id = p_creator;
  if not found then raise exception 'no such creator' using errcode = '22023'; end if;
  if p_blocked then
    update inf.user_sessions s set revoked_at = now(), revoked_by = auth.uid(), revoke_reason = 'creator blocked'
      from inf.creator_accounts a where a.creator_id = p_creator and s.user_id = a.user_id and s.revoked_at is null;
  end if;
  perform inf.audit('creator', p_creator::text, case when p_blocked then 'block' else 'unblock' end, null, jsonb_build_object('reason', p_reason));
end $$;

-- Only records nobody has engaged with yet (prospects without an account, outreach or tasks).
create or replace function inf.creator_delete_draft(p_creator uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('creator.delete_draft') then raise exception 'not allowed' using errcode = '42501'; end if;
  if exists (select 1 from inf.creator_accounts where creator_id = p_creator)
     or exists (select 1 from inf.creators where id = p_creator and status <> 'prospect')
     or exists (select 1 from inf.outreach_activities where creator_id = p_creator) then
    raise exception 'only untouched prospects can be deleted' using errcode = '22023';
  end if;
  delete from inf.creators where id = p_creator;
end $$;

-- Bulk actions on many creators. Returns how many changed.
create or replace function inf.creators_bulk(p_ids uuid[], p_action text, p_value text) returns int
language plpgsql security definer set search_path = '' as $$
declare v_n int := 0; v_id uuid;
begin
  if not inf.has_perm('creator.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if coalesce(array_length(p_ids, 1), 0) > 500 then raise exception 'at most 500 at a time' using errcode = '22023'; end if;
  case p_action
    when 'tag_add' then
      update inf.creators set tags = (select array_agg(distinct t) from unnest(tags || array[left(lower(trim(p_value)), 40)]) t)
       where id = any(p_ids) and not (left(lower(trim(p_value)), 40) = any(tags));
      get diagnostics v_n = row_count;
    when 'tag_remove' then
      update inf.creators set tags = array_remove(tags, lower(trim(p_value))) where id = any(p_ids) and lower(trim(p_value)) = any(tags);
      get diagnostics v_n = row_count;
    when 'owner' then
      if not exists (select 1 from inf.staff_profiles where user_id = p_value::uuid and status = 'active') then
        raise exception 'owner must be active staff' using errcode = '22023';
      end if;
      update inf.creators set owner_id = p_value::uuid where id = any(p_ids) and owner_id is distinct from p_value::uuid;
      get diagnostics v_n = row_count;
    when 'stage' then
      foreach v_id in array p_ids loop
        begin
          perform inf.creator_set_stage(v_id, p_value);
          v_n := v_n + 1;
        exception when sqlstate '22023' then null;  -- skip blocked / not signed up
        end;
      end loop;
    else raise exception 'unknown action' using errcode = '22023';
  end case;
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- List for the grid and kanban: filtered, sorted, paginated on the server. p keys (all optional):
--   q, status[], stage[], platform, followers_min, followers_max, niche, language, city, state, tier_id, owner_id
--   ('me' or uuid or 'none'), tag, follow_up ('overdue'|'today'), include_blocked, sort, dir, page, page_size
-- ---------------------------------------------------------------------------------------------------------------
-- Filtered rows (no sorting or paging); shared by the list and the kanban counts. Caller checks permission.
create or replace function inf.creator_rows(p jsonb) returns table (
  id uuid, display_name text, handle text, email text, status text, pipeline_stage text, is_blocked boolean,
  city text, state text, niches text[], languages text[], tags text[], owner_id uuid, tier_id uuid,
  updated_at timestamptz, last_activity_at timestamptz, last_contacted_at timestamptz, followers bigint,
  platforms text[], next_follow_up_at timestamptz, owner_name text, tier_name text, has_account boolean)
language sql stable security definer set search_path = '' as $$
  with stats as (
    select pl.creator_id, sum(coalesce(pl.followers, 0))::bigint as followers, array_agg(distinct pl.platform) as platforms
      from inf.creator_platforms pl group by pl.creator_id
  ), follow as (
    select o.creator_id, min(o.next_follow_up_at) as next_follow_up_at
      from inf.outreach_activities o where o.next_follow_up_at is not null and o.follow_up_done_at is null
     group by o.creator_id
  )
  select c.id, c.display_name, c.handle, c.email, c.status, c.pipeline_stage, c.is_blocked, c.city, c.state, c.niches,
         c.languages, c.tags, c.owner_id, c.tier_id, c.updated_at, c.last_activity_at, c.last_contacted_at,
         coalesce(s.followers, 0), coalesce(s.platforms, '{}'), f.next_follow_up_at, sp.full_name, t.name,
         exists (select 1 from inf.creator_accounts a where a.creator_id = c.id)
    from inf.creators c
    left join stats s on s.creator_id = c.id
    left join follow f on f.creator_id = c.id
    left join inf.staff_profiles sp on sp.user_id = c.owner_id
    left join inf.tiers t on t.id = c.tier_id
   where (coalesce((p ->> 'include_blocked')::boolean, false) or not c.is_blocked)
     and (nullif(trim(p ->> 'q'), '') is null
          or (c.display_name || ' ' || c.handle || ' ' || coalesce(c.email, '')) ilike '%' || replace(replace(replace(trim(p ->> 'q'), '\', '\\'), '%', '\%'), '_', '\_') || '%')
     and (coalesce(jsonb_array_length(p -> 'status'), 0) = 0 or c.status in (select jsonb_array_elements_text(p -> 'status')))
     and (coalesce(jsonb_array_length(p -> 'stage'), 0) = 0 or c.pipeline_stage in (select jsonb_array_elements_text(p -> 'stage')))
     and (nullif(p ->> 'platform', '') is null or (p ->> 'platform') = any(coalesce(s.platforms, '{}')))
     and (nullif(p ->> 'followers_min', '') is null or coalesce(s.followers, 0) >= (p ->> 'followers_min')::bigint)
     and (nullif(p ->> 'followers_max', '') is null or coalesce(s.followers, 0) <= (p ->> 'followers_max')::bigint)
     and (nullif(p ->> 'niche', '') is null or lower(p ->> 'niche') = any(c.niches))
     and (nullif(p ->> 'language', '') is null or exists (select 1 from unnest(c.languages) l where lower(l) = lower(p ->> 'language')))
     and (nullif(p ->> 'city', '') is null or lower(c.city) = lower(p ->> 'city'))
     and (nullif(p ->> 'state', '') is null or lower(c.state) = lower(p ->> 'state'))
     and (nullif(p ->> 'tier_id', '') is null or c.tier_id = (p ->> 'tier_id')::uuid)
     and (nullif(p ->> 'owner_id', '') is null
          or (p ->> 'owner_id' = 'me' and c.owner_id = auth.uid())
          or (p ->> 'owner_id' = 'none' and c.owner_id is null)
          or (p ->> 'owner_id' not in ('me', 'none') and c.owner_id::text = p ->> 'owner_id'))
     and (nullif(p ->> 'tag', '') is null or lower(p ->> 'tag') = any(c.tags))
     and (nullif(p ->> 'follow_up', '') is null
          or (p ->> 'follow_up' = 'overdue' and f.next_follow_up_at < now())
          or (p ->> 'follow_up' = 'today' and f.next_follow_up_at < (date_trunc('day', now() at time zone 'Asia/Kolkata') + interval '1 day') at time zone 'Asia/Kolkata'));
$$;

-- List for the grid and kanban: filtered, sorted, paginated on the server. p keys (all optional):
--   q, status[], stage[], platform, followers_min, followers_max, niche, language, city, state, tier_id, owner_id
--   ('me', 'none' or a uuid), tag, follow_up ('overdue'|'today'), include_blocked, sort, dir, page, page_size
create or replace function inf.creator_list(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_size int := least(greatest(coalesce((p ->> 'page_size')::int, 25), 1), 200);
  v_page int := greatest(coalesce((p ->> 'page')::int, 1), 1);
  v_sort text := coalesce(p ->> 'sort', 'updated');
  v_asc  boolean := p ->> 'dir' = 'asc';
  v_total bigint;
  v_rows jsonb;
begin
  if not inf.has_perm('creator.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_sort not in ('name', 'followers', 'updated', 'last_activity', 'stage', 'follow_up') then v_sort := 'updated'; end if;
  select count(*) into v_total from inf.creator_rows(p);
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v_rows from (
    select r.* from inf.creator_rows(p) r
     order by
       case when v_asc and v_sort = 'name' then lower(r.display_name) end asc,
       case when not v_asc and v_sort = 'name' then lower(r.display_name) end desc,
       case when v_asc and v_sort = 'followers' then r.followers end asc,
       case when not v_asc and v_sort = 'followers' then r.followers end desc,
       case when v_asc and v_sort = 'last_activity' then r.last_activity_at end asc nulls first,
       case when not v_asc and v_sort = 'last_activity' then r.last_activity_at end desc nulls last,
       case when v_asc and v_sort = 'stage' then r.pipeline_stage end asc,
       case when not v_asc and v_sort = 'stage' then r.pipeline_stage end desc,
       case when v_asc and v_sort = 'follow_up' then r.next_follow_up_at end asc nulls last,
       case when not v_asc and v_sort = 'follow_up' then r.next_follow_up_at end desc nulls last,
       case when v_asc and v_sort = 'updated' then r.updated_at end asc,
       case when not v_asc and v_sort = 'updated' then r.updated_at end desc,
       r.id
     limit v_size offset (v_page - 1) * v_size) x;
  return jsonb_build_object('total', v_total, 'page', v_page, 'page_size', v_size, 'rows', v_rows);
end $$;

-- Counts per pipeline stage for the kanban headers (same filters, ignoring the stage filter).
create or replace function inf.creator_stage_counts(p jsonb) returns table (stage text, n bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not inf.has_perm('creator.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  return query select r.pipeline_stage, count(*) from inf.creator_rows(p - 'stage') r group by 1;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Outreach
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.outreach_log(p_creator uuid, p_channel text, p_direction text, p_outcome text, p_notes text,
                                            p_next_follow_up timestamptz default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_stage text;
begin
  if not inf.has_perm('outreach.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_next_follow_up is not null and p_next_follow_up < now() - interval '1 day' then
    raise exception 'follow-up date is in the past' using errcode = '22023';
  end if;
  -- Logging new outreach closes earlier open follow-ups for this creator.
  update inf.outreach_activities set follow_up_done_at = now()
   where creator_id = p_creator and next_follow_up_at is not null and follow_up_done_at is null;
  insert into inf.outreach_activities (creator_id, channel, direction, outcome, notes, next_follow_up_at)
  values (p_creator, p_channel, coalesce(p_direction, 'outbound'), p_outcome, nullif(trim(p_notes), ''), p_next_follow_up)
  returning id into v_id;
  select pipeline_stage into v_stage from inf.creators where id = p_creator;
  update inf.creators set last_contacted_at = now(),
         pipeline_stage = case when v_stage = 'prospect' then 'contacted'
                               when v_stage in ('prospect', 'contacted') and p_outcome in ('negotiating', 'agreed') then 'negotiating'
                               else pipeline_stage end
   where id = p_creator;
  return v_id;
end $$;

create or replace function inf.follow_up_done(p_activity uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not inf.has_perm('outreach.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  update inf.outreach_activities set follow_up_done_at = now() where id = p_activity and follow_up_done_at is null;
end $$;

-- Overdue and due-today follow-ups for the widget (mine first, then everyone's for managers).
create or replace function inf.follow_ups_due(p_scope text default 'mine', p_limit int default 20)
returns table (activity_id uuid, creator_id uuid, display_name text, handle text, next_follow_up_at timestamptz,
               outcome text, notes text, owner_name text, overdue boolean)
language sql stable security definer set search_path = '' as $$
  select o.id, c.id, c.display_name, c.handle, o.next_follow_up_at, o.outcome, left(o.notes, 200), sp.full_name,
         o.next_follow_up_at < now()
    from inf.outreach_activities o
    join inf.creators c on c.id = o.creator_id
    left join inf.staff_profiles sp on sp.user_id = c.owner_id
   where inf.has_perm('creator.read') and o.follow_up_done_at is null and o.next_follow_up_at is not null
     and o.next_follow_up_at < (date_trunc('day', now() at time zone 'Asia/Kolkata') + interval '1 day') at time zone 'Asia/Kolkata'
     and (p_scope = 'all' or c.owner_id = auth.uid() or o.created_by = auth.uid())
   order by o.next_follow_up_at
   limit least(greatest(p_limit, 1), 100);
$$;

-- ---------------------------------------------------------------------------------------------------------------
-- Tasks
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.task_save(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id       uuid := nullif(p ->> 'id', '')::uuid;
  v_assignee uuid := nullif(p ->> 'assignee_id', '')::uuid;
  v_before   uuid;
  v_title    text := trim(p ->> 'title');
begin
  if not inf.has_perm('task.write') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_assignee is not null and not exists (select 1 from inf.staff_profiles where user_id = v_assignee and status = 'active') then
    raise exception 'assignee must be active staff' using errcode = '22023';
  end if;
  if v_id is null then
    insert into inf.tasks (title, description, assignee_id, due_at, priority, related_type, related_id)
    values (v_title, nullif(trim(p ->> 'description'), ''), v_assignee, nullif(p ->> 'due_at', '')::timestamptz,
            coalesce(nullif(p ->> 'priority', ''), 'normal'), nullif(p ->> 'related_type', ''), nullif(p ->> 'related_id', '')::uuid)
    returning id into v_id;
  else
    select assignee_id into v_before from inf.tasks where id = v_id;
    update inf.tasks set title = v_title, description = nullif(trim(p ->> 'description'), ''), assignee_id = v_assignee,
           due_at = nullif(p ->> 'due_at', '')::timestamptz, priority = coalesce(nullif(p ->> 'priority', ''), 'normal')
     where id = v_id;
    if not found then raise exception 'no such task' using errcode = '22023'; end if;
  end if;
  if v_assignee is not null and v_assignee <> auth.uid() and v_assignee is distinct from v_before then
    perform inf.notify(v_assignee, 'task.assigned', 'New task: ' || left(v_title, 120), null, '/admin/tasks',
                       jsonb_build_object('task_id', v_id), false, 'task_assigned:' || v_id || ':' || v_assignee);
  end if;
  return v_id;
end $$;

-- Assignees can complete their own tasks even without task.write.
create or replace function inf.task_set_status(p_task uuid, p_status text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not (inf.has_perm('task.write') or exists (select 1 from inf.tasks where id = p_task and assignee_id = auth.uid() and inf.is_staff())) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update inf.tasks set status = p_status, completed_at = case when p_status = 'done' then now() end where id = p_task;
  if not found then raise exception 'no such task' using errcode = '22023'; end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Saved views
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.saved_view_save(p_name text, p_filters jsonb, p_shared boolean) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not inf.has_perm('creator.read') then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into inf.saved_views (name, filters, is_shared) values (trim(p_name), p_filters, coalesce(p_shared, false))
  on conflict (owner_id, scope, name) do update set filters = excluded.filters, is_shared = excluded.is_shared
  returning id into v_id;
  return v_id;
end $$;

create or replace function inf.saved_view_delete(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from inf.saved_views where id = p_id and owner_id = auth.uid();
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- CSV import. The app parses and validates the file; this function de-duplicates against existing creators (handle,
-- email, phone, platform handle) and within the file, inserts the new prospects and stores the report.
-- p_rows: [{row, display_name, handle, email, phone_e164, city, state, niches[], languages[], tags[], platform,
--           platform_url, followers, source, owner_id}]
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.creator_import(p_file_name text, p_rows jsonb, p_invalid jsonb default '[]', p_dry_run boolean default true)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r        jsonb;
  v_report jsonb := coalesce(p_invalid, '[]'::jsonb);
  v_dupe   text;
  v_id     uuid;
  v_created int := 0; v_dupes int := 0;
  v_handles text[] := '{}'; v_emails text[] := '{}'; v_phones text[] := '{}';
  v_import uuid;
begin
  if not inf.has_perm('creator.import') then raise exception 'not allowed' using errcode = '42501'; end if;
  if jsonb_array_length(p_rows) > 5000 then raise exception 'at most 5000 rows per import' using errcode = '22023'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_dupe := case
      when lower(r ->> 'handle') = any(v_handles) then 'duplicate_in_file:handle'
      when nullif(lower(r ->> 'email'), '') = any(v_emails) then 'duplicate_in_file:email'
      when nullif(r ->> 'phone_e164', '') = any(v_phones) then 'duplicate_in_file:phone'
      when exists (select 1 from inf.creators where handle = lower(r ->> 'handle')) then 'existing:handle'
      when nullif(r ->> 'email', '') is not null and exists (select 1 from inf.creators where lower(email) = lower(r ->> 'email')) then 'existing:email'
      when nullif(r ->> 'phone_e164', '') is not null and exists (select 1 from inf.creators where phone_e164 = r ->> 'phone_e164') then 'existing:phone'
      when nullif(r ->> 'platform', '') is not null and exists (
        select 1 from inf.creator_platforms where platform = r ->> 'platform'
          and lower(handle) = lower(coalesce(nullif(r ->> 'platform_handle', ''), r ->> 'handle'))) then 'existing:platform_handle'
      end;
    v_handles := v_handles || lower(r ->> 'handle');
    if nullif(r ->> 'email', '') is not null then v_emails := v_emails || lower(r ->> 'email'); end if;
    if nullif(r ->> 'phone_e164', '') is not null then v_phones := v_phones || (r ->> 'phone_e164'); end if;
    if v_dupe is not null then
      v_dupes := v_dupes + 1;
      v_report := v_report || jsonb_build_array(jsonb_build_object('row', r -> 'row', 'handle', r ->> 'handle', 'result', 'duplicate', 'reason', v_dupe));
      continue;
    end if;
    v_created := v_created + 1;
    v_report := v_report || jsonb_build_array(jsonb_build_object('row', r -> 'row', 'handle', r ->> 'handle', 'result', 'created'));
    if not p_dry_run then
      insert into inf.creators (display_name, handle, email, phone_e164, city, state, niches, languages, tags, source, owner_id, created_by)
      values (r ->> 'display_name', lower(r ->> 'handle'), nullif(lower(r ->> 'email'), ''), nullif(r ->> 'phone_e164', ''),
              nullif(r ->> 'city', ''), nullif(r ->> 'state', ''),
              coalesce((select array_agg(lower(x)) from jsonb_array_elements_text(coalesce(r -> 'niches', '[]')) x), '{}'),
              coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(r -> 'languages', '[]')) x), '{}'),
              coalesce((select array_agg(lower(x)) from jsonb_array_elements_text(coalesce(r -> 'tags', '[]')) x), '{}'),
              coalesce(nullif(r ->> 'source', ''), 'import'), coalesce(nullif(r ->> 'owner_id', '')::uuid, auth.uid()), auth.uid())
      returning id into v_id;
      if nullif(r ->> 'platform', '') is not null and nullif(r ->> 'platform_url', '') is not null then
        insert into inf.creator_platforms (creator_id, platform, url, handle, followers, stats_updated_at)
        values (v_id, r ->> 'platform', r ->> 'platform_url', coalesce(nullif(r ->> 'platform_handle', ''), r ->> 'handle'),
                nullif(r ->> 'followers', '')::bigint, now());
      end if;
    end if;
  end loop;
  if not p_dry_run then
    insert into inf.creator_imports (file_name, total, created, duplicates, errors, report)
    values (left(p_file_name, 200), jsonb_array_length(p_rows) + jsonb_array_length(coalesce(p_invalid, '[]')), v_created, v_dupes,
            jsonb_array_length(coalesce(p_invalid, '[]')), v_report)
    returning id into v_import;
  end if;
  return jsonb_build_object('import_id', v_import, 'dry_run', p_dry_run, 'created', v_created, 'duplicates', v_dupes,
                            'errors', jsonb_array_length(coalesce(p_invalid, '[]')),
                            'report', (select coalesce(jsonb_agg(x order by (x ->> 'row')::int), '[]') from jsonb_array_elements(v_report) x));
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Dormancy: active creators with no activity for N days (setting creators.lifecycle.dormant_after_days). Creator
-- activity (any profile or portal action) moves them back to active.
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.creators_flag_dormant() returns int
language plpgsql security definer set search_path = '' as $$
declare v_days int := coalesce((inf.setting('creators.lifecycle') ->> 'dormant_after_days')::int, 45); v_n int;
begin
  update inf.creators set pipeline_stage = 'dormant'
   where pipeline_stage = 'active' and not is_blocked
     and coalesce(last_activity_at, created_at) < now() - make_interval(days => v_days);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function inf.creator_reactivate_on_activity() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.pipeline_stage = 'dormant' and new.last_activity_at is distinct from old.last_activity_at
     and new.last_activity_at > now() - interval '1 minute' then
    new.pipeline_stage := 'active';
  end if;
  return new;
end $$;
create trigger creators_reactivate before update of last_activity_at on inf.creators
  for each row execute function inf.creator_reactivate_on_activity();

-- Nightly housekeeping now also flags dormant creators (same inf-nightly job).
create or replace function inf.nightly_prune() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from inf.rate_hits where window_start < now() - interval '1 day';
  delete from inf.email_codes where created_at < now() - interval '7 days';
  delete from inf.trusted_devices where (revoked_at is not null or expires_at < now()) and created_at < now() - interval '90 days';
  update inf.user_sessions set revoked_at = now(), revoke_reason = 'expired'
   where revoked_at is null and last_seen_at < now() - interval '30 days';
  delete from inf.jobs where status in ('done', 'cancelled') and finished_at < now() - interval '30 days';
  perform inf.creators_flag_dormant();
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.outreach_activities enable row level security;
alter table inf.tasks enable row level security;
alter table inf.saved_views enable row level security;
alter table inf.creator_imports enable row level security;

create policy outreach_staff_read on inf.outreach_activities for select to authenticated using ((select inf.has_perm('creator.read')));
create policy tasks_read on inf.tasks for select to authenticated
  using ((select inf.has_perm('task.write')) or (assignee_id = (select auth.uid()) and (select inf.is_staff())));
create policy saved_views_read on inf.saved_views for select to authenticated
  using ((select inf.has_perm('creator.read')) and (owner_id = (select auth.uid()) or is_shared));
create policy creator_imports_read on inf.creator_imports for select to authenticated using ((select inf.has_perm('creator.import')));

insert into inf.client_grants (object_type, object_name, grantee, privilege) values
  ('table', 'inf.outreach_activities', 'authenticated', 'select'),
  ('table', 'inf.tasks', 'authenticated', 'select'),
  ('table', 'inf.saved_views', 'authenticated', 'select'),
  ('table', 'inf.creator_imports', 'authenticated', 'select'),
  ('function', 'inf.creator_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.creator_set_stage(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.creator_set_blocked(uuid, boolean, text)', 'authenticated', 'execute'),
  ('function', 'inf.creator_delete_draft(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.creators_bulk(uuid[], text, text)', 'authenticated', 'execute'),
  ('function', 'inf.creator_list(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.creator_stage_counts(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.outreach_log(uuid, text, text, text, text, timestamptz)', 'authenticated', 'execute'),
  ('function', 'inf.follow_up_done(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.follow_ups_due(text, int)', 'authenticated', 'execute'),
  ('function', 'inf.task_save(jsonb)', 'authenticated', 'execute'),
  ('function', 'inf.task_set_status(uuid, text)', 'authenticated', 'execute'),
  ('function', 'inf.saved_view_save(text, jsonb, boolean)', 'authenticated', 'execute'),
  ('function', 'inf.saved_view_delete(uuid)', 'authenticated', 'execute'),
  ('function', 'inf.creator_import(text, jsonb, jsonb, boolean)', 'authenticated', 'execute');
call inf.apply_client_grants();
