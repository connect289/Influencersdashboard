-- M5: Programme Repository (spec B5.2). Excel/CSV uploads now; Google Sheet sources later (the columns exist).
-- Reads catalog_* only. Offers point at catalog_programs by id and program_key (both stable: the catalogue upserts on
-- program_key and only ever deactivates), without a foreign key, so nothing on catalog_* changes.
-- Programmes missing from the catalogue become b2b.catalogue_requests for the Admin (D11); the catalogue is not written.

-- ---------- storage: original partner files (private; read and written by the server with the service role) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('b2b-programme-files', 'b2b-programme-files', false, 4194304,
        array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'text/csv'])
on conflict (id) do nothing;

insert into b2b.settings (key, value) values ('programmes', '{"stale_days": 90}') on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists b2b.partner_programme_sources (
  partner_id        bigint primary key references b2b.partners (id) on delete restrict,
  type              text not null default 'upload' check (type in ('upload', 'gsheet')),
  sheet_id          text,
  tab               text,
  column_template   jsonb not null default '{}' check (jsonb_typeof(column_template) = 'object'),
  sync_every_hours  int not null default 6 check (sync_every_hours between 1 and 168),
  auto_publish      boolean not null default false,
  last_checked_at   timestamptz,
  last_changed_at   timestamptz,
  updated_at        timestamptz not null default now()
);

create table if not exists b2b.partner_programme_versions (
  id              bigint generated always as identity primary key,
  partner_id      bigint not null references b2b.partners (id) on delete restrict,
  version_no      int not null,
  source_type     text not null default 'upload' check (source_type in ('upload', 'gsheet')),
  file_path       text,
  file_name       text,
  sheet           text,
  sheet_revision  text,
  status          text not null default 'draft' check (status in ('draft', 'published', 'superseded', 'rolled_back', 'discarded')),
  row_count       int not null default 0,
  uploaded_by     text,
  uploaded_at     timestamptz not null default now(),
  published_by    text,
  published_at    timestamptz,
  note            text,
  unique (partner_id, version_no)
);
create unique index if not exists partner_programme_versions_one_published on b2b.partner_programme_versions (partner_id) where status = 'published';

create table if not exists b2b.partner_programme_rows (
  id             bigint generated always as identity primary key,
  version_id     bigint not null references b2b.partner_programme_versions (id) on delete restrict,
  row_no         int not null,
  raw            jsonb not null,
  norm           jsonb not null,
  match_sig      text,
  programme_id   bigint,
  match_method   text check (match_method in ('previous', 'exact', 'fuzzy', 'manual')),
  confidence     numeric(4, 3),
  candidates     jsonb not null default '[]',
  review_status  text not null default 'no_match' check (review_status in ('auto', 'needs_review', 'no_match', 'approved', 'ignored')),
  ignore_reason  text,
  reviewed_by    text,
  reviewed_at    timestamptz,
  unique (version_id, row_no)
);
create index if not exists partner_programme_rows_review_idx on b2b.partner_programme_rows (version_id, review_status);

create table if not exists b2b.partner_programmes (
  id                      bigint generated always as identity primary key,
  partner_id              bigint not null references b2b.partners (id) on delete restrict,
  programme_id            bigint not null,
  program_key             text not null,
  partner_course_code     text,
  partner_programme_name  text,
  fees                    jsonb not null default '{}',
  eligibility             jsonb not null default '{}',
  commission              jsonb,
  season_from             date,
  season_to               date,
  intake                  text,
  active                  boolean not null default true,
  valid_from              timestamptz not null default now(),
  valid_to                timestamptz,
  source_version_id       bigint not null references b2b.partner_programme_versions (id) on delete restrict,
  source_row_id           bigint references b2b.partner_programme_rows (id) on delete restrict,
  unique (partner_id, programme_id, valid_from)
);
create unique index if not exists partner_programmes_live_uq on b2b.partner_programmes (partner_id, programme_id) where valid_to is null;
create index if not exists partner_programmes_programme_live_idx on b2b.partner_programmes (programme_id) where valid_to is null;

create table if not exists b2b.catalogue_requests (
  id           bigint generated always as identity primary key,
  partner_id   bigint not null references b2b.partners (id) on delete restrict,
  version_id   bigint not null references b2b.partner_programme_versions (id) on delete restrict,
  row_id       bigint not null unique references b2b.partner_programme_rows (id) on delete restrict,
  payload      jsonb not null,
  status       text not null default 'open' check (status in ('open', 'added', 'rejected')),
  note         text,
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz
);

