// One adapter per app (spec §4 lib/embeds): which panels the Apps page shows (each a one.ui_embed panel, migration
// 0012) and which deep links open the app itself for every write. Hosts and ids come from Settings at runtime.

export type Panel = { id: string; title: string; about: string };
type Hosts = Record<string, string | undefined>;
export type LinkContext = { hosts: Hosts; chatwootAccount?: string; wittyWorkflow?: string };
export type AppEmbed = {
  key: string;
  title: string;
  about: string;
  panels: Panel[];
  links: (c: LinkContext) => Array<{ label: string; href: string | undefined }>;
  /** What the spec lists for this page that the app has no read function for: shown as a deep link only. */
  gaps?: string[];
};

export const embeds: Record<string, AppEmbed> = {
  witty: {
    key: "witty",
    title: "Witty",
    about: "The WhatsApp counsellor: n8n workflow, Chatwoot inbox, Gemini, and its own health views.",
    panels: [
      { id: "witty.health_alerts", title: "Health alerts", about: "Witty's own alert view (w2_health_alerts)." },
      {
        id: "witty.digest",
        title: "Last 24 hours",
        about: "Witty's digest: conversations, replies, fallbacks (w2_health_digest).",
      },
      {
        id: "witty.replies",
        title: "Replies and latency",
        about: "Outgoing replies per day with p50 and p95 latency and the share by reply source.",
      },
      { id: "witty.outbox", title: "Outbox", about: "Messages to the CRMs by status." },
      {
        id: "witty.learnings",
        title: "Learnings waiting",
        about: "Learning-loop suggestions pending approval; approve or reject in Witty's own admin.",
      },
      { id: "witty.prompts", title: "Prompts", about: "Prompt names and versions (bodies stay in Witty)." },
      {
        id: "witty.n8n",
        title: "n8n, Chatwoot and Gemini",
        about: "Heartbeats from the app's probes, with the latest execution detail.",
      },
    ],
    links: (c) => [
      {
        label: "Chatwoot inbox",
        href:
          c.hosts.chatwoot && c.chatwootAccount
            ? `${c.hosts.chatwoot}/app/accounts/${c.chatwootAccount}/dashboard`
            : undefined,
      },
      {
        label: "n8n workflow",
        href: c.hosts.n8n && c.wittyWorkflow ? `${c.hosts.n8n}/workflow/${c.wittyWorkflow}` : undefined,
      },
      {
        label: "n8n executions",
        href: c.hosts.n8n && c.wittyWorkflow ? `${c.hosts.n8n}/workflow/${c.wittyWorkflow}/executions` : undefined,
      },
    ],
    gaps: [
      "Approving or rejecting learnings (w2_learning_apply) is done in Witty's admin; no read function lists blocks and the security log.",
    ],
  },
  b2b: {
    key: "b2b",
    title: "B2B CRM",
    about:
      "Partners, allocation, money and the B2C link. Its admin functions run as you: they need your B2B CRM admin access.",
    panels: [
      { id: "b2b.command_center", title: "Command centre", about: "b2b.command_center()." },
      { id: "b2b.alert_feed", title: "Alert feed", about: "b2b.alert_feed(30)." },
      {
        id: "b2b.partners",
        title: "Partners",
        about: "Each partner's status and its allocations in the last 30 days.",
      },
      { id: "b2b.b2c_link", title: "Link to Spark", about: "b2b.b2c_link_overview()." },
      { id: "b2b.capi", title: "Conversions API", about: "b2b.capi_overview()." },
      { id: "b2b.ai", title: "AI", about: "b2b.ai_overview()." },
      { id: "b2b.dashboards", title: "Dashboards", about: "b2b.dashboards_list(); open one in the B2B CRM." },
      { id: "b2b.health", title: "Health check", about: "b2b.health_check(), the same function B2B-01 reads." },
    ],
    links: (c) => [{ label: "Open the B2B CRM", href: c.hosts.b2b_app }],
  },
  b2c: {
    key: "b2c",
    title: "Spark",
    about:
      "The B2C CRM. Timers and queues are read directly (owner, 23 Oct); its own overviews run as you and need your Spark role.",
    panels: [
      { id: "b2c.timers", title: "Timers", about: "The b2c-* cron jobs and their latest finished run." },
      { id: "b2c.queues", title: "Queues", about: "Inbox from the master lead table, outbox, send queue, by status." },
      {
        id: "b2c.counsellors",
        title: "Counsellors (30 days)",
        about: "Leads, contacts, applications, enrolments and SLA per counsellor, from fact_leads.",
      },
      { id: "b2c.connectors", title: "Connectors", about: "b2c.connectors_overview() (Spark admin)." },
      { id: "b2c.nurture", title: "Nurture", about: "b2c.nurture_overview() (Spark marketing)." },
    ],
    links: (c) => [
      { label: "Open Spark's workspace", href: c.hosts.spark ? `${c.hosts.spark}/w` : undefined },
      { label: "Spark sales", href: c.hosts.spark ? `${c.hosts.spark}/s` : undefined },
    ],
    gaps: ["Support tickets and campaign or journey status have no read function for Eduwit One; open them in Spark."],
  },
  web: {
    key: "web",
    title: "Website",
    about: "eduwit.in: lead forms, the catalogue, the advisor, SEO. Its admin functions run on the server.",
    panels: [
      { id: "web.health", title: "Health", about: "web_health()." },
      { id: "web.overview", title: "Admin overview", about: "web_admin_overview()." },
      { id: "web.funnel", title: "Funnel (7 days)", about: "web_funnel_events by funnel and step." },
      {
        id: "web.quality",
        title: "Data quality",
        about: "web_data_quality(): the catalogue and what is hidden and why.",
      },
      { id: "web.seo", title: "SEO (28 days)", about: "web_seo_dashboard(28)." },
    ],
    links: (c) => [{ label: "Open the website admin", href: c.hosts.website ? `${c.hosts.website}/admin` : undefined }],
    gaps: ["Retrying the website outbox and forcing a catalogue poll are done from its /admin."],
  },
  influencer: {
    key: "influencer",
    title: "Influencer portal",
    about: "Creators, their links and the leads they bring (counts only).",
    panels: [
      { id: "influencer.health", title: "Health", about: "inf.health()." },
      { id: "influencer.creators", title: "Creators", about: "By status and pipeline stage, test creators excluded." },
      { id: "influencer.clicks", title: "Link clicks (30 days)", about: "Per day, bots apart." },
      {
        id: "influencer.outcomes",
        title: "Leads per referral code",
        about: "From b2b_referral_outcomes: leads, enrolments and stages per code (no lead details).",
      },
    ],
    links: (c) => [
      { label: "Open the portal admin", href: c.hosts.influencer ? `${c.hosts.influencer}/admin` : undefined },
    ],
    gaps: ["Login attempts have no read function for Eduwit One; see them in the portal."],
  },
  one: {
    key: "one",
    title: "Eduwit One",
    about: "Its own minute tick, event copy and queues (spec standard 7).",
    panels: [
      { id: "one.health", title: "Health", about: "one.health(): tick age, open P1s, queue depths." },
      {
        id: "one.runs",
        title: "Recent ticks",
        about: "The last 30 minute ticks: checks by result, the app call, any error key.",
      },
      {
        id: "one.events",
        title: "Event sources",
        about: "Each app log copied into one.events: status, rows, last copy.",
      },
    ],
    links: (c) => [{ label: "The watchdog endpoint", href: c.hosts.one ? `${c.hosts.one}/api/watchdog` : undefined }],
  },
  catalogue_engine: {
    key: "catalogue_engine",
    title: "Eduwit Scout",
    about:
      "Turns partner websites into the approved programme catalogue every Eduwit app reads (schema ce_pub). Read only here; publishing and review happen in its own dashboard.",
    panels: [
      {
        id: "catalogue_engine.status",
        title: "Partners and the live catalogue",
        about:
          "ce_pub.engine_status(): each partner's live version, what changed since, the queue, open review, alerts.",
      },
      {
        id: "catalogue_engine.versions",
        title: "Catalogue versions",
        about: "The last 30 versions: who published, when, how many programmes, what changed, any failed build.",
      },
      {
        id: "catalogue_engine.queue",
        title: "Queue, runs and review",
        about:
          "Jobs by stage and status, the last 10 runs, open review items by queue, open conflicts, alerts in 24 h.",
      },
    ],
    links: (c) => [
      { label: "Open the engine's dashboard", href: c.hosts.catalogue_engine },
      { label: "Catalogue", href: c.hosts.catalogue_engine ? `${c.hosts.catalogue_engine}/catalogue` : undefined },
      { label: "Review queue", href: c.hosts.catalogue_engine ? `${c.hosts.catalogue_engine}/review` : undefined },
      {
        label: "Partners and Publish",
        href: c.hosts.catalogue_engine ? `${c.hosts.catalogue_engine}/partners` : undefined,
      },
    ],
    gaps: [
      "Publishing, rolling back, review decisions and runs are done in the engine's dashboard; Eduwit One only reads.",
    ],
  },
  platform: {
    key: "platform",
    title: "Platform",
    about: "Supabase and pg_cron, shared by every app.",
    panels: [
      { id: "platform.cron", title: "Cron jobs", about: "Every job and its latest finished run, failures first." },
    ],
    links: () => [],
  },
};
