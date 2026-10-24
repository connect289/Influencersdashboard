// What it takes to set up and run each app, as seen from Eduwit One (the Operate page, /apps/<app>/operate, and the
// AI's runbook tool). Reads only: every step either happens in the app itself (a deep link) or on Settings → Setup;
// the only writes Eduwit One makes into an app are the catalogue's fixes (spec §8, D-079). The ids named here (Setup
// items, checks, fixes, tests, cron jobs, hosts) are checked against the catalogues by operate.test.ts, so a renamed
// check cannot leave a dangling step.

export type OperateApp = {
  key: string;
  /** Setup items this app needs before Eduwit One watches it fully, in the order to fill them. */
  needs: string[];
  /** Hosts (Settings → hosts) this app answers at. */
  hosts: string[];
  /** Prefixes of the app's own pg_cron jobs; empty when the app has none in this database. */
  cronPrefixes: string[];
  /** Vault names (Settings → Setup) that belong to this app's access; the runbook says how to rotate each. */
  secrets: string[];
  /** The fixes of spec §8 that act on this app. */
  fixes: string[];
  /** The synthetic tests that exercise it. */
  tests: string[];
  /** Once, in order: what has to exist for the app to run and for Eduwit One to watch it. */
  firstTime: Step[];
  /** Every day: where to look, in order. */
  daily: string[];
  /** When a check fires: the first place to look, per check (the rest is on the incident page). */
  whenFires: Array<{ check: string; look: string }>;
  /** What stays in the app itself (Eduwit One links to it and never does it). */
  inTheApp: string[];
};

export type Step = {
  title: string;
  detail: string;
  setup?: string;
  link?: "admin" | "setup" | "checks" | "tests" | "fixes";
};