do $rls$
declare t text;
begin
  foreach t in array array['partner_programme_sources', 'partner_programme_versions', 'partner_programme_rows', 'partner_programmes', 'catalogue_requests'] loop
    execute format('alter table b2b.%I enable row level security', t);
    if not exists (select 1 from pg_policies where schemaname = 'b2b' and tablename = t and policyname = 'admin_read') then
      execute format('create policy admin_read on b2b.%I for select to authenticated using ((select b2b.is_admin()))', t);
    end if;
    execute format('revoke all on b2b.%I from public, anon, authenticated', t);
    execute format('grant select on b2b.%I to authenticated', t);
    execute format('grant all on b2b.%I to service_role', t);
  end loop;
end $rls$;

-- ---------- matching helpers ----------

/* Lowercase letters and digits only: "MBA (Dual Spl.)" → "mbadualspl". */
create or replace function b2b.norm_key(p text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select lower(regexp_replace(coalesce(p, ''), '[^a-zA-Z0-9]', '', 'g'));
$$;

/* The catalogue university for a name the partner wrote: exact on name or short name, else the closest by trigram. */
create or replace function b2b.match_university(p text)
returns bigint language sql stable set search_path = '' as $$
  select u.id from public.catalog_universities u
   where b2b.norm_key(p) <> ''
     and (b2b.norm_key(u.name) = b2b.norm_key(p) or b2b.norm_key(u.short_name) = b2b.norm_key(p)
          or public.similarity(lower(u.name), lower(p)) >= 0.55)
   order by (b2b.norm_key(u.name) = b2b.norm_key(p) or b2b.norm_key(u.short_name) = b2b.norm_key(p)) desc,
            public.similarity(lower(u.name), lower(p)) desc
   limit 1;
$$;

/* The catalogue course key: exact key, then a synonym, then the longest key the text starts with ("mbadual…" → mba). */
create or replace function b2b.match_course_key(p text)
returns text language sql stable set search_path = '' as $$
  with k as (select b2b.norm_key(p) as v)
  select coalesce(
    (select c.course_key from public.catalog_programs c, k where c.course_key = k.v limit 1),
    (select s.course_key from public.catalog_synonyms s, k where s.alias = k.v limit 1),
    (select c.course_key from (select distinct course_key from public.catalog_programs) c, k
      where k.v like c.course_key || '%' and length(c.course_key) >= 2 order by length(c.course_key) desc limit 1));
$$;

/* Matches every open row of a version to catalog_programs (B5.2.3 step 2, without the AI step). */
create or replace function b2b.programme_match_version(p_version_id bigint)
returns void language plpgsql volatile set search_path = '' as $$
declare
  v_partner bigint;
  r record;
  v_uni bigint;
  v_ck text;
  v_spec text;
  v_ids bigint[];
  v_prev bigint;
  v_cands jsonb;
  v_best numeric;
begin
  select partner_id into v_partner from b2b.partner_programme_versions where id = p_version_id;

  for r in select * from b2b.partner_programme_rows where version_id = p_version_id and review_status not in ('approved', 'ignored') loop
    v_uni := b2b.match_university(r.norm ->> 'university');
    v_ck := b2b.match_course_key(r.norm ->> 'course');
    v_spec := b2b.norm_key(coalesce(nullif(r.norm ->> 'specialization', ''), 'General'));

    -- rows the normaliser rejected wait for a person
    if jsonb_array_length(coalesce(r.norm -> 'errors', '[]')) > 0 then
      update b2b.partner_programme_rows set programme_id = null, match_method = null, confidence = null, candidates = '[]', review_status = 'no_match'
       where id = r.id;
      continue;
    end if;

    -- 1. the same row (same signature) in this partner's earlier versions, as matched or approved then
    select pr.programme_id into v_prev
      from b2b.partner_programme_rows pr join b2b.partner_programme_versions pv on pv.id = pr.version_id
     where pv.partner_id = v_partner and pv.id <> p_version_id and pr.match_sig = r.match_sig
       and pr.review_status in ('auto', 'approved') and pr.programme_id is not null
       and exists (select 1 from public.catalog_programs c where c.id = pr.programme_id and c.active)
     order by pv.version_no desc, pr.id desc limit 1;
    if v_prev is not null then
      update b2b.partner_programme_rows set programme_id = v_prev, match_method = 'previous', confidence = 1, candidates = '[]', review_status = 'auto'
       where id = r.id;
      continue;
    end if;

    -- 2. exact: university + course + specialization + mode (+ level when given)
    select array_agg(c.id order by c.id) into v_ids
      from public.catalog_programs c
     where c.active and c.university_id = v_uni and c.course_key = v_ck
       and lower(c.mode) = lower(r.norm ->> 'mode')
       and (r.norm ->> 'level' is null or c.level = r.norm ->> 'level')
       and b2b.norm_key(coalesce(nullif(c.specialization, ''), 'General')) = v_spec;
    if cardinality(v_ids) = 1 then
      update b2b.partner_programme_rows set programme_id = v_ids[1], match_method = 'exact', confidence = 1, candidates = '[]', review_status = 'auto'
       where id = r.id;
      continue;
    end if;

    -- 3. close matches in the same university (and course when known): a person decides
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'score', round(x.score::numeric, 3)) order by x.score desc), '[]'), max(x.score)
      into v_cands, v_best
      from (
        select c.id,
               greatest(public.similarity(lower(c.specialization), lower(coalesce(nullif(r.norm ->> 'specialization', ''), 'general'))),
                        public.similarity(lower(c.program_name), lower(coalesce(r.norm ->> 'programme_name', concat_ws(' ', r.norm ->> 'course', r.norm ->> 'specialization')))))
               + case when lower(c.mode) = lower(r.norm ->> 'mode') then 0.1 else 0 end
               + case when cardinality(v_ids) > 1 and c.id = any (v_ids) then 0.5 else 0 end as score
          from public.catalog_programs c
         where c.active and c.university_id = v_uni and (v_ck is null or c.course_key = v_ck)
         order by score desc limit 5
      ) x;

    update b2b.partner_programme_rows
       set programme_id = case when v_best >= 0.45 then (v_cands -> 0 ->> 'id')::bigint end,
           match_method = case when v_best >= 0.45 then 'fuzzy' end,
           confidence = case when v_best is not null then least(v_best, 0.999) end,
           candidates = v_cands,
           review_status = case when v_best >= 0.45 then 'needs_review' else 'no_match' end
     where id = r.id;
  end loop;
