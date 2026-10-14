-- B2C CRM b24 (Phase 3): what the Phase 3 screens need from the database.
--   ai prices            the per-million-token prices b22 seeded were wrong; corrected only if nobody has edited the setting
--   ai_call_attach()     the app records the query spec and the SQL of an Ask after the call is logged (service only)
--   money_universities()  the university list for the Money page, with each one's current rate, billing and fallback
--   money_rules()         the counsellor overrides and university fallbacks in force, for the commission tab
--   guide articles       Money, Analytics, Team and the Brief, for Admin, Marketing and Sales

insert into b2c.settings as s (key, value) values
  ('ai', '{"model": "claude-sonnet-5-5", "daily_cap_inr": 500, "usd_inr": 85, "insights_hour_ist": 7,
           "price_usd_per_mtok": {"claude-sonnet-5-5": {"in": 2, "out": 10}, "claude-opus-5-5": {"in": 4, "out": 20},
                                  "claude-haiku-5-5": {"in": 0.1, "out": 0.5}, "claude-haiku-4-5": {"in": 1, "out": 5}}}')
on conflict (key) do update set value = jsonb_set(s.value, '{price_usd_per_mtok}', excluded.value -> 'price_usd_per_mtok'), updated_at = now()
 where s.version = 1 and s.actor_id is null;

create or replace function b2c.ai_call_attach(p_id bigint, p_spec jsonb, p_sql jsonb) returns void language plpgsql security definer set search_path = '' as $f$
begin
  update b2c.ai_calls set spec = p_spec, sql = p_sql where id = p_id;
end $f$;
revoke execute on function b2c.ai_call_attach(bigint, jsonb, jsonb) from public, anon, authenticated;
grant execute on function b2c.ai_call_attach(bigint, jsonb, jsonb) to service_role;

create or replace function b2c.money_universities() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.can('read_money') then raise exception 'not allowed'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', un.id, 'name', un.name,
            'programmes', (select count(*) from public.catalog_programs cp where cp.university_id = un.id and cp.active),
            'rate', (select jsonb_build_object('rate_type', r.rate_type, 'value', r.value, 'tiers', r.tiers, 'valid_from', r.valid_from)
                       from b2c.university_rates r where r.university_id = un.id and r.programme_id is null and r.retired_at is null
                        and r.valid_from <= current_date and (r.valid_to is null or r.valid_to >= current_date) order by r.valid_from desc limit 1),
            'programme_rates', (select count(*) from b2c.university_rates r where r.university_id = un.id and r.programme_id is not null and r.retired_at is null),
            'billing', exists (select 1 from b2c.university_billing b where b.university_id = un.id and b.gstin is not null),
            'fallback', (select to_jsonb(f) - 'set_by' from b2c.commission_fallbacks f where f.university_id = un.id),
            'enrollments', (select count(*) from b2c.enrollments e where e.university_id = un.id and e.status in ('reported', 'verified')))
          order by un.name), '[]')
     from public.catalog_universities un);
end $f$;

create or replace function b2c.money_rules() returns jsonb language plpgsql stable security definer set search_path = '' as $f$
begin
  if not b2c.can('read_money') then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'overrides', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'counsellor_id', o.counsellor_id, 'counsellor', u.full_name, 'programme_id', o.programme_id,
                     'programme', coalesce(cp.program_name, cp.course) || coalesce(' · ' || un.name, ''), 'rate_type', o.rate_type, 'fee_base', o.fee_base, 'value', o.value,
                     'valid_from', o.valid_from, 'valid_to', o.valid_to, 'reason', o.reason, 'created_at', o.created_at) order by o.created_at desc), '[]')
                    from b2c.commission_overrides o left join b2c.users u on u.user_id = o.counsellor_id
                    left join public.catalog_programs cp on cp.id = o.programme_id left join public.catalog_universities un on un.id = cp.university_id
                   where o.retired_at is null),
    'fallbacks', (select coalesce(jsonb_agg(jsonb_build_object('university_id', f.university_id, 'university', un.name, 'rate_type', f.rate_type, 'fee_base', f.fee_base,
                     'value', f.value, 'reason', f.reason, 'set_at', f.set_at) order by un.name), '[]')
                    from b2c.commission_fallbacks f left join public.catalog_universities un on un.id = f.university_id),
    'counsellors', (select coalesce(jsonb_agg(jsonb_build_object('user_id', u.user_id, 'name', u.full_name) order by u.full_name), '[]')
                      from b2c.users u where u.is_active and u.role in ('counsellor', 'sales_head', 'admin')));
end $f$;
grant execute on function b2c.money_universities(), b2c.money_rules() to authenticated;
revoke execute on function b2c.money_universities(), b2c.money_rules() from public, anon;

