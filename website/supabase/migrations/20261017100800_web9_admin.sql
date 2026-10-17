-- web9 · Admin back end (spec 11): allow-listed content editing with an audit row for every change, dashboards for the
-- lead funnels, Witty insights, data quality and the outbox. Programme data itself is never edited here (shared
-- catalogue). All functions are service-role only; the website checks the staff session and role before calling them,
-- and the functions check the role again.

-- Editable entities: table, key columns, editable columns, minimum role, cache tags to revalidate, delete allowed.
create table if not exists public.web_admin_entities (
  entity text primary key,
  tbl text not null,
  key_cols text[] not null,
  cols text[] not null,
  min_role text not null default 'content_editor' check (min_role in ('viewer', 'content_editor', 'super_admin')),
  tags text[] not null default '{content}',
  can_delete boolean not null default true,
  order_by text not null default '1'
);
alter table public.web_admin_entities enable row level security;
revoke all on public.web_admin_entities from anon, authenticated, public;
grant select on public.web_admin_entities to service_role;

insert into public.web_admin_entities (entity, tbl, key_cols, cols, min_role, tags, can_delete, order_by) values
  ('testimonials', 'web_testimonials', '{id}', '{name,detail,quote,rating,photo_path,source,consent_confirmed,published,sort}', 'content_editor', '{content}', true, 'sort, id'),
  ('faqs', 'web_faqs', '{id}', '{scope,question,answer,sort,published}', 'content_editor', '{content}', true, 'scope, sort, id'),
  ('authors', 'web_authors', '{id}', '{name,role,bio,photo_path,active}', 'content_editor', '{content}', false, 'name'),
  ('resources', 'web_resources', '{slug}', '{slug,title,summary,body,author_id,reviewer_id,status,published_at,refresh_due_at,tags,seo_title,seo_description}', 'content_editor', '{content}', true, 'updated_at desc'),
  ('popular_searches', 'web_popular_searches', '{id}', '{label,href,sort,active}', 'content_editor', '{content}', true, 'sort, id'),
  ('curated_views', 'web_curated_views', '{slug}', '{slug,title,h1,intro,filters,faqs,seo_description,status,sort}', 'content_editor', '{content}', true, 'sort, slug'),
  ('university_profiles', 'web_university_profiles', '{catalog_university_id}', '{display_name,logo_path,logo_permitted,state,city,website_url,about,published}', 'content_editor', '{catalog,content}', false, 'display_name'),
  ('pages', 'web_pages', '{path}', '{path,title,description,og_image,noindex}', 'content_editor', '{pages}', true, 'path'),
  ('redirects', 'web_redirects', '{from_path}', '{from_path,to_path,code,source}', 'content_editor', '{redirects}', true, 'created_at desc'),
  ('legal_pages', 'web_legal_pages', '{slug}', '{title,body,status,source_url,reviewed_by}', 'super_admin', '{content}', false, 'slug'),
  ('consent_texts', 'web_consent_texts', '{version}', '{version,channel,body,purposes,active,legal_reviewed_at}', 'super_admin', '{content}', false, 'created_at desc'),
  ('synonyms', 'web_tax_synonyms', '{id}', '{alias,kind,target_id,weight,source}', 'content_editor', '{catalog}', true, 'alias')
on conflict (entity) do update set tbl = excluded.tbl, key_cols = excluded.key_cols, cols = excluded.cols, min_role = excluded.min_role,
  tags = excluded.tags, can_delete = excluded.can_delete, order_by = excluded.order_by;

create or replace function public.web_admin_role_ok(p_role text, p_min text)
returns boolean language sql immutable as $$
  select (case p_role when 'super_admin' then 3 when 'content_editor' then 2 when 'viewer' then 1 else 0 end)
      >= (case p_min when 'super_admin' then 3 when 'content_editor' then 2 when 'viewer' then 1 else 9 end)
$$;