end $$;

-- ---------- reads ----------

create or replace function b2b.programme_label(p_id bigint)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'program_name', c.program_name, 'university', u.name, 'university_short', u.short_name,
                            'course', c.course, 'course_key', c.course_key, 'specialization', c.specialization, 'level', c.level, 'mode', c.mode,
                            'fee_total', c.fee_total, 'fee_yearly', c.fee_yearly, 'active', c.active)
    from public.catalog_programs c join public.catalog_universities u on u.id = c.university_id where c.id = p_id;
$$;

/* Partner list for the repository tab plus coverage by course (B5.2.5). */
create or replace function b2b.programmes_overview()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_stale int := coalesce((select (value ->> 'stale_days')::int from b2b.settings where key = 'programmes'), 90);
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'stale_days', v_stale,
    'partners', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', p.id, 'name', p.name, 'display_name', p.display_name, 'logo_url', p.logo_url, 'brand_color', p.brand_color, 'status', p.status,
               'source', s.type, 'live_count', (select count(*) from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active),
               'published', (select jsonb_build_object('id', v.id, 'version_no', v.version_no, 'published_at', v.published_at, 'file_name', v.file_name)
                               from b2b.partner_programme_versions v where v.partner_id = p.id and v.status = 'published'),
               'draft', (select jsonb_build_object('id', v.id, 'version_no', v.version_no, 'uploaded_at', v.uploaded_at,
                                                   'review', (select count(*) from b2b.partner_programme_rows r where r.version_id = v.id and r.review_status in ('needs_review', 'no_match')))
                           from b2b.partner_programme_versions v where v.partner_id = p.id and v.status = 'draft' order by v.id desc limit 1),
               'last_upload_at', (select max(v.uploaded_at) from b2b.partner_programme_versions v where v.partner_id = p.id),
               'stale', coalesce((select max(v.uploaded_at) from b2b.partner_programme_versions v where v.partner_id = p.id) < now() - make_interval(days => v_stale), false))
             order by (p.status = 'closed'), lower(coalesce(p.display_name, p.name)))
        from b2b.partners p left join b2b.partner_programme_sources s on s.partner_id = p.id), '[]'),
    'coverage', coalesce((
      select jsonb_agg(x order by x.programmes desc)
        from (
          select c.course_key, min(c.course) as course, count(*) as programmes,
                 count(*) filter (where n.partners >= 1) as covered,
                 count(*) filter (where n.partners = 1) as single,
                 count(*) filter (where n.partners >= 2) as competing
            from public.catalog_programs c
            left join lateral (select count(distinct o.partner_id) as partners from b2b.partner_programmes o
                                where o.programme_id = c.id and o.valid_to is null and o.active) n on true
           where c.active
           group by c.course_key
        ) x), '[]'),
    'requests', (select count(*) from b2b.catalogue_requests where status = 'open'));
