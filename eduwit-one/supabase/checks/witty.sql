-- Witty checks (spec §6, WITTY-*). Sources for scripts/db/gen-checks.ts. Phones never leave these queries: values
-- carry counts and row ids only.

-- check: WITTY-01
-- app: witty
-- kind: rpc
-- severity: P2
-- cadence_s: 60
-- fix: FIX-OUTBOX-W2
-- search_path: public
-- title: Witty's own health alerts are firing
-- description: public.w2_health_alerts() returned rows; P1 when outbox_failed or send_failed_last_hour is among them, P2 otherwise. The function names its tables without a schema, so this check runs with search_path public (D-042). Each alert kind is a subject. The second fix, FIX-CACHE-W2, attaches to cache_expired.
select jsonb_array_length(a) = 0 as ok,
       jsonb_build_object('alerts', a, 'severity', case when exists (select 1 from jsonb_array_elements(a) e
                           where e ->> 'alert' in ('outbox_failed', 'send_failed_last_hour')) then 'P1' else 'P2' end,
                          'subjects', (select coalesce(jsonb_agg(distinct e ->> 'alert'), '[]') from jsonb_array_elements(a) e)) as value
  from (select coalesce(public.w2_health_alerts(), '[]'::jsonb) as a) x

-- check: WITTY-02
-- app: witty
-- kind: http
-- severity: P1
-- cadence_s: 60
-- fix: FIX-N8N-RETRY
-- disabled: setup:n8n_api
-- title: The Witty n8n workflow is inactive, silent or erroring
-- description: n8n API: workflow PKPs7tXg9bej8AgX (id from one.settings.n8n) not active, no execution in 5 min, or an execution with status error or crashed in the last 15 min. Run by the app's n8n probe.

-- check: WITTY-03
-- app: witty
-- kind: sql
-- severity: P1
-- cadence_s: 900
-- title: Witty's inbox is silent while Chatwoot is receiving messages
-- description: Between 09:00 and 22:00 IST, no new w2_inbox row for witty_silence_h hours while the Chatwoot probe (heartbeat chatwoot, detail.incoming_recent) saw incoming messages in that window. Without a fresh Chatwoot reading, inbox silence alone fires (spec §15 fallback). Silence is counted from 09:00 IST at the earliest, so a quiet night does not page at 09:00 (m10 of the second review).
with w as (
  select (now() at time zone 'Asia/Kolkata')::time between time '09:00' and time '22:00' as in_hours,
         (select max(received_at) from public.w2_inbox) as last_inbox,
         greatest((select max(received_at) from public.w2_inbox),
                  (date_trunc('day', now() at time zone 'Asia/Kolkata') + time '09:00') at time zone 'Asia/Kolkata') as quiet_since,
         (select h.detail from one.heartbeats h where h.component = 'chatwoot' and h.last_ok_at > now() - interval '20 minutes') as cw)
select not (in_hours and quiet_since < now() - make_interval(hours => (select one.threshold('witty_silence_h'))::int)
            and (cw is null or coalesce((cw ->> 'incoming_recent')::int, 0) > 0)) as ok,
       jsonb_build_object('in_hours', in_hours, 'last_inbox_at', last_inbox, 'chatwoot_incoming_recent', cw -> 'incoming_recent',
                          'chatwoot_reading', cw is not null) as value
  from w

-- check: WITTY-04
-- app: witty
-- kind: sql
-- severity: P2
-- cadence_s: 900
-- title: Witty's reply latency p95 is over budget
-- description: p95 of w2_messages.latency_ms for outgoing replies in the last 15 min above witty_p95_ms, with at least 10 replies.
select count(*) < 10 or percentile_cont(0.95) within group (order by latency_ms) <= (select one.threshold('witty_p95_ms')) as ok,
       jsonb_build_object('replies', count(*), 'p95_ms', round(percentile_cont(0.95) within group (order by latency_ms)::numeric)) as value
  from public.w2_messages
 where direction = 'out' and kind = 'reply' and latency_ms is not null and created_at > now() - interval '15 minutes'

-- check: WITTY-05
-- app: witty
-- kind: http
-- severity: P2
-- cadence_s: 300
-- title: An escalated, paused conversation has no Chatwoot handoff label
-- description: w2_conversations with bot_paused and escalated_at set (read through one.witty_escalations()) whose Chatwoot conversation lacks the witty-handoff label. Run by the app's Chatwoot probe.

-- check: WITTY-06
-- app: witty
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: Witty nurture sent outside hours or too often
-- description: A sent w2_nurture_log row in the last 24 h outside 09:00 to 20:00 IST, or a phone with more than 6 sent nurture messages in 30 days.
with sent as (select phone, created_at from public.w2_nurture_log where status = 'sent' and created_at > now() - interval '30 days'),
v as (
  select (select count(*) from sent where created_at > now() - interval '24 hours'
            and (created_at at time zone 'Asia/Kolkata')::time not between time '09:00' and time '20:00') as off_hours_24h,
         (select count(*) from (select phone from sent group by phone having count(*) > 6) p) as phones_over_6)
select off_hours_24h = 0 and phones_over_6 = 0 as ok, jsonb_build_object('off_hours_24h', off_hours_24h, 'phones_over_6_in_30d', phones_over_6) as value
  from v

-- check: WITTY-07
-- app: witty
-- kind: sql
-- severity: P2
-- cadence_s: 3600
-- title: A Witty learning was applied without a decision
-- description: w2_learnings with status applied, decided_by null and auto false: a prompt or rule change nobody approved.
select count(*) = 0 as ok, jsonb_build_object('count', count(*), 'ids', coalesce(to_jsonb((array_agg(id order by id) filter (where id is not null))[1:20]), '[]')) as value
  from public.w2_learnings where status = 'applied' and decided_by is null and not coalesce(auto, false)

-- check: WITTY-08
-- app: witty
-- kind: http
-- severity: P2
-- cadence_s: 3600
-- disabled: setup:n8n_api
-- title: Nurture Worker or Learning Loop workflow is inactive while expected
-- description: n8n API: the nurture or learning workflow (ids in one.settings.n8n) is inactive while one.settings.witty.expect_nurture or expect_learning is true.

-- check: WITTY-09
-- app: witty
-- kind: http
-- severity: P2
-- cadence_s: 3600
-- disabled: setup:n8n_api
-- title: Witty's Gemini spend is over cap or hitting quota
-- description: Gemini spend today (tokens from n8n execution data priced from one.settings.ai) above one.settings.witty.gemini_daily_cap, or quota errors in the last hour's n8n executions.
