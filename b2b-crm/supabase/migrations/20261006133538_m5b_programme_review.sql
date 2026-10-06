-- M5b: Programme Repository writes, preview, publish and roll back (spec B5.2.3). Follows m5a.

-- ---------- writes ----------

/*
 * Creates a draft version from parsed, normalised rows (the app reads the stored file, applies the column template and
 * normalises; this function trusts nothing but the shape). Older drafts of the partner are discarded.
 * p: {partner_id, file_path, file_name, sheet, template, rows: [{row_no, raw, norm}]}
 */
create or replace function b2b.programme_version_create(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_partner bigint := (p ->> 'partner_id')::bigint;
  v_id bigint;
  v_no int;
  v_who text := coalesce(auth.uid()::text, 'system');
  v_rows int := jsonb_array_length(coalesce(p -> 'rows', '[]'));
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partners where id = v_partner and status <> 'closed') then
    raise exception 'partner not found or closed' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p -> 'rows') <> 'array' or v_rows = 0 then raise exception 'the file has no programme rows' using errcode = '22023'; end if;
  if v_rows > 5000 then raise exception 'at most 5000 rows per file' using errcode = '22023'; end if;
  if jsonb_typeof(coalesce(p -> 'template', '{}')) <> 'object' then raise exception 'template must be an object' using errcode = '22023'; end if;
  if p ->> 'file_path' is not null and p ->> 'file_path' !~ ('^' || v_partner || '/[0-9a-f-]{36}\.(xlsx|csv)$') then
    raise exception 'unexpected file path' using errcode = '22023';
  end if;

  perform 1 from b2b.partners where id = v_partner for update; -- one version number at a time per partner
  update b2b.partner_programme_versions set status = 'discarded' where partner_id = v_partner and status = 'draft';
  select coalesce(max(version_no), 0) + 1 into v_no from b2b.partner_programme_versions where partner_id = v_partner;

  insert into b2b.partner_programme_versions (partner_id, version_no, source_type, file_path, file_name, sheet, row_count, uploaded_by)
  values (v_partner, v_no, 'upload', p ->> 'file_path', left(p ->> 'file_name', 200), left(p ->> 'sheet', 100), v_rows, v_who)
  returning id into v_id;

  insert into b2b.partner_programme_rows (version_id, row_no, raw, norm, match_sig)
  select v_id, (x ->> 'row_no')::int, coalesce(x -> 'raw', '{}'), coalesce(x -> 'norm', '{}'),
         nullif(concat_ws('|', b2b.norm_key(x -> 'norm' ->> 'university'), b2b.norm_key(x -> 'norm' ->> 'course'),
                          b2b.norm_key(coalesce(nullif(x -> 'norm' ->> 'specialization', ''), 'General')), b2b.norm_key(x -> 'norm' ->> 'mode'),
                          b2b.norm_key(x -> 'norm' ->> 'level'), b2b.norm_key(x -> 'norm' ->> 'programme_code')), '|||||')
    from jsonb_array_elements(p -> 'rows') x;

  insert into b2b.partner_programme_sources (partner_id, type, column_template, updated_at)
  values (v_partner, 'upload', coalesce(p -> 'template', '{}'), now())
  on conflict (partner_id) do update set type = 'upload', column_template = excluded.column_template, updated_at = now();

  perform b2b.programme_match_version(v_id);
  perform b2b.log_event('programmes.uploaded', null, null, v_partner, jsonb_build_object('version_id', v_id, 'version_no', v_no, 'rows', v_rows, 'file', p ->> 'file_name'));
  return jsonb_build_object('id', v_id, 'version_no', v_no);
end $$;