end $$;

/* One partner's repository: source, versions, live offers. */
create or replace function b2b.programme_partner(p_partner_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partners where id = p_partner_id) then return null; end if;
  return jsonb_build_object(
    'partner', (select jsonb_build_object('id', p.id, 'name', p.name, 'display_name', p.display_name, 'logo_url', p.logo_url, 'brand_color', p.brand_color, 'status', p.status)
                  from b2b.partners p where p.id = p_partner_id),
    'source', (select to_jsonb(s) from b2b.partner_programme_sources s where s.partner_id = p_partner_id),
    'versions', coalesce((
      select jsonb_agg(jsonb_build_object('id', v.id, 'version_no', v.version_no, 'status', v.status, 'file_name', v.file_name, 'sheet', v.sheet,
                                          'has_file', v.file_path is not null, 'row_count', v.row_count, 'uploaded_at', v.uploaded_at, 'published_at', v.published_at, 'note', v.note,
                                          'counts', (select jsonb_object_agg(review_status, n) from (select review_status, count(*) n from b2b.partner_programme_rows r where r.version_id = v.id group by 1) c))
                       order by v.version_no desc)
        from b2b.partner_programme_versions v where v.partner_id = p_partner_id), '[]'),
    'offers', coalesce((
      select jsonb_agg(b2b.programme_label(o.programme_id) || jsonb_build_object(
               'offer_id', o.id, 'partner_course_code', o.partner_course_code, 'partner_programme_name', o.partner_programme_name,
               'fees', o.fees, 'eligibility', o.eligibility, 'commission', o.commission, 'season_from', o.season_from, 'season_to', o.season_to,
               'valid_from', o.valid_from)
             order by o.programme_id)
        from b2b.partner_programmes o where o.partner_id = p_partner_id and o.valid_to is null and o.active), '[]'));
end $$;

/* A version with its rows and match labels, for the review screen. */
create or replace function b2b.programme_version(p_version_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partner_programme_versions where id = p_version_id) then return null; end if;
  return (
    select to_jsonb(v) || jsonb_build_object(
             'rows', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'id', r.id, 'row_no', r.row_no, 'norm', r.norm, 'review_status', r.review_status, 'match_method', r.match_method,
                        'confidence', r.confidence, 'ignore_reason', r.ignore_reason, 'programme', b2b.programme_label(r.programme_id),
                        'candidates', coalesce((select jsonb_agg(b2b.programme_label((c ->> 'id')::bigint) || jsonb_build_object('score', c -> 'score'))
                                                  from jsonb_array_elements(r.candidates) c), '[]'),
                        'requested', exists (select 1 from b2b.catalogue_requests q where q.row_id = r.id))
                      order by r.row_no)
                 from b2b.partner_programme_rows r where r.version_id = v.id), '[]'))
      from b2b.partner_programme_versions v where v.id = p_version_id);
end $$;

/* Catalogue programmes to match a row by hand: a university's programmes, filtered by text. */
create or replace function b2b.catalogue_search(p_university_id bigint, p_q text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(b2b.programme_label(x.id))
      from (select c.id from public.catalog_programs c
             where c.active and (p_university_id is null or c.university_id = p_university_id)
               and (coalesce(trim(p_q), '') = '' or c.program_name ilike '%' || replace(replace(replace(trim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%'
                    or c.specialization ilike '%' || replace(replace(replace(trim(p_q), '\', '\\'), '%', '\%'), '_', '\_') || '%')
             order by c.course_key, c.specialization, c.mode limit 40) x), '[]');
end $$;

create or replace function b2b.catalogue_universities()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'short_name', u.short_name) order by u.name) from public.catalog_universities u), '[]');
end $$;
