/** The pre-routing pool (B13) and the Command Center: types and labels for b2b.pool_overview / b2b.command_center (m31l,
 *  Addendum 3; groups and outlook from b2b.pool_lead / b2b.route_outlook, m31f; the go-live checklist from
 *  b2b.routing_golive_check, m31e), plus the alert-digest type list the Dashboards → Alerts form edits (C87). */
import type { GoliveItem } from "@/lib/routing";

// The outlook labels are the shared routing contract (CONTRACT 1.3): one copy, in lib/routing.ts (W1).
export { OUTLOOK_LABEL } from "@/lib/routing";

// ---------- pool ----------

/** pool_lead's groups (m31f), in display order: the waits first, then what the Admin can act on, then the rest. */
export const POOL_GROUPS = ["chatting", "waiting_inactivity", "awaiting_consent", "held", "routing_off", "due", "opted_out", "too_old", "test"] as const;
export type PoolGroup = (typeof POOL_GROUPS)[number];

export const POOL_GROUP_LABEL: Record<PoolGroup, string> = {
  chatting: "Still chatting",
  waiting_inactivity: "Waiting for 18 h of inactivity",
  awaiting_consent: "Awaiting partner-sharing consent",
  held: "Held for review",
  routing_off: "Ready; automatic routing is off",
  due: "Ready; routes within a minute",
  opted_out: "Opted out",
  too_old: "No change in 90 days",
  test: "Test leads",
};

/** The group label with the Admin's inactivity setting filled in (engine.witty_unqualified_idle_hours, default 18). */
export function poolGroupLabel(g: PoolGroup, unqualifiedIdleHours?: number | null): string {
  if (g === "waiting_inactivity" && unqualifiedIdleHours && Number.isFinite(unqualifiedIdleHours)) return `Waiting for ${unqualifiedIdleHours} h of inactivity`;
  return POOL_GROUP_LABEL[g];
}

export const POOL_GROUP_HINT: Record<PoolGroup, string> = {
  chatting: "Qualified chat leads (Witty or the website agent) are decided after 30 minutes of quiet, or at once on an escalation or a final programme.",
  waiting_inactivity: "Unqualified Witty leads (Amendment 1): decided once the student has sent nothing for the set hours. Witty's own replies never restart the clock, and a qualifying change decides the lead at once.",
  awaiting_consent: "The student was asked whether we may share their details with admission partners. YES routes the lead, NO sends it to B2C sales, and no answer within 48 hours sends it to B2C nurture. Queued requests wait for the hourly sending budget.",
  held: "Imported or entered with \"hold for review\". Release them on the Intake screen, or route single leads by hand.",
  routing_off: "Turn on automatic routing, or route single leads by hand from the lead.",
  due: "The next routing run picks these up.",
  opted_out: "Never routed.",
  too_old: "Automatic routing skips leads with no change in 90 days; route them by hand if they are still worth it.",
  test: "Never routed automatically; route by hand to try a partner's sandbox.",
};

export const AGE_BUCKETS = ["< 1 h", "< 1 day", "< 7 days", "older"] as const;

/** lead_readiness.wait (m31d): why the lead is not ready yet and until when. */
export type PoolWait = {
  kind: "inactivity" | "chatting" | "consent";
  why: string | null;
  until: string | null;
  last_inbound: string | null;
  /** inactivity: the hours of the setting */
  hours?: number | null;
  /** consent: the open request */
  request_id?: number | null;
  status?: "queued" | "requested" | "sent" | "unsendable" | null;
  expires_at?: string | null;
  context?: "decision" | "nurture" | "admin" | null;
};

/** One pool row: pool_overview's lead columns || pool_lead(l) (m31f). */
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
  /** lead_class.missing codes (no_name, no_email, no_course, witty_unconfirmed, no_valid_contact, phone_not_verified) */
  not_qualified: string[];
  /** lead_readiness.missing sentences */
  missing: string[];
  paid: boolean;
  paid_platform: string | null;
  import_id: number | null;
  /** route_outlook (CONTRACT 1.3) */
  outlook: string;
  outlook_reason: string | null;
  outlook_lane: "sales" | "nurture" | null;
  wait: PoolWait | null;
  decide_after: string | null;
};

