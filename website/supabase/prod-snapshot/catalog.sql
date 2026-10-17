-- =====================================================================================================================
-- Snapshot of production schema taken 2026-10-17, read-only, for local dev.
-- Source: Supabase project xlseqwgyjuqhktrguhyc (Mumbai), reconstructed from pg_catalog / information_schema /
-- pg_get_viewdef / pg_get_functiondef / pg_indexes with SELECT-only queries. NOTHING here was run against production.
--
-- Scope: the shared programme catalogue.
--   public.catalog_universities, public.catalog_programs, public.catalog_synonyms, public.catalog_stage (loader staging)
--   schema catalog: catalog.changes + views universities_v, synonyms_v, programmes_v (partner_rates_v kept as reference only)
--   public.course_directory / public.eduwit_knowledge_base (legacy Witty v1 n8n vector stores, 3072-dim embeddings)
--   trigger function catalog_programs_fee_check + its dependency w2_fee_sanity; loader functions catalog_stage_add /
--   catalog_commit / catalog_load / catalog_remove_source (+ w2_bump, w2_meta, w2_search_cache minimal stubs)
--
-- Ownership: these base tables are owned by Witty (n8n loads them through catalog_stage_add + catalog_commit) and are read
-- by the B2B CRM, B2C CRM and Witty. The website must NEVER alter them; build web_* objects keyed to catalog_programs.id /
-- program_key instead.
--
-- Seed data: website/supabase/seed/catalog_sample.json (29 universities, 715 programmes, 32 synonyms).
-- When seeding, either disable catalog_programs_fee_check_trg or accept that it re-runs the fee sanity check.
-- =====================================================================================================================

create extension if not exists pg_trgm with schema public;      -- production: pg_trgm 1.6 in schema public
create extension if not exists vector with schema public;       -- production: vector 0.8.0 in schema public

-- ---------------------------------------------------------------------------------------------------------------------
-- Sequences
-- ---------------------------------------------------------------------------------------------------------------------
create sequence if not exists public.catalog_universities_id_seq;
create sequence if not exists public.catalog_programs_id_seq;
create sequence if not exists public.course_directory_id_seq;
create sequence if not exists public.eduwit_knowledge_base_id_seq;

-- ---------------------------------------------------------------------------------------------------------------------
-- public.catalog_universities   (29 rows)
-- No state, logo, NAAC, NIRF, UGC-DEB validity columns: approvals live in recognitions[] + the free-text
-- accreditation_text "DATA_CHUNK" blob (see db.md §1.4).
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.catalog_universities (
  id bigint DEFAULT nextval('catalog_universities_id_seq'::regclass) NOT NULL,
  name text NOT NULL,
  short_name text,
  institution_type text,
  recognitions text[],
  accreditation_text text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT catalog_universities_name_key UNIQUE (name),
  CONSTRAINT catalog_universities_pkey PRIMARY KEY (id)
);
alter sequence public.catalog_universities_id_seq owned by public.catalog_universities.id;

