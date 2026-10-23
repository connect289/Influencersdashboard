-- Heartbeat checks (spec §6 HB-*, §7). Sources for scripts/db/gen-checks.ts. One check per component, each firing
-- when its one.heartbeats row has had no good reading for expected_interval_s × heartbeat_multiple. A component never
-- seen is reported as never_seen, not as down: before its prober first runs there is nothing to compare, and the app
-- itself is covered by the external watchdog (D-018). P1 for n8n, Spark, the website and vercel:one (spec §6).

-- check: HB-n8n:PKPs7tXg9bej8AgX
-- app: witty
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- disabled: setup:n8n_api
-- title: Heartbeat lost: the Witty n8n workflow
-- description: Latest execution startedAt of the Witty workflow (1-minute timer), written by the app's n8n probe; expected every 60 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'n8n:PKPs7tXg9bej8AgX', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'n8n:PKPs7tXg9bej8AgX'

-- check: HB-n8n:instance
-- app: witty
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- disabled: setup:n8n_api
-- title: Heartbeat lost: the n8n instance
-- description: n8n API /api/v1/workflows answered, written by the app's n8n probe; expected every 300 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'n8n:instance', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'n8n:instance'

-- check: HB-chatwoot
-- app: witty
-- kind: heartbeat
-- severity: P2
-- cadence_s: 60
-- title: Heartbeat lost: Chatwoot
-- description: Chatwoot API inbox list answered (with the incoming message count WITTY-03 reads), written by the app's Chatwoot probe; expected every 300 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'chatwoot', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'chatwoot'

-- check: HB-spark
-- app: b2c
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- title: Heartbeat lost: Spark
-- description: Spark's /api/health, written by the app's health probe; expected every 120 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'spark', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'spark'

-- check: HB-b2b-app
-- app: b2b
-- kind: heartbeat
-- severity: P2
-- cadence_s: 60
-- title: Heartbeat lost: the B2B CRM app
-- description: The B2B CRM host's /api/health, written by the app's health probe; expected every 120 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'b2b-app', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'b2b-app'

-- check: HB-website
-- app: web
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- title: Heartbeat lost: the website
-- description: The website's /api/health, written by the app's health probe; expected every 60 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'website', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'website'

-- check: HB-vercel:website
-- app: web
-- kind: heartbeat
-- severity: P2
-- cadence_s: 300
-- title: Heartbeat lost: the website's Vercel deployment
-- description: Vercel API latest production deployment READY, written by the app's Vercel probe; expected every 600 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'vercel:website', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'vercel:website'

-- check: HB-vercel:one
-- app: one
-- kind: heartbeat
-- severity: P1
-- cadence_s: 300
-- title: Heartbeat lost: Eduwit One's Vercel deployment
-- description: Vercel API latest production deployment of eduwit-one READY, written by the app's Vercel probe; expected every 600 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'vercel:one', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'vercel:one'

-- check: HB-influencer
-- app: influencer
-- kind: heartbeat
-- severity: P2
-- cadence_s: 60
-- title: Heartbeat lost: the influencer portal
-- description: The portal host's /api/health, written by the app's health probe; expected every 120 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'influencer', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'influencer'

-- check: HB-whatsapp:witty
-- app: witty
-- kind: heartbeat
-- severity: P2
-- cadence_s: 300
-- disabled: setup:whatsapp
-- title: Heartbeat lost: Witty's WhatsApp number
-- description: WhatsApp Cloud API phone number status and quality rating, written by the app's WhatsApp probe; expected every 900 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'whatsapp:witty', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'whatsapp:witty'

-- check: HB-whatsapp:b2c
-- app: b2c
-- kind: heartbeat
-- severity: P2
-- cadence_s: 300
-- disabled: setup:whatsapp
-- title: Heartbeat lost: Spark's WhatsApp number
-- description: WhatsApp Cloud API phone number status and quality rating, written by the app's WhatsApp probe; expected every 900 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'whatsapp:b2c', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'whatsapp:b2c'

-- check: HB-gemini
-- app: witty
-- kind: heartbeat
-- severity: P2
-- cadence_s: 300
-- disabled: setup:n8n_api
-- title: Heartbeat lost: Gemini (Witty's model)
-- description: The last successful n8n execution that called Gemini, written by the app's n8n probe; expected every 900 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'gemini', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'gemini'

-- check: HB-meta
-- app: b2b
-- kind: heartbeat
-- severity: P2
-- cadence_s: 900
-- disabled: setup:meta
-- title: Heartbeat lost: Meta lead intake
-- description: The last b2b.intake_requests fetched successfully or a Graph API ping, written by the app's Meta probe; expected every 3600 s.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'meta', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'meta'

-- check: HB-one:tick
-- app: one
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- title: Heartbeat lost: Eduwit One's minute tick
-- description: Written first thing by one.tick(). If the tick stops this check stops too, so the external watchdog reads the same row (D-018); this check catches a tick that runs but skips its heartbeat.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'one:tick', 'last_ok_at', h.last_ok_at, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'one:tick'

-- check: HB-one:app
-- app: one
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- title: Heartbeat lost: the Eduwit One app
-- description: The app's answer to the tick's job call (/api/internal/tick), which writes this row; expected every 60 s once the app is deployed and app.base_url is set.
select coalesce(h.last_ok_at > now() - make_interval(secs => (h.expected_interval_s * one.threshold('heartbeat_multiple'))::int), true) as ok,
       jsonb_build_object('component', 'one:app', 'last_ok_at', h.last_ok_at, 'last_error', h.last_error, 'never_seen', h.component is null) as value
  from (select 1) x left join one.heartbeats h on h.component = 'one:app'
