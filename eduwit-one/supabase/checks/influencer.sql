-- Influencer portal checks (spec §6, INF-*; D-019, D-020). Sources for scripts/db/gen-checks.ts. The portal runs on
-- schema inf since 18 Oct; its health is read through one.inf_health(), and nothing is granted on inf.

-- check: INF-01
-- app: influencer
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: A lead carries a referral code no creator owns
-- description: Leads from the last 30 days whose student_leads.referral_code matches no legacy public.influencers code, no inf.tracking_links code and no inf.deals code (retargeted to schema inf, D-019).
select count(*) = 0 as ok, jsonb_build_object('count', count(*), 'codes', coalesce(jsonb_agg(distinct l.referral_code), '[]')) as value
  from public.student_leads l
 where l.created_at > now() - interval '30 days' and nullif(l.referral_code, '') is not null and not coalesce(l.is_test, false)
   and not exists (select 1 from public.influencers i where i.referral_code = l.referral_code)
   and not exists (select 1 from inf.tracking_links t where t.code = l.referral_code)
   and not exists (select 1 from inf.deals d where d.code = l.referral_code)

-- check: INF-02
-- app: influencer
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: Legacy referral outcomes disagree with the leads table
-- description: For each legacy public.influencers code, the public.b2b_referral_outcomes row count differs from the student_leads count with that referral_code.
with o as (select referral_code, count(*) as n from public.b2b_referral_outcomes group by 1),
l as (select referral_code, count(*) as n from public.student_leads where referral_code in (select referral_code from public.influencers) group by 1),
d as (select coalesce(o.referral_code, l.referral_code) as code, coalesce(o.n, 0) as outcomes, coalesce(l.n, 0) as leads
        from o full join l on l.referral_code = o.referral_code where coalesce(o.n, 0) <> coalesce(l.n, 0))
select count(*) = 0 as ok, jsonb_build_object('mismatches', coalesce(jsonb_agg(jsonb_build_object('code', code, 'outcomes', outcomes, 'leads', leads)) filter (where code is not null), '[]')) as value
  from d

-- check: INF-03
-- app: influencer
-- kind: sql
-- severity: P2
-- cadence_s: 300
-- tags: security
-- title: Repeated failed legacy portal logins for one code
-- description: More than 20 failed public.influencer_login_attempts for one referral code in 15 min.
select count(*) = 0 as ok, jsonb_build_object('codes', coalesce(jsonb_agg(jsonb_build_object('code', referral_code, 'failed', n)) filter (where referral_code is not null), '[]')) as value
  from (select referral_code, count(*) as n from public.influencer_login_attempts
         where not ok and at > now() - interval '15 minutes' group by referral_code having count(*) > 20) x

-- check: INF-04
-- app: influencer
-- kind: http
-- severity: P1
-- cadence_s: 60
-- open_after: 2
-- title: The influencer portal's /api/health is not ok
-- description: GET <hosts.influencer>/api/health not ok twice in a row. Run by the app's health probe, which also writes heartbeat influencer.

-- check: INF-05
-- app: influencer
-- kind: rpc
-- severity: P1
-- cadence_s: 60
-- title: The influencer portal's database health is not ok
-- description: inf.health() through one.inf_health(): database or job queue not ok (D-019, D-020).
select coalesce((h ->> 'db')::boolean, false) and coalesce((h ->> 'queue_ok')::boolean, false) as ok, h as value
  from (select one.inf_health() as h) x

-- check: INF-06
-- app: influencer
-- kind: integrity
-- severity: P1
-- cadence_s: 3600
-- tags: security
-- title: Legacy influencer accounts are still active
-- description: public.influencers rows with status active. The legacy RLS policy lets each read full student_leads rows of its referred leads (portal SHARED_CHANGES L-1, D-019); retire them through a cleanup proposal.
select count(*) = 0 as ok, jsonb_build_object('active_legacy_accounts', count(*)) as value
  from public.influencers where status = 'active'
