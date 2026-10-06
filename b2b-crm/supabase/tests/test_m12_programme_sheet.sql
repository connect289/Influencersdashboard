-- M12a Google Sheet sources, on STAGING (uses partner 22, a staging fixture), rolled back: connecting validates the
-- sheet id, a sheet version needs a connected sheet, a sync stores the hash and template, failed and clean checks are
-- recorded (a failure raises an alert), a new sheet resets the hash, and disconnecting goes back to uploads.
-- Every row of the final select must say ok = true.
begin;
create temp table r (name text, ok boolean, detail text);
grant all on r to authenticated;
insert into auth.users (id, email, aud, role) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'sheet-admin@test.local', 'authenticated', 'authenticated');
insert into b2b.app_users (user_id, email) values ('aaaaaaaa-0000-0000-0000-0000000000a9', 'sheet-admin@test.local');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-0000000000a9","role":"authenticated","aal":"aal2","email":"sheet-admin@test.local"}', true);
do $t$
declare pid bigint := 22; s jsonb; v jsonb; rows jsonb := '[{"row_no":2,"raw":{"Course":"MBA"},"norm":{"university":"E2E University","course":"MBA","mode":"Online","level":"PG"}}]';
begin
  begin perform b2b.programme_sheet_save(pid, 'not-a-sheet', null, 6); insert into r values ('bad_sheet_id', false, 'ran');
  exception when others then insert into r values ('bad_sheet_id', sqlerrm like 'paste the link%', sqlerrm); end;
  begin perform b2b.programme_version_create(jsonb_build_object('partner_id', pid, 'source', 'gsheet', 'rows', rows, 'template', '{}'::jsonb));
        insert into r values ('gsheet_needs_connection', false, 'ran');
  exception when others then insert into r values ('gsheet_needs_connection', sqlerrm like 'connect the Google Sheet%', sqlerrm); end;
  s := b2b.programme_sheet_save(pid, '1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abc', 'Programmes', 12);
  insert into r values ('sheet_saved', s ->> 'type' = 'gsheet' and s ->> 'tab' = 'Programmes' and (s ->> 'sync_every_hours')::int = 12, s::text);
  v := b2b.programme_version_create(jsonb_build_object('partner_id', pid, 'source', 'gsheet', 'rows', rows, 'template', '{"course":"Course"}'::jsonb,
         'sheet', 'Programmes', 'file_name', 'Google Sheet', 'content_hash', 'abc123'));
  insert into r select 'version_from_sheet', x.source_type = 'gsheet' and x.status = 'draft', x.source_type || ' v' || x.version_no from b2b.partner_programme_versions x where x.id = (v ->> 'id')::bigint;
  insert into r select 'source_after_sync', type = 'gsheet' and content_hash = 'abc123' and last_changed_at is not null and column_template ->> 'course' = 'Course', to_jsonb(s2)::text
    from b2b.partner_programme_sources s2 where partner_id = pid;
  perform b2b.programme_sheet_checked(pid, 'HTTP 403: the sheet is not shared');
  insert into r select 'check_failed_recorded', last_error like 'HTTP 403%' and content_hash = 'abc123', last_error from b2b.partner_programme_sources where partner_id = pid;
  perform b2b.programme_sheet_checked(pid, null);
  insert into r select 'check_ok_clears_error', last_error is null, null from b2b.partner_programme_sources where partner_id = pid;
  s := b2b.programme_sheet_save(pid, '1ZZZdEfGhIjKlMnOpQrStUvWxYz0123456789_-abc', null, 6);
  insert into r values ('new_sheet_resets_hash', s ->> 'content_hash' is null and s ->> 'tab' = 'Programmes', s ->> 'content_hash');
  perform b2b.programme_sheet_disconnect(pid);
  insert into r select 'disconnected', type = 'upload' and sheet_id is not null, type from b2b.partner_programme_sources where partner_id = pid;
end $t$;
reset role;
insert into r select 'alert_logged', count(*) = 1, null from b2b.events where type = 'alert.programme_sheet_failed' and partner_id = 22 and occurred_at = now();
select name, ok, left(detail, 200) detail from r order by ok, name;
rollback;