export type PoolOverview = {
  /** is_live('routing') and engine.enabled */
  routing_on: boolean;
  routing_live: boolean;
  engine_enabled: boolean;
  /** a3_fixed.witty_idle_minutes (30): the PART 2 idle gate for qualified chat leads */
  idle_minutes: number;
  /** engine.witty_unqualified_idle_hours (default 18): Amendment 1 */
  unqualified_idle_hours: number;
  golive: GoliveItem[];
  total: number;
  groups: Partial<Record<PoolGroup, { n: number; oldest: string; ages: [number, number, number, number] }>>;
  outlook: Record<string, number>;
  missing: Record<string, number>;
  rows: PoolRow[];
};

export const PAID_PLATFORM_LABEL: Record<string, string> = { meta: "Meta ads", google: "Google ads", other: "Paid" };

/** "Paid · Meta ads" for a paid pool row, else null. */
export function poolPaidText(r: Pick<PoolRow, "paid" | "paid_platform">): string | null {
  if (!r.paid) return null;
  const p = r.paid_platform ? PAID_PLATFORM_LABEL[r.paid_platform] : null;
  return p && p !== "Paid" ? `Paid · ${p}` : "Paid";
}

/** "3 h", "25 min", "2 days": a short duration for countdowns. */
export function durationText(ms: number): string {
  const m = Math.round(ms / 60_000);
  if (m < 1) return "under a minute";
  if (m < 60) return `${m} min`;
  const h = Math.round(m / 60);
  if (h < 48) return `${h} h`;
  const d = Math.round(h / 24);
  return `${d} days`;
}

/** When a pool row is decided, in words, for the "Decides" column: the countdown of a stored wait (consent requests say
 *  "queued" while they wait for the hourly budget), else what has to happen first. */
export function poolDecidesText(r: Pick<PoolRow, "group" | "wait" | "decide_after">, now: number = Date.now()): string {
  if (r.wait) {
    if (r.wait.kind === "consent" && r.wait.status === "queued") return "queued: waits for the hourly request budget";
    const until = r.decide_after ?? r.wait.until;
    const ms = until ? new Date(until).getTime() - now : NaN;
    const when = !Number.isFinite(ms) ? null : ms <= 0 ? "now" : `in ${durationText(ms)}`;
    if (r.wait.kind === "consent") {
      const prefix = r.wait.status === "unsendable" ? "request could not be sent; " : "answer due ";
      return when ? `${prefix}${when}` : "awaiting the answer";
    }
    return when ?? "soon";
  }
  switch (r.group) {
    case "due": return "next run, within a minute";
    case "routing_off": return "when automatic routing is on";
    case "held": return "when released";
    case "opted_out": return "never";
    case "too_old": return "by hand only";
    case "test": return "by hand only (sandbox)";
    default: return "soon";
  }
}

// ---------- command center ----------

/** One of the three insight cards (C91): an open AI recommendation or a recent anomaly alert. */
export type Insight = {
  source: "recommendation" | "anomaly";
  id: number;
  /** recommendation kind, or the alert event type */
  kind: string;
  title: string;
  /** simulation.gain_pct of a recommendation; null for anomalies */
  gain_pct: number | null;
  occurred_at: string;
  partner_id: number | null;
};

/** Where an insight card leads: recommendations to the AI screen, anomalies to their partner when they have one. */
export function insightHref(i: Insight): string {
  return i.source === "recommendation" ? "/ai" : i.partner_id ? `/partners/${i.partner_id}` : "/ai";
}

/** The card's title: a recommendation's own title, an anomaly's alert label. */
export function insightTitle(i: Insight): string {
  return i.source === "anomaly" ? ALERT_LABEL[i.kind] ?? i.title : i.title;
}

