-- Unsubscribe links in emails, 13 Nov 2026 (schema inf only; D-198).
-- Withdrawing consent must be as easy as giving it (DPDP Act), and bulk-sender rules ask for one-click unsubscribe.
-- Every email that is not a required notice now carries a signed link (the app signs and checks it; no secret is read
-- from the database). Following it turns the email channel off for that kind of notification, in the same tables the
-- notification settings page writes, so the consent log records it like any other choice.
-- 1. inf.communication_consents.source says how a choice was made: 'settings' (the settings page, as until now) or
--    'unsubscribe_link'. The two consent triggers read it from the transaction-local setting inf.consent_source,
--    which only inf.unsubscribe_email sets.
-- 2. inf.unsubscribe_email(user, category), service role only (the public route uses the admin client after checking
--    the link's signature). Category 'digest' turns the digest off when it is sent by email (and a digest email copy
--    the person had switched on by itself). Any other category is a notification group (inf.notification_events.grp)
--    and turns email off for every event of that group the person can receive, except required ones, which keep
--    arriving, and the digest, which has its own category. Events whose email is off by default get the choice
--    recorded too, so a later change of defaults does not bring back what the person stopped. Returns how many
--    choices changed (0 when everything was off already, the person is unknown or the category matches nothing), so
--    following a link twice is harmless.
-- 3. inf.my_consents() also returns the source.
-- Idempotent. Inverse statements: see the rollback block at the end.

-- ---------------------------------------------------------------------------------------------------------------
-- 1. The consent log records where a choice came from
-- ---------------------------------------------------------------------------------------------------------------
alter table inf.communication_consents
  add column if not exists source text not null default 'settings' check (source in ('settings', 'unsubscribe_link'));

create or replace function inf.consent_from_preference() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.enabled is not distinct from new.enabled then return null; end if;
  if new.channel in ('email', 'whatsapp') then
    insert into inf.communication_consents (user_id, purpose, channel, granted, source)
    values (new.user_id, new.event, new.channel, new.enabled,
            case when current_setting('inf.consent_source', true) = 'unsubscribe_link' then 'unsubscribe_link' else 'settings' end);
  end if;
  return null;
end $$;

create or replace function inf.consent_from_digest() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.frequency is not distinct from new.frequency and old.channel is not distinct from new.channel then return null; end if;
  insert into inf.communication_consents (user_id, purpose, channel, granted, detail, source)
  values (new.user_id, 'digest', new.channel, new.frequency <> 'off', new.frequency,
          case when current_setting('inf.consent_source', true) = 'unsubscribe_link' then 'unsubscribe_link' else 'settings' end);
  return null;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- 2. Following an unsubscribe link (service role; the app has already checked the link's signature)
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.unsubscribe_email(p_user uuid, p_category text) returns int
language plpgsql security definer set search_path = '' as $$
declare v_audience text[]; v_n int := 0; v_m int := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_user is null or p_category is null or not exists (select 1 from auth.users u where u.id = p_user) then return 0; end if;
  perform set_config('inf.consent_source', 'unsubscribe_link', true);
  if p_category = 'digest' then
    -- No row yet means the default digest, which is sent by email. A digest sent by WhatsApp is left alone.
    insert into inf.digest_preferences as d (user_id, frequency, channel) values (p_user, 'off', 'email')
    on conflict (user_id) do update set frequency = 'off', updated_at = now()
      where d.channel = 'email' and d.frequency <> 'off';
    get diagnostics v_n = row_count;
    -- An email copy of the digest the person switched on by itself (next to a WhatsApp digest) stops as well.
    update inf.notification_preferences np set enabled = false, updated_at = now()
     where np.user_id = p_user and np.event like 'digest.%' and np.channel = 'email' and np.enabled;
    get diagnostics v_m = row_count;
    v_n := v_n + v_m;
  else
    v_audience := array_remove(array[
      case when exists (select 1 from inf.creator_accounts a where a.user_id = p_user) then 'creator' end,
      case when exists (select 1 from inf.agency_members m where m.user_id = p_user) then 'agency' end,
      case when exists (select 1 from inf.staff_profiles s where s.user_id = p_user) then 'staff' end], null);
    insert into inf.notification_preferences as np (user_id, event, channel, enabled)
    select p_user, e.event, 'email', false from inf.notification_events e
     where e.grp = p_category and not e.mandatory and e.event not like 'digest.%' and e.audience && v_audience
    on conflict (user_id, event, channel) do update set enabled = false, updated_at = now()
      where np.enabled;
    get diagnostics v_n = row_count;
  end if;
  perform set_config('inf.consent_source', '', true);
  return v_n;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
-- 3. A person's own consent history shows the source
-- ---------------------------------------------------------------------------------------------------------------
create or replace function inf.my_consents() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('purpose', c.purpose, 'channel', c.channel, 'granted', c.granted, 'detail', c.detail,
                                               'source', c.source, 'created_at', c.created_at) order by c.created_at desc, c.id desc), '[]')
    from (select * from inf.communication_consents x where x.user_id = auth.uid() order by x.created_at desc, x.id desc limit 200) c
   where inf.session_ok()
$$;

-- No client role may call inf.unsubscribe_email (the service role has execute through the schema's default privileges).
call inf.apply_client_grants();

-- ---------------------------------------------------------------------------------------------------------------
-- Rollback (inverse statements; the definitions as they stood before, from 20261025000100_inf_insight_privacy.sql)
-- ---------------------------------------------------------------------------------------------------------------
-- drop function if exists inf.unsubscribe_email(uuid, text);
-- create or replace function inf.consent_from_preference() returns trigger
-- language plpgsql security definer set search_path = '' as $$
-- begin
--   if tg_op = 'UPDATE' and old.enabled is not distinct from new.enabled then return null; end if;
--   if new.channel in ('email', 'whatsapp') then
--     insert into inf.communication_consents (user_id, purpose, channel, granted) values (new.user_id, new.event, new.channel, new.enabled);
--   end if;
--   return null;
-- end $$;
-- create or replace function inf.consent_from_digest() returns trigger
-- language plpgsql security definer set search_path = '' as $$
-- begin
--   if tg_op = 'UPDATE' and old.frequency is not distinct from new.frequency and old.channel is not distinct from new.channel then return null; end if;
--   insert into inf.communication_consents (user_id, purpose, channel, granted, detail)
--   values (new.user_id, 'digest', new.channel, new.frequency <> 'off', new.frequency);
--   return null;
-- end $$;
-- create or replace function inf.my_consents() returns jsonb
-- language sql stable security definer set search_path = '' as $$
--   select coalesce(jsonb_agg(jsonb_build_object('purpose', c.purpose, 'channel', c.channel, 'granted', c.granted, 'detail', c.detail,
--                                                'created_at', c.created_at) order by c.created_at desc), '[]')
--     from (select * from inf.communication_consents x where x.user_id = auth.uid() order by x.created_at desc limit 200) c
--    where inf.session_ok()
-- $$;
-- -- The source of earlier choices is lost with the column (the choices themselves stay in the log and in force).
-- alter table inf.communication_consents drop column if exists source;
-- call inf.apply_client_grants();
