-- web3_taxonomy — canonical taxonomy over the shared catalogue (spec 5.2/5.3, docs/TAXONOMY_PROPOSAL.md).
-- Website-owned `web_tax_*` tables keyed to catalogue ids; designed to be promoted to a shared layer later (A-TAX-1).
-- Nothing here alters a shared object: the catalogue is only read.

-- ---------------------------------------------------------------------------------------------------------------
-- Text normaliser used by synonyms, search and the auto-mapper (no `unaccent` in production — A-EXT-1).
create or replace function public.web_norm(p text)
returns text language sql immutable parallel safe as $$
  select nullif(btrim(regexp_replace(regexp_replace(
    replace(replace(replace(replace(lower(coalesce(p, '')), '&', ' and '), '.', ''), '''', ''), '’', ''),
    '[^a-z0-9+]+', ' ', 'g'), '\s+', ' ', 'g')), '')
$$;

create or replace function public.web_slugify(p text)
returns text language sql immutable parallel safe as $$
  select btrim(regexp_replace(replace(coalesce(public.web_norm(p), ''), '+', ' '), '\s+', '-', 'g'), '-')
$$;

-- ---------------------------------------------------------------------------------------------------------------
create table if not exists public.web_tax_levels (
  id text primary key check (id ~ '^[a-z_]+$'),
  label text not null,
  short_label text not null,
  sort smallint not null,
  description text
);

create table if not exists public.web_tax_categories (
  id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  label text not null,
  sort smallint not null,
  description text
);

create table if not exists public.web_tax_programmes (
  id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  short_name text not null,
  full_name text not null,
  level_id text not null references public.web_tax_levels (id),
  category_id text references public.web_tax_categories (id), -- null: taken from the specialisation (generic diplomas)
  sort smallint not null default 100,
  search_prior real not null default 20 check (search_prior between 0 and 100), -- relevance tie-break (demand)
  description text,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.web_tax_specialisations (
  id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null,
  category_hint text references public.web_tax_categories (id),
  sort smallint not null default 100,
  description text,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.web_tax_goal_tags (
  id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  label text not null,
  description text,
  sort smallint not null default 100,
  active boolean not null default true
);

create table if not exists public.web_tax_career_tags (
  id text primary key check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  label text not null,
  sort smallint not null default 100,
  active boolean not null default true
);

create table if not exists public.web_tax_tag_links (
  id bigint generated always as identity primary key,
  tag_kind text not null check (tag_kind in ('goal', 'career')),
  tag_id text not null,
  programme_id text references public.web_tax_programmes (id) on delete cascade,
  specialisation_id text references public.web_tax_specialisations (id) on delete cascade,
  check (programme_id is not null or specialisation_id is not null),
  unique nulls not distinct (tag_kind, tag_id, programme_id, specialisation_id)
);

-- Aliases → canonical targets. `university` targets are catalogue university ids (as text); `stopword` targets '-'.
create table if not exists public.web_tax_synonyms (
  id bigint generated always as identity primary key,
  alias text not null,
  alias_norm text generated always as (public.web_norm(alias)) stored,
  alias_compact text generated always as (replace(public.web_norm(alias), ' ', '')) stored,
  kind text not null check (kind in ('programme', 'specialisation', 'level', 'university', 'category', 'mode', 'stopword')),
  target_id text not null,
  weight real not null default 1,
  source text not null default 'seed' check (source in ('seed', 'catalog_synonyms', 'admin')),
  created_at timestamptz not null default now(),
  unique (alias_compact, kind, target_id)
);
create index if not exists web_tax_synonyms_compact_idx on public.web_tax_synonyms (alias_compact);
create index if not exists web_tax_synonyms_trgm_idx on public.web_tax_synonyms using gin (alias_norm public.gin_trgm_ops);

-- Auto-mapping rules (data, editable in the admin; applied in priority order).
create table if not exists public.web_tax_rules_programme (
  id integer generated always as identity primary key,
  priority integer not null,
  course_key text not null,
  program_name_re text,          -- optional, case-insensitive
  programme_id text not null references public.web_tax_programmes (id),
  spec_from_name_re text,        -- capture group 1 = specialisation, used when the stored one is generic or unknown
  note text,
  active boolean not null default true
);

create table if not exists public.web_tax_rules_attribute (
  id integer generated always as identity primary key,
  priority integer not null,
  pattern text not null,          -- case-insensitive regex over course and specialisation; matched text is removed
  attribute text not null check (attribute ~ '^[a-z_]+$'),
  value_from_capture boolean not null default false,
  replace_with text,              -- for whole-value matches such as "Hindi Medium" → "General"
  note text,
  active boolean not null default true
);

create table if not exists public.web_tax_rules_format (
  id integer generated always as identity primary key,
  pattern text not null,          -- case-insensitive regex over the stored specialisation
  format text not null check (format in ('work-integrated', 'apprenticeship', 'work-linked')),
  active boolean not null default true
);

create table if not exists public.web_tax_formats (
  id text primary key,
  label text not null,
  description text
);

-- One row per catalogue offering (active or not, so nothing is ever silently lost).
create table if not exists public.web_tax_offering_map (
  catalog_program_id bigint primary key,
  program_key text,
  programme_id text references public.web_tax_programmes (id),
  specialisation_ids text[] not null default '{}',
  spec_display text,
  format text references public.web_tax_formats (id),
  attributes jsonb not null default '{}',
  mapped_by text not null default 'rule' check (mapped_by in ('rule', 'admin')),
  confidence text check (confidence in ('exact', 'synonym', 'split', 'name', 'fuzzy', 'admin')),
  rule_note text,
  source_fingerprint text not null,
  needs_review boolean not null default false,
  reviewed_at timestamptz,
  reviewed_by text,
  hidden_reason text,             -- admin can hide an offering from the finder (it stays in the report)
  updated_at timestamptz not null default now()
);
create index if not exists web_tax_offering_map_programme_idx on public.web_tax_offering_map (programme_id);
create index if not exists web_tax_offering_map_review_idx on public.web_tax_offering_map (needs_review) where needs_review;

-- Editorial university profile (facts stay in the catalogue; this holds slug, display name, logo permission, about).
create table if not exists public.web_university_profiles (
  catalog_university_id bigint primary key,
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  display_name text not null,
  logo_path text,
  logo_permitted boolean not null default false,
  state text,
  city text,
  website_url text check (website_url is null or website_url ~ '^https://'),
  about text,
  facts_override jsonb not null default '{}', -- admin corrections to parsed facts, each with a source note
  published boolean not null default true,
  updated_at timestamptz not null default now()
);

-- Popularity signal for tie-breaking (filled from anonymous panel opens / applications in later phases).
create table if not exists public.web_offering_popularity (
  catalog_program_id bigint primary key,
  score real not null default 0,
  updated_at timestamptz not null default now()
);

do $$
declare t text;
begin
  foreach t in array array['web_tax_levels','web_tax_categories','web_tax_programmes','web_tax_specialisations',
    'web_tax_goal_tags','web_tax_career_tags','web_tax_tag_links','web_tax_synonyms','web_tax_rules_programme',
    'web_tax_rules_attribute','web_tax_rules_format','web_tax_formats','web_tax_offering_map','web_university_profiles',
    'web_offering_popularity'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated, public', t);
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Seed: levels, categories, formats, programmes
insert into public.web_tax_levels (id, label, short_label, sort, description) values
  ('certificate', 'Certificate', 'Certificate', 10, 'Short programmes focused on one skill area'),
  ('diploma', 'Diploma', 'Diploma', 20, 'Diploma programmes, usually after Class 12'),
  ('ug', 'Undergraduate (UG)', 'UG', 30, 'Bachelor''s degrees and integrated degrees after Class 12'),
  ('pg_diploma', 'PG Diploma / Certificate', 'PG Diploma', 40, 'Postgraduate diplomas and certificates after graduation'),
  ('pg', 'Postgraduate (PG)', 'PG', 50, 'Master''s degrees after graduation'),
  ('doctorate', 'Doctorate', 'Doctorate', 60, 'Doctoral programmes')
on conflict (id) do nothing;

insert into public.web_tax_categories (id, label, sort) values
  ('management', 'Management', 10),
  ('computer-applications-it', 'Computer Applications & IT', 20),
  ('commerce', 'Commerce', 30),
  ('arts-humanities', 'Arts & Humanities', 40),
  ('science', 'Science', 50),
  ('social-work', 'Social Work', 60),
  ('education', 'Education', 70)
on conflict (id) do nothing;

insert into public.web_tax_formats (id, label, description) values
  ('work-integrated', 'Work-integrated learning', 'Study is combined with work at a partner organisation'),
  ('apprenticeship', 'Apprenticeship-embedded', 'Includes a formal apprenticeship alongside the degree'),
  ('work-linked', 'Work-linked', 'Designed around the learner''s current job')
on conflict (id) do nothing;

insert into public.web_tax_programmes (id, short_name, full_name, level_id, category_id, sort) values
  ('mba', 'MBA', 'Master of Business Administration', 'pg', 'management', 10),
  ('mca', 'MCA', 'Master of Computer Applications', 'pg', 'computer-applications-it', 20),
  ('mcom', 'M.Com', 'Master of Commerce', 'pg', 'commerce', 30),
  ('ma', 'MA', 'Master of Arts', 'pg', 'arts-humanities', 40),
  ('msc', 'M.Sc', 'Master of Science', 'pg', 'science', 50),
  ('msw', 'MSW', 'Master of Social Work', 'pg', 'social-work', 60),
  ('bba', 'BBA', 'Bachelor of Business Administration', 'ug', 'management', 10),
  ('bca', 'BCA', 'Bachelor of Computer Applications', 'ug', 'computer-applications-it', 20),
  ('bcom', 'B.Com', 'Bachelor of Commerce', 'ug', 'commerce', 30),
  ('ba', 'BA', 'Bachelor of Arts', 'ug', 'arts-humanities', 40),
  ('bsc', 'B.Sc', 'Bachelor of Science', 'ug', 'science', 50),
  ('bba-mba', 'BBA + MBA', 'BBA + MBA integrated degree', 'ug', 'management', 60),
  ('bca-mca', 'BCA + MCA', 'BCA + MCA integrated degree', 'ug', 'computer-applications-it', 61),
  ('bcom-mba', 'B.Com + MBA', 'B.Com + MBA integrated degree', 'ug', 'commerce', 62),
  ('pgdm', 'PGDM', 'Post Graduate Diploma in Management', 'pg_diploma', 'management', 10),
  ('pgdba', 'PGDBA', 'Post Graduate Diploma in Business Administration', 'pg_diploma', 'management', 20),
  ('pgcm', 'PGCM', 'Post Graduate Certificate in Management', 'pg_diploma', 'management', 30),
  ('dba', 'DBA', 'Diploma in Business Administration', 'diploma', 'management', 10),
  ('dca', 'DCA', 'Diploma in Computer Applications', 'diploma', 'computer-applications-it', 20),
  ('diploma', 'Diploma', 'Diploma', 'diploma', null, 30),
  ('certificate', 'Certificate', 'Certificate programme', 'certificate', null, 10)
on conflict (id) do nothing;

update public.web_tax_programmes p set search_prior = v.prior from (values
  ('mba', 100), ('bba', 80), ('bca', 80), ('mca', 80), ('bcom', 70), ('mcom', 60), ('ba', 60), ('ma', 50), ('pgdm', 50),
  ('msc', 40), ('bsc', 40), ('pgcm', 30), ('pgdba', 30), ('msw', 30)) v(id, prior) where p.id = v.id;

-- Specialisations with their aliases (the canonical name is always an alias too).
with s(id, name, cat, aliases) as (values
  ('general', 'General', null, array['general']),
  ('general-management', 'General Management', 'management', array['general management','business management','business administration']),
  ('marketing', 'Marketing', 'management', array['marketing','marketing management','strategic marketing management','marketing product and growth','sales and marketing']),
  ('digital-marketing', 'Digital Marketing', 'management', array['digital marketing','digital marketing management','chief digital marketing strategist program','digital marketing with ai']),
  ('finance', 'Finance', 'management', array['finance','finance management','financial management','applied finance','financial services']),
  ('accounting-taxation', 'Accounting & Taxation', 'commerce', array['accounting and taxation','business accounting and taxation','accountancy','accounting','accounting with ai','finance and accounting','taxation']),
  ('banking-insurance', 'Banking, Financial Services & Insurance', 'commerce', array['banking and financial services','banking and insurance','banking and finance','bfsi','bfsi management','banking and fintech','banking']),
  ('fintech', 'FinTech', 'management', array['fintech','fintech management','financial technology','fintech regulations and security','finance fintech and investments','it and fintech','financial technology and ai']),
  ('international-finance', 'International Finance', 'management', array['international finance','intenational finance','international finance and accounting']),
  ('financial-analytics', 'Financial Analytics', 'management', array['financial analytics','digital finance and accountinc analytics','digital finance and accounting analytics']),
  ('human-resource-management', 'Human Resource Management', 'management', array['human resource management','hr','hrm','human resource','human resources','hrm human resource management','human capital management','hr and people analytics','people management']),
  ('business-analytics', 'Business Analytics', 'management', array['business analytics','business analytics management','business data analyst','business data analytics','business intelligence technology','business analytics and ai','analytics']),
  ('data-analytics', 'Data Analytics', 'computer-applications-it', array['data analytics','data analysis','data analytics and visualization','big data','big data analytics','data analytics and ai']),
  ('data-science', 'Data Science', 'computer-applications-it', array['data science','data science and analytics','analytics and data science','data science and business analytics','ai and data science','operations and data sciences management']),
  ('data-engineering', 'Data Engineering & Databases', 'computer-applications-it', array['data engineering','applied data engineering','database administration','advanced database nosql','data management']),
  ('ai-ml', 'Artificial Intelligence & Machine Learning', 'computer-applications-it', array['artificial intelligence','ai','ai and ml','aiml','artificial intelligence and machine learning','machine learning','machine learning and ai','machine learning and artificial intelligence','deep learning','natural language processing','quantum machine learning']),
  ('cloud-computing', 'Cloud Computing & DevOps', 'computer-applications-it', array['cloud computing','cloud computing technologies','cloud and security','cloud technology and information security','devops','linux','cloud']),
  ('cyber-security', 'Cyber Security', 'computer-applications-it', array['cyber security','cybersecurity','cyber security and forensics','ethical hacking','information security']),
  ('blockchain', 'Blockchain', 'computer-applications-it', array['blockchain','blockchain technology','blockchain technologies','blockchain management','blockchain technology and management']),
  ('software-development', 'Software Development', 'computer-applications-it', array['software development','software engineering','full stack development','full stack web development','fullstack development','dot net technologies','net centric technologies','open source technologies']),
  ('mobile-app-development', 'Mobile App Development', 'computer-applications-it', array['mobile app development','mobile application development','mobile computing','mobile programming']),
  ('game-development', 'Game Development', 'computer-applications-it', array['game development','game programming','ar vr game development']),
  ('iot', 'Internet of Things', 'computer-applications-it', array['internet of things','internet of things iot','iot','industrial iot and automation']),
  ('emerging-technologies', 'Emerging Technologies', 'computer-applications-it', array['emerging technologies','new age technology','comprehensive emerging technologies','quantum computing']),
  ('ux-design', 'UX Design', 'computer-applications-it', array['ux','ux design','user experience']),
  ('information-technology', 'Information Technology & Systems', 'computer-applications-it', array['information technology','it management','information technology management','it and systems management','information system management','information systems','systems','computer applications']),
  ('computer-science', 'Computer Science', 'science', array['computer science']),
  ('computational-science', 'Computational Science', 'science', array['computational science']),
  ('international-business', 'International Business', 'management', array['international business','international business management','global business']),
  ('operations-management', 'Operations Management', 'management', array['operations','operations management','production and operations management','technology and operations']),
  ('supply-chain-management', 'Logistics & Supply Chain Management', 'management', array['logistics and supply chain management','logistics and supply chain','supply chain management','supply chain','operations and supply chain','operations and supply chain management','operation and supply chain management','business logistics and supply chain management','shipping and logistics management','logistics materials and supply chain management','global logistics and supply chain management','material management','materials management','logistics']),
  ('project-management', 'Project Management', 'management', array['project management','modern project management','construction and project management','construction project management']),
  ('energy-infrastructure', 'Energy & Infrastructure Management', 'management', array['infrastructure management','power management','oil and gas management']),
  ('healthcare-management', 'Healthcare & Hospital Management', 'management', array['healthcare management','health care management','hospital administration','hospital administration and health care management','hospital and healthcare management','pharma and healthcare management','pharma and health care management','healthcare','hospital management']),
  ('biotechnology-management', 'Biotechnology Management', 'management', array['biotechnology management']),
  ('retail-management', 'Retail Management', 'management', array['retail management','retail']),
  ('e-commerce', 'E-Commerce', 'commerce', array['e commerce','ecommerce','e commerce management']),
  ('digital-business', 'Digital Business', 'management', array['digital business','e business']),
  ('entrepreneurship', 'Entrepreneurship', 'management', array['entrepreneurship','entrepreneurship and family business','entrepreneurship and venture building','entrepreneurship management','family business']),
  ('event-management', 'Event Management', 'management', array['event management']),
  ('hospitality-management', 'Hospitality Management', 'management', array['hospitality management','hotel management']),
  ('tourism-management', 'Travel & Tourism Management', 'management', array['tourism management','travel and tourism management']),
  ('sports-management', 'Sports Management', 'management', array['sports management']),
  ('real-estate-management', 'Real Estate Management', 'management', array['real estate management']),
  ('agribusiness-management', 'Agribusiness Management', 'management', array['agribusiness management','agri business','agri business management','agribusiness']),
  ('food-technology-management', 'Food Technology Management', 'management', array['food technology management']),
  ('strategy-leadership', 'Strategy & Leadership', 'management', array['strategy and consulting','leadership and strategy','strategic management','leadership']),
  ('journalism-mass-communication', 'Journalism & Mass Communication', 'arts-humanities', array['journalism and mass communication','mass communication','journalism']),
  ('english', 'English', 'arts-humanities', array['english','english literature','english with communication studies']),
  ('hindi', 'Hindi', 'arts-humanities', array['hindi']),
  ('urdu', 'Urdu', 'arts-humanities', array['urdu']),
  ('arabic', 'Arabic', 'arts-humanities', array['arabic','professional arabic']),
  ('history', 'History', 'arts-humanities', array['history']),
  ('political-science', 'Political Science', 'arts-humanities', array['political science','politics']),
  ('sociology', 'Sociology', 'arts-humanities', array['sociology']),
  ('economics', 'Economics', 'arts-humanities', array['economics','applied economics','econometrics']),
  ('public-policy', 'Public Policy', 'arts-humanities', array['public policy','public policy and development','public policy and governance']),
  ('international-relations', 'International Relations', 'arts-humanities', array['international relations']),
  ('islamic-studies', 'Islamic Studies', 'arts-humanities', array['islamic studies']),
  ('education', 'Education', 'education', array['education','general education']),
  ('mathematics', 'Mathematics', 'science', array['mathematics','maths','math']),
  ('physics', 'Physics', 'science', array['physics']),
  ('drug-regulatory-affairs', 'Drug Regulatory Affairs', 'science', array['drug regulatory affairs'])
), ins as (
  insert into public.web_tax_specialisations (id, name, category_hint)
  select id, name, cat from s on conflict (id) do nothing
)
insert into public.web_tax_synonyms (alias, kind, target_id)
select a, 'specialisation', s.id from s, unnest(s.aliases) a
on conflict do nothing;

-- Programme aliases (seeded from catalog_synonyms where they point at a programme the website has, plus common forms).
insert into public.web_tax_synonyms (alias, kind, target_id)
select a, 'programme', p from (values
  ('mba', array['mba','m b a','master of business administration','masters in business administration','executive mba','emba']),
  ('bba', array['bba','b b a','bachelor of business administration','bachelors in business administration']),
  ('bca', array['bca','b c a','bachelor of computer applications','bachelor of computer application']),
  ('mca', array['mca','m c a','master of computer applications','master of computer application']),
  ('bcom', array['bcom','b com','bachelor of commerce','bcom honours','bcom hons']),
  ('mcom', array['mcom','m com','master of commerce']),
  ('ba', array['ba','b a','bachelor of arts','ba programme','ba prog']),
  ('ma', array['ma','m a','master of arts']),
  ('bsc', array['bsc','b sc','bachelor of science']),
  ('msc', array['msc','m sc','master of science']),
  ('msw', array['msw','master of social work']),
  ('pgdm', array['pgdm','post graduate diploma in management','pg diploma in management','postgraduate diploma in management']),
  ('pgdba', array['pgdba','post graduate diploma in business administration']),
  ('pgcm', array['pgcm','post graduate certificate in management']),
  ('dba', array['diploma in business administration']),
  ('dca', array['dca','diploma in computer applications']),
  ('bba-mba', array['bba mba','bba + mba','integrated bba mba']),
  ('bca-mca', array['bca mca','bca + mca','integrated bca mca']),
  ('bcom-mba', array['bcom mba','b com mba','bcom + mba'])
) v(p, aliases), unnest(v.aliases) a
on conflict do nothing;

insert into public.web_tax_synonyms (alias, kind, target_id) values
  ('ug', 'level', 'ug'), ('undergraduate', 'level', 'ug'), ('bachelor', 'level', 'ug'), ('bachelors', 'level', 'ug'),
  ('graduation', 'level', 'ug'), ('pg', 'level', 'pg'), ('postgraduate', 'level', 'pg'), ('post graduate', 'level', 'pg'),
  ('masters', 'level', 'pg'), ('master', 'level', 'pg'), ('pg diploma', 'level', 'pg_diploma'),
  ('post graduate diploma', 'level', 'pg_diploma'), ('diploma', 'level', 'diploma'), ('certificate', 'level', 'certificate'),
  ('certification', 'level', 'certificate'), ('online', 'mode', 'Online'), ('distance', 'mode', 'ODL'),
  ('odl', 'mode', 'ODL'), ('correspondence', 'mode', 'ODL'), ('distance learning', 'mode', 'ODL'),
  ('management', 'category', 'management'), ('commerce', 'category', 'commerce'), ('arts', 'category', 'arts-humanities'),
  ('humanities', 'category', 'arts-humanities'), ('science', 'category', 'science'),
  ('computer', 'category', 'computer-applications-it'), ('computers', 'category', 'computer-applications-it')
on conflict do nothing;

-- Hinglish / filler words ignored by search.
insert into public.web_tax_synonyms (alias, kind, target_id)
select w, 'stopword', '-' from unnest(array['karna','karni','karna hai','hai','chahiye','mujhe','muje','me','mein','main','ka','ki','ke',
  'kaise','kya','kare','karu','krna','in','for','with','the','a','an','of','course','courses','program','programme','programs',
  'programmes','degree','degrees','best','top','college','colleges','admission','admissions','apply','near','india','from','and',
  'or','to','want','i','do','my','fees','fee','details','information','info','please','pls','plz','is','are','which','what',
  'good','job','jobs','after','under','below','within','upto','up','lakh','lakhs','lac','k','rs','inr','year','years','month',
  'months','working','professional','professionals','specialisation','specialization','specialisations','specializations'])
w on conflict do nothing;

-- Goal and career tags (editable data, spec 5.2).
insert into public.web_tax_goal_tags (id, label, description, sort) values
  ('first-degree', 'Get my first degree', 'Bachelor''s and integrated degrees you can start after Class 12', 10),
  ('career-switch', 'Switch my career', 'Programmes that open a new field, such as management, analytics or technology', 20),
  ('promotion', 'Grow in my current job', 'Postgraduate programmes for a promotion or a bigger role', 30),
  ('upskill-while-working', 'Learn while I work', 'Flexible programmes designed around a job', 40),
  ('government-job-eligibility', 'Meet degree requirements for government jobs', 'Degrees from UGC-entitled universities; always check the specific recruitment rules', 50),
  ('higher-studies', 'Prepare for higher studies', 'Degrees that lead on to a master''s or further study', 60),
  ('start-a-business', 'Start or grow a business', 'Management and entrepreneurship programmes', 70)
on conflict (id) do nothing;

insert into public.web_tax_tag_links (tag_kind, tag_id, programme_id)
select 'goal', g, p from (values
  ('first-degree', array['ba','bba','bca','bcom','bsc','bba-mba','bca-mca','bcom-mba']),
  ('career-switch', array['mba','pgdm','pgcm','mca','pgdba']),
  ('promotion', array['mba','pgdm','pgcm','mcom','mca','msc','ma','pgdba']),
  ('upskill-while-working', array['mba','pgdm','pgcm','pgdba','mca','mcom','ma','msc','dba','dca','diploma','certificate']),
  ('government-job-eligibility', array['ba','bcom','bsc','bba','bca','ma','mcom','msc','mba','mca','msw']),
  ('higher-studies', array['ba','bcom','bsc','bba','bca','ma','mcom','msc']),
  ('start-a-business', array['bba','mba','pgdm'])
) v(g, progs), unnest(v.progs) p
on conflict do nothing;
insert into public.web_tax_tag_links (tag_kind, tag_id, specialisation_id)
select 'goal', g, s from (values
  ('career-switch', array['data-science','business-analytics','data-analytics','ai-ml','digital-marketing','cyber-security','cloud-computing']),
  ('start-a-business', array['entrepreneurship','digital-business','e-commerce'])
) v(g, specs), unnest(v.specs) s
on conflict do nothing;

insert into public.web_tax_career_tags (id, label, sort) values
  ('marketing-manager', 'Marketing manager', 10), ('digital-marketer', 'Digital marketer', 20),
  ('data-analyst', 'Data analyst', 30), ('data-scientist', 'Data scientist', 40), ('hr-manager', 'HR manager', 50),
  ('financial-analyst', 'Financial analyst', 60), ('banking-professional', 'Banking professional', 70),
  ('software-developer', 'Software developer', 80), ('operations-manager', 'Operations manager', 90),
  ('supply-chain-manager', 'Supply chain manager', 100), ('business-analyst', 'Business analyst', 110),
  ('entrepreneur', 'Entrepreneur', 120), ('healthcare-administrator', 'Healthcare administrator', 130),
  ('accountant', 'Accountant', 140), ('cyber-security-analyst', 'Cyber security analyst', 150)
on conflict (id) do nothing;
insert into public.web_tax_tag_links (tag_kind, tag_id, specialisation_id)
select 'career', c, s from (values
  ('marketing-manager', array['marketing','digital-marketing']), ('digital-marketer', array['digital-marketing']),
  ('data-analyst', array['data-analytics','business-analytics','data-science']), ('data-scientist', array['data-science','ai-ml']),
  ('hr-manager', array['human-resource-management']), ('financial-analyst', array['finance','financial-analytics','international-finance']),
  ('banking-professional', array['banking-insurance','fintech']), ('software-developer', array['software-development','mobile-app-development','cloud-computing']),
  ('operations-manager', array['operations-management']), ('supply-chain-manager', array['supply-chain-management']),
  ('business-analyst', array['business-analytics']), ('entrepreneur', array['entrepreneurship','digital-business']),
  ('healthcare-administrator', array['healthcare-management']), ('accountant', array['accounting-taxation']),
  ('cyber-security-analyst', array['cyber-security'])
) v(c, specs), unnest(v.specs) s
on conflict do nothing;

-- Auto-mapping rules.
insert into public.web_tax_rules_programme (priority, course_key, program_name_re, programme_id, spec_from_name_re, note) values
  (10, 'diploma', '^post\s*graduate diploma', 'pgdba', null, 'PG Diploma in Business Administration rows stored as DIPLOMA'),
  (20, 'diploma', '^advanced diploma', 'diploma', '^advanced diploma in (.+?)(?:\s+program(?:me)?)?\s*-', 'Advanced diplomas'),
  (30, 'diploma', null, 'diploma', '^diploma in (.+?)(?:\s+course)?\s*-', 'Generic diplomas; subject from the name'),
  (40, 'certificate', null, 'certificate', '^certificate program(?:me)? in (.+?)\s*-', 'Generic certificates; subject from the name'),
  (100, 'mba', null, 'mba', null, null), (100, 'mca', null, 'mca', null, null), (100, 'mcom', null, 'mcom', null, null),
  (100, 'ma', null, 'ma', null, null), (100, 'msc', null, 'msc', null, null), (100, 'msw', null, 'msw', null, null),
  (100, 'bba', null, 'bba', null, null), (100, 'bca', null, 'bca', null, null), (100, 'bcom', null, 'bcom', null, null),
  (100, 'ba', null, 'ba', null, null), (100, 'bsc', null, 'bsc', null, null), (100, 'bbamba', null, 'bba-mba', null, null),
  (100, 'bcamca', null, 'bca-mca', null, null), (100, 'bcommba', null, 'bcom-mba', null, null),
  (100, 'pgdm', null, 'pgdm', null, null), (100, 'pgcm', null, 'pgcm', null, null), (100, 'dba', null, 'dba', null, null),
  (100, 'dca', null, 'dca', null, null);

insert into public.web_tax_rules_attribute (priority, pattern, attribute, value_from_capture, replace_with, note) values
  (10, '\(\s*with\s+pap\s+option\s*\)', 'pay_after_placement', false, null, null),
  (10, '\(\s*with\s+pay\s+after\s+placement\s+option\s*\)', 'pay_after_placement', false, null, null),
  (10, '\(\s*hon(?:ou)?rs\s*\)|\(\s*hons\s*\)', 'honours', false, null, null),
  (10, '\(\s*executive\s*\)', 'executive', false, null, null),
  (10, '\(\s*with\s+internship\s*\)', 'internship', false, null, null),
  (10, '\(\s*dual\s+speciali[sz]ation\s*\)', 'dual_specialisation', false, null, null),
  (10, '\(\s*professional\s+certificate\s*\)', 'professional_certificate', false, null, null),
  (10, '\(\s*advanced\s*\)', 'advanced', false, null, null),
  (20, '^\s*(hindi|kannada|malayalam|tamil|telugu|marathi|bengali|urdu)\s+medium\s*$', 'medium', true, 'General', 'Language of instruction, not a subject'),
  (20, '^\s*dual\s+speciali[sz]ation\s*$', 'dual_specialisation', false, 'General', 'Student picks two specialisations'),
  (20, '^\s*hon(?:ou)?rs\s*$', 'honours', false, 'General', null);

insert into public.web_tax_rules_format (pattern, format) values
  ('^\s*apprenticeship\s+embedded\s+degree\s+program(?:me)?\s*$', 'apprenticeship'),
  ('^\s*work\s+integrated\s+(?:learning\s+)?program(?:me)?\s*$', 'work-integrated'),
  ('^\s*work\s+linked\s+program(?:me)?\s*$', 'work-linked');

-- Catalogue-derived taxonomy data: university profiles and aliases, catalogue course synonyms. Idempotent; run by
-- the catalogue poller whenever the catalogue changes, so new universities get a profile (slug) and aliases.
create table if not exists public.web_university_defaults (
  name text primary key,          -- catalogue university name
  slug text not null unique,
  display_name text not null,
  aliases text[] not null default '{}'
);
alter table public.web_university_defaults enable row level security;
revoke all on public.web_university_defaults from anon, authenticated, public;
grant select, insert, update, delete on public.web_university_defaults to service_role;

insert into public.web_university_defaults (name, slug, display_name)
select name, slug, display from (values
  ('ARKA JAIN University', 'arka-jain-university', 'ARKA JAIN University'),
  ('Alliance University', 'alliance-university', 'Alliance University'),
  ('Amity University', 'amity-university', 'Amity University'),
  ('Aligarh Muslim University', 'aligarh-muslim-university', 'Aligarh Muslim University'),
  ('Andhra University', 'andhra-university', 'Andhra University'),
  ('BML Munjal University', 'bml-munjal-university', 'BML Munjal University'),
  ('Bharati Vidyapeeth Deemed University', 'bharati-vidyapeeth', 'Bharati Vidyapeeth (Deemed to be University)'),
  ('Chaudhary Charan Singh University', 'chaudhary-charan-singh-university', 'Chaudhary Charan Singh University'),
  ('Christ University', 'christ-university', 'Christ University'),
  ('Deen Dayal Upadhyay Gorakhpur University', 'ddu-gorakhpur-university', 'Deen Dayal Upadhyay Gorakhpur University'),
  ('D. Y. Patil University', 'dy-patil-university', 'D. Y. Patil University'),
  ('Dayananda Sagar University', 'dayananda-sagar-university', 'Dayananda Sagar University'),
  ('Galgotias University', 'galgotias-university', 'Galgotias University'),
  ('GLA University', 'gla-university', 'GLA University'),
  ('Jain University', 'jain-university', 'Jain University'),
  ('Jamia Hamdard University', 'jamia-hamdard', 'Jamia Hamdard'),
  ('JAYPEE INSTITUTE OF INFORMATION TECHNOLOGY', 'jaypee-institute-of-information-technology', 'Jaypee Institute of Information Technology'),
  ('Lovely Professional University', 'lovely-professional-university', 'Lovely Professional University'),
  ('Maharashtra Institute of Technology', 'mit-school-of-distance-education', 'MIT School of Distance Education'),
  ('Manipal University Jaipur', 'manipal-university-jaipur', 'Manipal University Jaipur'),
  ('Mizoram University', 'mizoram-university', 'Mizoram University'),
  ('Narsee Monjee Institute of Management Studies', 'nmims', 'NMIMS'),
  ('Shoolini University', 'shoolini-university', 'Shoolini University'),
  ('Sikkim Manipal University', 'sikkim-manipal-university', 'Sikkim Manipal University'),
  ('Sandip University', 'sandip-university', 'Sandip University'),
  ('University of Petroleum and Energy Studies', 'upes', 'UPES'),
  ('Uttaranchal University', 'uttaranchal-university', 'Uttaranchal University'),
  ('Vivekananda Global University', 'vivekananda-global-university', 'Vivekananda Global University'),
  ('Vellore Institute of Technology', 'vit', 'VIT')
) v(name, slug, display)
on conflict (name) do nothing;

update public.web_university_defaults d set aliases = v.aliases
from (values
  ('ARKA JAIN University', array['arka jain','aju']), ('Amity University', array['amity','amity online']),
  ('Aligarh Muslim University', array['aligarh','amu']), ('Andhra University', array['andhra']),
  ('Bharati Vidyapeeth Deemed University', array['bharati vidyapeeth','bvdu','bharati']),
  ('Chaudhary Charan Singh University', array['ccsu','ccs university','ccs']), ('Christ University', array['christ']),
  ('Deen Dayal Upadhyay Gorakhpur University', array['ddu','gorakhpur university','ddu gorakhpur']),
  ('D. Y. Patil University', array['dy patil','d y patil','dpu','dypatil']), ('Dayananda Sagar University', array['dayananda sagar','dsu']),
  ('Galgotias University', array['galgotias','galgotia']), ('GLA University', array['gla']), ('Jain University', array['jain','jain online']),
  ('Jamia Hamdard University', array['jamia hamdard','hamdard']), ('JAYPEE INSTITUTE OF INFORMATION TECHNOLOGY', array['jaypee','jiit']),
  ('Lovely Professional University', array['lpu','lovely']), ('Maharashtra Institute of Technology', array['mitsde','mit']),
  ('Manipal University Jaipur', array['manipal','muj','manipal jaipur']), ('Mizoram University', array['mizoram','mzu']),
  ('Narsee Monjee Institute of Management Studies', array['nmims','narsee monjee']), ('Shoolini University', array['shoolini']),
  ('Sikkim Manipal University', array['manipal','smu','sikkim manipal']), ('Sandip University', array['sandip']),
  ('University of Petroleum and Energy Studies', array['upes']), ('Uttaranchal University', array['uttaranchal']),
  ('Vivekananda Global University', array['vgu','vivekananda global']), ('Vellore Institute of Technology', array['vit','vellore']),
  ('BML Munjal University', array['bml munjal','bml']), ('Alliance University', array['alliance'])
) v(name, aliases)
where d.name = v.name;

create or replace function public.web_tax_sync_catalog()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_profiles int; v_syn int; v_cat int;
begin
  insert into public.web_university_profiles (catalog_university_id, slug, display_name)
  select u.id,
         coalesce(d.slug, public.web_slugify(u.name)),
         coalesce(d.display_name, u.name)
  from public.catalog_universities u
  left join public.web_university_defaults d on d.name = u.name
  where not exists (select 1 from public.web_university_profiles p where p.catalog_university_id = u.id)
    and not exists (select 1 from public.web_university_profiles p where p.slug = coalesce(d.slug, public.web_slugify(u.name)))
  on conflict do nothing;
  get diagnostics v_profiles = row_count;

  insert into public.web_tax_synonyms (alias, kind, target_id)
  select x, 'university', u.id::text
  from public.catalog_universities u
  left join public.web_university_defaults d on d.name = u.name
  cross join lateral unnest(array[u.name, u.short_name] || coalesce(d.aliases, '{}')) x
  where public.web_norm(x) is not null
  on conflict do nothing;
  get diagnostics v_syn = row_count;

  insert into public.web_tax_synonyms (alias, kind, target_id, source)
  select s.alias, 'programme', s.course_key, 'catalog_synonyms'
  from public.catalog_synonyms s
  where exists (select 1 from public.web_tax_programmes p where p.id = s.course_key)
    -- "onlinemba"/"distancemba" would swallow the study-mode word; mode is resolved separately.
    and s.alias !~* '(online|distance)'
  on conflict do nothing;
  get diagnostics v_cat = row_count;

  return jsonb_build_object('profiles_added', v_profiles, 'university_aliases_added', v_syn, 'catalog_synonyms_added', v_cat);
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- Auto-mapper (spec 5.3): deterministic rules first, then synonyms, splits, the name, and finally fuzzy matching.
-- Admin mappings are never overwritten; if the catalogue row changes after an admin mapping, it is flagged for review.

create or replace function public.web_tax_strip_attributes(p text, out clean text, out attrs jsonb)
language plpgsql stable security definer set search_path = '' as $$
declare r record; m text[];
begin
  clean := coalesce(p, '');
  attrs := '{}';
  for r in select * from public.web_tax_rules_attribute where active order by priority, id loop
    m := regexp_match(clean, r.pattern, 'i');
    if m is not null then
      attrs := attrs || jsonb_build_object(r.attribute,
        case when r.value_from_capture and m[1] is not null then to_jsonb(initcap(m[1])) else 'true'::jsonb end);
      if r.replace_with is not null then
        clean := r.replace_with;
      else
        clean := regexp_replace(clean, r.pattern, ' ', 'i');
      end if;
    end if;
  end loop;
  clean := btrim(regexp_replace(clean, '\s+', ' ', 'g'));
end $$;

-- Exact alias lookup for one specialisation phrase.
create or replace function public.web_tax_spec_lookup(p text)
returns text language sql stable security definer set search_path = '' as $$
  select s.target_id from public.web_tax_synonyms s
  join public.web_tax_specialisations t on t.id = s.target_id and t.active
  where s.kind = 'specialisation' and s.alias_compact = replace(public.web_norm(p), ' ', '')
  order by s.weight desc, s.id limit 1
$$;

-- Resolves a specialisation phrase: whole phrase, else a split into two known parts at an "and".
create or replace function public.web_tax_resolve_spec(p text, out ids text[], out confidence text)
language plpgsql stable security definer set search_path = '' as $$
declare n text; v text; words text[]; i int; l text; r text; lid text; rid text;
begin
  n := public.web_norm(p);
  if n is null then return; end if;
  v := public.web_tax_spec_lookup(n);
  if v is not null then
    ids := array[v];
    confidence := case when exists (select 1 from public.web_tax_specialisations where id = v and public.web_norm(name) = n)
                       then 'exact' else 'synonym' end;
    return;
  end if;
  words := string_to_array(n, ' ');
  for i in 2 .. coalesce(array_length(words, 1), 0) - 1 loop
    if words[i] = 'and' then
      l := array_to_string(words[1:i-1], ' ');
      r := array_to_string(words[i+1:], ' ');
      lid := public.web_tax_spec_lookup(l);
      rid := public.web_tax_spec_lookup(r);
      if lid is not null and rid is not null and lid <> rid then
        ids := array[lid, rid];
        confidence := 'split';
        return;
      end if;
    end if;
  end loop;
end $$;

create or replace function public.web_tax_fingerprint(c public.catalog_programs)
returns text language sql immutable security definer set search_path = '' as $$
  select md5(concat_ws('|', c.course_key, c.course, c.level_raw, c.specialization, c.program_name))
$$;

-- Maps one catalogue row; returns the proposed mapping (does not write).
create or replace function public.web_tax_propose(c public.catalog_programs)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rule public.web_tax_rules_programme;
  v_format text; v_raw text; v_name text; v_tail text; v_capture text;
  v_course_attrs jsonb; v_spec_attrs jsonb; v_clean text; v_ids text[]; v_conf text; v_note text;
  v_attrs jsonb;
begin
  select * into v_rule from public.web_tax_rules_programme r
   where r.active and r.course_key = c.course_key
     and (r.program_name_re is null or c.program_name ~* r.program_name_re)
   order by r.priority, r.id limit 1;

  v_raw := coalesce(c.specialization, '');
  v_name := coalesce(c.program_name, '');

  -- Delivery formats stored as the specialisation: the subject is inside program_name.
  select f.format into v_format from public.web_tax_rules_format f where f.active and v_raw ~* f.pattern limit 1;
  if v_format is not null then
    if right(v_name, length(v_raw)) = v_raw then
      v_name := regexp_replace(left(v_name, length(v_name) - length(v_raw)), '[\s-]+$', '');
    end if;
    v_raw := coalesce(substring(v_name from '^[^-]*-\s*(.+)$'), 'General');
    v_note := 'format row; subject from program_name';
  else
    -- Repair specialisations the loader cut at a hyphen ("Full-Stack Development" stored as "Stack Development").
    v_tail := btrim(substring(v_name from '^[^-]*-\s*(.+)$'));
    if v_tail is not null and length(v_tail) > length(v_raw) and v_raw <> ''
       and lower(v_tail) like '%' || lower(v_raw) and lower(v_tail) <> lower(v_raw)
       and substring(lower(v_tail) from length(v_tail) - length(v_raw)) ~ '^[-\s]' then
      v_raw := v_tail;
      v_note := 'specialisation repaired from program_name';
    end if;
  end if;

  select a.clean, a.attrs into v_clean, v_spec_attrs from public.web_tax_strip_attributes(v_raw) a;
  select a.attrs into v_course_attrs from public.web_tax_strip_attributes(c.course) a;
  v_attrs := coalesce(v_course_attrs, '{}') || coalesce(v_spec_attrs, '{}');

  select r.ids, r.confidence into v_ids, v_conf from public.web_tax_resolve_spec(v_clean) r;

  -- Generic programmes (diploma, certificate): the subject in the programme name beats a generic stored value.
  if v_rule.spec_from_name_re is not null and (v_ids is null or v_ids = array['general']) then
    v_capture := (regexp_match(c.program_name, v_rule.spec_from_name_re, 'i'))[1];
    if v_capture is not null then
      declare n_ids text[]; n_conf text;
      begin
        select r.ids, r.confidence into n_ids, n_conf from public.web_tax_resolve_spec(v_capture) r;
        if n_ids is not null then
          v_ids := n_ids; v_conf := 'name'; v_clean := initcap(v_capture);
          v_note := concat_ws('; ', v_note, 'specialisation from programme name');
        end if;
      end;
    end if;
  end if;

  -- Fuzzy fallback (flagged for review).
  if v_ids is null and public.web_norm(v_clean) is not null then
    select array[s.target_id], 'fuzzy' into v_ids, v_conf
    from public.web_tax_synonyms s
    where s.kind = 'specialisation' and public.similarity(s.alias_norm, public.web_norm(v_clean)) >= 0.6
    order by public.similarity(s.alias_norm, public.web_norm(v_clean)) desc limit 1;
  end if;

  return jsonb_build_object(
    'programme_id', v_rule.programme_id,
    'specialisation_ids', to_jsonb(coalesce(v_ids, '{}'::text[])),
    'spec_display', nullif(v_clean, ''),
    'format', v_format,
    'attributes', v_attrs,
    'confidence', v_conf,
    'rule_note', v_note
  );
end $$;

create or replace function public.web_tax_automap(p_dry_run boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  c public.catalog_programs; v_map public.web_tax_offering_map; v jsonb; fp text;
  n_new int := 0; n_changed int := 0; n_review int := 0; n_same int := 0;
begin
  perform public.web_tax_sync_catalog();
  for c in select * from public.catalog_programs order by id loop
    fp := public.web_tax_fingerprint(c);
    select * into v_map from public.web_tax_offering_map where catalog_program_id = c.id;
    if v_map.catalog_program_id is not null and v_map.source_fingerprint = fp then
      n_same := n_same + 1;
      continue;
    end if;
    if v_map.mapped_by = 'admin' then
      n_review := n_review + 1;
      if not p_dry_run then
        update public.web_tax_offering_map set needs_review = true, source_fingerprint = fp, program_key = c.program_key,
          rule_note = 'catalogue row changed after admin mapping', updated_at = now()
        where catalog_program_id = c.id;
      end if;
      continue;
    end if;
    v := public.web_tax_propose(c);
    if v_map.catalog_program_id is null then n_new := n_new + 1; else n_changed := n_changed + 1; end if;
    if not p_dry_run then
      insert into public.web_tax_offering_map as t (catalog_program_id, program_key, programme_id, specialisation_ids,
        spec_display, format, attributes, mapped_by, confidence, rule_note, source_fingerprint, needs_review, updated_at)
      values (c.id, c.program_key, v->>'programme_id',
        array(select jsonb_array_elements_text(v->'specialisation_ids')),
        v->>'spec_display', v->>'format', v->'attributes', 'rule', v->>'confidence', v->>'rule_note', fp,
        coalesce(v->>'confidence', 'none') in ('fuzzy', 'none') or v->>'programme_id' is null, now())
      on conflict (catalog_program_id) do update set
        program_key = excluded.program_key, programme_id = excluded.programme_id,
        specialisation_ids = excluded.specialisation_ids, spec_display = excluded.spec_display, format = excluded.format,
        attributes = excluded.attributes, confidence = excluded.confidence, rule_note = excluded.rule_note,
        source_fingerprint = excluded.source_fingerprint, needs_review = excluded.needs_review, updated_at = now()
      where t.mapped_by = 'rule';
    end if;
  end loop;
  return jsonb_build_object('new', n_new, 'changed', n_changed, 'admin_needs_review', n_review, 'unchanged', n_same,
    'dry_run', p_dry_run,
    'unmapped', (select count(*) from public.catalog_programs cp left join public.web_tax_offering_map om on om.catalog_program_id = cp.id
                 where cp.active and (om.programme_id is null or cardinality(om.specialisation_ids) = 0)));
end $$;

-- Unmapped and review queue (admin, spec 5.3): nothing is silently lost.
create or replace function public.web_tax_unmapped()
returns table (catalog_program_id bigint, university text, course text, specialization text, program_name text, mode text,
               active boolean, programme_id text, specialisation_ids text[], confidence text, reason text)
language sql stable security definer set search_path = '' as $$
  select c.id, u.name, c.course, c.specialization, c.program_name, c.mode, c.active, m.programme_id,
         coalesce(m.specialisation_ids, '{}'), m.confidence,
         case when m.catalog_program_id is null then 'not yet mapped'
              when m.programme_id is null then 'no programme rule'
              when cardinality(m.specialisation_ids) = 0 then 'specialisation not recognised'
              when m.needs_review then coalesce(m.rule_note, 'needs review')
         end
  from public.catalog_programs c
  join public.catalog_universities u on u.id = c.university_id
  left join public.web_tax_offering_map m on m.catalog_program_id = c.id
  where m.catalog_program_id is null or m.programme_id is null or cardinality(m.specialisation_ids) = 0 or m.needs_review
  order by c.active desc, u.name, c.program_name
$$;

-- Admin override (Phase 10 UI). Validates targets; audited.
create or replace function public.web_tax_set_mapping(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_id bigint := (p->>'catalog_program_id')::bigint; v_specs text[]; c public.catalog_programs;
begin
  select * into c from public.catalog_programs where id = v_id;
  if c.id is null then return jsonb_build_object('ok', false, 'reason', 'unknown_offering'); end if;
  if not exists (select 1 from public.web_tax_programmes where id = p->>'programme_id') then
    return jsonb_build_object('ok', false, 'reason', 'unknown_programme');
  end if;
  v_specs := array(select jsonb_array_elements_text(coalesce(p->'specialisation_ids', '[]')));
  if cardinality(v_specs) = 0 or exists (select 1 from unnest(v_specs) s where not exists
      (select 1 from public.web_tax_specialisations t where t.id = s)) then
    return jsonb_build_object('ok', false, 'reason', 'unknown_specialisation');
  end if;
  insert into public.web_tax_offering_map as t (catalog_program_id, program_key, programme_id, specialisation_ids, spec_display,
    format, attributes, mapped_by, confidence, rule_note, source_fingerprint, needs_review, reviewed_at, reviewed_by, hidden_reason)
  values (v_id, c.program_key, p->>'programme_id', v_specs, nullif(p->>'spec_display', ''), nullif(p->>'format', ''),
    coalesce(p->'attributes', '{}'), 'admin', 'admin', nullif(p->>'note', ''), public.web_tax_fingerprint(c), false, now(),
    p->>'actor_email', nullif(p->>'hidden_reason', ''))
  on conflict (catalog_program_id) do update set programme_id = excluded.programme_id,
    specialisation_ids = excluded.specialisation_ids, spec_display = coalesce(excluded.spec_display, t.spec_display),
    format = excluded.format, attributes = excluded.attributes, mapped_by = 'admin', confidence = 'admin',
    rule_note = excluded.rule_note, source_fingerprint = excluded.source_fingerprint, needs_review = false,
    reviewed_at = now(), reviewed_by = excluded.reviewed_by, hidden_reason = excluded.hidden_reason, updated_at = now();
  insert into public.web_audit_log (actor, action, entity, entity_id, after)
  values (nullif(p->>'actor_id', '')::uuid, 'taxonomy.set_mapping', 'web_tax_offering_map', v_id::text, p - 'actor_id');
  return jsonb_build_object('ok', true);
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.web_tax_sync_catalog()', 'public.web_tax_strip_attributes(text)', 'public.web_tax_spec_lookup(text)',
    'public.web_tax_resolve_spec(text)', 'public.web_tax_fingerprint(public.catalog_programs)',
    'public.web_tax_propose(public.catalog_programs)', 'public.web_tax_automap(boolean)', 'public.web_tax_unmapped()',
    'public.web_tax_set_mapping(jsonb)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
-- web_norm / web_slugify are pure helpers used by generated columns; still not exposed to the browser roles.
revoke all on function public.web_norm(text), public.web_slugify(text) from public, anon, authenticated;
grant execute on function public.web_norm(text), public.web_slugify(text) to service_role;

-- Map whatever the catalogue holds now (production at deploy; locally the seed calls it after loading).
select public.web_tax_automap(false);
