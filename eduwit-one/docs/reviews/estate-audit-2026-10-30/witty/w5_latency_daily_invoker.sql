-- w5_latency_daily_invoker (proposed 30 Oct 2026, Witty audit; not applied)
--
-- What: public.w2_latency_daily runs with the caller's rights (security_invoker) and is no longer granted to anon or
-- authenticated.
-- Why: the view aggregates public.w2_messages, which is protected by RLS; no application reads the view through the
-- API. postgres and service_role keep reading every row. Idempotent.

alter view public.w2_latency_daily set (security_invoker = true);
revoke all on table public.w2_latency_daily from anon, authenticated;

-- rollback:
-- alter view public.w2_latency_daily reset (security_invoker);
-- grant all on table public.w2_latency_daily to anon, authenticated;