-- ---------------------------------------------------------------------------------------------------------------------
-- public.catalog_programs   (715 rows, all active, all source_file = 'master')
-- program_key = md5(lower(university.name) || '|' || lower(program_name) || '|' || lower(coalesce(mode,'')))
-- (set by catalog_commit; upsert key, so ids are stable while name+mode are unchanged; renamed rows get a new id and the
-- old one is deactivated). No duration / intake / EMI / approval columns; extras live in fee_other jsonb.
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.catalog_programs (
  id bigint DEFAULT nextval('catalog_programs_id_seq'::regclass) NOT NULL,
  university_id bigint NOT NULL,
  level text,
  level_raw text,
  course text,
  course_key text,
  dual boolean DEFAULT false NOT NULL,
  specialization text,
  program_name text NOT NULL,
  mode text,
  fee_yearly numeric,
  fee_semester numeric,
  fee_total numeric,
  fee_exam numeric,
  fee_registration numeric,
  fee_other jsonb,
  min_qualification text,
  min_pct_general numeric,
  min_pct_reserved numeric,
  eligibility_text text,
  brochure_url text,
  source_row integer,
  flags text[],
  active boolean DEFAULT true NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  program_key text,
  search_doc tsvector GENERATED ALWAYS AS (to_tsvector('simple'::regconfig, ((((COALESCE(program_name, ''::text) || ' '::text) || COALESCE(specialization, ''::text)) || ' '::text) || COALESCE(course, ''::text)))) STORED,
  source_file text,
  CONSTRAINT catalog_programs_pkey PRIMARY KEY (id),
  CONSTRAINT catalog_programs_university_id_fkey FOREIGN KEY (university_id) REFERENCES public.catalog_universities(id) ON DELETE CASCADE
);
alter sequence public.catalog_programs_id_seq owned by public.catalog_programs.id;
CREATE INDEX IF NOT EXISTS catalog_programs_course_idx ON public.catalog_programs USING btree (course_key, level, mode) WHERE active;
CREATE INDEX IF NOT EXISTS catalog_programs_name_trgm ON public.catalog_programs USING gin (program_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS catalog_programs_spec_trgm ON public.catalog_programs USING gin (specialization gin_trgm_ops);
CREATE UNIQUE INDEX IF NOT EXISTS catalog_programs_key_idx ON public.catalog_programs USING btree (program_key);
CREATE INDEX IF NOT EXISTS catalog_programs_search_idx ON public.catalog_programs USING gin (search_doc);
CREATE INDEX IF NOT EXISTS catalog_programs_uni_idx ON public.catalog_programs USING btree (university_id);
CREATE INDEX IF NOT EXISTS catalog_programs_course_trgm ON public.catalog_programs USING gin (course gin_trgm_ops);
CREATE INDEX IF NOT EXISTS catalog_programs_source_idx ON public.catalog_programs USING btree (source_file);
CREATE INDEX IF NOT EXISTS catalog_programs_course_spec_idx ON public.catalog_programs USING btree (course_key, specialization) WHERE active;

-- ---------------------------------------------------------------------------------------------------------------------
-- public.catalog_synonyms   (32 rows). Course-level only (alias -> course_key); aliases are lower-case alphanumerics with
-- spaces/punctuation removed ("masterofbusinessadministration"). No specialisation synonyms exist in the database.
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.catalog_synonyms (
  alias text NOT NULL,
  course_key text NOT NULL,
  CONSTRAINT catalog_synonyms_pkey PRIMARY KEY (alias)
);

-- ---------------------------------------------------------------------------------------------------------------------
-- public.catalog_stage   (0 rows) — transient staging area for the n8n catalogue loader: rows are added per batch by
-- catalog_stage_add(batch, {universities:[...], programs:[...]}) and consumed/deleted by catalog_commit(batch).
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.catalog_stage (
  batch text NOT NULL,
  kind text NOT NULL,
  "row" jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS catalog_stage_batch_idx ON public.catalog_stage USING btree (batch, kind);

-- ---------------------------------------------------------------------------------------------------------------------
-- Legacy Witty v1 (n8n LangChain) vector stores. Not referenced by any SQL function except match_documents /
-- match_eduwit_knowledge_base. course_directory = 715 text chunks (one per programme, built from the same master sheet);
-- eduwit_knowledge_base = 35 FAQ chunks from Google Drive PDFs. NOT a source of truth.
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.course_directory (
  id bigint DEFAULT nextval('course_directory_id_seq'::regclass) NOT NULL,
  content text NOT NULL,
  metadata jsonb,
  embedding vector(3072),
  CONSTRAINT course_directory_pkey PRIMARY KEY (id)
);
CREATE TABLE IF NOT EXISTS public.eduwit_knowledge_base (
  id bigint DEFAULT nextval('eduwit_knowledge_base_id_seq'::regclass) NOT NULL,
  content text,
  metadata jsonb,
  embedding vector(3072),
  CONSTRAINT eduwit_knowledge_base_pkey PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------------------------------------------------
-- Minimal stubs for objects the catalogue functions touch (NOT the real definitions; enough to make this file load).
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.w2_meta (            -- real table: key text PK, value jsonb, updated_at timestamptz
  key text PRIMARY KEY,
  value jsonb,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS public.w2_search_cache (    -- STUB: real column list not snapshotted (catalog_commit only deletes from it)
  key text PRIMARY KEY,
  value jsonb,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- ---------------------------------------------------------------------------------------------------------------------
-- Functions (verbatim pg_get_functiondef). Production grants: EXECUTE to PUBLIC/anon/authenticated/service_role on all of
-- these (they are SECURITY INVOKER, so RLS on the tables still applies).
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.w2_bump(p_key text)
 RETURNS integer
 LANGUAGE sql
AS $function$
insert into w2_meta (key, value) values (p_key, '1'::jsonb)
on conflict (key) do update set value = to_jsonb(coalesce((w2_meta.value #>> '{}')::int, 0) + 1), updated_at = now()
returning (value #>> '{}')::int;
$function$;

CREATE OR REPLACE FUNCTION public.w2_fee_sanity(p_level text, p_dual boolean, p_y numeric, p_s numeric, p_t numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare
  -- allowed ratio of total to yearly fee, by programme length
  t_lo numeric; t_hi numeric;
  y numeric := nullif(p_y, 0); s numeric := nullif(p_s, 0); t numeric := nullif(p_t, 0);
  ys boolean; yt boolean; st boolean;          -- pair consistent? (null = pair not present)
  bad int;
  note text := null;
  k int;
  w numeric;                                   -- extra tolerance when only two fees exist (one-time charges blur them)
begin
  if coalesce(p_dual, false) then t_lo := 1.0; t_hi := 6.0;           -- dual degrees: 4-5 years
  elsif upper(coalesce(p_level, '')) = 'PG' then t_lo := 1.7; t_hi := 2.8;   -- 2-year masters (+ one-time fees)
  elsif upper(coalesce(p_level, '')) = 'UG' then t_lo := 2.6; t_hi := 4.6;   -- 3- or 4-year bachelors
  else t_lo := 0.9; t_hi := 2.6;                                      -- diploma, certificate: 1-2 years
  end if;

  -- A "yearly" fee that is exactly the semester fee times the whole programme's semesters is really the total.
  if y is not null and s is not null and t is null then
    foreach k in array array[4, 6, 8] loop
      if abs(y - s * k) <= y * 0.02 and (y / s) > 2.7 then
        return jsonb_build_object('y', null, 's', s, 't', y, 'note', 'fee check: yearly fee was the total for ' || k || ' semesters; moved to total');
      end if;
    end loop;
  end if;

  w := case when (y is null)::int + (s is null)::int + (t is null)::int = 1 then 0.15 else 0 end;
  ys := case when y is null or s is null then null else (2 * s / y) between 0.75 * (1 - w) and 1.35 * (1 + w) end;
  yt := case when y is null or t is null then null else (t / y) between t_lo * (1 - w) and t_hi * (1 + w) end;
  st := case when s is null or t is null then null else (t / s) between 2 * t_lo * (1 - w) and 2 * t_hi * (1 + w) end;
  bad := (case when ys = false then 1 else 0 end) + (case when yt = false then 1 else 0 end) + (case when st = false then 1 else 0 end);

  if bad = 0 then
    return jsonb_build_object('y', y, 's', s, 't', t, 'note', null);
  end if;

  if y is not null and s is not null and t is not null then
    if bad = 1 then          -- one pair slightly off (e.g. first semester includes registration): keep all, flag for review
      return jsonb_build_object('y', y, 's', s, 't', t, 'note', 'fee check: yearly, semester and total do not fully agree; review the sheet');
    end if;
    if bad = 3 then
      return jsonb_build_object('y', null, 's', null, 't', null, 'note', 'fee check: yearly, semester and total all contradict each other; all dropped');
    end if;
    -- bad = 2: the field in both failing pairs is the odd one out
    if st then return jsonb_build_object('y', null, 's', s, 't', t, 'note', 'fee check: yearly fee contradicted semester and total; yearly dropped'); end if;
    if yt then return jsonb_build_object('y', y, 's', null, 't', t, 'note', 'fee check: semester fee contradicted yearly and total; semester dropped'); end if;
    return jsonb_build_object('y', y, 's', s, 't', null, 'note', 'fee check: total fee contradicted yearly and semester; total dropped');
  end if;

  -- only two fees and they disagree: no way to tell which is right
  return jsonb_build_object('y', null, 's', null, 't', null,
    'note', 'fee check: ' || concat_ws(' and ', case when y is not null then 'yearly' end, case when s is not null then 'semester' end,
                                       case when t is not null then 'total' end) || ' fees contradict each other; both dropped');
end $function$;

CREATE OR REPLACE FUNCTION public.catalog_programs_fee_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare r jsonb; v_orig jsonb;
begin
  -- fee_other is normally an object; keep any other JSON value under "value"
  if new.fee_other is not null and jsonb_typeof(new.fee_other) <> 'object' then
    new.fee_other := case when jsonb_typeof(new.fee_other) = 'null' then '{}'::jsonb else jsonb_build_object('value', new.fee_other) end;
  end if;
  -- an update that re-saves an already-cleaned row keeps its original import values
  v_orig := coalesce(new.fee_other->'as_imported',
                     jsonb_build_object('fee_yearly', new.fee_yearly, 'fee_semester', new.fee_semester, 'fee_total', new.fee_total));
  if tg_op = 'UPDATE' and new.fee_other ? 'as_imported'
     and (new.fee_yearly, new.fee_semester, new.fee_total) is not distinct from (old.fee_yearly, old.fee_semester, old.fee_total) then
    r := w2_fee_sanity(new.level, new.dual, (v_orig->>'fee_yearly')::numeric, (v_orig->>'fee_semester')::numeric, (v_orig->>'fee_total')::numeric);
  else
    v_orig := jsonb_build_object('fee_yearly', new.fee_yearly, 'fee_semester', new.fee_semester, 'fee_total', new.fee_total);
    r := w2_fee_sanity(new.level, new.dual, new.fee_yearly, new.fee_semester, new.fee_total);
  end if;
  new.flags := array(select f from unnest(coalesce(new.flags, '{}')) f where f not like 'fee check:%');
  new.fee_other := coalesce(new.fee_other, '{}'::jsonb) - 'as_imported';
  new.fee_yearly := (r->>'y')::numeric;
  new.fee_semester := (r->>'s')::numeric;
  new.fee_total := (r->>'t')::numeric;
  if r->>'note' is not null then
    new.flags := new.flags || (r->>'note');
    new.fee_other := new.fee_other || jsonb_build_object('as_imported', v_orig);
  end if;
  return new;
end $function$;

DROP TRIGGER IF EXISTS catalog_programs_fee_check_trg ON public.catalog_programs;
CREATE TRIGGER catalog_programs_fee_check_trg BEFORE INSERT OR UPDATE ON public.catalog_programs FOR EACH ROW EXECUTE FUNCTION catalog_programs_fee_check();

CREATE OR REPLACE FUNCTION public.catalog_stage_add(p_batch text, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_u int; v_p int;
begin
insert into catalog_stage (batch, kind, row) select p_batch, 'university', u from jsonb_array_elements(coalesce(p->'universities', '[]'::jsonb)) u;
get diagnostics v_u = row_count;
insert into catalog_stage (batch, kind, row) select p_batch, 'program', x from jsonb_array_elements(coalesce(p->'programs', '[]'::jsonb)) x;
get diagnostics v_p = row_count;
return jsonb_build_object('batch', p_batch, 'universities', v_u, 'programs', v_p);
end $function$;

CREATE OR REPLACE FUNCTION public.catalog_commit(p_batch text, p_deactivate_missing boolean DEFAULT true, p_source_file text DEFAULT 'master'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_unis int; v_progs int; v_off int := 0; v_staged int;
begin
select count(*) into v_staged from catalog_stage where batch = p_batch and kind = 'program';
if v_staged = 0 then
return jsonb_build_object('error', 'nothing staged for batch ' || p_batch);
end if;
insert into catalog_universities (name, short_name, institution_type, recognitions, accreditation_text, updated_at)
select distinct on (u->>'name') u->>'name', u->>'short_name', u->>'institution_type',
array(select jsonb_array_elements_text(coalesce(u->'recognitions', '[]'::jsonb))), u->>'accreditation_text', now()
from catalog_stage s, lateral (select s.row as u) x
where s.batch = p_batch and s.kind = 'university' and coalesce(u->>'name', '') <> ''
on conflict (name) do update set short_name = coalesce(excluded.short_name, catalog_universities.short_name),
institution_type = coalesce(excluded.institution_type, catalog_universities.institution_type),
recognitions = case when cardinality(excluded.recognitions) > 0 then excluded.recognitions else catalog_universities.recognitions end,
accreditation_text = coalesce(nullif(excluded.accreditation_text, ''), catalog_universities.accreditation_text), updated_at = now();
get diagnostics v_unis = row_count;
insert into catalog_universities (name, updated_at)
select distinct s.row->>'university_name', now() from catalog_stage s
where s.batch = p_batch and s.kind = 'program' and coalesce(s.row->>'university_name', '') <> ''
on conflict (name) do nothing;
create temporary table if not exists _cat_keys (program_key text primary key) on commit drop;
truncate _cat_keys;
with src as (
select distinct on (k.key) k.key, x, u.id as university_id
from catalog_stage s
cross join lateral (select s.row as x) r
join catalog_universities u on u.name = x->>'university_name'
cross join lateral (select md5(lower(u.name) || '|' || lower(x->>'program_name') || '|' || lower(coalesce(x->>'mode', ''))) as key) k
where s.batch = p_batch and s.kind = 'program' and coalesce(x->>'program_name', '') <> ''
order by k.key, (x->>'source_row')::int
), ins as (
insert into catalog_programs (program_key, university_id, level, level_raw, course, course_key, dual, specialization, program_name, mode,
fee_yearly, fee_semester, fee_total, fee_exam, fee_registration, fee_other, min_qualification, min_pct_general, min_pct_reserved,
eligibility_text, brochure_url, source_row, flags, active, source_file, updated_at)
select key, university_id, x->>'level', x->>'level_raw', x->>'course', x->>'course_key', coalesce((x->>'dual')::boolean, false), x->>'specialization',
x->>'program_name', x->>'mode', (x->>'fee_yearly')::numeric, (x->>'fee_semester')::numeric, (x->>'fee_total')::numeric,
(x->>'fee_exam')::numeric, (x->>'fee_registration')::numeric, x->'fee_other', x->>'min_qualification',
(x->>'min_pct_general')::numeric, (x->>'min_pct_reserved')::numeric, x->>'eligibility_text', x->>'brochure_url',
(x->>'source_row')::int, array(select jsonb_array_elements_text(coalesce(x->'flags', '[]'::jsonb))), true, p_source_file, now()
from src
on conflict (program_key) do update set university_id = excluded.university_id, level = excluded.level, level_raw = excluded.level_raw,
course = excluded.course, course_key = excluded.course_key, dual = excluded.dual, specialization = excluded.specialization,
program_name = excluded.program_name, mode = excluded.mode, fee_yearly = excluded.fee_yearly, fee_semester = excluded.fee_semester,
fee_total = excluded.fee_total, fee_exam = excluded.fee_exam, fee_registration = excluded.fee_registration, fee_other = excluded.fee_other,
min_qualification = excluded.min_qualification, min_pct_general = excluded.min_pct_general, min_pct_reserved = excluded.min_pct_reserved,
eligibility_text = excluded.eligibility_text, brochure_url = excluded.brochure_url, source_row = excluded.source_row, flags = excluded.flags,
active = true, source_file = excluded.source_file, updated_at = now()
returning program_key
)
insert into _cat_keys select program_key from ins;
get diagnostics v_progs = row_count;
if p_deactivate_missing then
update catalog_programs p set active = false, updated_at = now()
where p.active and p.source_file = p_source_file and not exists (select 1 from _cat_keys k where k.program_key = p.program_key);
get diagnostics v_off = row_count;
end if;
delete from catalog_stage where batch = p_batch or created_at < now() - interval '1 day';
perform w2_bump('catalog_version');
delete from w2_search_cache;
return jsonb_build_object('batch', p_batch, 'source_file', p_source_file, 'universities', v_unis, 'programs', v_progs, 'deactivated', v_off);
end $function$;

CREATE OR REPLACE FUNCTION public.catalog_load(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare v_batch text := 'single-' || md5(random()::text || clock_timestamp()::text);
begin
perform catalog_stage_add(v_batch, p);
return catalog_commit(v_batch, true);
end $function$;

CREATE OR REPLACE FUNCTION public.catalog_remove_source(p_source_file text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare n int;
begin
update catalog_programs set active = false, updated_at = now() where active and source_file = p_source_file;
get diagnostics n = row_count;
if n > 0 then perform w2_bump('catalog_version'); delete from w2_search_cache; end if;
return jsonb_build_object('source_file', p_source_file, 'deactivated', n);
end $function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- RLS posture in production (for parity in local dev)
--   catalog_universities / catalog_programs: RLS on, single policy crm_staff_select (SELECT to authenticated using
--     crm_role() IS NOT NULL). anon/authenticated hold full table grants, but with no anon policy anon reads 0 rows.
--   catalog_synonyms / catalog_stage / course_directory / eduwit_knowledge_base: RLS on, NO policies (service_role only).
-- The crm_role() policy is not reproduced here (depends on the old CRM's crm_users table).
-- ---------------------------------------------------------------------------------------------------------------------
alter table public.catalog_universities enable row level security;
alter table public.catalog_programs enable row level security;
alter table public.catalog_synonyms enable row level security;
alter table public.catalog_stage enable row level security;
alter table public.course_directory enable row level security;
alter table public.eduwit_knowledge_base enable row level security;

-- =====================================================================================================================
-- schema catalog (owned by the B2B CRM, migration m32c_a4_catalog). Production grants: USAGE on schema + SELECT on the
-- views to role b2c_app and service_role ONLY. anon/authenticated have no USAGE on schema catalog. Views are plain
-- (security definer-style, owner postgres; reloptions null), so they bypass RLS on the base tables.
-- =====================================================================================================================
create schema if not exists catalog;

CREATE TABLE IF NOT EXISTS catalog.changes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  kind text NOT NULL,
  ref_id bigint NOT NULL,
  CONSTRAINT changes_pkey PRIMARY KEY (id),
  CONSTRAINT changes_kind_check CHECK ((kind = ANY (ARRAY['programme_version'::text, 'rate'::text])))
);
CREATE INDEX IF NOT EXISTS changes_at_idx ON catalog.changes USING btree (at DESC);
alter table catalog.changes enable row level security;   -- policy "readers" FOR SELECT TO b2c_app, service_role USING (true)

-- ---- STUBS of the B2B partner-offer tables that programmes_v LEFT JOINs (production: both empty on 2026-10-17).
-- Only the columns the view reads are reproduced; b2b.partners in production has ~40 more columns (incl. commercial and
-- secret-reference fields that must never reach the website).
create schema if not exists b2b;
CREATE TABLE IF NOT EXISTS b2b.partners (
  id bigint PRIMARY KEY,
  name text NOT NULL,
  display_name text,
  status text NOT NULL DEFAULT 'draft'
);
CREATE TABLE IF NOT EXISTS b2b.partner_programmes (    -- real column list (FKs to partner_programme_versions/rows omitted)
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  partner_id bigint NOT NULL REFERENCES b2b.partners(id),
  programme_id bigint NOT NULL,                        -- catalog_programs.id, deliberately no FK
  program_key text NOT NULL,
  partner_course_code text,
  partner_programme_name text,
  fees jsonb DEFAULT '{}'::jsonb NOT NULL,             -- keys yearly / semester / total / exam / registration
  eligibility jsonb DEFAULT '{}'::jsonb NOT NULL,
  commission jsonb,                                    -- COMMERCIAL: never expose
  season_from date,
  season_to date,
  intake text,
  active boolean DEFAULT true NOT NULL,
  valid_from timestamp with time zone DEFAULT now() NOT NULL,
  valid_to timestamp with time zone,
  source_version_id bigint NOT NULL,
  source_row_id bigint,
  UNIQUE (partner_id, programme_id, valid_from)
);

CREATE OR REPLACE VIEW catalog.universities_v AS
 SELECT id,
    name,
    short_name,
    institution_type,
    recognitions,
    accreditation_text,
    updated_at
   FROM catalog_universities u;

CREATE OR REPLACE VIEW catalog.synonyms_v AS
 SELECT alias,
    course_key
   FROM catalog_synonyms s;

-- NOTE: duration / emi_available / typical_emi / scholarship_notes read fee_other keys 'duration', 'emi_available',
-- 'typical_emi', 'scholarship' which NO production row has (the sheet loader stores EMI as fee_other->'Emi'), so those
-- four columns are always NULL today. intakes / deadlines come only from live partner offers (none today) => empty.
CREATE OR REPLACE VIEW catalog.programmes_v AS
 SELECT c.id,
    c.university_id,
    u.name AS university_name,
    c.program_name AS programme_name,
    c.course,
    c.course_key,
    c.specialization,
    c.level,
    c.mode,
    NULLIF(c.fee_other ->> 'duration'::text, ''::text) AS duration,
    c.min_qualification,
    c.min_pct_general AS min_pct,
    c.min_pct_reserved,
    c.eligibility_text,
    COALESCE(c.fee_yearly, o.fee_yearly) AS fee_per_year,
    COALESCE(c.fee_semester, o.fee_semester) AS fee_per_semester,
    COALESCE(c.fee_total, o.fee_total) AS fee_total,
    COALESCE(c.fee_exam, o.fee_exam) AS fee_exam,
    COALESCE(c.fee_registration, o.fee_registration) AS fee_registration,
        CASE
            WHEN c.fee_other ? 'emi_available'::text THEN (c.fee_other ->> 'emi_available'::text) = ANY (ARRAY['true'::text, 'yes'::text, '1'::text])
            ELSE NULL::boolean
        END AS emi_available,
    NULLIF(c.fee_other ->> 'typical_emi'::text, ''::text) AS typical_emi,
    NULLIF(c.fee_other ->> 'scholarship'::text, ''::text) AS scholarship_notes,
    o.intakes,
    o.deadlines,
    u.accreditation_text AS accreditation,
    u.recognitions,
    c.brochure_url,
    COALESCE(o.partners, 0::bigint)::integer AS offered_by_partner_count,
    GREATEST(c.updated_at, u.updated_at, o.updated_at) AS updated_at
   FROM catalog_programs c
     JOIN catalog_universities u ON u.id = c.university_id
     LEFT JOIN LATERAL ( SELECT count(DISTINCT pp.partner_id) AS partners,
            min(NULLIF(pp.fees ->> 'yearly'::text, ''::text)::numeric) AS fee_yearly,
            min(NULLIF(pp.fees ->> 'semester'::text, ''::text)::numeric) AS fee_semester,
            min(NULLIF(pp.fees ->> 'total'::text, ''::text)::numeric) AS fee_total,
            min(NULLIF(pp.fees ->> 'exam'::text, ''::text)::numeric) AS fee_exam,
            min(NULLIF(pp.fees ->> 'registration'::text, ''::text)::numeric) AS fee_registration,
            array_remove(array_agg(DISTINCT pp.intake), NULL::text) AS intakes,
            array_remove(array_agg(DISTINCT pp.season_to), NULL::date) AS deadlines,
            max(pp.valid_from) AS updated_at
           FROM b2b.partner_programmes pp
             JOIN b2b.partners p ON p.id = pp.partner_id
          WHERE pp.programme_id = c.id AND pp.active AND pp.valid_to IS NULL AND p.status <> 'closed'::text AND (pp.season_to IS NULL OR pp.season_to >= CURRENT_DATE)) o ON true
  WHERE c.active;

-- catalog.partner_rates_v (COMMISSION RATES — must never be read by the website) is intentionally NOT recreated. It joins
-- b2b.partner_programmes, b2b.partners, b2b.rates and b2b.money_periods and exposes partner_name, rate_type, value,
-- effective_pct, effective_inr, is_highest_for_programme/university. Definition: b2b-crm/supabase/migrations/m32c_a4_catalog.sql.

-- Production grants on schema catalog (reproduced for parity; b2c_app is a NOLOGIN role created by m32c):
-- grant usage on schema catalog to b2c_app, service_role;
-- grant select on catalog.programmes_v, catalog.universities_v, catalog.synonyms_v, catalog.partner_rates_v, catalog.changes to b2c_app, service_role;
grant usage on schema catalog to service_role;
grant select on catalog.programmes_v, catalog.universities_v, catalog.synonyms_v, catalog.changes to service_role;
