-- M2g (6 Oct 2026, Vikas's decision): no authenticator code for Google sign-in.
-- Google sign-in relies on the Google account's own 2-step verification (spec B3 lets the Admin switch TOTP off for
-- Google). Password and emailed-link sessions still need a TOTP-verified session (aal2), so a leaked password alone
-- never gets in. require_totp = true keeps the stricter rule (TOTP for every method).

create or replace function b2b.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from b2b.app_users u
     where u.user_id = auth.uid() and u.is_active and u.role = 'admin'
       and (
         coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
         or (
           not u.require_totp
           -- every way this session was authenticated is an OAuth provider (Google), none is a password or email link
           and jsonb_typeof(auth.jwt() -> 'amr') = 'array'
           and jsonb_array_length(auth.jwt() -> 'amr') > 0
           and not exists (select 1 from jsonb_array_elements(auth.jwt() -> 'amr') m where coalesce(m ->> 'method', '') <> 'oauth')
         )
       ));
$$;

update b2b.app_users set require_totp = false, updated_at = now()
 where email = 'connect@eduwit.in' and require_totp;
