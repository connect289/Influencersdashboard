-- Cross-app integrity checks (spec §6, INT-*). Sources for scripts/db/gen-checks.ts. An allocation is "open" while
-- its status is queued, pushing, pushed or accepted (b2b.allocations CHECK constraint, 23 Oct).

-- check: INT-01
-- app: integrity
-- kind: sql
-- severity: P1
-- cadence_s: 300
-- title: A lead is both with a partner and owned in Spark
-- description: A lead whose student_leads.destination_type is partner, with an open partner allocation, that also has an owner in b2c.leads_state.
select count(*) = 0 as ok, jsonb_build_object('count', count(*), 'lead_ids', coalesce(to_jsonb((array_agg(l.id order by l.id))[1:20]), '[]')) as value
  from public.student_leads l
 where l.destination_type = 'partner' and not coalesce(l.is_test, false)
   and exists (select 1 from b2b.allocations a where a.lead_id = l.id and a.destination_type = 'partner' and a.status in ('queued', 'pushing', 'pushed', 'accepted'))
   and exists (select 1 from b2c.leads_state s where s.lead_id = l.id and s.owner_id is not null and s.deleted_at is null)

-- check: INT-02
-- app: integrity
-- kind: sql
-- severity: P1
-- cadence_s: 300
-- title: A partner-barred lead was allocated to a partner again
-- description: A b2b.partner_bars row (not erased) for a lead with a partner allocation created after the bar.
select count(*) = 0 as ok, jsonb_build_object('count', count(*), 'lead_ids', coalesce(to_jsonb((array_agg(distinct b.lead_id))[1:20]), '[]')) as value
  from b2b.partner_bars b
  join b2b.allocations a on a.lead_id = b.lead_id and a.destination_type = 'partner' and a.created_at > b.barred_at and not coalesce(a.is_test, false)
 where b.erased_at is null

-- check: INT-03
-- app: integrity
-- kind: sql
-- severity: P1
-- cadence_s: 300
-- title: A lead held by Spark has an open partner allocation
-- description: b2c.lead_records.held_by_b2c is true while the lead has an open partner allocation.
select count(*) = 0 as ok, jsonb_build_object('count', count(*), 'lead_ids', coalesce(to_jsonb((array_agg(r.lead_id order by r.lead_id))[1:20]), '[]')) as value
  from b2c.lead_records r
 where r.held_by_b2c and not coalesce(r.is_test, false) and not coalesce(r.deleted, false)
   and exists (select 1 from b2b.allocations a where a.lead_id = r.lead_id and a.destination_type = 'partner' and a.status in ('queued', 'pushing', 'pushed', 'accepted'))

-- check: INT-04
-- app: integrity
-- kind: sql
-- severity: P1
-- cadence_s: 3600
-- tags: money
-- title: Money rows disappeared
-- description: The row count of b2b.earnings, b2b.invoices, b2c.commission_lines or b2c.earnings is lower than in this check's own result from 23 to 25 h ago. Money tables are append-only by design, so any drop is a deletion.
with cur as (
  select jsonb_build_object('b2b_earnings', (select count(*) from b2b.earnings), 'b2b_invoices', (select count(*) from b2b.invoices),
                            'b2c_commission_lines', (select count(*) from b2c.commission_lines), 'b2c_earnings', (select count(*) from b2c.earnings)) as c),
prev as (
  select r.value -> 'counts' as p from one.results r
   where r.check_id = 'INT-04' and r.status in ('ok', 'fail') and r.ran_at between now() - interval '25 hours' and now() - interval '23 hours'
   order by r.ran_at desc limit 1),
drops as (
  select k.key from cur, jsonb_each(cur.c) k left join prev on true
   where (k.value)::bigint < coalesce((prev.p ->> k.key)::bigint, 0))
select (select count(*) from drops) = 0 as ok,
       jsonb_build_object('counts', (select c from cur), 'previous', (select p from prev), 'dropped', (select coalesce(jsonb_agg(key), '[]') from drops)) as value

-- check: INT-05
-- app: integrity
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: Witty or the web advisor sent a marketing message
-- description: A w2_messages or web_advisor_messages row in the last 24 h whose kind is a marketing, campaign, broadcast or promo kind. Both are conversational agents and must not market.
select (select count(*) from public.w2_messages where created_at > now() - interval '24 hours' and kind ~* '(market|campaign|broadcast|promo)') = 0
       and (select count(*) from public.web_advisor_messages where created_at > now() - interval '24 hours' and kind ~* '(market|campaign|broadcast|promo)') = 0 as ok,
       jsonb_build_object('witty', (select count(*) from public.w2_messages where created_at > now() - interval '24 hours' and kind ~* '(market|campaign|broadcast|promo)'),
                          'web_advisor', (select count(*) from public.web_advisor_messages where created_at > now() - interval '24 hours' and kind ~* '(market|campaign|broadcast|promo)')) as value

-- check: INT-06
-- app: integrity
-- kind: sql
-- severity: P1
-- cadence_s: 3600
-- tags: code
-- title: The student_leads columns changed
-- description: A column of student_leads in the baseline captured at install is gone or has a new type: a rename, drop or type change breaks every app that reads it. An added column is listed in the value but does not fail (m11 of the second review); accept a new baseline from the Settings page.
with cur as (
  select jsonb_agg(column_name || ':' || udt_name order by ordinal_position) as cols
    from information_schema.columns where table_schema = 'public' and table_name = 'student_leads')
select b.value is null or not exists (select 1 from jsonb_array_elements_text(b.value) c where not cur.cols ? c) as ok,
       jsonb_build_object('added', (select coalesce(jsonb_agg(c), '[]') from jsonb_array_elements_text(cur.cols) c where b.value is not null and not b.value ? c),
                          'removed_or_changed', (select coalesce(jsonb_agg(c), '[]') from jsonb_array_elements_text(b.value) c where not cur.cols ? c),
                          'baseline_at', b.captured_at) as value
  from cur left join one.baselines b on b.key = 'student_leads_columns'

-- check: INT-07
-- app: integrity
-- kind: sql
-- severity: P1
-- cadence_s: 900
-- tags: consent
-- title: A lead was shared or marketed to without consent
-- description: A non-test lead with an open partner allocation and no consent_partner_share_at, or a marketing WhatsApp (campaign or journey) sent today (IST) to a lead with no consent_marketing_at.
with v as (
  select (select count(distinct a.lead_id) from b2b.allocations a join public.student_leads l on l.id = a.lead_id
           where a.destination_type = 'partner' and a.status in ('queued', 'pushing', 'pushed', 'accepted')
             and l.consent_partner_share_at is null and not coalesce(l.is_test, false)) as shared_without_consent,
         (select count(distinct m.lead_id) from b2c.wa_messages m join public.student_leads l on l.id = m.lead_id
           where m.direction = 'out' and (m.campaign_id is not null or m.journey_run_id is not null or coalesce(m.purpose, '') ~* 'market|campaign')
             and m.status in ('sent', 'delivered', 'read') and m.created_at >= (((now() at time zone 'Asia/Kolkata')::date)::timestamp at time zone 'Asia/Kolkata') and m.created_at < ((((now() at time zone 'Asia/Kolkata')::date + 1)::timestamp) at time zone 'Asia/Kolkata')
             and l.consent_marketing_at is null and not coalesce(l.is_test, false)) as marketed_without_consent)
select shared_without_consent + marketed_without_consent = 0 as ok, to_jsonb(v) as value from v
