-- Unsubscribe links (D-198): the database check to send through an HTTP SQL API (one request, no psql, no pgTAP).
-- Send migrations/20261113140000_inf_unsubscribe.sql followed by this file as ONE request, with no begin or commit
-- added: a request of several statements is one transaction, and this file is a single statement that always ends with
--     ERROR: TESTRESULT total=<checks> failed=<failed> <the failed checks, or "all passed">
-- so the answer is visible and the whole request rolls back, the migration included; nothing is left behind. (An API
-- that commits each statement on its own would keep the migration: where that is not known, send a harmless pair
-- first, e.g. "create table inf.zz_probe (); select 1/0;", and see that the table is not there.) Where the migration is
-- already applied, send this file alone.
-- What it writes, inside the rolled-back transaction only: three test sign-in accounts in auth.users
-- (zz-inf-unsub-…@example.invalid; any trigger another app keeps on auth.users fires for them and is rolled back with
-- them), two test creators ("ZZ unsubscribe test", handles zz.unsub.http.…), one test staff profile, their sessions,
-- their notification choices, and a few test notifications with their queued copies and jobs. Nothing is sent: no
-- email, no WhatsApp message, no HTTP request (the last check counts pg_net's queue when pg_net is installed). It reads
-- no secret and prints no personal data. A step that fails unexpectedly is reported the same way:
-- total=0 failed=1 stopped by <error>. The fuller suite is 029_unsubscribe.sql (pgTAP, local database).
do $unsub$
declare
  v_total int := 0; v_failed int := 1; v_detail text; v_ctx text;
  u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid(); u3 uuid := gen_random_uuid();
  s2 uuid := gen_random_uuid();
  c1 uuid; c2 uuid; v_tag text := txid_current()::text;
  n int; m int; v_seen text; v_before int; q0 bigint := 0; q1 bigint := 0;
  x_campaigns int; x_contracts int; x_announcements int; x_staff_campaigns int;
  v_service constant text := '{"role":"service_role"}';
  v_person2 text;
begin
  create temp table zz_unsub_check (seq serial, name text, ok boolean, detail text) on commit drop;
  begin
    if to_regclass('net.http_request_queue') is not null then
      execute 'select count(*) from net.http_request_queue' into q0;
    end if;
    -- The runner's own identity: no signed-in person, no service role, until a step says otherwise.
    perform set_config('request.jwt.claim.role', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);

    -- ---------- test rows (this transaction only) ----------
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    select '00000000-0000-0000-0000-000000000000', t.id, 'authenticated', 'authenticated', 'zz-inf-unsub-' || t.k || '-' || v_tag || '@example.invalid', '', now(),
           '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', 'ZZ unsubscribe test ' || t.k), now(), now()
      from (values (u1, 'one'), (u2, 'two'), (u3, 'staff')) as t(id, k);
    insert into inf.creators (display_name, handle, email, status)
    values ('ZZ unsubscribe test one', 'zz.unsub.http.1.' || right(v_tag, 8), 'zz-inf-unsub-one-' || v_tag || '@example.invalid', 'active')
    returning id into c1;
    insert into inf.creators (display_name, handle, email, status)
    values ('ZZ unsubscribe test two', 'zz.unsub.http.2.' || right(v_tag, 8), 'zz-inf-unsub-two-' || v_tag || '@example.invalid', 'active')
    returning id into c2;
    insert into inf.creator_accounts (creator_id, user_id) values (c1, u1), (c2, u2);
    insert into inf.staff_profiles (user_id, full_name, email) values (u3, 'ZZ unsubscribe test staff', 'zz-inf-unsub-staff-' || v_tag || '@example.invalid');
    insert into inf.user_sessions (session_id, user_id, kind, verified_at, verified_via) values (s2, u2, 'creator', now(), 'otp');
    v_person2 := json_build_object('sub', u2, 'role', 'authenticated', 'session_id', s2,
                                   'amr', json_build_array(json_build_object('method', 'otp', 'timestamp', extract(epoch from now())::int)))::text;

    select count(*) filter (where e.grp = 'campaigns' and 'creator' = any (e.audience)),
           count(*) filter (where e.grp = 'contracts' and 'creator' = any (e.audience)),
           count(*) filter (where e.grp = 'announcements' and 'creator' = any (e.audience)),
           count(*) filter (where e.grp = 'campaigns' and 'staff' = any (e.audience))
      into x_campaigns, x_contracts, x_announcements, x_staff_campaigns
      from inf.notification_events e where not e.mandatory and e.event not like 'digest.%';

    -- ---------- what the migration made ----------
    insert into zz_unsub_check (name, ok)
    select 'consent_source_column', exists (select 1 from information_schema.columns c
             where c.table_schema = 'inf' and c.table_name = 'communication_consents' and c.column_name = 'source'
               and c.is_nullable = 'NO' and c.column_default like '%settings%');
    insert into zz_unsub_check (name, ok)
    select 'function_definer_empty_search_path', coalesce((select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p
             where p.oid = to_regprocedure('inf.unsubscribe_email(uuid, text)')), false);
    insert into zz_unsub_check (name, ok) values
      ('only_service_role_may_execute', not has_function_privilege('authenticated', 'inf.unsubscribe_email(uuid, text)', 'execute')
         and not has_function_privilege('anon', 'inf.unsubscribe_email(uuid, text)', 'execute')
         and has_function_privilege('service_role', 'inf.unsubscribe_email(uuid, text)', 'execute'));
    insert into zz_unsub_check (name, ok)
    select 'consent_triggers_in_place', count(*) = 2 from pg_trigger t
     where not t.tgisinternal and t.tgname in ('notification_preferences_consent', 'digest_preferences_consent')
       and t.tgrelid in ('inf.notification_preferences'::regclass, 'inf.digest_preferences'::regclass);
    insert into zz_unsub_check (name, ok, detail) values
      ('catalogue_has_events_to_turn_off', x_campaigns >= 3 and x_contracts >= 1 and x_announcements >= 1 and x_staff_campaigns >= 1,
       x_campaigns || '/' || x_contracts || '/' || x_announcements || '/' || x_staff_campaigns);

    -- ---------- who may call it ----------
    begin
      perform inf.unsubscribe_email(u1, 'campaigns');
      insert into zz_unsub_check (name, ok, detail) values ('refuses_caller_without_service_role', false, 'no error');
    exception when insufficient_privilege then
      insert into zz_unsub_check (name, ok) values ('refuses_caller_without_service_role', true);
    end;
    perform set_config('request.jwt.claims', v_person2, true);
    begin
      perform inf.unsubscribe_email(u2, 'campaigns');
      insert into zz_unsub_check (name, ok, detail) values ('refuses_signed_in_person_for_themselves', false, 'no error');
    exception when insufficient_privilege then
      insert into zz_unsub_check (name, ok) values ('refuses_signed_in_person_for_themselves', true);
    end;
    perform set_config('request.jwt.claims', '', true);
    insert into zz_unsub_check (name, ok)
    select 'refused_calls_change_nothing', not exists (select 1 from inf.notification_preferences where user_id in (u1, u2, u3))
             and not exists (select 1 from inf.communication_consents where user_id in (u1, u2, u3));

    -- ---------- one notification group ----------
    perform set_config('request.jwt.claims', v_service, true);
    n := inf.unsubscribe_email(u1, 'campaigns');
    m := inf.unsubscribe_email(u1, 'campaigns');
    perform set_config('request.jwt.claims', '', true);
    insert into zz_unsub_check (name, ok, detail) values
      ('group_turns_off_every_optional_event', n = x_campaigns, n || ' of ' || x_campaigns),
      ('second_click_changes_nothing', m = 0, m::text);
    insert into zz_unsub_check (name, ok)
    select 'group_email_is_off', count(*) = x_campaigns from inf.notification_preferences np join inf.notification_events e on e.event = np.event
     where np.user_id = u1 and e.grp = 'campaigns' and np.channel = 'email' and not np.enabled;
    insert into zz_unsub_check (name, ok)
    select 'no_other_group_channel_or_person', not exists (select 1 from inf.notification_preferences np join inf.notification_events e on e.event = np.event
             where (np.user_id = u1 and (e.grp <> 'campaigns' or np.channel <> 'email' or e.mandatory or not ('creator' = any (e.audience))))
                or np.user_id in (u2, u3));
    insert into zz_unsub_check (name, ok, detail)
    select 'consent_log_has_each_withdrawal_once', count(*) = x_campaigns and bool_and(c.source = 'unsubscribe_link' and not c.granted and c.channel = 'email'), count(*)::text
      from inf.communication_consents c where c.user_id = u1;

    -- What is queued afterwards (queued only: nothing is sent from here).
    perform inf.notify(u1, 'campaign.invited', 'ZZ unsubscribe test', 'Test row, rolled back.', '/creator', '{}', false, 'zz-unsub-http-1-' || v_tag);
    perform inf.notify(u1, 'deal.proposed', 'ZZ unsubscribe test', 'Test row, rolled back.', '/creator', '{}', false, 'zz-unsub-http-2-' || v_tag);
    perform inf.notify(u2, 'campaign.invited', 'ZZ unsubscribe test', 'Test row, rolled back.', '/creator', '{}', false, 'zz-unsub-http-3-' || v_tag);
    insert into zz_unsub_check (name, ok)
    select 'stopped_kind_is_not_queued_by_email', not exists (select 1 from inf.notification_deliveries d join inf.notifications x on x.id = d.notification_id
             where x.idem_key = 'zz-unsub-http-1-' || v_tag and d.channel = 'email')
         and exists (select 1 from inf.notifications x where x.idem_key = 'zz-unsub-http-1-' || v_tag);
    insert into zz_unsub_check (name, ok)
    select 'other_kinds_and_other_people_still_get_email', count(*) = 2 from inf.notification_deliveries d join inf.notifications x on x.id = d.notification_id
     where x.idem_key in ('zz-unsub-http-2-' || v_tag, 'zz-unsub-http-3-' || v_tag) and d.channel = 'email';

    -- ---------- required notices keep arriving ----------
    perform set_config('request.jwt.claims', v_service, true);
    n := inf.unsubscribe_email(u1, 'contracts');
    m := inf.unsubscribe_email(u1, 'money');
    perform set_config('request.jwt.claims', '', true);
    insert into zz_unsub_check (name, ok, detail) values
      ('contracts_only_optional_notices', n = x_contracts, n || ' of ' || x_contracts),
      ('money_all_required_nothing_changes', m = 0, m::text);
    insert into zz_unsub_check (name, ok)
    select 'no_required_event_has_a_choice', not exists (select 1 from inf.notification_preferences np join inf.notification_events e on e.event = np.event
             where np.user_id in (u1, u2, u3) and e.mandatory);
    perform inf.notify(u1, 'contract.sent', 'ZZ unsubscribe test', 'Test row, rolled back.', '/creator', '{}', false, 'zz-unsub-http-4-' || v_tag);
    perform inf.notify(u1, 'contract.comment', 'ZZ unsubscribe test', 'Test row, rolled back.', '/creator', '{}', false, 'zz-unsub-http-5-' || v_tag);
    insert into zz_unsub_check (name, ok)
    select 'required_contract_notice_still_queued_by_email', exists (select 1 from inf.notification_deliveries d join inf.notifications x on x.id = d.notification_id
             where x.idem_key = 'zz-unsub-http-4-' || v_tag and d.channel = 'email')
         and not exists (select 1 from inf.notification_deliveries d join inf.notifications x on x.id = d.notification_id
             where x.idem_key = 'zz-unsub-http-5-' || v_tag and d.channel = 'email');

    -- ---------- announcements leave the digest alone; the digest has its own link ----------
    perform set_config('request.jwt.claims', v_service, true);
    n := inf.unsubscribe_email(u1, 'announcements');
    perform set_config('request.jwt.claims', '', true);
    insert into zz_unsub_check (name, ok, detail)
    select 'announcements_leave_the_digest', n = x_announcements
             and not exists (select 1 from inf.notification_preferences where user_id = u1 and event like 'digest.%')
             and not exists (select 1 from inf.digest_preferences where user_id = u1), n::text;
    select count(*) into v_before from inf.communication_consents where user_id = u1;
    perform set_config('request.jwt.claims', v_service, true);
    n := inf.unsubscribe_email(u1, 'digest');
    m := inf.unsubscribe_email(u1, 'digest');
    insert into zz_unsub_check (name, ok)
    select 'digest_recipient_no_more', not exists (select 1 from inf.digest_recipients(date '2026-11-16') r where r.user_id = u1);
    perform set_config('request.jwt.claims', '', true);
    insert into zz_unsub_check (name, ok, detail) values ('digest_turned_off_once', n = 1 and m = 0, n || '/' || m);
    insert into zz_unsub_check (name, ok)
    select 'digest_choice_is_off_by_email', (select d.frequency || ':' || d.channel from inf.digest_preferences d where d.user_id = u1) = 'off:email';
    insert into zz_unsub_check (name, ok, detail)
    select 'digest_withdrawal_in_consent_log', count(*) = v_before + 1
             and (select c.purpose || ':' || c.channel || ':' || c.granted || ':' || c.detail || ':' || c.source
                    from inf.communication_consents c where c.user_id = u1 order by c.id desc limit 1) = 'digest:email:false:off:unsubscribe_link',
           (count(*) - v_before)::text
      from inf.communication_consents where user_id = u1;

    -- A digest sent by WhatsApp is not an email; an email copy switched on next to it is.
    perform set_config('request.jwt.claims', v_person2, true);
    perform inf.digest_preference_set('daily', 'whatsapp');
    perform inf.notification_preference_set('lead.new', 'email', true);
    perform set_config('request.jwt.claims', v_service, true);
    n := inf.unsubscribe_email(u2, 'digest');
    perform set_config('request.jwt.claims', v_person2, true);
    perform inf.notification_preference_set('digest.creator', 'email', true);
    perform set_config('request.jwt.claims', v_service, true);
    m := inf.unsubscribe_email(u2, 'digest');
    perform set_config('request.jwt.claims', '', true);
    insert into zz_unsub_check (name, ok, detail)
    select 'whatsapp_digest_left_alone_email_copy_stopped', n = 0 and m = 1
             and (select d.frequency || ':' || d.channel from inf.digest_preferences d where d.user_id = u2) = 'daily:whatsapp'
             and (select np.enabled from inf.notification_preferences np where np.user_id = u2 and np.event = 'digest.creator' and np.channel = 'email') = false,
           n || '/' || m;

    -- ---------- settings and the link write the same tables; each choice keeps its source ----------
    perform set_config('request.jwt.claims', v_service, true);
    n := inf.unsubscribe_email(u2, 'leads');
    perform set_config('request.jwt.claims', v_person2, true);
    perform inf.notification_preference_set('lead.new', 'email', true);
    select string_agg((x.value ->> 'granted') || ':' || (x.value ->> 'source'), ',' order by x.ord) into v_seen
      from jsonb_array_elements(inf.my_consents()) with ordinality as x(value, ord) where x.value ->> 'purpose' = 'lead.new';
    insert into zz_unsub_check (name, ok, detail) values
      ('person_sees_each_choice_with_its_source', n >= 1 and v_seen = 'true:settings,false:unsubscribe_link,true:settings', v_seen);
    select string_agg(p.value ->> 'enabled', ',') into v_seen
      from jsonb_array_elements(inf.my_notification_preferences() -> 'prefs') as p(value)
     where p.value ->> 'event' = 'lead.enrolled' and p.value ->> 'channel' = 'email';
    insert into zz_unsub_check (name, ok, detail) values ('settings_page_reads_the_links_choice', v_seen = 'false', v_seen);
    perform set_config('request.jwt.claims', '', true);

    -- ---------- staff, and inputs that match nothing ----------
    perform set_config('request.jwt.claims', v_service, true);
    n := inf.unsubscribe_email(u3, 'campaigns');
    m := inf.unsubscribe_email(gen_random_uuid(), 'campaigns') + inf.unsubscribe_email(u3, 'no_such_group')
       + inf.unsubscribe_email(u3, null) + inf.unsubscribe_email(null, 'campaigns');
    perform set_config('request.jwt.claims', '', true);
    insert into zz_unsub_check (name, ok, detail)
    select 'staff_get_staff_events_only', n = x_staff_campaigns
             and not exists (select 1 from inf.notification_preferences np join inf.notification_events e on e.event = np.event
                              where np.user_id = u3 and not ('staff' = any (e.audience))), n || ' of ' || x_staff_campaigns;
    insert into zz_unsub_check (name, ok, detail) values ('unknown_person_category_and_nulls_change_nothing', m = 0, m::text);

    -- ---------- the consent log stays a log ----------
    begin
      insert into inf.communication_consents (user_id, purpose, channel, granted, source) values (u1, 'digest', 'email', false, 'import');
      insert into zz_unsub_check (name, ok, detail) values ('consent_log_accepts_only_known_sources', false, 'no error');
    exception when check_violation then
      insert into zz_unsub_check (name, ok) values ('consent_log_accepts_only_known_sources', true);
    end;
    begin
      update inf.communication_consents set source = 'settings' where user_id = u1;
      insert into zz_unsub_check (name, ok, detail) values ('consent_log_is_append_only', false, 'no error');
    exception when others then
      insert into zz_unsub_check (name, ok) values ('consent_log_is_append_only', true);
    end;

    if to_regclass('net.http_request_queue') is not null then
      execute 'select count(*) from net.http_request_queue' into q1;
    end if;
    insert into zz_unsub_check (name, ok, detail) values ('no_http_request_queued', q1 = q0, (q1 - q0)::text);

    select count(*), count(*) filter (where ok is not true),
           coalesce(string_agg(name || coalesce(' (' || left(detail, 80) || ')', ''), ', ' order by seq) filter (where ok is not true), 'all passed')
      into v_total, v_failed, v_detail from zz_unsub_check;
  exception when others then
    get stacked diagnostics v_ctx = pg_exception_context;
    v_total := 0; v_failed := 1;
    v_detail := 'stopped by ' || sqlstate || ' ' || left(sqlerrm, 200) || ' at ' || left(split_part(v_ctx, E'\n', 1), 120);
  end;
  raise exception 'TESTRESULT total=% failed=% %', v_total, v_failed, v_detail;
end $unsub$;