create or replace function public.web_admin_list(p_entity text, p_search text default null, p_limit int default 100, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare e public.web_admin_entities; v jsonb;
begin
  select * into e from public.web_admin_entities where entity = p_entity;
  if e.entity is null then raise exception 'unknown entity %', p_entity; end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]'') from (select * from public.%I x where $1 is null or x::text ilike ''%%'' || $1 || ''%%'' order by %s limit $2 offset $3) t',
    e.tbl, e.order_by)
    into v using nullif(btrim(p_search), ''), least(greatest(p_limit, 1), 500), greatest(p_offset, 0);
  return jsonb_build_object('rows', v, 'key', to_jsonb(e.key_cols), 'cols', to_jsonb(e.cols), 'can_delete', e.can_delete, 'min_role', e.min_role);
end $$;

create or replace function public.web_admin_get(p_entity text, p_key jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare e public.web_admin_entities; v jsonb; w text;
begin
  select * into e from public.web_admin_entities where entity = p_entity;
  if e.entity is null then raise exception 'unknown entity %', p_entity; end if;
  select string_agg(format('%I::text = %L', k, p_key->>k), ' and ') into w from unnest(e.key_cols) k;
  execute format('select to_jsonb(t) from public.%I t where %s', e.tbl, w) into v;
  return v;
end $$;

-- Insert or update one row (only allow-listed columns), with an audit row. Returns the saved row and the tags to revalidate.
create or replace function public.web_admin_save(p_entity text, p_row jsonb, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  e public.web_admin_entities; v_cols text[]; v_where text; v_before jsonb; v_after jsonb; v_has_key boolean; v_id text;
begin
  select * into e from public.web_admin_entities where entity = p_entity;
  if e.entity is null then return jsonb_build_object('ok', false, 'error', 'unknown_entity'); end if;
  if not public.web_admin_role_ok(p_role, e.min_role) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  -- Content rules the tables cannot express alone.
  if p_entity = 'testimonials' and coalesce((p_row->>'published')::boolean, false) and not coalesce((p_row->>'consent_confirmed')::boolean, false) then
    return jsonb_build_object('ok', false, 'error', 'Testimonials can be published only after the student agreed to be quoted.');
  end if;
  if p_entity = 'resources' and p_row->>'status' = 'published' and (p_row->>'author_id' is null or p_row->>'reviewer_id' is null) then
    return jsonb_build_object('ok', false, 'error', 'Every guide needs a named author and reviewer before publishing.');
  end if;
  if p_entity = 'consent_texts' and exists (select 1 from public.web_consent_texts where version = p_row->>'version') then
    -- consent texts are versioned: an existing version can only be (de)activated or marked reviewed, never reworded
    if (select body from public.web_consent_texts where version = p_row->>'version') is distinct from p_row->>'body' then
      return jsonb_build_object('ok', false, 'error', 'Accepted consent texts cannot be reworded. Create a new version instead.');
    end if;
  end if;

  select array_agg(c) into v_cols from unnest(e.cols) c where p_row ? c;
  v_has_key := (select bool_and(p_row ? k and p_row->>k is not null) from unnest(e.key_cols) k);
  if v_has_key then
    select string_agg(format('t.%I::text = %L', k, p_row->>k), ' and ') into v_where from unnest(e.key_cols) k;
    execute format('select to_jsonb(t) from public.%I t where %s', e.tbl, v_where) into v_before;
  end if;
  if v_before is not null then
    if v_cols is null then return jsonb_build_object('ok', false, 'error', 'nothing_to_save'); end if;
    execute format('update public.%I t set %s %s from jsonb_populate_record(null::public.%I, $1) r where %s returning to_jsonb(t)',
      e.tbl,
      (select string_agg(format('%I = r.%I', c, c), ', ') from unnest(v_cols) c),
      case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = e.tbl and column_name = 'updated_at') then ', updated_at = now()' else '' end,
      e.tbl, v_where)
      into v_after using p_row;
  else
    v_cols := array(select distinct c from unnest(coalesce(v_cols, '{}') || case when v_has_key then e.key_cols else '{}' end) c);
    execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1) r returning to_jsonb(%I.*)',
      e.tbl, (select string_agg(format('%I', c), ', ') from unnest(v_cols) c), (select string_agg(format('r.%I', c), ', ') from unnest(v_cols) c), e.tbl, e.tbl)
      into v_after using p_row;
  end if;
  v_id := (select string_agg(v_after->>k, ':') from unnest(e.key_cols) k);
  insert into public.web_audit_log (actor, actor_email, action, entity, entity_id, before, after)
  values (p_actor, p_actor_email, case when v_before is null then 'create' else 'update' end, p_entity, v_id, v_before, v_after);
  return jsonb_build_object('ok', true, 'row', v_after, 'tags', to_jsonb(e.tags), 'id', v_id);
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end $$;

