-- web10 · SEO toolkit (spec 13.4): Search Console data, keyword list with position tracking, opportunity finder,
-- content planner (briefs and drafts on web_resources; named author + reviewer still required to publish), on-page
-- checks, internal-link suggestions, 404 monitor with one-click redirects, local SEO checklist. Website-owned only.

create table if not exists public.web_seo_daily (
  day date not null,
  query text not null,
  page text not null,
  clicks integer not null default 0,
  impressions integer not null default 0,
  position numeric(6, 2),
  source text not null default 'gsc' check (source in ('gsc', 'sample')),
  primary key (day, query, page)
);
create index if not exists web_seo_daily_query_idx on public.web_seo_daily (query, day);
create index if not exists web_seo_daily_page_idx on public.web_seo_daily (page, day);

create table if not exists public.web_seo_sync (
  id bigint generated always as identity primary key,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  source text not null,
  rows_written integer,
  error text
);

create table if not exists public.web_seo_keywords (
  id bigint generated always as identity primary key,
  keyword text not null unique check (keyword = lower(btrim(keyword)) and length(keyword) between 2 and 120),
  priority smallint not null default 2 check (priority between 1 and 3),
  target_path text check (target_path ~ '^/'),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.web_404_log (
  path text primary key check (path ~ '^/'),
  hits integer not null default 1,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  last_referrer text,
  resolved_at timestamptz
);

create table if not exists public.web_seo_checks (
  path text primary key check (path ~ '^/'),
  score smallint not null check (score between 0 and 100),
  issues jsonb not null default '[]',
  checked_at timestamptz not null default now()
);

create table if not exists public.web_link_suggestions (
  id bigint generated always as identity primary key,
  from_slug text not null,
  to_path text not null check (to_path ~ '^/'),
  anchor text not null,
  reason text,
  status text not null default 'suggested' check (status in ('suggested', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by text,
  unique (from_slug, to_path)
);

create table if not exists public.web_local_seo_tasks (
  id bigint generated always as identity primary key,
  task text not null unique,
  done boolean not null default false,
  done_at timestamptz,
  done_by text,
  sort smallint not null default 100
);

insert into public.web_settings (key, value) values ('business_hours', 'null') on conflict (key) do nothing;

alter table public.web_resources add column if not exists brief jsonb;
alter table public.web_resources add column if not exists draft_source text check (draft_source in ('human', 'claude_assisted'));

insert into public.web_local_seo_tasks (task, sort) values
  ('Claim and verify the Google Business Profile for Eduwit Learning Services (Indirapuram)', 10),
  ('Name, address and phone on the profile match the website footer exactly', 20),
  ('Opening hours, categories (Educational consultant) and services filled in', 30),
  ('Website link on the profile points to https://eduwit.in/', 40),
  ('Listed on Justdial, Sulekha and IndiaMART with the same name, address and phone', 50),
  ('Ask students who were happy with counselling for a Google review (no incentives)', 60),
  ('Add photos of the Indirapuram office to the profile', 70)
on conflict (task) do nothing;

do $$
declare t text;
begin
  foreach t in array array['web_seo_daily', 'web_seo_sync', 'web_seo_keywords', 'web_404_log', 'web_seo_checks', 'web_link_suggestions', 'web_local_seo_tasks'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated, public', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;

insert into public.web_admin_entities (entity, tbl, key_cols, cols, min_role, tags, can_delete, order_by) values
  ('keywords', 'web_seo_keywords', '{id}', '{keyword,priority,target_path,notes}', 'content_editor', '{}', true, 'priority, keyword'),
  ('local_seo', 'web_local_seo_tasks', '{id}', '{task,done,done_at,done_by,sort}', 'content_editor', '{}', true, 'sort, id')
on conflict (entity) do nothing;
update public.web_admin_entities set cols = array_append(cols, 'brief') where entity = 'resources' and not 'brief' = any(cols);
update public.web_admin_entities set cols = array_append(cols, 'draft_source') where entity = 'resources' and not 'draft_source' = any(cols);

-- Search Console import (one call per sync; idempotent per day/query/page).
create or replace function public.web_seo_import(p_rows jsonb, p_source text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_n int; v_sync bigint;
begin
  insert into public.web_seo_sync (source) values (p_source) returning id into v_sync;
  insert into public.web_seo_daily (day, query, page, clicks, impressions, position, source)
  select (r->>'day')::date, lower(btrim(r->>'query')), r->>'page', coalesce((r->>'clicks')::int, 0), coalesce((r->>'impressions')::int, 0),
         (r->>'position')::numeric, p_source
  from jsonb_array_elements(coalesce(p_rows, '[]')) r
  where r->>'query' is not null and r->>'page' like '/%'
  on conflict (day, query, page) do update set clicks = excluded.clicks, impressions = excluded.impressions, position = excluded.position, source = excluded.source;
  get diagnostics v_n = row_count;
  update public.web_seo_sync set finished_at = now(), rows_written = v_n where id = v_sync;
  return jsonb_build_object('ok', true, 'rows', v_n);
end $$;

-- Dashboard (trends, top queries and pages, rising/falling pages, low-CTR candidates) for the last N days vs the N before.
create or replace function public.web_seo_dashboard(p_days int default 28)
returns jsonb language sql stable security definer set search_path = '' as $$
  with b as (select current_date - least(greatest(p_days, 7), 180) as cur, current_date - 2 * least(greatest(p_days, 7), 180) as prev),
  cur as (select d.* from public.web_seo_daily d, b where d.day > b.cur),
  prev as (select d.* from public.web_seo_daily d, b where d.day > b.prev and d.day <= b.cur),
  pages as (
    select coalesce(c.page, p.page) page, coalesce(c.clicks, 0) clicks, coalesce(p.clicks, 0) prev_clicks, coalesce(c.impressions, 0) impressions
    from (select page, sum(clicks) clicks, sum(impressions) impressions from cur group by 1) c
    full join (select page, sum(clicks) clicks from prev group by 1) p on p.page = c.page)
  select jsonb_build_object(
    'source', (select source from public.web_seo_daily order by day desc limit 1),
    'last_sync', (select to_jsonb(s) from public.web_seo_sync s order by id desc limit 1),
    'totals', (select jsonb_build_object('clicks', coalesce(sum(clicks), 0), 'impressions', coalesce(sum(impressions), 0),
                 'ctr', case when sum(impressions) > 0 then round(sum(clicks)::numeric / sum(impressions) * 100, 2) else 0 end,
                 'position', round(sum(position * impressions) / nullif(sum(impressions), 0), 1)) from cur),
    'trend', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'clicks', c, 'impressions', i) order by day)
                 from (select day, sum(clicks) c, sum(impressions) i from cur group by day) t), '[]'),
    'top_queries', coalesce((select jsonb_agg(x order by (x->>'clicks')::int desc, (x->>'impressions')::int desc) from (
                 select jsonb_build_object('query', query, 'clicks', sum(clicks), 'impressions', sum(impressions),
                   'position', round(sum(position * impressions) / nullif(sum(impressions), 0), 1)) x
                 from cur group by query order by sum(clicks) desc, sum(impressions) desc limit 25) q), '[]'),
    'top_pages', coalesce((select jsonb_agg(jsonb_build_object('page', page, 'clicks', clicks, 'impressions', impressions) order by clicks desc)
                 from (select * from pages order by clicks desc limit 20) t), '[]'),
    'rising', coalesce((select jsonb_agg(jsonb_build_object('page', page, 'clicks', clicks, 'prev', prev_clicks) order by clicks - prev_clicks desc)
                 from (select * from pages where clicks > prev_clicks order by clicks - prev_clicks desc limit 10) t), '[]'),
    'falling', coalesce((select jsonb_agg(jsonb_build_object('page', page, 'clicks', clicks, 'prev', prev_clicks) order by prev_clicks - clicks desc)
                 from (select * from pages where clicks < prev_clicks order by prev_clicks - clicks desc limit 10) t), '[]'),
    'low_ctr', coalesce((select jsonb_agg(x order by (x->>'impressions')::int desc) from (
                 select jsonb_build_object('page', page, 'impressions', sum(impressions), 'clicks', sum(clicks),
                   'ctr', round(sum(clicks)::numeric / nullif(sum(impressions), 0) * 100, 2)) x
                 from cur group by page having sum(impressions) >= 100 and sum(clicks)::numeric / nullif(sum(impressions), 0) < 0.02
                 order by sum(impressions) desc limit 15) q), '[]'))
$$;

-- Keyword list with positions from Search Console and cannibalisation flags (two indexable pages ranking for one keyword,
-- or two keywords mapped to different target pages for the same query).
create or replace function public.web_seo_keywords_report(p_days int default 28)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', k.id, 'keyword', k.keyword, 'priority', k.priority, 'target_path', k.target_path, 'notes', k.notes,
    'position', (select round(sum(d.position * d.impressions) / nullif(sum(d.impressions), 0), 1) from public.web_seo_daily d
                  where d.query = k.keyword and d.day > current_date - p_days),
    'target_position', (select round(sum(d.position * d.impressions) / nullif(sum(d.impressions), 0), 1) from public.web_seo_daily d
                  where d.query = k.keyword and d.page = k.target_path and d.day > current_date - p_days),
    'ranking_pages', coalesce((select jsonb_agg(distinct d.page) from public.web_seo_daily d
                  where d.query = k.keyword and d.day > current_date - p_days and d.impressions > 0), '[]'),
    'cannibalised', (select count(distinct d.page) > 1 from public.web_seo_daily d
                  where d.query = k.keyword and d.day > current_date - p_days and d.impressions >= 10))
    order by k.priority, k.keyword), '[]')
  from public.web_seo_keywords k