export const OPERATE: Record<string, OperateApp> = {
  witty: {
    key: "witty",
    needs: ["n8n_api", "chatwoot", "whatsapp", "lightsail", "test_rows_agreement", "test_whatsapp_number"],
    hosts: ["n8n", "chatwoot"],
    cronPrefixes: [],
    secrets: ["one_n8n_key", "one_chatwoot_token", "one_whatsapp_token", "one_test_wa_token"],
    fixes: ["FIX-N8N-RETRY", "FIX-OUTBOX-W2", "FIX-CACHE-W2"],
    tests: ["T-WITTY-TURN", "T-WITTY-QUALIFY"],
    firstTime: [
      {
        title: "The n8n workflow runs every minute",
        detail:
          "Witty is the n8n workflow set in Settings → n8n (witty_workflow_id), on the Lightsail server. It must be active with its 1-minute timer; its Cache Manager renews the Gemini prompt caches every 10 and 15 minutes by itself.",
        link: "admin",
      },
      {
        title: "Give Eduwit One an n8n API key",
        detail:
          "n8n → Settings → n8n API → create a key; paste it as Setup item n8n_api and validate. That switches on WITTY-02, WITTY-08, the n8n heartbeats, FIX-N8N-RETRY and T-WITTY-QUALIFY.",
        setup: "n8n_api",
      },
      {
        title: "Give it a Chatwoot token",
        detail:
          "Chatwoot → profile → access token of the user Eduwit One reads as; Setup item chatwoot. Switches on WITTY-03, WITTY-05, the Chatwoot heartbeat and T-WITTY-TURN.",
        setup: "chatwoot",
      },
      {
        title: "WhatsApp quality and templates",
        detail:
          "A Meta system-user token with whatsapp_business_management (Setup item whatsapp) adds the whatsapp:witty heartbeat and the template and quality parts of B2C-06.",
        setup: "whatsapp",
      },
      {
        title: "The test number",
        detail:
          "Add the real test phone to w2_trusted with is_test = true (Setup item test_whatsapp_number); T-WITTY-TURN sends it one message a day. WhatsApp's 24-hour window applies: if the test has not run for a day, send one message to the test number from Witty's side first.",
        setup: "test_whatsapp_number",
      },
    ],
    daily: [
      "Overview: the Witty tile is green and its heartbeats (n8n workflow, n8n instance, Chatwoot, Gemini) are fresh.",
      "Apps → Witty → Health alerts and Last 24 hours: Witty's own views (w2_health_alerts, w2_health_digest).",
      "Apps → Witty → Outbox: failed rows mean messages to the CRMs did not go; FIX-OUTBOX-W2 lists them and proposes.",
      "Apps → Witty → Learnings waiting: approve or reject in Witty's own admin.",
    ],
    whenFires: [
      {
        check: "WITTY-02",
        look: "n8n → the Witty workflow's executions: the latest should have started within 2 minutes; an inactive flag or executions in error. FIX-N8N-RETRY retries each failed execution once when switched on.",
      },
      {
        check: "WITTY-01",
        look: "w2_health_alerts(): failed outbox rows or expired prompt caches. Caches that stay expired mean the Cache Manager (Gemini) is failing: look at its executions.",
      },
      {
        check: "WITTY-03",
        look: "Chatwoot → the inbox: incoming messages with no reply. Is the n8n workflow running and Chatwoot's webhook to it alive?",
      },
      {
        check: "WITTY-08",
        look: "n8n → the nurture and learning workflows: one is inactive while Settings → witty expects it.",
      },
    ],
    inTheApp: [
      "Editing prompts, approving learnings and blocking numbers: Witty's admin.",
      "Starting or stopping a workflow, re-running the Cache Manager: n8n.",
      "Replying to a student: Chatwoot.",
    ],
  },
  b2b: {
    key: "b2b",
    needs: ["b2b_app", "meta", "test_rows_agreement", "test_b2b_intake_key", "test_runner_user", "test_partner"],
    hosts: ["b2b_app"],
    cronPrefixes: ["b2b-"],
    secrets: [
      "one_b2b_read_key",
      "one_b2b_intake_key",
      "one_test_partner_secret",
      "one_meta_token",
      "one_test_runner_password",
      "one_test_runner_totp",
    ],
    fixes: ["FIX-OUTBOX-B2B", "FIX-CURSOR-B2C", "FIX-WEBHOOK-REKICK"],
    tests: ["T-B2B-INTAKE", "T-B2B-PUSH", "T-HANDOFF"],
    firstTime: [
      {
        title: "The B2B CRM's own timers run",
        detail:
          "Its b2b-* pg_cron jobs (intake, outbox, allocation, money, ML, sync to Spark) are listed below with their last run; PLAT-01 and PLAT-02 fail when one fails or goes silent.",
        link: "checks",
      },
      {
        title: "A referrals-only API key for Eduwit One",
        detail:
          "B2B CRM → Settings → API keys: a key with the referrals scope only (D-017); Setup item b2b_app. It gives the b2b-app heartbeat and the deep links.",
        setup: "b2b_app",
      },
      {
        title: "Your own B2B admin session",
        detail:
          "Approving FIX-OUTBOX-B2B runs B2B's b2b.outbox_retry under your session: sign in to Eduwit One with Google or two-factor (aal2), as a B2B admin, or B2B refuses each row (D-082).",
        link: "fixes",
      },
      {
        title: "The tests' identities",
        detail:
          "An intake-only key (test_b2b_intake_key), the test runner user as a B2B admin with two-factor (test_runner_user) and a test partner with the sandbox adapter and a test endpoint (test_partner). Each test switches on by itself when its items are validated.",
        setup: "test_runner_user",
      },
      {
        title: "Meta Ads (optional)",
        detail: "An ad-account read token (Setup item meta) adds the Marketing spend tiles and the meta heartbeat.",
        setup: "meta",
      },
    ],
    daily: [
      "Overview: no open P1 on the B2B tile; the b2b-app heartbeat is fresh.",
      "Apps → B2B CRM → Health check: b2b.health_check() with its deliveries and the B2C sync cursor (B2B-01 reads the same).",
      "Apps → B2B CRM → Command centre and Alert feed: the CRM's own view of allocation, money and partners.",
      "Proposals: an open FIX-OUTBOX-B2B proposal lists dead deliveries to Spark; approve it to send them again.",
    ],
    whenFires: [
      {
        check: "B2B-01",
        look: "b2b.health_check(): a stale or failed b2b-* job, dead or waiting deliveries to Spark (FIX-OUTBOX-B2B proposes), or the sync cursor over 600 s (FIX-CURSOR-B2C runs the sync once).",
      },
      {
        check: "B2B-06",
        look: "Deliveries to Spark failing: is Spark up (spark heartbeat, PLAT-05)? FIX-WEBHOOK-REKICK kicks the outbox once Spark's /v1/handoffs answers.",
      },
      {
        check: "B2B-04",
        look: "A sales-ready lead with no allocation: the CRM's allocation screen; Eduwit One never allocates.",
      },
      { check: "B2B-11", look: "An ml.model_failed event: the ML tick's last error in the alert feed." },
    ],
    inTheApp: [
      "Allocation, money, partner mappings, live switches and settings: always the B2B CRM itself (spec §8 forbids Eduwit One).",
      "Setting a delivery back to dead after a resend: the CRM's delivery screen.",
    ],
  },
  b2c: {
    key: "b2c",
    needs: [
      "spark_job_key",
      "whatsapp",
      "test_rows_agreement",
      "test_runner_user",
      "test_spark_user",
      "test_spark_journey",
      "test_b2b_intake_key",
    ],
    hosts: ["spark"],
    cronPrefixes: ["b2c-"],
    secrets: ["one_whatsapp_token", "one_test_runner_password", "one_test_runner_totp"],
    fixes: ["FIX-INBOX-RETRY", "FIX-OUTBOX-B2C", "FIX-CACHE-B2C"],
    tests: ["T-B2C-NURTURE"],
    firstTime: [
      {
        title: "Spark's base URL and internal key",
        detail:
          "Until Spark's deploy is registered in its own settings (b2c.app_deploy_set(base_url, key) by a Spark admin), its six HTTP jobs are no-ops and PLAT-05 fails. Eduwit One only reads that the values exist (Setup item spark_job_key).",
        setup: "spark_job_key",
      },
      {
        title: "Spark's timers run",
        detail:
          "The b2c-* pg_cron jobs (minute, jobs, sync batch and urgent, nurture, programme cache, nightly) are listed below; b2c-capacity has failed on production since 22 Oct (B2C-10).",
        link: "checks",
      },
      {
        title: "WhatsApp templates and quality",
        detail: "Setup item whatsapp adds the whatsapp:b2c heartbeat and the template and quality parts of B2C-06.",
        setup: "whatsapp",
      },
      {
        title: "The tests' identities",
        detail:
          "A Spark counsellor marked as a test user (test_spark_user), the test runner user as a Spark admin with is_test_user (test_runner_user) and a journey in test mode whose first step queues a WhatsApp message (test_spark_journey). T-B2C-NURTURE then switches on.",
        setup: "test_spark_journey",
      },
    ],
    daily: [
      "Overview: the Spark tile and the spark heartbeat.",
      "Apps → Spark → Timers and Queues: every b2c-* job ran recently; inbox, outbox and send queue hold nothing in error or stuck.",
      "Apps → Spark → Counsellors: leads, contacts and SLA per counsellor (fact_leads, test rows left out).",
    ],
    whenFires: [
      {
        check: "B2C-02",
        look: "Inbox rows in error: Spark's system health page. FIX-INBOX-RETRY applies up to 50 envelopes again, as Spark's own retry would.",
      },
      { check: "B2C-03", look: "Outbox rows stuck sending: FIX-OUTBOX-B2C unsticks them and runs the urgent sync." },
      {
        check: "B2C-10",
        look: "A failed b2c-* job: its last message is in the incident's evidence (b2c-capacity: 'cannot extract elements from a scalar' in b2c.capacity_tick()).",
      },
      { check: "CAT-01", look: "Spark's programme cache is stale: FIX-CACHE-B2C refreshes it with force." },
    ],
    inTheApp: [
      "Support tickets, campaigns and journeys: Spark itself (no read function for Eduwit One).",
      "Registering a deploy and rotating b2c_internal_key: a Spark admin, in Spark.",
    ],
  },
  web: {
    key: "web",
    needs: ["website_health", "vercel", "test_rows_agreement", "test_mailbox", "test_preview_url"],
    hosts: ["website", "website_internal"],
    cronPrefixes: [],
    secrets: ["one_vercel_token", "one_test_mailbox_key"],
    fixes: ["FIX-OUTBOX-WEB", "FIX-CATALOG-POLL"],
    tests: ["T-WEB-ENQUIRY", "T-WEB-CATALOG", "T-WEB-ADVISOR"],
    firstTime: [
      {
        title: "The website answers /api/health",
        detail:
          "eduwit.in on Vercel; its health answers {ok: true} (WEB-02, the website heartbeat; Setup item website_health is verified once it does).",
        setup: "website_health",
      },
      {
        title: "A Vercel read token",
        detail:
          "Vercel → Account settings → Tokens, read scope for the eduwit team (Setup item vercel): WEB-07 watches failed deployments and the vercel:website and vercel:one heartbeats.",
        setup: "vercel",
      },
      {
        title: "Deploys from main",
        detail:
          "The website deploys from a branch, not main (D-003): merge it or record the branch as the source of truth (Setup item github).",
        link: "setup",
      },
      {
        title: "The website tests wait for the website",
        detail:
          "T-WEB-ENQUIRY, T-WEB-ADVISOR and T-WEB-CATALOG need a test mailbox, a preview URL and the website changes their proposals ask for (D-071).",
        setup: "test_preview_url",
      },
    ],
    daily: [
      "Overview: the Website tile, the website and vercel:website heartbeats.",
      "Apps → Website → Health and Admin overview: web_health() and the outbox, the catalogue poll age and the hidden programmes.",
      "Apps → Website → Data quality: what the catalogue hides and why (CAT-04: programmes with no fee).",
    ],
    whenFires: [
      {
        check: "WEB-01",
        look: "Dead outbox rows or a stale catalogue poll: FIX-OUTBOX-WEB sends dead rows again and runs the worker; FIX-CATALOG-POLL runs the poll. Otherwise /admin.",
      },
      { check: "WEB-02", look: "/api/health not ok: Vercel's deployment logs for the website." },
      { check: "WEB-07", look: "A failed Vercel deployment: Vercel → eduwit-website → Deployments." },
      {
        check: "CAT-02",
        look: "A catalogue change not yet polled by the website: FIX-CATALOG-POLL, else the website's /admin.",
      },
    ],
    inTheApp: [
      "Retrying the outbox by hand and forcing a poll: the website's /admin (the fixes do the same when switched on).",
    ],
  },
  influencer: {
    key: "influencer",
    needs: ["influencer_portal", "test_rows_agreement", "test_creator", "n8n_api"],
    hosts: ["influencer"],
    cronPrefixes: ["inf-", "influencer_"],
    secrets: [],
    fixes: [],
    tests: ["T-INFLUENCER"],
    firstTime: [
      {
        title: "The portal answers /api/health",
        detail: "influencer.eduwit.in; INF-04 and the influencer heartbeat read it (Setup item influencer_portal).",
        setup: "influencer_portal",
      },
      {
        title: "Its inf-* timers run",
        detail:
          "Eight inf-* pg_cron jobs (jobs, lead sync, analytics, digests, scorecards, nightly) are listed below; INF-01 to INF-03 read inf.health().",
        link: "checks",
      },
      {
        title: "Retire the legacy accounts",
        detail:
          "Three active legacy influencer accounts still read referred leads through the old RLS policy (INF-06, D-019): deactivate them in the portal.",
        link: "checks",
      },
      {
        title: "A test creator",
        detail:
          "Invite a creator marked as a test creator (Setup item test_creator); T-INFLUENCER waits for the portal change its proposal asks for (D-071).",
        setup: "test_creator",
      },
    ],
    daily: [
      "Overview: the Influencer portal tile and heartbeat.",
      "Apps → Influencer portal → Health, Creators and Link clicks: inf.health(), creators by stage, clicks with bots apart.",
    ],
    whenFires: [
      { check: "INF-01", look: "inf.health() not ok: the portal's /admin and its inf-jobs queue." },
      { check: "INF-06", look: "An active legacy influencer account: deactivate it in the portal (D-019)." },
    ],
    inTheApp: ["Creators, contracts, payouts and login attempts: the portal's admin; Eduwit One has no fix for it."],
  },
  one: {
    key: "one",
    needs: [
      "supabase_api_schema",
      "one_app_env",
      "email",
      "alerts_p1_inbox",
      "uptimerobot",
      "watchdog_monitor",
      "ai_key",
      "vercel",
      "alerts_second_contact",
      "developer_contact",
      "brand_assets",
    ],
    hosts: ["one"],
    cronPrefixes: ["one-"],
    secrets: ["one_internal_key", "one_email_key", "one_uptimerobot_key", "one_anthropic_key"],
    fixes: [],
    tests: ["T-ALERT"],
    firstTime: [
      {
        title: "The database part",
        detail:
          "Rehearse every migration on staging, dump production, apply (RUNBOOK-database.md). The first tick after the apply starts the fixes' observation window. Nothing here can be done from the app.",
        link: "setup",
      },
      {
        title: "Expose schema one in the Data API",
        detail:
          "Supabase → Project settings → Data API → exposed schemas: add one (Setup item supabase_api_schema). Until then every page shows 'not exposed'.",
        setup: "supabase_api_schema",
      },
      {
        title: "Deploy the app",
        detail:
          "Vercel Pro, env ONE_SUPABASE_URL, ONE_SUPABASE_ANON_KEY, ONE_SUPABASE_SERVICE_KEY, ONE_INTERNAL_KEY (Setup item one_app_env), and the sign-in callback URL in Supabase Auth. The one:app heartbeat and every HTTP probe follow.",
        setup: "one_app_env",
      },
      {
        title: "Alert email",
        detail:
          "A Resend key (Setup item email) and the P1 inbox (alerts_p1_inbox); validate sends a test email. Then the second contact and the developer address.",
        setup: "email",
      },
      {
        title: "The external watchdog",
        detail:
          "An UptimeRobot keyword monitor on /api/watchdog (Setup item watchdog_monitor) is the only thing that notices Supabase, pg_cron or Vercel being down. Its alert contact must be active.",
        setup: "watchdog_monitor",
      },
      {
        title: "The AI",
        detail:
          "An Anthropic key (Setup item ai_key, Claude only); the daily cap is in Settings → AI. The eval (npm run ai:eval --live) is the contract test.",
        setup: "ai_key",
      },
    ],
    daily: [
      "The banner at the top of every page: no 'the minute tick last finished … ago'; ONE-01 and ONE-02 closed.",
      "Apps → Eduwit One → Recent ticks: every minute has a run with no error key; Event sources all ok.",
      "Settings → Setup: what is still open; Settings → Fixes: the window's state and the dry runs.",
      "Brief: yesterday's brief arrived by email at 08:00 IST.",
    ],
    whenFires: [
      {
        check: "ONE-02",
        look: "Alert emails waiting over 5 minutes: app.base_url and the Vercel deployment (the tick's call to the app), then the Resend key. The watchdog pages after 10 minutes.",
      },
      {
        check: "ONE-01",
        look: "The tick report's _error key, a killed check, an event source in error, the AI backlog or spend: the incident's evidence names which. RUNBOOK.md → Alerts.",
      },
      {
        check: "ONE-STORM",
        look: "Many P1s at once: one cause (Supabase, pg_net or the app); the storm email names the top three checks.",
      },
      {
        check: "HB-one:tick",
        look: "pg_cron is not running one-tick: cron.job and cron.job_run_details as the owner; Supabase's logs.",
      },
    ],
    inTheApp: [
      "Applying or rolling back a migration, rotating one_internal_key, the database password: a person with database access (RUNBOOK-database.md).",
    ],
  },
};

export const OPERATE_APPS = Object.keys(OPERATE);

/** The pg_cron jobs that belong to an app, from the platform.cron panel's rows. */
export function appJobs<T extends { job: string }>(app: OperateApp, jobs: T[]): T[] {
  if (app.cronPrefixes.length === 0) return [];
  return jobs.filter((j) => app.cronPrefixes.some((p) => j.job.startsWith(p)));
}

/** How ready an app is: the Setup items it needs that are validated, over all of them. */
export function readiness(app: OperateApp, items: Array<{ id: string; state: { validated?: boolean } }>) {
  const needed = app.needs
    .map((id) => items.find((i) => i.id === id))
    .filter((i): i is NonNullable<typeof i> => Boolean(i));
  const done = needed.filter((i) => i.state.validated === true);
  return {
    done: done.length,
    total: needed.length,
    missing: needed.filter((i) => i.state.validated !== true).map((i) => i.id),
  };
}