/** "+5.2%" / "−1%" for a simulated gain. */
export function gainText(pct: number): string {
  const v = Math.round(pct * 10) / 10;
  return `${v > 0 ? "+" : v < 0 ? "−" : ""}${Math.abs(v)}%`;
}

export type CommandCenter = {
  routing_on: boolean;
  kpis: {
    leads_today: number; leads_yday: number;
    to_partners_today: number; to_partners_yday: number; to_b2c_today: number;
    accepted_today: number; accepted_yday: number;
    duplicate_rate_7d: number | null;
    sla_due_7d: number; sla_met_7d: number;
    commission_expected_month: number; commission_realised_month: number; accepted_month: number;
  };
  /** What needs the Admin (Addendum 3): re-enquiries to acknowledge, consent requests, lost-in-grace, bars, held items. */
  counts: {
    reenquiries_open: number; consent_pending: number; consent_queued: number; lost_in_grace: number;
    barred_today: number; barred_total: number; not_passed_open: number; flags_open: number;
  };
  golive: GoliveItem[];
  insights: Insight[];
  flow: { source: string; destination: string; n: number }[];
  stream: { id: number; type: string; at: string; lead_id: number | null; lead_name: string | null; partner_name: string | null; detail: string | null }[];
  alerts: { id: number; type: string; at: string; lead_id: number | null; partner_name: string | null; detail: string | null }[];
  alert_counts: Record<string, number>;
  partners: {
    id: number; name: string; status: string; live: boolean; daily_cap: number | null; paused_reason: string | null; auto_paused_at: string | null;
    today: number; accepted_7d: number; duplicates_7d: number; lost_in_grace: number; failing: number; failed_24h: number; last_event_at: string | null;
  }[];
  pool: { total: number; chatting: number; waiting_inactivity: number; awaiting_consent: number };
  switches: Record<string, boolean>;
  live_partners: number;
  has_partners: boolean;
  has_offers: boolean;
};

export const STREAM_LABEL: Record<string, string> = {
  "lead.routed": "Routed",
  "lead.rerouted": "Moved to the next partner",
  "lead.recalled": "Recalled from the partner",
  "b2c.lead_handed_off": "Handed to B2C",
  "lead.pushed": "Sent to partner",
  "lead.accepted": "Accepted",
  "lead.duplicate": "Duplicate at partner",
  "lead.push_failed": "Push failed",
  "lead.not_passed": "Not passed",
  "lead.route_to_partners": "Sent to partners by hand",
  "lead.requalified": "Qualified later: decided again",
  "lead.reenquired": "Enquired again",
  "lead.partner_lost": "Marked lost by the partner (7-day grace)",
  "lead.partner_revived": "Back with the partner",
  "lead.partner_barred": "Partner-barred",
  "lead.consent_requested": "Asked for partner-sharing consent",
  "lead.consent_answered": "Consent answered",
  "notification.sent": "Student messaged",
};

export const STREAM_TONE: Record<string, "success" | "warning" | "danger" | "info" | "neutral"> = {
  "lead.accepted": "success",
  "lead.partner_revived": "success",
  "notification.sent": "success",
  "lead.duplicate": "warning",
  "lead.rerouted": "warning",
  "lead.recalled": "warning",
  "lead.partner_lost": "warning",
  "lead.push_failed": "danger",
  "lead.partner_barred": "danger",
  "lead.not_passed": "neutral",
  "lead.consent_requested": "neutral",
  "b2c.lead_handed_off": "info",
  "lead.requalified": "info",
  "lead.reenquired": "info",
  "lead.consent_answered": "info",
};