$$;

-- 404 monitor: the proxy reports misses; staff turn one into a redirect with one click.
create or replace function public.web_404_hit(p_path text, p_referrer text)
returns void language sql volatile security definer set search_path = '' as $$
  insert into public.web_404_log (path, last_referrer) values (left(p_path, 300), left(p_referrer, 300))
  on conflict (path) do update set hits = public.web_404_log.hits + 1, last_seen = now(), last_referrer = coalesce(excluded.last_referrer, public.web_404_log.last_referrer)
$$;

create or replace function public.web_404_report()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'misses', coalesce((select jsonb_agg(to_jsonb(l) order by l.hits desc) from (select * from public.web_404_log where resolved_at is null order by hits desc limit 200) l), '[]'),
    'chains', coalesce((select jsonb_agg(jsonb_build_object('from', a.from_path, 'via', a.to_path, 'to', b.to_path))
                from public.web_redirects a join public.web_redirects b on b.from_path = a.to_path), '[]'))
$$;

create or replace function public.web_404_redirect(p_path text, p_to text, p_actor uuid, p_actor_email text, p_role text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v jsonb;
begin
  v := public.web_admin_save('redirects', jsonb_build_object('from_path', p_path, 'to_path', p_to, 'code', 301, 'source', '404_monitor'), p_actor, p_actor_email, p_role);
  if (v->>'ok')::boolean then update public.web_404_log set resolved_at = now() where path = p_path; end if;
  return v;
end $$;

-- On-page checks are computed by the website (it renders the pages) and stored here.
create or replace function public.web_seo_check_save(p_path text, p_score int, p_issues jsonb)
returns void language sql volatile security definer set search_path = '' as $$
  insert into public.web_seo_checks (path, score, issues) values (p_path, p_score, coalesce(p_issues, '[]'))
  on conflict (path) do update set score = excluded.score, issues = excluded.issues, checked_at = now()
$$;

create or replace function public.web_seo_checks_list()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(c) order by c.score, c.path), '[]') from public.web_seo_checks c
$$;

