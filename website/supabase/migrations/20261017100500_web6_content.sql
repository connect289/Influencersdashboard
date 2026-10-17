-- web6_content — website content managed in the admin (spec 6 Phase "Content and migration", 11): legal pages (migrated
-- verbatim from the current site), testimonials, FAQs, resources with named authors and reviewers, popular searches,
-- runtime redirects and per-page SEO overrides. All website-owned; no shared object is touched.

create table if not exists public.web_legal_pages (
  slug text primary key check (slug in ('terms-and-conditions', 'privacy-policy', 'disclaimer', 'refund-policy', 'cookie-policy', 'data-privacy-opt-out')),
  title text not null,
  -- Ordered blocks: {"type": "h2"|"h3"|"p"|"ul"|"ol", "text": "...", "items": ["..."]}
  body jsonb not null default '[]',
  status text not null default 'pending_migration' check (status in ('pending_migration', 'migrated', 'proposed_edit')),
  source_url text,
  migrated_at timestamptz,
  version integer not null default 1,
  reviewed_by text,
  updated_at timestamptz not null default now()
);

insert into public.web_legal_pages (slug, title, source_url) values
  ('terms-and-conditions', 'Terms and Conditions', 'https://eduwit.in/legal/terms-and-conditions'),
  ('privacy-policy', 'Privacy Policy', 'https://eduwit.in/legal/privacy-policy'),
  ('disclaimer', 'Disclaimer', 'https://eduwit.in/legal/disclaimer'),
  ('refund-policy', 'Refund Policy', 'https://eduwit.in/legal/refund-policy'),
  ('cookie-policy', 'Cookie Policy', 'https://eduwit.in/legal/cookie-policy'),
  ('data-privacy-opt-out', 'Data Privacy & Opt-out', 'https://eduwit.in/legal/data-privacy-opt-out')
on conflict (slug) do nothing;

create table if not exists public.web_testimonials (
  id bigint generated always as identity primary key,
  name text not null check (length(name) between 2 and 80),
  detail text,                       -- e.g. programme and university, as the student agreed to be shown
  quote text not null check (length(quote) between 10 and 1200),
  rating smallint check (rating between 1 and 5),
  photo_path text,
  source text not null default 'new' check (source in ('legacy', 'new')),
  consent_confirmed boolean not null default false, -- the student agreed to be quoted (required to publish)
  published boolean not null default false check (not published or consent_confirmed),
  sort smallint not null default 100,
  created_at timestamptz not null default now()
);

create table if not exists public.web_faqs (
  id bigint generated always as identity primary key,
  scope text not null check (scope ~ '^(home|contact|how-it-works|about|curated:[a-z0-9-]+|university:[a-z0-9-]+)$'),
  question text not null check (length(question) <= 300),
  answer text not null check (length(answer) <= 3000),
  sort smallint not null default 100,
  published boolean not null default true,
  updated_at timestamptz not null default now()
);
create index if not exists web_faqs_scope_idx on public.web_faqs (scope, sort) where published;

insert into public.web_faqs (scope, question, answer, sort)
select * from (values
  ('home', 'Is counselling with Eduwit free?', 'Yes. Counselling is free. You pay programme fees to the university, never on this website.', 10),
  ('home', 'Where do the fees and approvals come from?', 'From the programme catalogue Eduwit maintains with its partner universities. Every fee shows the date it was last verified, and approvals, NAAC grades and NIRF ranks appear only where the university states them.', 20),
  ('home', 'What does UGC-DEB mean?', 'The University Grants Commission''s Distance Education Bureau decides which universities may offer which programmes online or by distance learning. We show each university''s status as stated in its records.', 30),
  ('home', 'Do I apply on this website?', 'You fill in one short pre-application. A counsellor checks your eligibility and helps you complete the university''s own application. Eduwit never asks for payment on this website.', 40),
  ('home', 'Who is Witty?', 'Witty is Eduwit''s AI admissions assistant. It answers from Eduwit''s programme data and hands over to a counsellor for anything it can''t confirm.', 50),
  ('how-it-works', 'How long does it take to hear from a counsellor?', 'A counsellor contacts you using the method you choose in the form. You can also message us on WhatsApp at any time.', 10),
  ('how-it-works', 'Can I change my mind about the programme?', 'Yes. Your counsellor can help you compare other programmes and universities before you apply.', 20),
  ('contact', 'How do I ask for my data to be deleted?', 'Use the Data Privacy & Opt-out page or email connect@eduwit.in. You can withdraw consent at any time.', 10)
) v(scope, question, answer, sort)
where not exists (select 1 from public.web_faqs);

create table if not exists public.web_authors (
  id bigint generated always as identity primary key,
  name text not null,
  role text,
  bio text,
  photo_path text,
  active boolean not null default true
);

create table if not exists public.web_resources (
  slug text primary key check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) <= 100),
  title text not null,
  summary text,
  body jsonb not null default '[]',  -- same block format as legal pages
  author_id bigint references public.web_authors (id),
  reviewer_id bigint references public.web_authors (id),
  status text not null default 'idea' check (status in ('idea', 'brief', 'draft', 'review', 'published', 'refresh_due', 'archived')),
  -- spec 13.4: a named human author and reviewer are mandatory before publishing
  check (status <> 'published' or (author_id is not null and reviewer_id is not null)),
  published_at timestamptz,
  refresh_due_at timestamptz,
  tags text[] not null default '{}',
  seo_title text,
  seo_description text check (length(seo_description) <= 200),
  updated_at timestamptz not null default now()
);

