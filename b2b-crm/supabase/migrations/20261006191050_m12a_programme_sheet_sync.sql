-- M12a: Google Sheet sources for the Programme Repository (spec B5.2). The partner shares its sheet with "anyone with the
-- link can view"; the app downloads it as Excel (every tab), reads the chosen tab with the saved column template and
-- creates a draft version through the same matching and review as an upload. A hash of the tab's rows tells whether
-- anything changed, so an unchanged sheet only updates last_checked_at. Publishing still needs the Admin's review.

alter table b2b.partner_programme_sources add column if not exists content_hash text;
alter table b2b.partner_programme_sources add column if not exists last_error text;

/* Same as m5b, plus: a 'gsheet' source keeps the sheet settings and records the content hash and change time. */
create or replace function b2b.programme_version_create(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_partner bigint := (p ->> 'partner_id')::bigint;
  v_id bigint;
  v_no int;
  v_who text := coalesce(auth.uid()::text, 'system');
  v_rows int := jsonb_array_length(coalesce(p -> 'rows', '[]'));
  v_src text := coalesce(p ->> 'source', 'upload');
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partners where id = v_partner and status <> 'closed') then
    raise exception 'partner not found or closed' using errcode = 'P0002';
  end if;
  if v_src not in ('upload', 'gsheet') then raise exception 'unknown source' using errcode = '22023'; end if;
  if jsonb_typeof(p -> 'rows') <> 'array' or v_rows = 0 then raise exception 'the file has no programme rows' using errcode = '22023'; end if;
  if v_rows > 5000 then raise exception 'at most 5000 rows per file' using errcode = '22023'; end if;
  if jsonb_typeof(coalesce(p -> 'template', '{}')) <> 'object' then raise exception 'template must be an object' using errcode = '22023'; end if;
  if p ->> 'file_path' is not null and p ->> 'file_path' !~ ('^' || v_partner || '/[0-9a-f-]{36}\.(xlsx|csv)$') then
    raise exception 'unexpected file path' using errcode = '22023';
  end if;
  if v_src = 'gsheet' and not exists (select 1 from b2b.partner_programme_sources s where s.partner_id = v_partner and s.type = 'gsheet' and s.sheet_id is not null) then
    raise exception 'connect the Google Sheet first' using errcode = '22023';
  end if;

  perform 1 from b2b.partners where id = v_partner for update; -- one version number at a time per partner
  update b2b.partner_programme_versions set status = 'discarded' where partner_id = v_partner and status = 'draft';
  select coalesce(max(version_no), 0) + 1 into v_no from b2b.partner_programme_versions where partner_id = v_partner;

  insert into b2b.partner_programme_versions (partner_id, version_no, source_type, file_path, file_name, sheet, row_count, uploaded_by)
  values (v_partner, v_no, v_src, p ->> 'file_path', left(p ->> 'file_name', 200), left(p ->> 'sheet', 100), v_rows, v_who)
  returning id into v_id;

  insert into b2b.partner_programme_rows (version_id, row_no, raw, norm, match_sig)
  select v_id, (x ->> 'row_no')::int, coalesce(x -> 'raw', '{}'), coalesce(x -> 'norm', '{}'),
         nullif(concat_ws('|', b2b.norm_key(x -> 'norm' ->> 'university'), b2b.norm_key(x -> 'norm' ->> 'course'),
                          b2b.norm_key(coalesce(nullif(x -> 'norm' ->> 'specialization', ''), 'General')), b2b.norm_key(x -> 'norm' ->> 'mode'),
                          b2b.norm_key(x -> 'norm' ->> 'level'), b2b.norm_key(x -> 'norm' ->> 'programme_code')), '|||||')
    from jsonb_array_elements(p -> 'rows') x;

  if v_src = 'gsheet' then
    update b2b.partner_programme_sources
       set column_template = coalesce(p -> 'template', '{}'), tab = left(p ->> 'sheet', 100), content_hash = left(p ->> 'content_hash', 128),
           last_checked_at = now(), last_changed_at = now(), last_error = null, updated_at = now()
     where partner_id = v_partner;
  else
    insert into b2b.partner_programme_sources (partner_id, type, column_template, updated_at)
    values (v_partner, 'upload', coalesce(p -> 'template', '{}'), now())
    on conflict (partner_id) do update set type = 'upload', column_template = excluded.column_template, updated_at = now();
  end if;

  perform b2b.programme_match_version(v_id);
  perform b2b.log_event('programmes.uploaded', null, null, v_partner, jsonb_build_object('version_id', v_id, 'version_no', v_no, 'rows', v_rows,
                        'file', p ->> 'file_name', 'source', v_src));
  return jsonb_build_object('id', v_id, 'version_no', v_no);