-- Opportunity finder: queries with impressions (or taxonomy matches) with no dedicated landing page yet.
create or replace function public.web_seo_opportunities(p_days int default 90)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  with q as (
    select d.query, sum(d.impressions) impressions, sum(d.clicks) clicks,
           round(sum(d.position * d.impressions) / nullif(sum(d.impressions), 0), 1) position,
           (array_agg(d.page order by d.impressions desc))[1] best_page
    from public.web_seo_daily d where d.day > current_date - p_days group by d.query having sum(d.impressions) >= 20)
  select coalesce(jsonb_agg(jsonb_build_object('query', q.query, 'impressions', q.impressions, 'clicks', q.clicks, 'position', q.position,
      'best_page', q.best_page, 'question', q.query ~* '^(is|are|can|how|what|which|why|does|kya|kaise|kitna)\M',
      'filters', public.web_resolve_to_filters(q.query)) order by q.impressions desc), '[]')
  into v
  from q
  where not exists (select 1 from public.web_curated_views c where c.status = 'published' and lower(c.title) = q.query)
    and (q.best_page is null or q.best_page not like '/programmes/%' or q.best_page = '/programmes')
    and not exists (select 1 from public.web_resources r where r.status = 'published' and lower(r.title) like '%' || q.query || '%');
  return v;
end $$;

create or replace function public.web_link_suggestions_list()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(s) order by s.status, s.created_at desc), '[]') from public.web_link_suggestions s
$$;

create or replace function public.web_link_suggestions_add(p_rows jsonb)
returns integer language plpgsql volatile security definer set search_path = '' as $$
declare n int;
begin
  insert into public.web_link_suggestions (from_slug, to_path, anchor, reason)
  select r->>'from_slug', r->>'to_path', r->>'anchor', r->>'reason' from jsonb_array_elements(coalesce(p_rows, '[]')) r
  on conflict (from_slug, to_path) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.web_link_decide(p_id bigint, p_status text, p_actor_email text)
returns void language sql volatile security definer set search_path = '' as $$
  update public.web_link_suggestions set status = p_status, decided_at = now(), decided_by = p_actor_email
  where id = p_id and p_status in ('approved', 'rejected')
$$;

-- Related links shown on a guide: approved suggestions only (editor approval, spec 13.4).
create or replace function public.web_resource_links(p_slug text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('href', to_path, 'anchor', anchor) order by id), '[]')
  from public.web_link_suggestions where from_slug = p_slug and status = 'approved'
$$;

do $$
declare f text;
begin
  foreach f in array array['public.web_seo_import(jsonb, text)', 'public.web_seo_dashboard(integer)', 'public.web_seo_keywords_report(integer)',
    'public.web_404_hit(text, text)', 'public.web_404_report()', 'public.web_404_redirect(text, text, uuid, text, text)',
    'public.web_seo_check_save(text, integer, jsonb)', 'public.web_seo_checks_list()', 'public.web_seo_opportunities(integer)',
    'public.web_link_suggestions_list()', 'public.web_link_suggestions_add(jsonb)', 'public.web_link_decide(bigint, text, text)',
    'public.web_resource_links(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