create table if not exists public.web_popular_searches (
  id bigint generated always as identity primary key,
  label text not null,
  href text not null check (href ~ '^/'),
  sort smallint not null default 100,
  active boolean not null default true
);
insert into public.web_popular_searches (label, href, sort)
select * from (values
  ('Online MBA', '/programmes/online-mba', 10),
  ('MBA in Marketing', '/programmes?programme=mba&spec=marketing', 20),
  ('Online BCA', '/programmes/online-bca', 30),
  ('MBA under ₹2 lakh', '/programmes?programme=mba&fee_max=200000', 40),
  ('Data science', '/programmes?spec=data-science', 50),
  ('Online MCA', '/programmes/online-mca', 60),
  ('B.Com', '/programmes?programme=bcom', 70),
  ('MBA for working professionals', '/programmes?programme=mba&goal=upskill-while-working', 80)
) v(label, href, sort)
where not exists (select 1 from public.web_popular_searches);

create table if not exists public.web_redirects (
  from_path text primary key check (from_path ~ '^/[^?#]*$'),
  to_path text not null check (to_path ~ '^(/|https://)'),
  code smallint not null default 301 check (code in (301, 302, 307, 308)),
  source text not null default 'admin' check (source in ('legacy_map', 'admin', '404_monitor', 'slug_change')),
  hits integer not null default 0,
  last_hit_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.web_pages (
  path text primary key check (path ~ '^/'),
  title text check (length(title) <= 70),
  description text check (length(description) <= 200),
  og_image text,
  noindex boolean not null default false,
  updated_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['web_legal_pages','web_testimonials','web_faqs','web_authors','web_resources','web_popular_searches','web_redirects','web_pages'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated, public', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;

-- Read functions (service role; cached by the website with the "content" tag).
create or replace function public.web_home_content()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'faqs', coalesce((select jsonb_agg(jsonb_build_object('q', question, 'a', answer) order by sort, id) from public.web_faqs where scope = 'home' and published), '[]'),
    'testimonials', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'detail', detail, 'quote', quote, 'rating', rating, 'photo', photo_path) order by sort, id)
                              from public.web_testimonials where published), '[]'),
    'popular', coalesce((select jsonb_agg(jsonb_build_object('label', label, 'href', href) order by sort, id) from public.web_popular_searches where active), '[]'),
    'resources', coalesce((select jsonb_agg(x) from (select jsonb_build_object('slug', slug, 'title', title, 'summary', summary, 'published_at', published_at) x
                           from public.web_resources where status in ('published', 'refresh_due') order by published_at desc nulls last limit 3) t), '[]'))
$$;

create or replace function public.web_faqs_for(p_scope text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('q', question, 'a', answer) order by sort, id), '[]')
  from public.web_faqs where scope = p_scope and published
$$;

create or replace function public.web_legal_page(p_slug text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('slug', slug, 'title', title, 'body', body, 'status', status, 'migrated_at', migrated_at, 'version', version, 'updated_at', updated_at)
  from public.web_legal_pages where slug = p_slug
$$;

create or replace function public.web_resources_list()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('slug', r.slug, 'title', r.title, 'summary', r.summary, 'published_at', r.published_at, 'tags', r.tags,
           'author', a.name) order by r.published_at desc nulls last), '[]')
  from public.web_resources r left join public.web_authors a on a.id = r.author_id
  where r.status in ('published', 'refresh_due')
$$;

create or replace function public.web_resource(p_slug text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('slug', r.slug, 'title', r.title, 'summary', r.summary, 'body', r.body, 'published_at', r.published_at,
           'updated_at', r.updated_at, 'tags', r.tags, 'seo_title', r.seo_title, 'seo_description', r.seo_description,
           'author', jsonb_build_object('name', a.name, 'role', a.role, 'bio', a.bio),
           'reviewer', jsonb_build_object('name', v.name, 'role', v.role))
  from public.web_resources r
  join public.web_authors a on a.id = r.author_id
  join public.web_authors v on v.id = r.reviewer_id
  where r.slug = p_slug and r.status in ('published', 'refresh_due')
$$;

create or replace function public.web_redirects_all()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(from_path, jsonb_build_object('to', to_path, 'code', code)), '{}') from public.web_redirects
$$;

create or replace function public.web_redirect_hit(p_from text)
returns void language sql volatile security definer set search_path = '' as $$
  update public.web_redirects set hits = hits + 1, last_hit_at = now() where from_path = p_from
$$;

create or replace function public.web_page_meta(p_path text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(p) - 'updated_at' from public.web_pages p where p.path = p_path
$$;

do $$
declare f text;
begin
  foreach f in array array['public.web_home_content()', 'public.web_faqs_for(text)', 'public.web_legal_page(text)', 'public.web_resources_list()',
    'public.web_resource(text)', 'public.web_redirects_all()', 'public.web_redirect_hit(text)', 'public.web_page_meta(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