end $$;

/* Connect (or change) the partner's Google Sheet. Uploading a file later switches the source back to uploads. */
create or replace function b2b.programme_sheet_save(p_partner_id bigint, p_sheet_id text, p_tab text, p_every_hours int)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare s b2b.partner_programme_sources;
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from b2b.partners where id = p_partner_id and status <> 'closed') then raise exception 'partner not found or closed' using errcode = 'P0002'; end if;
  if coalesce(p_sheet_id, '') !~ '^[A-Za-z0-9_-]{25,100}$' then raise exception 'paste the link of the Google Sheet' using errcode = '22023'; end if;
  if coalesce(p_every_hours, 6) not between 1 and 168 then raise exception 'check every 1 to 168 hours' using errcode = '22023'; end if;
  insert into b2b.partner_programme_sources (partner_id, type, sheet_id, tab, sync_every_hours, updated_at)
  values (p_partner_id, 'gsheet', p_sheet_id, nullif(left(trim(p_tab), 100), ''), coalesce(p_every_hours, 6), now())
  on conflict (partner_id) do update set type = 'gsheet', sheet_id = excluded.sheet_id, tab = coalesce(excluded.tab, b2b.partner_programme_sources.tab),
         sync_every_hours = excluded.sync_every_hours,
         content_hash = case when b2b.partner_programme_sources.sheet_id is distinct from excluded.sheet_id then null else b2b.partner_programme_sources.content_hash end,
         last_error = null, updated_at = now()
  returning * into s;
  perform b2b.log_event('programmes.sheet_connected', null, null, p_partner_id, jsonb_build_object('sheet_id', p_sheet_id, 'tab', s.tab));
  return to_jsonb(s);
end $$;

/* A sync that found nothing new, or failed: only the check time and the error change. */
create or replace function b2b.programme_sheet_checked(p_partner_id bigint, p_error text)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.partner_programme_sources set last_checked_at = now(), last_error = left(nullif(p_error, ''), 300)
   where partner_id = p_partner_id and type = 'gsheet';
  if p_error is not null then
    perform b2b.log_event('alert.programme_sheet_failed', null, null, p_partner_id, jsonb_build_object('error', left(p_error, 300)));
  end if;
end $$;

/* Back to file uploads; the sheet link is kept so it can be reconnected. */
create or replace function b2b.programme_sheet_disconnect(p_partner_id bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if not b2b.is_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update b2b.partner_programme_sources set type = 'upload', updated_at = now() where partner_id = p_partner_id and type = 'gsheet';
  perform b2b.log_event('programmes.sheet_disconnected', null, null, p_partner_id, '{}');
end $$;

revoke execute on function b2b.programme_sheet_save(bigint, text, text, int), b2b.programme_sheet_checked(bigint, text),
                           b2b.programme_sheet_disconnect(bigint) from public, anon;
grant execute on function b2b.programme_sheet_save(bigint, text, text, int), b2b.programme_sheet_checked(bigint, text),
                          b2b.programme_sheet_disconnect(bigint) to authenticated, service_role;
