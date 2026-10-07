/** The pre-routing pool (B13) and the basic Command Center: types and labels for b2b.pool_overview / b2b.command_center. */

export const POOL_GROUPS = ["chatting", "held", "routing_off", "due", "opted_out", "too_old", "test"] as const;
export type PoolGroup = (typeof POOL_GROUPS)[number];

export const POOL_GROUP_LABEL: Record<PoolGroup, string> = {
  chatting: "Still chatting with Witty",
  held: "Held for review",
  routing_off: "Ready; automatic routing is off",
  due: "Ready; routes within a minute",
  opted_out: "Opted out",
  too_old: "Older than 90 days",
  test: "Test leads",
};

export const POOL_GROUP_HINT: Record<PoolGroup, string> = {
  chatting: "Decided once the chat has been quiet for the idle time, or at once on hand-off.",
  held: "Imported or entered with \"hold for review\". Release them on the Intake screen, or route single leads by hand.",
  routing_off: "Turn on automatic routing, or route single leads by hand from the lead.",
  due: "The next routing run picks these up.",
  opted_out: "Never routed.",
  too_old: "Automatic routing skips leads this old; route them by hand if they are still worth it.",
  test: "Never routed automatically; route by hand to try a partner's sandbox.",
};

export const OUTLOOK_LABEL: Record<string, string> = {
  partners: "To a partner",
  b2c_sales: "B2C sales (paid campaign)",
  b2c_nurture: "B2C nurture (not qualified)",
  not_passed: "Not passed (junk or mismatch)",
};

export const AGE_BUCKETS = ["< 1 h", "< 1 day", "< 7 days", "older"] as const;

export type PoolRow = {
  id: number;
  name: string | null;
  source: string | null;
  course: string | null;
  status: string | null;
  created_at: string;
  last_seen: string | null;
  group: PoolGroup;
  class: string | null;
  class_reason: string | null;
  not_qualified: string[];
  paid: boolean;
  outlook: string;
};

export type PoolOverview = {
  routing_on: boolean;
  idle_minutes: number;
  total: number;
  groups: Partial<Record<PoolGroup, { n: number; oldest: string; ages: [number, number, number, number] }>>;
  outlook: Record<string, number>;
  missing: Record<string, number>;
  rows: PoolRow[];
};

export type CommandCenter = {
  kpis: {
    leads_today: number; leads_yday: number;
    to_partners_today: number; to_partners_yday: number; to_b2c_today: number;
    accepted_today: number; accepted_yday: number;
    duplicate_rate_7d: number | null;
    sla_due_7d: number; sla_met_7d: number;
    commission_expected_month: number; accepted_month: number;
  };
  flow: { source: string; destination: string; n: number }[];
  stream: { id: number; type: string; at: string; lead_id: number | null; lead_name: string | null; partner_name: string | null; detail: string | null }[];
  alerts: { id: number; type: string; at: string; lead_id: number | null; partner_name: string | null; detail: string | null }[];
  alert_counts: Record<string, number>;
  partners: {
    id: number; name: string; status: string; live: boolean; daily_cap: number | null; today: number; accepted_7d: number;
    duplicates_7d: number; failing: number; failed_24h: number; last_event_at: string | null;
  }[];
  pool: { total: number; chatting: number };
  switches: Record<string, boolean>;
  live_partners: number;
  has_partners: boolean;
  has_offers: boolean;
};

export const STREAM_LABEL: Record<string, string> = {
  "lead.routed": "Routed",
  "lead.rerouted": "Moved to the next partner",
  "b2c.lead_handed_off": "Handed to B2C",
  "lead.pushed": "Sent to partner",
  "lead.accepted": "Accepted",
  "lead.duplicate": "Duplicate at partner",
  "lead.push_failed": "Push failed",
  "lead.not_passed": "Not passed",
  "lead.route_to_partners": "Sent to partners by hand",
  "notification.sent": "Student messaged",
};

export const STREAM_TONE: Record<string, "success" | "warning" | "danger" | "info" | "neutral"> = {
  "lead.accepted": "success",
  "notification.sent": "success",
  "lead.duplicate": "warning",
  "lead.rerouted": "warning",
  "lead.push_failed": "danger",
  "lead.not_passed": "neutral",
  "b2c.lead_handed_off": "info",
};

export const ALERT_LABEL: Record<string, string> = {
  "alert.push_failed": "Push failed after every retry",
  "alert.push_error": "Push error",
  "alert.partner_rejected": "Partner rejected a lead",
  "alert.partner_bad_signature": "Partner event with a bad signature",
  "alert.commission_dispute": "Late duplicate claim (dispute)",
  "alert.notification_failed": "Student message failed",
  "alert.programme_sheet_failed": "Partner Google Sheet could not be read",
  "alert.webhook_dead": "Webhook delivery gave up",
  "alert.b2c_bad_signature": "B2C CRM event with a bad signature",
  "alert.partner_optout_notice": "Student opted out: tell the partner",
  "alert.erasure_requested": "Student asked for data erasure",
  "alert.mapping_unmapped": "Partner sent something not mapped",
  "alert.mapping_drift": "Partner's CRM schema changed",
  "alert.sla_breach": "Partner missed the first-contact SLA",
  "alert.reconciliation_items": "Reconciliation found mismatches",
  "alert.intake_new_form": "Leads from a new Meta or Google form (map it)",
  "alert.intake_bad_signature": "Lead webhook with a bad signature or key",
  "alert.intake_failed": "A lead from an ad form could not be stored",
  "alert.capi_failed": "Conversions refused or given up (CAPI)",
  "alert.capi_auth": "Meta or Google refused the CAPI credentials",
  "alert.partner_auth": "A partner's CRM refused Eduwit's credentials",
  "alert.invoice_overdue": "A partner invoice is overdue",
  "routing.error": "Routing error",
};

/** Change against the same hours yesterday, as a short label; null when there is nothing to compare. */
export function delta(today: number, yday: number): { text: string; tone: "up" | "down" | "flat" } | null {
  if (today === 0 && yday === 0) return null;
  if (yday === 0) return { text: `+${today} vs 0`, tone: "up" };
  const pct = Math.round(((today - yday) / yday) * 100);
  return { text: `${pct > 0 ? "+" : ""}${pct}% vs yesterday`, tone: pct > 0 ? "up" : pct < 0 ? "down" : "flat" };
}

/** SLA compliance as a share, or null while nothing has reached its deadline. */
export function slaShare(met: number, due: number): number | null {
  return due > 0 ? met / due : null;
}

/** Groups the 7-day flow by destination for the bar chart, largest first, with each destination's sources. */
export function flowByDestination(flow: CommandCenter["flow"]) {
  const map = new Map<string, { destination: string; n: number; sources: { source: string; n: number }[] }>();
  for (const f of flow) {
    const d = map.get(f.destination) ?? { destination: f.destination, n: 0, sources: [] };
    d.n += f.n;
    d.sources.push({ source: f.source, n: f.n });
    map.set(f.destination, d);
  }
  return [...map.values()].sort((a, b) => b.n - a.n).map((d) => ({ ...d, sources: d.sources.sort((a, b) => b.n - a.n) }));
}