/** Alert and feed event types in words (the Command Center's alerts, the alert feed of m31l and the digest form). */
export const ALERT_LABEL: Record<string, string> = {
  "alert.push_failed": "Push failed after every retry",
  "alert.push_error": "Push error",
  "alert.push_collect_error": "A partner's push answer could not be read",
  "alert.partner_rejected": "Partner rejected a lead",
  "alert.partner_bad_signature": "Partner event with a bad signature",
  "alert.commission_dispute": "Commission dispute (late duplicate or activity after lost)",
  "alert.partner_recall_notice": "Lead recalled from a partner: tell the partner",
  "alert.notification_failed": "Student message failed",
  "alert.programme_sheet_failed": "Partner Google Sheet could not be read",
  "alert.webhook_dead": "Webhook delivery gave up",
  "alert.b2c_bad_signature": "B2C CRM event with a bad signature",
  "alert.partner_optout_notice": "Student opted out: tell the partner",
  "alert.erasure_requested": "Student asked for data erasure",
  "alert.consent_unsendable": "Consent request could not be sent (no channel)",
  "alert.consent_withdrawn": "Student withdrew partner-sharing consent: tell the partner",
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
  "alert.model_drift": "Model inputs or predictions drifted from training",
  "alert.model_fallback": "Lead model fell back to segment rates",
  "alert.ncpl_drop": "Partner's net commission per lead dropped",
  "alert.partner_auto_paused": "Partner paused automatically",
  "alert.ai_budget": "AI optimiser: daily budget reached",
  "alert.ai_run_failed": "AI optimiser run failed",
  "alert.ai_rollback": "AI change rolled back automatically",
  "alert.ai_review_worse": "Approved AI change did worse than the holdout",
  "alert.metric": "Metric alert",
  "alert.metric_invalid": "Metric alert broken",
  "alert.schedule_failed": "Scheduled report failed",
  "routing.error": "Routing error",
  // feed types the alert feed also carries (m31l alert_feed)
  "lead.reenquired": "A lead with a partner enquired again (acknowledge it)",
  "lead.partner_barred": "Lead partner-barred (duplicate or lost): B2C only from now on",
};

/** The alert types the Admin digest can carry (admin_alerts.types, m28b seed + m31o merge, C87), grouped for the form. */
export const DIGEST_TYPE_GROUPS: { label: string; types: string[] }[] = [
  { label: "Routing and partners", types: [
    "alert.partner_auto_paused", "alert.ncpl_drop", "alert.model_fallback", "alert.sla_breach", "alert.partner_rejected", "alert.push_failed",
    "alert.push_collect_error", "alert.commission_dispute", "alert.partner_recall_notice", "alert.partner_auth", "alert.programme_sheet_failed",
    "alert.reconciliation_items", "alert.partner_bad_signature", "alert.mapping_drift",
  ] },
  { label: "Students and consent", types: ["alert.consent_unsendable", "alert.consent_withdrawn", "alert.partner_optout_notice", "alert.erasure_requested", "alert.notification_failed"] },
  { label: "Intake and integrations", types: ["alert.intake_failed", "alert.webhook_dead", "alert.capi_auth"] },
  { label: "AI optimiser", types: ["alert.ai_budget", "alert.ai_run_failed", "alert.ai_rollback", "alert.ai_review_worse"] },
  { label: "System", types: ["alert.schedule_failed", "alert.metric_invalid", "routing.error"] },
];

/** The 29 digest types in display order. Metric alerts (alert.metric) send their own message and are never a digest type. */
export const DIGEST_TYPES: string[] = DIGEST_TYPE_GROUPS.flatMap((g) => g.types);

/** The checkbox list of the digest form: every known digest type plus whatever the setting already holds (display order kept,
 *  unknown saved types appended under their own heading). */
export function digestTypeGroups(saved: string[] | null | undefined): { label: string; types: string[] }[] {
  const extra = [...new Set((saved ?? []).filter((t) => !DIGEST_TYPES.includes(t)))];
  return extra.length ? [...DIGEST_TYPE_GROUPS, { label: "Other", types: extra }] : DIGEST_TYPE_GROUPS;
}

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