/* Review one row of a draft: approve the suggested match, match by hand, ignore with a reason, or request a catalogue addition. */
create or replace function b2b.programme_row_review(p_row_id bigint, p_action text, p_programme_id bigint default null, p_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  r b2b.partner_programme_rows;
  v_status text;
  v_partner bigint;
  v_who text := coalesce(auth.uid()::text, 'system');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into r from b2b.partner_programme_rows where id = p_row_id for update;
  if r.id is null then raise exception 'row not found' using errcode = 'P0002'; end if;
  select status, partner_id into v_status, v_partner from b2b.partner_programme_versions where id = r.version_id;
  if v_status <> 'draft' then raise exception 'only a draft version can be reviewed' using errcode = '22023'; end if;

  case p_action
    when 'approve' then
      if r.programme_id is null then raise exception 'no suggested programme to approve' using errcode = '22023'; end if;
      update b2b.partner_programme_rows set review_status = 'approved', reviewed_by = v_who, reviewed_at = now(), ignore_reason = null where id = r.id;
    when 'match' then
      if not exists (select 1 from public.catalog_programs where id = p_programme_id and active) then
        raise exception 'choose an active catalogue programme' using errcode = '22023';
      end if;
      update b2b.partner_programme_rows set programme_id = p_programme_id, match_method = 'manual', confidence = 1, review_status = 'approved',
             reviewed_by = v_who, reviewed_at = now(), ignore_reason = null where id = r.id;
    when 'ignore' then
      if coalesce(trim(p_reason), '') = '' then raise exception 'a reason is required' using errcode = '22023'; end if;
      update b2b.partner_programme_rows set review_status = 'ignored', ignore_reason = left(trim(p_reason), 300), reviewed_by = v_who, reviewed_at = now() where id = r.id;
    when 'request' then
      insert into b2b.catalogue_requests (partner_id, version_id, row_id, payload) values (v_partner, r.version_id, r.id, r.norm)
      on conflict (row_id) do nothing;
      update b2b.partner_programme_rows set review_status = 'ignored', ignore_reason = 'Not in the catalogue: addition requested',
             reviewed_by = v_who, reviewed_at = now() where id = r.id;
    when 'reopen' then
      update b2b.partner_programme_rows set review_status = case when programme_id is null then 'no_match' else 'needs_review' end,
             ignore_reason = null, reviewed_by = null, reviewed_at = null where id = r.id;
    else raise exception 'unknown action' using errcode = '22023';
  end case;
  return jsonb_build_object('id', r.id);
end $$;

/* Approves every row of a draft whose match the Admin has checked in bulk (fuzzy suggestions with a programme). */
create or replace function b2b.programme_rows_approve(p_version_id bigint, p_row_ids bigint[])
returns int language plpgsql volatile security definer set search_path = '' as $$
declare n int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if (select status from b2b.partner_programme_versions where id = p_version_id) is distinct from 'draft' then
    raise exception 'only a draft version can be reviewed' using errcode = '22023';
  end if;
  update b2b.partner_programme_rows set review_status = 'approved', reviewed_by = coalesce(auth.uid()::text, 'system'), reviewed_at = now()
   where version_id = p_version_id and id = any (p_row_ids) and review_status = 'needs_review' and programme_id is not null;
  get diagnostics n = row_count;
  return n;
end $$;

/* The offers a version would publish: one per matched programme (the first row wins), with the fields routing uses. */
create or replace function b2b.programme_version_offers(p_version_id bigint)
returns table (programme_id bigint, program_key text, row_id bigint, row_no int, code text, name text, fees jsonb, eligibility jsonb,
               commission jsonb, season_from date, season_to date, intake text, active boolean)
language sql stable set search_path = '' as $$
  select distinct on (r.programme_id) r.programme_id, c.program_key, r.id, r.row_no,
         nullif(r.norm ->> 'programme_code', ''), nullif(r.norm ->> 'programme_name', ''),
         coalesce(r.norm -> 'fees', '{}'), coalesce(r.norm -> 'eligibility', '{}'), r.norm -> 'commission',
         (r.norm ->> 'season_from')::date, (r.norm ->> 'season_to')::date, nullif(r.norm ->> 'intake', ''),
         coalesce((r.norm ->> 'active')::boolean, true)
    from b2b.partner_programme_rows r join public.catalog_programs c on c.id = r.programme_id and c.active
   where r.version_id = p_version_id and r.review_status in ('auto', 'approved')
   order by r.programme_id, r.row_no;
$$;

/* What publishing a version would change against the live offers (B5.2.3 step 4). */
create or replace function b2b.programme_version_preview(p_version_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v b2b.partner_programme_versions;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into v from b2b.partner_programme_versions where id = p_version_id;
  if v.id is null then return null; end if;
  return (
    with n as (select * from b2b.programme_version_offers(p_version_id) where active),
         l as (select * from b2b.partner_programmes where partner_id = v.partner_id and valid_to is null and active),
         added as (select n.* from n where not exists (select 1 from l where l.programme_id = n.programme_id)),
         removed as (select l.* from l where not exists (select 1 from n where n.programme_id = l.programme_id)),
         changed as (
           select n.programme_id,
                  array_remove(array[
                    case when n.fees is distinct from l.fees then 'fees' end,
                    case when n.eligibility is distinct from l.eligibility then 'eligibility' end,
                    case when n.commission is distinct from l.commission then 'commission' end,
                    case when n.code is distinct from l.partner_course_code or n.name is distinct from l.partner_programme_name then 'code or name' end,
                    case when n.season_from is distinct from l.season_from or n.season_to is distinct from l.season_to or n.intake is distinct from l.intake then 'dates' end
                  ], null) as fields,
                  l.fees as old_fees, n.fees as new_fees, l.commission as old_commission, n.commission as new_commission
             from n join l on l.programme_id = n.programme_id)
    select jsonb_build_object(
      'version', jsonb_build_object('id', v.id, 'version_no', v.version_no, 'status', v.status, 'partner_id', v.partner_id),
      'pending_review', (select count(*) from b2b.partner_programme_rows r where r.version_id = v.id and r.review_status in ('needs_review', 'no_match')),
      'ignored', (select count(*) from b2b.partner_programme_rows r where r.version_id = v.id and r.review_status = 'ignored'),
      'duplicates', (select count(*) - count(distinct r.programme_id) from b2b.partner_programme_rows r where r.version_id = v.id and r.review_status in ('auto', 'approved')),
      'live_count', (select count(*) from l),
      'new_count', (select count(*) from n),
      'added', coalesce((select jsonb_agg(b2b.programme_label(a.programme_id) || jsonb_build_object('fees', a.fees, 'commission', a.commission,
                                   'fee_gap', b2b.fee_gap(a.programme_id, a.fees)) order by a.programme_id) from added a), '[]'),
      'removed', coalesce((select jsonb_agg(b2b.programme_label(x.programme_id) || jsonb_build_object(
                                   'last_partner', not exists (select 1 from b2b.partner_programmes o where o.programme_id = x.programme_id
                                                                 and o.partner_id <> v.partner_id and o.valid_to is null and o.active)) order by x.programme_id) from removed x), '[]'),
      'changed', coalesce((select jsonb_agg(b2b.programme_label(c.programme_id) || jsonb_build_object('fields', to_jsonb(c.fields),
                                   'old_fees', c.old_fees, 'new_fees', c.new_fees, 'old_commission', c.old_commission, 'new_commission', c.new_commission,
                                   'fee_gap', b2b.fee_gap(c.programme_id, c.new_fees)) order by c.programme_id)
                            from changed c where cardinality(c.fields) > 0), '[]'),
      'unchanged', (select count(*) from changed c where cardinality(c.fields) = 0),
      'proposed_commission', (select count(*) from n where n.commission is not null))
  );
end $$;

/* Gap between the partner's total fee and the catalogue's, as a fraction (B5.2.4: over 10% is highlighted). */
create or replace function b2b.fee_gap(p_programme_id bigint, p_fees jsonb)
returns numeric language sql stable set search_path = '' as $$
  select case when (p_fees ->> 'total') is not null and c.fee_total > 0
              then round(abs((p_fees ->> 'total')::numeric - c.fee_total) / c.fee_total, 3) end
    from public.catalog_programs c where c.id = p_programme_id;
$$;