create or replace function public.web_admin_delete(p_entity text, p_key jsonb, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare e public.web_admin_entities; v_where text; v_before jsonb;
begin
  select * into e from public.web_admin_entities where entity = p_entity;
  if e.entity is null or not e.can_delete then return jsonb_build_object('ok', false, 'error', 'not_deletable'); end if;
  if not public.web_admin_role_ok(p_role, e.min_role) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select string_agg(format('t.%I::text = %L', k, p_key->>k), ' and ') into v_where from unnest(e.key_cols) k;
  execute format('delete from public.%I t where %s returning to_jsonb(t)', e.tbl, v_where) into v_before;
  if v_before is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  insert into public.web_audit_log (actor, actor_email, action, entity, entity_id, before)
  values (p_actor, p_actor_email, 'delete', p_entity, (select string_agg(p_key->>k, ':') from unnest(e.key_cols) k), v_before);
  return jsonb_build_object('ok', true, 'tags', to_jsonb(e.tags));
end $$;

-- Feature flags and settings through the admin, audited (web_settings_set already keeps the history).
insert into public.web_settings (key, value) values ('application_form', '{"hidden": [], "optional": []}')
on conflict (key) do nothing;

create or replace function public.web_admin_setting(p_key text, p_value jsonb, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
begin
  if not public.web_admin_role_ok(p_role, case when p_key in ('web_advisor_enabled', 'require_phone_otp', 'push_unverified_gate_leads', 'document_upload_enabled', 'lead_writer', 'web_advisor_models', 'web_advisor_budget') then 'super_admin' else 'content_editor' end) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  -- web_settings_set keeps the history and writes the audit row.
  perform public.web_settings_set(p_key, p_value, p_actor, p_actor_email);
  return jsonb_build_object('ok', true);
end $$;

-- Dashboard counts.
create or replace function public.web_admin_overview()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'leads_today', (select count(*) from public.web_lead_submissions where kind like '%.verified' and created_at > date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
    'leads_7d', (select count(*) from public.web_lead_submissions where kind like '%.verified' and created_at > now() - interval '7 days'),
    'applications_7d', (select count(*) from public.web_applications where status = 'submitted' and submitted_at > now() - interval '7 days'),
    'chats_7d', (select count(*) from public.web_advisor_sessions where turns > 0 and created_at > now() - interval '7 days'),
    'outbox_dead', (select count(*) from public.web_outbox where status = 'dead'),
    'outbox_pending', (select count(*) from public.web_outbox where status in ('pending', 'processing')),
    'unmapped', (select count(*) from public.catalog_programs p where p.active and not exists (select 1 from public.web_tax_offering_map m where m.catalog_program_id = p.id and m.programme_id is not null)),
    'needs_review', (select count(*) from public.web_tax_offering_map where needs_review),
    'privacy_requests_open', (select count(*) from public.web_deletion_requests where status = 'open'))
$$;

-- Funnels (spec 11): server-side truth where it exists, client beacons (web_funnel_events) for view/open steps.
create or replace function public.web_admin_funnels(p_days int default 30)
returns jsonb language sql stable security definer set search_path = '' as $$
  with since as (select now() - make_interval(days => least(greatest(p_days, 1), 365)) as t),
  ev as (select funnel, step, count(distinct coalesce(nullif(anon_id, 'unconsented'), id::text)) n
           from public.web_funnel_events, since where at > since.t group by funnel, step)
  select jsonb_build_object(
    'gate', jsonb_build_array(
      jsonb_build_object('step', 'Hero view', 'n', coalesce((select n from ev where funnel = 'gate' and step = 'hero_view'), 0)),
      jsonb_build_object('step', 'Gate opened', 'n', coalesce((select n from ev where funnel = 'gate' and step = 'gate_open'), 0)),
      jsonb_build_object('step', 'Gate submitted', 'n', (select count(*) from public.web_gate_attempts, since where surface = 'gate' and submitted_at > since.t)),
      jsonb_build_object('step', 'Email code sent', 'n', (select count(*) from public.web_gate_attempts, since where surface = 'gate' and code_sent_at > since.t)),
      jsonb_build_object('step', 'Email verified', 'n', (select count(*) from public.web_gate_attempts, since where surface = 'gate' and verified_at > since.t)),
      jsonb_build_object('step', 'First message', 'n', (select count(*) from public.web_advisor_sessions, since where turns > 0 and created_at > since.t)),
      jsonb_build_object('step', 'Qualified', 'n', (select count(*) from public.web_advisor_sessions, since where classification in ('HOT', 'WARM', 'COLD') and created_at > since.t))),
    'form', jsonb_build_array(
      jsonb_build_object('step', 'Panel opened', 'n', coalesce((select n from ev where funnel = 'form' and step = 'panel_open'), 0)),
      jsonb_build_object('step', 'Form started', 'n', coalesce((select n from ev where funnel = 'form' and step = 'form_start'), 0)),
      jsonb_build_object('step', 'Email verified (lead)', 'n', (select count(*) from public.web_gate_attempts, since where surface = 'application' and verified_at > since.t)),
      jsonb_build_object('step', 'Step 2 saved', 'n', (select count(*) from public.web_applications, since where kind = 'application' and steps ? '2' and created_at > since.t)),
      jsonb_build_object('step', 'Step 3 saved', 'n', (select count(*) from public.web_applications, since where kind = 'application' and steps ? '3' and created_at > since.t)),
      jsonb_build_object('step', 'Step 4 saved', 'n', (select count(*) from public.web_applications, since where kind = 'application' and steps ? '4' and created_at > since.t)),
      jsonb_build_object('step', 'Submitted', 'n', (select count(*) from public.web_applications, since where kind = 'application' and status = 'submitted' and created_at > since.t))),
    'enquiry', jsonb_build_array(
      jsonb_build_object('step', 'Submitted', 'n', (select count(*) from public.web_gate_attempts, since where surface = 'enquiry' and submitted_at > since.t)),
      jsonb_build_object('step', 'Email verified (lead)', 'n', (select count(*) from public.web_gate_attempts, since where surface = 'enquiry' and verified_at > since.t))))
$$;

-- Witty insights (read-only; no prompt editing here — prompts belong to the shared agent core).
create or replace function public.web_admin_advisor_insights(p_days int default 30)
returns jsonb language sql stable security definer set search_path = '' as $$
  with since as (select now() - make_interval(days => least(greatest(p_days, 1), 365)) as t),
  s as (select a.* from public.web_advisor_sessions a, since where a.created_at > since.t and a.turns > 0)
  select jsonb_build_object(
    'conversations', (select count(*) from s),
    'turns', coalesce((select sum(turns) from s), 0),
    'handoffs', (select count(*) from s where escalated_at is not null),
    'by_classification', coalesce((select jsonb_object_agg(classification, n) from (select classification, count(*) n from s group by 1) x), '{}'),
    'tokens', coalesce((select sum(prompt_tokens + output_tokens) from s), 0),
    'cached_tokens', coalesce((select sum(cached_tokens) from s), 0),
    'cost_usd', coalesce((select round(sum(cost_usd), 4) from s), 0),
    'avg_latency_ms', (select round(avg(m.latency_ms)) from public.web_advisor_messages m join s on s.id = m.session_id where m.direction = 'out'),
    'avg_ttft_ms', (select round(avg((m.meta->>'ttft_ms')::numeric)) from public.web_advisor_messages m join s on s.id = m.session_id where m.direction = 'out' and m.meta ? 'ttft_ms'),
    'fallback_replies', (select count(*) from public.web_advisor_messages m join s on s.id = m.session_id where m.direction = 'out' and m.reply_source = 'fallback'),
    'top_questions', coalesce((select jsonb_agg(jsonb_build_object('text', q, 'n', n) order by n desc) from (
        select left(lower(btrim(m.content)), 80) q, count(*) n from public.web_advisor_messages m join s on s.id = m.session_id
         where m.direction = 'in' and m.id = (select min(id) from public.web_advisor_messages f where f.session_id = m.session_id and f.direction = 'in')
         group by 1 order by 2 desc limit 15) x), '[]'),
    'thumbs_down', coalesce((select jsonb_agg(x order by x->>'at' desc) from (
        select jsonb_build_object('at', f.created_at, 'reply', left(m.content, 400), 'mode', m.answer_mode,
          'question', (select left(p.content, 200) from public.web_advisor_messages p where p.session_id = m.session_id and p.direction = 'in' and p.id < m.id order by p.id desc limit 1)) x
          from public.web_advisor_feedback f join public.web_advisor_messages m on m.id = f.message_id, since
         where f.rating = -1 and f.created_at > since.t order by f.created_at desc limit 25) y), '[]'),
    'thumbs_up', (select count(*) from public.web_advisor_feedback f, since where f.rating = 1 and f.created_at > since.t))
$$;

create or replace function public.web_admin_outbox(p_status text default null, p_limit int default 100)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.web_outbox group by 1) x), '{}'),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'status', status, 'attempts', attempts, 'max_attempts', max_attempts,
        'last_error', last_error, 'created_at', created_at, 'next_attempt_at', next_attempt_at, 'processed_at', processed_at) order by id desc)
      from (select * from public.web_outbox where p_status is null or status = p_status order by id desc limit least(greatest(p_limit, 1), 500)) o), '[]'))
