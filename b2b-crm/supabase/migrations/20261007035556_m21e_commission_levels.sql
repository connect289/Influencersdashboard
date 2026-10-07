-- M21e: commission at programme, university or partner level (Vikas, 7 Oct). The partner's programme sheet carries a
-- commission % per programme, GST included unless the Admin says otherwise; publishing the reviewed sheet confirms it as
-- partner + programme rates. University-level (per partner) and partner-wide rates are set in Routing → Rates.
-- The most specific rate in force wins: partner + programme, then partner + university, then partner, then programme,
-- then university.
--   rates scope 'partner_university'; partner_programme_sources.commission_includes_gst (default true)
--   rate_for                 the new order
--   rate_save                takes partner_university with a catalogue university
--   rates_from_offers        live offers' commission → partner + programme rates (file source); rates whose commission left the file end
--   rates_confirm_from_offers  the Admin's button, now with the GST flag
--   programme_version_publish  publishing a version confirms its commission
--   programme_commission_gst_save  "commission in this partner's file includes GST" on or off (rates follow)

alter table b2b.rates drop constraint if exists rates_scope_check;
alter table b2b.rates add constraint rates_scope_check check (scope in ('partner_programme', 'partner_university', 'partner', 'programme', 'university'));
alter table b2b.rates drop constraint if exists rates_check2;
alter table b2b.rates add constraint rates_scope_ids_check check (case scope
  when 'partner_programme' then partner_id is not null and programme_id is not null
  when 'partner_university' then partner_id is not null and programme_id is null and university_id is not null
  when 'partner' then partner_id is not null and programme_id is null
  when 'programme' then partner_id is null and programme_id is not null
  else partner_id is null and programme_id is null and university_id is not null end);
create index if not exists rates_partner_university_idx on b2b.rates (partner_id, university_id) where valid_to is null and scope = 'partner_university';
alter table b2b.partner_programme_sources add column if not exists commission_includes_gst boolean not null default true;

/* The rate in force for a partner and programme: partner + programme, partner + university, partner, programme, university. */
create or replace function b2b.rate_for(p_partner bigint, p_programme bigint, p_on date default current_date)
returns b2b.rates language sql stable set search_path = '' as $fn$
  with u as (select c.university_id from public.catalog_programs c where c.id = p_programme)
  select r.* from b2b.rates r
   where r.valid_from <= p_on and (r.valid_to is null or r.valid_to >= p_on)
     and ((r.scope = 'partner_programme' and r.partner_id = p_partner and r.programme_id = p_programme)
       or (r.scope = 'partner_university' and r.partner_id = p_partner and r.university_id = (select university_id from u))
       or (r.scope = 'partner' and r.partner_id = p_partner)
       or (r.scope = 'programme' and r.programme_id = p_programme)
       or (r.scope = 'university' and r.university_id = (select university_id from u)))
   order by case r.scope when 'partner_programme' then 1 when 'partner_university' then 2 when 'partner' then 3 when 'programme' then 4 else 5 end,
            r.valid_from desc, r.id desc
   limit 1;
$fn$;

