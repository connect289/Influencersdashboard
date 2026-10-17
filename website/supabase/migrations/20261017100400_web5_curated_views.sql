-- web5_curated_views — curated finder views (spec 4, 6.6): /programmes/<slug> is the finder with filters pre-applied plus
-- an admin-written intro and FAQs. Created deliberately in the admin for high-demand searches, never auto-generated.

create table if not exists public.web_curated_views (
  slug text primary key check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) <= 80),
  title text not null,                 -- <title> / H1
  h1 text,
  intro text,                          -- short paragraph(s), plain text with blank lines between paragraphs
  filters jsonb not null default '{}', -- same keys as the finder URL (programme, spec, mode, level, …)
  faqs jsonb not null default '[]',    -- [{ "q": "...", "a": "..." }]
  seo_description text check (length(seo_description) <= 200),
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  sort smallint not null default 100,
  updated_at timestamptz not null default now(),
  updated_by text
);
alter table public.web_curated_views enable row level security;
revoke all on public.web_curated_views from anon, authenticated, public;
grant select, insert, update, delete on public.web_curated_views to service_role;

create or replace function public.web_curated_view(p_slug text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select to_jsonb(v) - 'updated_by' from public.web_curated_views v where v.slug = p_slug and v.status = 'published'
$$;

create or replace function public.web_curated_views_list()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('slug', slug, 'title', title, 'filters', filters, 'updated_at', updated_at) order by sort, title), '[]')
  from public.web_curated_views where status = 'published'
$$;

do $$
declare f text;
begin
  foreach f in array array['public.web_curated_view(text)', 'public.web_curated_views_list()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- Starter views for the highest-demand searches (published; editable in the admin). Copy states only general facts;
-- numbers on the page come live from the catalogue.
insert into public.web_curated_views (slug, title, h1, intro, filters, faqs, seo_description, status, sort) values
  ('online-mba', 'Online MBA programmes', 'Online MBA',
   'Compare online and distance MBA programmes: the full fee, duration, specialisations, approvals and eligibility, side by side. Each university''s UGC-DEB status, NAAC grade and NIRF rank are shown where the university states them.' || chr(10) || chr(10) || 'Every fee shown is the full programme fee as published by the university. A counsellor can confirm the latest fee and the next intake.',
   '{"programme": ["mba"]}',
   '[{"q": "Who can apply for an online MBA?", "a": "Most universities ask for a bachelor''s degree in any subject, often with a minimum percentage. Each programme''s eligibility is shown in its details; a counsellor can confirm yours."},
     {"q": "What is the difference between online and distance (ODL) MBA?", "a": "Online programmes are taught through a learning platform with live and recorded classes; distance (ODL) programmes rely more on study material and contact sessions. UGC-DEB decides which universities may offer each mode; check the status shown for each university."},
     {"q": "Can I pay the fee in instalments?", "a": "Yes. Easy EMI is available on programme fees; ask a counsellor for the options for the programme you choose."}]',
   'Compare online and distance MBA programmes by full fee, duration, specialisation and approvals, with each university''s UGC-DEB status and NAAC grade.', 'published', 10),
  ('online-bca', 'Online BCA programmes', 'Online BCA',
   'Compare online and distance BCA programmes: the full fee, duration, specialisations such as data science and cloud computing, approvals and eligibility.',
   '{"programme": ["bca"]}',
   '[{"q": "Who can apply for an online BCA?", "a": "Usually anyone who has passed Class 12; some universities set a minimum percentage or subject requirement. Each programme''s eligibility is shown in its details."}]',
   'Compare online and distance BCA programmes by full fee, duration, specialisation and approvals.', 'published', 20),
  ('online-mca', 'Online MCA programmes', 'Online MCA',
   'Compare online and distance MCA programmes: the full fee, duration, specialisations, approvals and eligibility.',
   '{"programme": ["mca"]}',
   '[{"q": "Who can apply for an online MCA?", "a": "Usually graduates; many universities ask for mathematics at Class 12 or graduation level. Each programme''s eligibility is shown in its details."}]',
   'Compare online and distance MCA programmes by full fee, duration, specialisation and approvals.', 'published', 30)
on conflict (slug) do nothing;
