-- B2C CRM b50 (audit of 30 Oct 2026): the emailed sign-in code is drawn from pgcrypto's gen_random_bytes, as the
-- trusted-device token is; same six digits and limits.
-- Idempotent. Checks: supabase/tests/test_audit_2026_10.sql. Rollback: the block at the end.

create or replace function b2c.mfa_issue(p_user uuid, p_session uuid) returns text language plpgsql security definer set search_path = '' as $f$
declare v_code text;
begin
  if not exists (select 1 from b2c.users where user_id = p_user and is_active) then raise exception 'not an active user'; end if;
  if (select count(*) from b2c.email_codes where user_id = p_user and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'too many codes: try again in an hour';
  end if;
  v_code := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into b2c.email_codes (user_id, session_id, code_hash, expires_at)
  values (p_user, p_session, extensions.crypt(v_code, extensions.gen_salt('bf', 8)), now() + interval '10 minutes');
  return v_code;
end $f$;

-- rollback (restores the b1 definition):
-- create or replace function b2c.mfa_issue(p_user uuid, p_session uuid) returns text language plpgsql security definer set search_path = '' as $f$
-- declare v_code text;
-- begin
--   if not exists (select 1 from b2c.users where user_id = p_user and is_active) then raise exception 'not an active user'; end if;
--   if (select count(*) from b2c.email_codes where user_id = p_user and created_at > now() - interval '1 hour') >= 5 then
--     raise exception 'too many codes: try again in an hour';
--   end if;
--   v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
--   insert into b2c.email_codes (user_id, session_id, code_hash, expires_at)
--   values (p_user, p_session, extensions.crypt(v_code, extensions.gen_salt('bf', 8)), now() + interval '10 minutes');
--   return v_code;
-- end $f$;