insert into b2c.user_guides as g (role, slug, section, title, body, screens, sort) values
('admin', 'money', 'Money', 'University commission and invoices', $t$**Money** has the university side and the counsellor side. The CRM moves no money: it books what is owed, raises invoices and records what came in.

- **Rates**: one rate per university (or per programme), percent of the first-year fee, a fixed amount or tiers, each valid from a date. A changed rate never touches what was booked before.
- Each reported enrolment linked to the catalogue books commission at the rate on its enrolment date; a refund inside the refund window reverses it. **Enrolments** lists those not yet linked.
- **Close a period** to settle tiers: the tier is picked on the period's numbers and the difference is booked as one adjustment.
- **Invoices**: draft from everything booked and not yet invoiced, check, then **Approve** (the number is given then, with no gaps). Cancelling raises a credit note.
- **Receipts**: record each payment and its TDS; it settles the matching invoice first, then the oldest.
- **Statements**: upload a university's CSV to see four piles: matched, amount differs, theirs only, ours only.

Rates, GST, SAC and the refund window are set under Settings → money and should be confirmed by your CA.$t$, '{/w/money}', 110),
('admin', 'commission', 'Money', 'Counsellor commission', $t$A counsellor earns the **highest rate any active partner pays** for the programme, worked out when the enrolment is booked. Each line keeps the programme, every partner considered and the rate, so it can be checked later.

- **Needs a rate**: no partner rate and no fallback. Set a fallback for the university or programme and the lines rebook.
- **Overrides** set a rate for one counsellor or one programme for a time.
- A line is **provisional** until the refund window passes, then **confirmed**, then **due**.
- On the run day a **run** is prepared with every due line. Check it (hold back any line you doubt), then **Approve** it once paid: its lines become **settled** and each counsellor gets a statement. The finance CSV has one row per counsellor.
- A refund after settlement books a **clawback** against the next run.$t$, '{/w/money}', 115),
('admin', 'analytics', 'Analytics', 'Dashboards and Ask', $t$**Analytics** has the standard dashboards for each role and any you build. Every number opens the leads behind it.

- **Edit** a dashboard to add widgets: a metric, how to split it, the period and the chart. As Admin, editing a standard dashboard changes it for everyone in its roles; **Copy** makes your own. **Publish** makes one of yours the standard for a role.
- Filters at the top apply to every widget.
- **Ask** answers a question in plain words: Claude picks the metrics and the split from the catalogue, the CRM runs the query with your access, and you see the query it ran.
- **Schedules** email a dashboard as a PDF or CSV; **alerts** tell you when a number crosses a line or moves unusually.
- **Insights** each morning point out what changed.

Claude never sees a phone number or an email. Every call is logged with its cost under a daily cap (Settings → ai).$t$, '{/w/analytics,/w/analytics/*}', 120),
('admin', 'team', 'Team', 'Targets and performance', $t$**Team performance** shows each counsellor's month against target (the marker shows where they should be by today), the activity monitor (calls, connected, WhatsApp and email sent, median first contact, SLA breaches, overdue tasks, untouched leads, unlogged calls) and capacity (leads assigned this month against the cap).

Set targets per counsellor per month: enrolments, applications, counselled, connected calls, calls and commission. The sales head sets targets for counsellors under **My team**. The leaderboard shows only the names of counsellors who chose to appear on it.$t$, '{/w/team}', 125),
('marketing', 'analytics', 'Analytics', 'Dashboards and Ask', $t$**Analytics** has your dashboards (nurture, campaigns and journeys, deliverability, segments, lead sources) and any you build. Every number opens the leads behind it.

**Ask** answers a question in plain words from the metric catalogue, with your access: you see the query it ran. **Schedules** email a dashboard; **alerts** watch a number for you. You can read the money dashboards but not change rates or invoices.$t$, '{/w/analytics,/w/analytics/*}', 110),
('sales', 'money', 'Money', 'My commission', $t$**My money** shows what you have earned this month and what is due, line by line: the student, the programme, the partners considered and the rate.

- **Provisional** lines wait for the refund window; **due** lines go in the next run; **settled** lines were paid.
- A refund before payment voids the line; after payment it is taken back from the next run.
- Download each approved run's **statement** as a PDF.

A question about a line? Ask your Admin, who can see how the rate was found.$t$, '{/s/money}', 110),
('sales', 'analytics', 'Analytics', 'My numbers', $t$**Analytics** shows your funnel, follow-ups, activity, money and week (the sales head sees the team's). Every number opens the leads behind it.

**Ask** answers a question about your own leads in plain words. It only ever sees your leads, never another counsellor's, and never a phone number or an email.$t$, '{/s/analytics,/s/analytics/*}', 120),
('sales', 'brief', 'Calling', 'Brief before you call', $t$Before a call, the lead screen shows a **brief**: three to five lines on who the student is, what they want, what Witty and earlier calls found, and where they are. Each line names where it came from: a field of the lead, a Witty message, an activity or the partner's history.

The brief is written by Claude from the lead's fields, Witty chat and activity, with phone numbers and email addresses removed first (only the first name is kept). It refreshes when something important changes, or press **Refresh**. Check anything that matters before you rely on it.$t$, '{/s/leads/*}', 25),
('sales', 'targets', 'Team', 'Targets and the leaderboard', $t$**Today** shows your progress against this month's target. The leaderboard shows the team's standing; your name appears only if you turn on **Show my name** there. Others see you as "A counsellor" otherwise.$t$, '{/s}', 130)
on conflict (role, slug) do update set title = excluded.title, body = excluded.body, screens = excluded.screens, updated_at = now()
 where g.updated_by is null and g.version = 1;
