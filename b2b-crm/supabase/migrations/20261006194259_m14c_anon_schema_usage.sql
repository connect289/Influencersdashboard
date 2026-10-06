-- M14c: the public machine endpoints (/v1/partners/{slug}/events, /v1/events/b2ccrm, /v1/handoffs,
-- /v1/leads/{id}/route-to-partners) call their b2b functions with the publishable (anon) key, and those functions check
-- the caller's HMAC signature or API key themselves. The anon role had EXECUTE on them but no USAGE on schema b2b, so
-- every call failed (found while testing m14; the partner event route shipped in m8c had the same problem).
-- Anon still has no table privileges in b2b (0 of 32 checked) and EXECUTE on only those four functions; new b2b
-- functions no longer get EXECUTE for PUBLIC by default, so nothing becomes callable by accident.

grant usage on schema b2b to anon;
alter default privileges in schema b2b revoke execute on functions from public;