create or replace function b2b.rate_save(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_scope text := p ->> 'scope';
  v_partner bigint := nullif(p ->> 'partner_id', '')::bigint;
  v_prog bigint := nullif(p ->> 'programme_id', '')::bigint;
  v_from date := coalesce(nullif(p ->> 'valid_from', '')::date, current_date);
  v_uni bigint := nullif(p ->> 'university_id', '')::bigint;
  v_id bigint;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_scope not in ('partner', 'partner_university', 'partner_programme') then raise exception 'rates are set per partner, per university at a partner or per partner programme' using errcode = '22023'; end if;
  if v_scope = 'partner_university' and not exists (select 1 from public.catalog_universities where id = v_uni) then
    raise exception 'choose a university' using errcode = '22023';
  end if;
  if not exists (select 1 from b2b.partners where id = v_partner) then raise exception 'choose a partner' using errcode = '22023'; end if;
  if v_scope = 'partner_programme' and not exists (select 1 from public.catalog_programs where id = v_prog) then
    raise exception 'choose a catalogue programme' using errcode = '22023';
  end if;
  if p ->> 'rate_type' = 'percent' and not (nullif(p ->> 'value', '')::numeric > 0 and (p ->> 'value')::numeric <= 100) then
    raise exception 'a percentage must be above 0 and at most 100' using errcode = '22023';
  end if;
  if p ->> 'rate_type' = 'fixed' and not (nullif(p ->> 'value', '')::numeric > 0) then raise exception 'enter the amount' using errcode = '22023'; end if;
  if p ->> 'rate_type' = 'tiered' and jsonb_typeof(p -> 'tiers') <> 'array' then raise exception 'tiers must be a list' using errcode = '22023'; end if;

  update b2b.rates set valid_to = greatest(valid_from, v_from - 1)
   where valid_to is null and scope = v_scope and partner_id = v_partner
     and programme_id is not distinct from (case when v_scope = 'partner_programme' then v_prog end)
     and university_id is not distinct from (case when v_scope = 'partner_university' then v_uni end);

  insert into b2b.rates (scope, partner_id, programme_id, university_id, rate_type, fee_base, value, tiers, gst_inclusive, valid_from, source, source_version_id, note, created_by)
  values (v_scope, v_partner, case when v_scope = 'partner_programme' then v_prog end, case when v_scope = 'partner_university' then v_uni end,
          p ->> 'rate_type', coalesce(nullif(p ->> 'fee_base', ''), 'first_year'),
          case when p ->> 'rate_type' = 'tiered' then null else (p ->> 'value')::numeric end,
          case when p ->> 'rate_type' = 'tiered' then p -> 'tiers' end,
          coalesce((p ->> 'gst_inclusive')::boolean, false), v_from, coalesce(nullif(p ->> 'source', ''), 'manual'),
          nullif(p ->> 'source_version_id', '')::bigint, nullif(left(trim(p ->> 'note'), 300), ''), coalesce(auth.uid()::text, 'system'))
  returning id into v_id;
  perform b2b.log_event('rate.created', null, null, v_partner, jsonb_build_object('rate_id', v_id, 'scope', v_scope, 'programme_id', v_prog,
                        'university_id', v_uni, 'rate_type', p ->> 'rate_type', 'value', p -> 'value', 'valid_from', v_from));
  return jsonb_build_object('id', v_id);
end $fn$;

/* The partner's live offers carry the commission from its file; each becomes a partner + programme rate (source 'file').
   Unchanged rates are kept; a programme whose commission left the file has its file rate end today, so from tomorrow the
   university or partner rate applies. Tier references ("Tier 2") are skipped: set tiered rates by hand. */
create or replace function b2b.rates_from_offers(p_partner_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_gst boolean := coalesce((select commission_includes_gst from b2b.partner_programme_sources where partner_id = p_partner_id), true);
  o record;
  r b2b.rates;
  v_created int := 0; v_same int := 0; v_tier int := 0; v_ended int := 0;
begin
  for o in select * from b2b.partner_programmes where partner_id = p_partner_id and valid_to is null and active and commission is not null loop
    if o.commission ->> 'type' not in ('percent', 'fixed') then v_tier := v_tier + 1; continue; end if;
    select * into r from b2b.rates where scope = 'partner_programme' and partner_id = p_partner_id and programme_id = o.programme_id and valid_to is null;
    if r.id is not null and r.rate_type = o.commission ->> 'type' and r.value = (o.commission ->> 'value')::numeric and r.gst_inclusive = v_gst then
      v_same := v_same + 1; continue;
    end if;
    update b2b.rates set valid_to = greatest(valid_from, current_date - 1)
     where valid_to is null and scope = 'partner_programme' and partner_id = p_partner_id and programme_id = o.programme_id;
    insert into b2b.rates (scope, partner_id, programme_id, rate_type, fee_base, value, gst_inclusive, valid_from, source, source_version_id, note, created_by)
    values ('partner_programme', p_partner_id, o.programme_id, o.commission ->> 'type', coalesce(r.fee_base, 'first_year'), (o.commission ->> 'value')::numeric,
            v_gst, current_date, 'file', o.source_version_id,
            'From the partner''s programme sheet' || case when v_gst then ' (GST included)' else ' (GST extra)' end, coalesce(auth.uid()::text, 'system'));
    v_created := v_created + 1;
  end loop;
  with gone as (
    update b2b.rates fr set valid_to = greatest(fr.valid_from, current_date - 1)
     where fr.valid_to is null and fr.scope = 'partner_programme' and fr.partner_id = p_partner_id and fr.source = 'file'
       and not exists (select 1 from b2b.partner_programmes po where po.partner_id = p_partner_id and po.programme_id = fr.programme_id and po.valid_to is null
                         and po.active and po.commission ->> 'type' in ('percent', 'fixed'))
    returning 1)
  select count(*) into v_ended from gone;
  if v_created + v_ended > 0 then
    perform b2b.log_event('rate.from_file', null, null, p_partner_id, jsonb_build_object('created', v_created, 'ended', v_ended, 'gst_inclusive', v_gst));
  end if;
  return jsonb_build_object('created', v_created, 'unchanged', v_same, 'ended', v_ended, 'tiers_skipped', v_tier, 'gst_inclusive', v_gst);
end $fn$;

create or replace function b2b.rates_confirm_from_offers(p_partner_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return b2b.rates_from_offers(p_partner_id);
end $fn$;

/* Whether the commission in the partner's sheet includes GST; the partner + programme rates follow at once. */
create or replace function b2b.programme_commission_gst_save(p_partner_id bigint, p_includes_gst boolean)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.partner_programme_sources set commission_includes_gst = coalesce(p_includes_gst, true), updated_at = now() where partner_id = p_partner_id;
  if not found then raise exception 'add the partner''s programme file first' using errcode = '22023'; end if;
  perform b2b.log_event('programmes.commission_gst', null, null, p_partner_id, jsonb_build_object('includes_gst', p_includes_gst));
  return b2b.rates_from_offers(p_partner_id);
end $fn$;

create or replace function b2b.programme_version_publish(p_version_id bigint, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v b2b.partner_programme_versions;
  v_prev b2b.partner_programme_versions;
  v_now timestamptz := clock_timestamp();
  v_who text := coalesce(auth.uid()::text, 'system');
  v_added int; v_removed int; v_changed int;
  v_rates jsonb;
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
  -- the commission in the file is confirmed by publishing it (reviewed above): partner + programme rates, GST as the source says
  v_rates := b2b.rates_from_offers(v.partner_id);

  perform b2b.log_event(case when v.status = 'draft' then 'programmes.published' else 'programmes.rolled_back' end, null, null, v.partner_id,
                        jsonb_build_object('version_id', v.id, 'version_no', v.version_no, 'added', v_added, 'removed', v_removed, 'changed', v_changed,
                                           'replaced_version_no', v_prev.version_no, 'rates', v_rates));
  return jsonb_build_object('added', v_added, 'removed', v_removed, 'changed', v_changed, 'rates', v_rates);
end $fn$;

revoke execute on function b2b.rate_for(bigint, bigint, date), b2b.rates_from_offers(bigint) from public, anon, authenticated;
grant execute on function b2b.rate_for(bigint, bigint, date), b2b.rates_from_offers(bigint) to service_role;
revoke execute on function b2b.rate_save(jsonb), b2b.rates_confirm_from_offers(bigint), b2b.programme_version_publish(bigint, text),
                           b2b.programme_commission_gst_save(bigint, boolean) from public, anon;
grant execute on function b2b.rate_save(jsonb), b2b.rates_confirm_from_offers(bigint), b2b.programme_version_publish(bigint, text),
                          b2b.programme_commission_gst_save(bigint, boolean) to authenticated, service_role;
