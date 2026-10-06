-- M5c: Programme Repository publish, roll back and discard; checklist; grants. Follows m5b.

/*
 * Publishes a version (a draft, or an earlier version to roll back to). In one transaction: offers not in the version
 * end (valid_to = now, never deleted), changed offers end and restart, new ones start; the version becomes the only
 * published one. Leads already allocated keep their partner.
 */
create or replace function b2b.programme_version_publish(p_version_id bigint, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v b2b.partner_programme_versions;
  v_prev b2b.partner_programme_versions;
  v_now timestamptz := clock_timestamp();
  v_who text := coalesce(auth.uid()::text, 'system');
  v_added int; v_removed int; v_changed int;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into v from b2b.partner_programme_versions where id = p_version_id for update;
  if v.id is null then raise exception 'version not found' using errcode = 'P0002'; end if;
  perform 1 from b2b.partners where id = v.partner_id for update;
  if v.status not in ('draft', 'superseded', 'rolled_back') then raise exception 'this version cannot be published' using errcode = '22023'; end if;
  if exists (select 1 from b2b.partner_programme_rows where version_id = v.id and review_status in ('needs_review', 'no_match')) then
    raise exception 'rows still need review' using errcode = '22023';
  end if;
  if not exists (select 1 from b2b.programme_version_offers(v.id)) then raise exception 'the version has no matched programmes' using errcode = '22023'; end if;

  -- end live offers that are gone or changed
  with n as (select * from b2b.programme_version_offers(v.id) where active),
       ended as (
         update b2b.partner_programmes o set valid_to = v_now
          where o.partner_id = v.partner_id and o.valid_to is null
            and not exists (select 1 from n where n.programme_id = o.programme_id and o.active
                              and n.fees is not distinct from o.fees and n.eligibility is not distinct from o.eligibility
                              and n.commission is not distinct from o.commission and n.code is not distinct from o.partner_course_code
                              and n.name is not distinct from o.partner_programme_name and n.season_from is not distinct from o.season_from
                              and n.season_to is not distinct from o.season_to and n.intake is not distinct from o.intake)
         returning o.programme_id)
  select count(*) filter (where not exists (select 1 from n where n.programme_id = e.programme_id)),
         count(*) filter (where exists (select 1 from n where n.programme_id = e.programme_id))
    into v_removed, v_changed from ended e;

  -- start new and changed offers
  insert into b2b.partner_programmes (partner_id, programme_id, program_key, partner_course_code, partner_programme_name, fees, eligibility,
                                      commission, season_from, season_to, intake, active, valid_from, source_version_id, source_row_id)
  select v.partner_id, n.programme_id, n.program_key, n.code, n.name, n.fees, n.eligibility, n.commission, n.season_from, n.season_to, n.intake,
         true, v_now, v.id, n.row_id
    from b2b.programme_version_offers(v.id) n
   where n.active
     and not exists (select 1 from b2b.partner_programmes o where o.partner_id = v.partner_id and o.programme_id = n.programme_id and o.valid_to is null);
  get diagnostics v_added = row_count;
  v_added := v_added - v_changed;

  select * into v_prev from b2b.partner_programme_versions where partner_id = v.partner_id and status = 'published';
  if v_prev.id is not null then
    update b2b.partner_programme_versions set status = case when v.status = 'draft' then 'superseded' else 'rolled_back' end where id = v_prev.id;
  end if;
  update b2b.partner_programme_versions set status = 'published', published_by = v_who, published_at = v_now, note = nullif(left(trim(p_note), 500), '')
   where id = v.id;
  update b2b.partner_programme_sources set last_changed_at = v_now, updated_at = v_now where partner_id = v.partner_id;

  perform b2b.log_event(case when v.status = 'draft' then 'programmes.published' else 'programmes.rolled_back' end, null, null, v.partner_id,
                        jsonb_build_object('version_id', v.id, 'version_no', v.version_no, 'added', v_added, 'removed', v_removed, 'changed', v_changed,
                                           'replaced_version_no', v_prev.version_no));
  return jsonb_build_object('added', v_added, 'removed', v_removed, 'changed', v_changed);
end $$;

create or replace function b2b.programme_version_discard(p_version_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.partner_programme_versions set status = 'discarded' where id = p_version_id and status = 'draft';
  if not found then raise exception 'only a draft can be discarded' using errcode = '22023'; end if;
end $$;

-- ---------- the partner go-live checklist now knows about published programmes ----------
create or replace function b2b.partner_checklist(p b2b.partners)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_array(
    jsonb_build_object('key', 'agreement',   'done', false, 'available', false),
    jsonb_build_object('key', 'programmes',  'done', exists (select 1 from b2b.partner_programmes o where o.partner_id = p.id and o.valid_to is null and o.active), 'available', true),
    jsonb_build_object('key', 'credentials', 'done', p.outbound_secret_id is not null, 'available', false),
    jsonb_build_object('key', 'mapping',     'done', false, 'available', false),
    jsonb_build_object('key', 'sla_hours',   'done', exists (select 1 from jsonb_each(p.working_hours) d where jsonb_typeof(d.value) = 'object'), 'available', true),
    jsonb_build_object('key', 'branding',    'done', p.display_name is not null and p.brand_color is not null and p.logo_url is not null, 'available', true),
    jsonb_build_object('key', 'test_leads',  'done', false, 'available', false)
  );
$$;

-- ---------- grants ----------
revoke execute on function b2b.norm_key(text), b2b.match_university(text), b2b.match_course_key(text), b2b.programme_match_version(bigint),
                           b2b.programme_label(bigint), b2b.programme_version_offers(bigint), b2b.fee_gap(bigint, jsonb)
  from public, anon, authenticated;
grant execute on function b2b.norm_key(text), b2b.match_university(text), b2b.match_course_key(text), b2b.programme_match_version(bigint),
                          b2b.programme_label(bigint), b2b.programme_version_offers(bigint), b2b.fee_gap(bigint, jsonb)
  to service_role;
revoke execute on function b2b.programmes_overview(), b2b.programme_partner(bigint), b2b.programme_version(bigint), b2b.catalogue_search(bigint, text),
                           b2b.catalogue_universities(), b2b.programme_version_create(jsonb), b2b.programme_row_review(bigint, text, bigint, text),
                           b2b.programme_rows_approve(bigint, bigint[]), b2b.programme_version_preview(bigint), b2b.programme_version_publish(bigint, text),
                           b2b.programme_version_discard(bigint)
  from public, anon;
grant execute on function b2b.programmes_overview(), b2b.programme_partner(bigint), b2b.programme_version(bigint), b2b.catalogue_search(bigint, text),
                          b2b.catalogue_universities(), b2b.programme_version_create(jsonb), b2b.programme_row_review(bigint, text, bigint, text),
                          b2b.programme_rows_approve(bigint, bigint[]), b2b.programme_version_preview(bigint), b2b.programme_version_publish(bigint, text),
                          b2b.programme_version_discard(bigint)
  to authenticated, service_role;