$$;

create or replace function public.web_admin_audit(p_entity text default null, p_limit int default 100)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc), '[]')
  from (select * from public.web_audit_log where p_entity is null or entity = p_entity order by id desc limit least(greatest(p_limit, 1), 500)) a
$$;

-- Taxonomy tool (spec 5.3): rows needing a mapping and the canonical options to map them to.
create or replace function public.web_admin_taxonomy()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'unmapped', coalesce((select jsonb_agg(to_jsonb(u)) from public.web_tax_unmapped() u), '[]'),
    'programmes', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'label', short_name || ' — ' || full_name) order by sort, id) from public.web_tax_programmes where active), '[]'),
    'specialisations', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'label', name) order by name) from public.web_tax_specialisations where active), '[]'),
    'by_confidence', coalesce((select jsonb_object_agg(coalesce(confidence, 'none'), n) from (select confidence, count(*) n from public.web_tax_offering_map group by 1) x), '{}'))
$$;

create or replace function public.web_admin_privacy_done(p_id bigint, p_status text, p_note text, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_before jsonb;
begin
  if not public.web_admin_role_ok(p_role, 'super_admin') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_status not in ('done', 'rejected') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
  select to_jsonb(r) into v_before from public.web_deletion_requests r where id = p_id;
  update public.web_deletion_requests set status = p_status, processed_at = now(), processed_by = p_actor_email, note = left(p_note, 500) where id = p_id;
  insert into public.web_audit_log (actor, actor_email, action, entity, entity_id, before, after)
  values (p_actor, p_actor_email, 'privacy.' || p_status, 'web_deletion_requests', p_id::text, v_before, jsonb_build_object('status', p_status, 'note', p_note));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.web_admin_privacy_requests()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(r) order by r.requested_at desc), '[]') from public.web_deletion_requests r
$$;

do $$
declare f text;
begin
  foreach f in array array['public.web_admin_list(text, text, integer, integer)', 'public.web_admin_get(text, jsonb)',
    'public.web_admin_save(text, jsonb, uuid, text, text)', 'public.web_admin_delete(text, jsonb, uuid, text, text)',
    'public.web_admin_setting(text, jsonb, uuid, text, text)', 'public.web_admin_overview()', 'public.web_admin_funnels(integer)',
    'public.web_admin_advisor_insights(integer)', 'public.web_admin_outbox(text, integer)', 'public.web_admin_audit(text, integer)',
    'public.web_admin_privacy_requests()', 'public.web_admin_role_ok(text, text)', 'public.web_admin_taxonomy()',
    'public.web_admin_privacy_done(bigint, text, text, uuid, text, text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
