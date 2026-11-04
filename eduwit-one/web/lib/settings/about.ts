// What each one.settings key is, for the Settings index and the editor page. A key not listed here still has an editor.

export const settingAbout: Record<string, { title: string; text: string }> = {
  alerts: {
    title: "Alert routing",
    text: "Recipients, escalation timing, the P2 digest hour and storm limits. The owner's: it decides who is told.",
  },
  ai: { title: "AI models", text: "Provider and models per tier, routing per task kind, daily caps in rupees." },
  events: {
    title: "Privacy (PII)",
    text: 'pii_columns: key patterns ("*" is a wildcard) removed from every copied event, panel answer and AI input. It cannot be emptied.',
  },
  test_identities: {
    title: "Test identities",
    text: "The identities the synthetic tests use; a test runs only on these (spec §17.9).",
  },
  hosts: { title: "Hosts", text: "The apps' addresses: probes, health checks and deep links read them each minute." },
  vendors: { title: "Vendor APIs", text: "Where the email, WhatsApp, Vercel and other clients send their requests." },
  app: { title: "App", text: "base_url: where the minute tick calls the app with the internal key." },
  chatwoot: { title: "Chatwoot", text: "The account and inbox the Chatwoot probe reads." },
  n8n: { title: "n8n", text: "Witty's workflow ids the n8n probe watches." },
  whatsapp: { title: "WhatsApp", text: "The numbers the WhatsApp probe reads (status and quality rating)." },
  access: { title: "Sign-in", text: "owners (seeded on install), trusted_days, idle_hours, code_minutes." },
  thresholds: {
    title: "Thresholds",
    text: "The numbers the SQL checks compare against, by name (docs/CHECKS.md lists which check reads which).",
  },
  checks: {
    title: "Check runner",
    text: "lock_timeout and transaction_timeout per check, slow_ms, and whether a missing source opens an incident.",
  },
  tests: { title: "Synthetic tests", text: "Schedules per test and how long test rows are kept before the purge." },
  analytics: { title: "Analytics funnel", text: "The funnel's steps and the event types behind each." },
  witty: { title: "Witty expectations", text: "Whether the nurture and learning workflows are expected to be active." },
  fixes: { title: "Fixes", text: "Each auto-fix's switch and limits; the observation window." },
  retention: { title: "Retention", text: "How long results, events and AI calls are kept." },
  proposals: { title: "Proposals", text: "How long an undecided proposal stays open." },
};

/** Where a key's editor lives: its own page when one exists, else the generic editor. */
export function settingHref(key: string): string {
  if (key === "checks") return "/settings/checks#runner";
  if (key === "fixes") return "/settings/fixes";
  return `/settings/${key}`;
}
