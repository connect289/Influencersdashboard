-- Heartbeat checks (spec §6 HB-*, §7). Sources for scripts/db/gen-checks.ts. One check per component; the verdict is
-- one.heartbeat_state(): no good reading for expected_interval_s × heartbeat_multiple is down, and so is a component
-- read but never once ok (D-050). A component never written is ok only until it is expected: one:app once app.base_url
-- is set, the app's probes once the app has answered a tick, each after heartbeat_never_seen_grace_min (M2 of the
-- second review, D-056). P1 for n8n, Spark, the website and vercel:one (spec §6).

-- check: HB-n8n:PKPs7tXg9bej8AgX
-- app: witty
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- disabled: setup:n8n_api
-- title: Heartbeat lost: the Witty n8n workflow
-- description: Latest execution startedAt of the Witty workflow (1-minute timer), written by the app's n8n probe; expected every 60 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('n8n:PKPs7tXg9bej8AgX') as s) x

-- check: HB-n8n:instance
-- app: witty
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- disabled: setup:n8n_api
-- title: Heartbeat lost: the n8n instance
-- description: n8n API /api/v1/workflows answered, written by the app's n8n probe; expected every 300 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('n8n:instance') as s) x

-- check: HB-chatwoot
-- app: witty
-- kind: heartbeat
-- severity: P2
-- cadence_s: 60
-- title: Heartbeat lost: Chatwoot
-- description: Chatwoot API inbox list answered (with the incoming message count WITTY-03 reads), written by the app's Chatwoot probe; expected every 300 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('chatwoot') as s) x

-- check: HB-spark
-- app: b2c
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- title: Heartbeat lost: Spark
-- description: Spark's /api/health, written by the app's health probe; expected every 120 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('spark') as s) x

-- check: HB-b2b-app
-- app: b2b
-- kind: heartbeat
-- severity: P2
-- cadence_s: 60
-- title: Heartbeat lost: the B2B CRM app
-- description: The B2B CRM host's /api/health, written by the app's health probe; expected every 120 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('b2b-app') as s) x

-- check: HB-website
-- app: web
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- title: Heartbeat lost: the website
-- description: The website's /api/health, written by the app's health probe; expected every 60 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('website') as s) x

-- check: HB-vercel:website
-- app: web
-- kind: heartbeat
-- severity: P2
-- cadence_s: 300
-- title: Heartbeat lost: the website's Vercel deployment
-- description: Vercel API latest production deployment READY, written by the app's Vercel probe; expected every 600 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('vercel:website') as s) x

-- check: HB-vercel:one
-- app: one
-- kind: heartbeat
-- severity: P1
-- cadence_s: 300
-- title: Heartbeat lost: Eduwit One's Vercel deployment
-- description: Vercel API latest production deployment of eduwit-one READY, written by the app's Vercel probe; expected every 600 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('vercel:one') as s) x

-- check: HB-influencer
-- app: influencer
-- kind: heartbeat
-- severity: P2
-- cadence_s: 60
-- title: Heartbeat lost: the influencer portal
-- description: The portal host's /api/health, written by the app's health probe; expected every 120 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('influencer') as s) x

-- check: HB-whatsapp:witty
-- app: witty
-- kind: heartbeat
-- severity: P2
-- cadence_s: 300
-- disabled: setup:whatsapp
-- title: Heartbeat lost: Witty's WhatsApp number
-- description: WhatsApp Cloud API phone number status and quality rating, written by the app's WhatsApp probe; expected every 900 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('whatsapp:witty') as s) x

-- check: HB-whatsapp:b2c
-- app: b2c
-- kind: heartbeat
-- severity: P2
-- cadence_s: 300
-- disabled: setup:whatsapp
-- title: Heartbeat lost: Spark's WhatsApp number
-- description: WhatsApp Cloud API phone number status and quality rating, written by the app's WhatsApp probe; expected every 900 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('whatsapp:b2c') as s) x

-- check: HB-gemini
-- app: witty
-- kind: heartbeat
-- severity: P2
-- cadence_s: 300
-- disabled: setup:n8n_api
-- title: Heartbeat lost: Gemini (Witty's model)
-- description: The last successful n8n execution that called Gemini, written by the app's n8n probe; expected every 900 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('gemini') as s) x

-- check: HB-meta
-- app: b2b
-- kind: heartbeat
-- severity: P2
-- cadence_s: 900
-- disabled: setup:meta
-- title: Heartbeat lost: Meta lead intake
-- description: The last b2b.intake_requests fetched successfully or a Graph API ping, written by the app's Meta probe; expected every 3600 s.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('meta') as s) x

-- check: HB-one:tick
-- app: one
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- title: Heartbeat lost: Eduwit One's minute tick
-- description: Written first thing by one.tick(). If the tick stops this check stops too, so the external watchdog reads the same row (D-018); this check catches a tick that runs but skips its heartbeat.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('one:tick') as s) x

-- check: HB-one:app
-- app: one
-- kind: heartbeat
-- severity: P1
-- cadence_s: 60
-- title: Heartbeat lost: the Eduwit One app
-- description: The app's answer to the tick's job call (/api/internal/tick), which writes this row; expected every 60 s once the app is deployed and app.base_url is set.
select (s ->> 'ok')::boolean as ok, s as value from (select one.heartbeat_state('one:app') as s) x
