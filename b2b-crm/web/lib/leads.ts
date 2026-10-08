/**
 * Leads screen: URL state, labels, row badges, bulk-action toasts and CSV. Pure functions (no server or browser APIs) so
 * they are unit tested and shared by the page, the client table and the export route. The URL is the only state: every
 * view is a link. Shapes mirror b2b.leads_list / leads_facets / lead_filter_sql (m31l, Addendum 3) and leads_export_page.
 */
import { CONSENT_STATE_LABEL, LANE_LABEL, REASON_LABEL, notPassedLabel, type ConsentState, type Lane } from "@/lib/routing";

export const SORTS = ["created_at", "last_activity", "name"] as const;
/**
 * The `dest` filter (b2b.lead_filter_sql `destination`): the four routing destinations, then the Addendum 3 flags, which
 * sit on top of a destination (a partner-barred lead is with B2C; a lost-in-grace lead is still with its partner).
 */
export const DESTINATIONS = ["unrouted", "partner", "in_house", "not_passed", "barred", "qualification_nurture", "awaiting_consent", "reenquired", "lost_grace"] as const;
export const ROUTING_DESTINATIONS = ["unrouted", "partner", "in_house", "not_passed"] as const satisfies readonly Destination[];
export const FLAG_DESTINATIONS = ["barred", "qualification_nurture", "awaiting_consent", "reenquired", "lost_grace"] as const satisfies readonly Destination[];
/** The paid label (Meta / Google attribution, D38): a filter, never a routing input. */
export const PAID_FILTERS = ["meta", "google", "any"] as const;
export const DELETE_REASONS = ["junk", "test", "duplicate entry", "spam", "student request", "other"] as const;
/** A lead with a partner can only be removed for these reasons (the partner already has it). */
export const PARTNER_DELETE_REASONS: readonly DeleteReason[] = ["junk", "spam", "student request"];
export const PAGE_SIZE = 50;

export type Sort = (typeof SORTS)[number];
export type Destination = (typeof DESTINATIONS)[number];
export type PaidFilter = (typeof PAID_FILTERS)[number];
export type DeleteReason = (typeof DELETE_REASONS)[number];
export type Cursor = { v: string; id: string };

export type LeadQuery = {
  q: string;
  stage: string[];
  source: string[];
  status: string[];
  dest: Destination | null;
  paid: PaidFilter | null;
  sort: Sort;
  dir: "asc" | "desc";
  test: boolean;
  bin: boolean;
};

export type HoldKind = "barred" | "qualification_nurture" | "selling";

export type LeadRow = {
  id: number;
  created_at: string;
  student_name: string | null;
  whatsapp_number: string | null;
  email_id: string | null;
  city: string | null;
  state: string | null;
  interested_course: string | null;
  interested_specialization: string | null;
  program_level: string | null;
  study_mode_preference: string | null;
  lead_source: string | null;
  channel: string | null;
  campaign: string | null;
  lead_status: string | null;
  temperature: string | null;
  stage: string | null;
  sub_stage: string | null;
  lead_stage: string | null;
  destination_type: string | null;
  partner_id: number | null;
  last_activity_at: string | null;
  deleted_at: string | null;
  is_opted_out: boolean | null;
  is_test: boolean;
  partner_consent: boolean;
  is_bot_paused: boolean | null;
  /** Junk, mismatch, invalid or blocked phone: kept in the master database, not passed to any CRM. `detail` is the spam rule (m31d). */
  not_passed?: { reason: string; decided_at: string; detail?: string | null } | null;
  // ---- Addendum 3 (m31l leads_list) ----
  /** Permanent partner bar (R2): duplicate at partners or lost by a partner. The lead can never go to a partner again. */
  partner_bar_reason: string | null;
  partner_barred_at: string | null;
  /** Partners that proved they already had this student (PART 5.4). `other_providers` is their names, '; '-joined. */
  other_providers_count: number | null;
  other_providers?: string | null;
  b2c_lane: Lane | null;
  allocation_reason: string | null;
  hold_kind: HoldKind | null;
  /** A new enquiry arrived while the lead was held, not yet acknowledged by the Admin (D18). */
  reenquired_open: boolean | null;
  paid_platform: string | null;
  consent_state: ConsentState | null;
  /** Set while the partner has marked the lead lost and the 7-day grace runs (PART 6.1). */
  lost_grace_until: string | null;
};

export type LeadPage = { rows: LeadRow[]; next: Cursor | null; total: number | null };
export type Facets = {
  stage: Record<string, number>;
  source: Record<string, number>;
  status: Record<string, number>;
  /** Keyed by every DESTINATIONS value (the flags are counted on the list's base filter too). */
  destination: Record<string, number>;
  paid: { meta: number; google: number; any: number };
  bin: number;
  tests: number;
};

type SearchParams = Record<string, string | string[] | undefined>;

const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? "";

/** Comma-separated list, trimmed, de-duplicated, capped: the database embeds each value as a literal anyway. */
function list(v: string | string[] | undefined): string[] {
  const out = new Set<string>();
  for (const part of one(v).split(",")) {
    const s = part.trim().slice(0, 60);
    if (s) out.add(s);
    if (out.size === 20) break;
  }
  return [...out];
}

export function parseLeadQuery(sp: SearchParams): LeadQuery {
  const sort = one(sp.sort) as Sort;
  const dest = one(sp.dest) as Destination;
  const paid = one(sp.paid) as PaidFilter;
  return {
    q: one(sp.q).trim().slice(0, 100),
    stage: list(sp.stage),
    source: list(sp.source),
    status: list(sp.status).map((s) => s.toUpperCase()),
    dest: DESTINATIONS.includes(dest) ? dest : null,
    paid: PAID_FILTERS.includes(paid) ? paid : null,
    sort: SORTS.includes(sort) ? sort : "created_at",
    dir: one(sp.dir) === "asc" ? "asc" : "desc",
    test: one(sp.test) === "1",
    bin: one(sp.view) === "bin",
  };
}

/** The selected lead for the drawer, or null. Ids are positive bigints. */
export function parseLeadId(sp: SearchParams): number | null {
  const v = one(sp.lead);
  if (!/^\d{1,15}$/.test(v)) return null;
  const n = Number(v);
  return n > 0 ? n : null;
}

/** Arguments for b2b.leads_list / leads_facets / leads_export_start (lead_filter_sql keys). */
export function toRpcParams(q: LeadQuery, extra: { after?: Cursor | null; limit?: number; masked?: boolean } = {}) {
  return {
    q: q.q || undefined,
    stage: q.stage,
    source: q.source,
    status: q.status,
    destination: q.dest ?? undefined,
    paid: q.paid ?? undefined,
    include_test: q.test,
    bin: q.bin,
    sort: q.sort,
    dir: q.dir,
    limit: extra.limit ?? PAGE_SIZE,
    after: extra.after ?? undefined,
    masked: extra.masked,
  };
}

/** URL search string for a query, with optional changes. Defaults are left out so links stay short. */
export function leadsSearch(q: LeadQuery, patch: Partial<LeadQuery> = {}, lead: number | null = null): string {
  const m = { ...q, ...patch };
  const p = new URLSearchParams();
  if (m.q) p.set("q", m.q);
  if (m.stage.length) p.set("stage", m.stage.join(","));
  if (m.source.length) p.set("source", m.source.join(","));
  if (m.status.length) p.set("status", m.status.join(","));
  if (m.dest) p.set("dest", m.dest);
  if (m.paid) p.set("paid", m.paid);
  if (m.sort !== "created_at") p.set("sort", m.sort);
  if (m.dir !== "desc") p.set("dir", m.dir);
  if (m.test) p.set("test", "1");
  if (m.bin) p.set("view", "bin");
  if (lead) p.set("lead", String(lead));
  const s = p.toString();
  return s ? `?${s}` : "";
}

export function leadsHref(q: LeadQuery, patch: Partial<LeadQuery> = {}, lead: number | null = null): string {
  return `/leads${leadsSearch(q, patch, lead)}`;
}

/** Adds or removes one value of a multi-select filter. */
export function toggle(values: string[], value: string): string[] {
  return values.includes(value) ? values.filter((v) => v !== value) : [...values, value];
}

/** Every filter that narrows the list (sort, the test switch and the bin are views, not filters). */
export const CLEAR_FILTERS: Partial<LeadQuery> = { q: "", stage: [], source: [], status: [], dest: null, paid: null };

export function hasFilters(q: LeadQuery): boolean {
  return Boolean(q.q || q.stage.length || q.source.length || q.status.length || q.dest || q.paid);
}

// ---------- labels ----------

const WORDS: Record<string, string> = { whatsapp: "WhatsApp", sms: "SMS", csv: "CSV", api: "API", mba: "MBA", utm: "UTM", otp: "OTP", seo: "SEO", pg: "PG", ug: "UG" };

/** "whatsapp_direct" → "WhatsApp direct"; "EARN_IT" → "Earn it"; empty → "None". */
export function humanize(s: string | null | undefined): string {
  if (!s || s === "(none)" || s === "NONE") return "None";
  const words = s.replace(/[_-]+/g, " ").trim().toLowerCase().split(/\s+/);
  return words.map((w, i) => WORDS[w] ?? (i === 0 ? w.charAt(0).toUpperCase() + w.slice(1) : w)).join(" ");
}

export function statusTone(status: string | null | undefined): "danger" | "warning" | "info" | "neutral" {
  switch ((status ?? "").toUpperCase()) {
    case "HOT": return "danger";
    case "WARM": return "warning";
    case "COLD": return "info";
    default: return "neutral";
  }
}

const B2C_LABEL = "B2C CRM";

export const DESTINATION_LABEL: Record<string, string> = {
  unrouted: "Not routed",
  partner: "Partner",
  in_house: B2C_LABEL,
  not_passed: "Not passed",
  barred: "Partner-barred",
  qualification_nurture: "Qualification nurture",
  awaiting_consent: "Awaiting consent",
  reenquired: "Re-enquired",
  lost_grace: "Lost, in grace",
};

/** Page description for a filtered view (the Addendum 3 flags and the Not passed view). */
export const DESTINATION_HINT: Record<string, string> = {
  not_passed:
    "Junk, programme-mismatch, invalid-phone and blocked-phone leads, with the spam rule that caught them: kept in the master database, but no CRM works them. Select leads and pass them to a CRM when the classification was wrong or Eduwit now offers the programme; they are then judged on their details and can reach partners.",
  barred:
    "Partner-barred leads can never go to a partner again: a duplicate cascade or a partner marking them lost. B2C works them; a new enquiry is sent to B2C as re-enquired, and bulk routing skips them with a count.",
  qualification_nurture:
    "Leads in B2C's qualification nurture: not yet qualified (missing details, a course outside the catalogue or no answer to the consent request). They return to routing once qualified.",
  awaiting_consent:
    "Leads with an open partner-sharing consent request: asked from Witty's number or the B2C number, 48 hours to answer. YES routes them to partners; NO or no answer keeps them with B2C.",
  reenquired:
    "Held leads with a new enquiry the Admin has not acknowledged yet (a new form, Witty again). Partner-held leads are never re-routed by a re-enquiry; acknowledge them from the lead's Routing tab.",
  lost_grace:
    "Partners marked these leads lost less than 7 days ago. They stay with the partner: new partner activity brings them back with no dispute; after the grace they move to B2C nurture and are partner-barred.",
};

export const PAID_FILTER_LABEL: Record<PaidFilter, string> = { meta: "Meta ads", google: "Google ads", any: "Any paid" };
export const PAID_PLATFORM_LABEL: Record<string, string> = { meta: "Meta", google: "Google", other: "other" };
export const BAR_REASON_LABEL: Record<string, string> = { duplicate: "duplicate at partners", lost: "lost by a partner" };

/** Indian mobile numbers as +91 98000 00012; anything else is shown as stored. */
export function formatPhone(raw: string | null | undefined): string {
  if (!raw) return "—";
  const d = raw.replace(/\D/g, "");
  if (d.length === 12 && d.startsWith("91")) return `+91 ${d.slice(2, 7)} ${d.slice(7)}`;
  if (d.length === 10) return `+91 ${d.slice(0, 5)} ${d.slice(5)}`;
  return raw;
}

/** wa.me link for a stored number, or null when it is not a plausible phone. */
export function whatsappLink(raw: string | null | undefined): string | null {
  const d = (raw ?? "").replace(/\D/g, "");
  if (d.length < 10 || d.length > 15) return null;
  return `https://wa.me/${d.length === 10 ? `91${d}` : d}`;
}

/** "12 Oct" in IST, for badges; "—" when missing. */
export function shortDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return new Intl.DateTimeFormat("en-IN", { timeZone: "Asia/Kolkata", day: "numeric", month: "short" }).format(d);
}

// ---------- row badges ----------

export type BadgeTone = "neutral" | "success" | "warning" | "danger" | "info" | "brand";
export type RowBadge = { key: string; text: string; tone: BadgeTone; title?: string };

/** The suffix of every qualification-nurture hold (hold_kind, D16/R7), whatever its reason. */
const QUALIFYING = "qualifying";

/** Short forms of REASON_LABEL for the row badge suffix ('B2C sales · duplicate cascade'); the full label is the hover title. */
const SHORT_REASON: Record<string, string> = {
  duplicate_cascade: "duplicate cascade",
  not_qualified: QUALIFYING,
  consent_no_answer: "qualifying (no consent answer)",
  partner_lost: "lost by a partner",
  b2c_created: "created in B2C",
  import_choice: "import choice",
  rule: "routing rule",
  manual: "sent by the Admin",
  manual_route_failed: "manual route failed",
  no_partner_offers_programme: "no partner offers it",
  no_capacity: "no eligible partner",
  partners_unreachable: "partner limit reached",
  partner_attempts_exhausted: "attempt limit reached",
  no_partner_consent: "student said NO to sharing",
  partner_barred: "re-enquired, partner-barred",
  b2c_held: "held by B2C",
  test_handoff: "test hand-off",
  paid_campaign: "paid campaign (old rule)",
};

const lowerFirst = (s: string) => (/^[A-Z][a-z]/.test(s) ? s.charAt(0).toLowerCase() + s.slice(1) : s);

/** consent_state values (CONTRACT 1.3) that mean a request is open: 'requested' covers requested, sent and unsendable requests. */
const AWAITING_CONSENT: ReadonlySet<string> = new Set(["requested", "queued"]);

/**
 * The Routing cell of a row, in display order: destination (Not passed · reason, Partner #id, 'B2C sales · duplicate
 * cascade', 'B2C nurture · qualifying'), then the red flags (Partner-barred, Other providers (n), Re-enquired, Lost, in
 * grace until <date>), Awaiting consent, and the Paid label. An unrouted lead without flags gets no badge.
 */
export function rowBadges(row: LeadRow): RowBadge[] {
  const out: RowBadge[] = [];
  if (row.not_passed) {
    out.push({ key: "not_passed", tone: "danger", text: `Not passed · ${notPassedLabel(row.not_passed.reason, row.not_passed.detail)}`, title: `Decided ${shortDate(row.not_passed.decided_at)}` });
  } else if (row.destination_type === "partner") {
    out.push({ key: "destination", tone: "brand", text: `Partner${row.partner_id ? ` #${row.partner_id}` : ""}` });
  } else if (row.destination_type === "in_house") {
    const lane: string = (row.b2c_lane && LANE_LABEL[row.b2c_lane]) || B2C_LABEL;
    const reason = row.allocation_reason;
    const suffix = row.hold_kind === "qualification_nurture" ? QUALIFYING : reason ? SHORT_REASON[reason] ?? lowerFirst(REASON_LABEL[reason] ?? humanize(reason)) : null;
    const full = reason ? REASON_LABEL[reason] ?? humanize(reason) : undefined;
    out.push({ key: "destination", tone: "info", text: suffix ? `${lane} · ${suffix}` : lane, title: full });
  } else if (row.destination_type) {
    out.push({ key: "destination", tone: "info", text: DESTINATION_LABEL[row.destination_type] ?? humanize(row.destination_type) });
  }
  if (row.partner_bar_reason) {
    const why = BAR_REASON_LABEL[row.partner_bar_reason] ?? humanize(row.partner_bar_reason).toLowerCase();
    out.push({ key: "barred", tone: "danger", text: "Partner-barred", title: `Partner-barred (${why}) since ${shortDate(row.partner_barred_at)}: B2C only, for ever` });
  }
  if ((row.other_providers_count ?? 0) > 0) {
    out.push({ key: "providers", tone: "danger", text: `Other providers (${row.other_providers_count})`, title: row.other_providers ? `Already with: ${row.other_providers}` : "Partners that proved they already had this student" });
  }
  if (row.reenquired_open) {
    out.push({ key: "reenquired", tone: "danger", text: "Re-enquired", title: "A new enquiry arrived while the lead was held: acknowledge it in the Routing tab" });
  }
  if (row.lost_grace_until) {
    out.push({ key: "lost_grace", tone: "danger", text: `Lost, in grace until ${shortDate(row.lost_grace_until)}`, title: "The partner marked it lost. New partner activity brings it back; after the grace it moves to B2C nurture and is partner-barred" });
  }
  if (row.consent_state && AWAITING_CONSENT.has(row.consent_state)) {
    out.push({ key: "consent", tone: "warning", text: "Awaiting consent", title: CONSENT_STATE_LABEL[row.consent_state] ?? humanize(row.consent_state) });
  }
  if (row.paid_platform) {
    const platform = PAID_PLATFORM_LABEL[row.paid_platform] ?? humanize(row.paid_platform);
    out.push({ key: "paid", tone: "neutral", text: row.paid_platform === "other" ? "Paid" : `Paid · ${platform}`, title: "Meta / Google attribution label (no effect on routing)" });
  }
  return out;
}

// ---------- bulk-action toasts ----------

/** b2b.route_to_partners_many's counts (m31l 4). */
export type RouteManyCounts = {
  sent: number; to_partner: number; back_to_b2c: number; consent_requested: number;
  skipped_barred: number; skipped_no_consent: number; skipped_not_held: number; failed: number;
};
/** b2b.reroute_many's counts (m31l 3). */
export type RerouteManyCounts = {
  done: number; skipped_no_partner_allocation: number; skipped_contacted_no_breach: number; skipped_lost_in_grace: number; skipped_barred: number; failed: number;
};

const n0 = (v: number | null | undefined) => (typeof v === "number" && Number.isFinite(v) ? v : 0);

/** 'Sent 12 · to a partner 8 · consent requested 1 · back to B2C 3 · skipped 3 partner-barred · 2 without consent · 1 not with B2C'. */
export function bulkRouteToast(c: Partial<RouteManyCounts>): string {
  const parts = [n0(c.sent) > 0 ? `Sent ${n0(c.sent)}` : "Nothing sent"];
  if (n0(c.to_partner)) parts.push(`to a partner ${n0(c.to_partner)}`);
  if (n0(c.consent_requested)) parts.push(`consent requested ${n0(c.consent_requested)}`);
  if (n0(c.back_to_b2c)) parts.push(`back to B2C ${n0(c.back_to_b2c)}`);
  const skipped: string[] = [];
  if (n0(c.skipped_barred)) skipped.push(`${n0(c.skipped_barred)} partner-barred`);
  if (n0(c.skipped_no_consent)) skipped.push(`${n0(c.skipped_no_consent)} without consent`);
  if (n0(c.skipped_not_held)) skipped.push(`${n0(c.skipped_not_held)} not with B2C`);
  if (skipped.length) parts.push(`skipped ${skipped.join(" · ")}`);
  if (n0(c.failed)) parts.push(`${n0(c.failed)} failed`);
  return parts.join(" · ");
}

/** 'Re-routed 5 · skipped 2 lost, in grace · 1 not with a partner · 1 contacted, no SLA breach · 1 partner-barred · 2 failed'. */
export function rerouteToast(c: Partial<RerouteManyCounts>): string {
  const parts = [n0(c.done) > 0 ? `Re-routed ${n0(c.done)}` : "Nothing re-routed"];
  const skipped: string[] = [];
  if (n0(c.skipped_lost_in_grace)) skipped.push(`${n0(c.skipped_lost_in_grace)} lost, in grace`);
  if (n0(c.skipped_no_partner_allocation)) skipped.push(`${n0(c.skipped_no_partner_allocation)} not with a partner`);
  if (n0(c.skipped_contacted_no_breach)) skipped.push(`${n0(c.skipped_contacted_no_breach)} contacted, no SLA breach`);
  if (n0(c.skipped_barred)) skipped.push(`${n0(c.skipped_barred)} partner-barred`);
  if (skipped.length) parts.push(`skipped ${skipped.join(" · ")}`);
  if (n0(c.failed)) parts.push(`${n0(c.failed)} failed`);
  return parts.join(" · ");
}

/**
 * What a bulk 'Send to partners' would skip, counted from the rows before the call (the database counts again). A lead
 * is sendable only when B2C holds it, it is not partner-barred and the student has given partner-sharing consent.
 */
export function sendToPartnersPreview(rows: LeadRow[]): { sendable: number; barred: number; no_consent: number; not_held: number } {
  let sendable = 0, barred = 0, no_consent = 0, not_held = 0;
  for (const r of rows) {
    if (r.not_passed || r.destination_type !== "in_house") { not_held++; continue; }
    if (r.partner_bar_reason) { barred++; continue; }
    if (r.consent_state !== "given") { no_consent++; continue; }
    sendable++;
  }
  return { sendable, barred, no_consent, not_held };
}

/** What a bulk 'Re-route' would skip up front (whether the partner already contacted the student is only known to the database). */
export function reroutePreview(rows: LeadRow[], to: "b2c" | "partners"): { candidates: number; lost_in_grace: number; barred: number; not_with_partner: number } {
  let candidates = 0, lost_in_grace = 0, barred = 0, not_with_partner = 0;
  for (const r of rows) {
    if (r.not_passed || r.destination_type !== "partner") { not_with_partner++; continue; }
    if (r.lost_grace_until) { lost_in_grace++; continue; }
    if (to === "partners" && r.partner_bar_reason) { barred++; continue; }
    candidates++;
  }
  return { candidates, lost_in_grace, barred, not_with_partner };
}

// ---------- CSV ----------

/**
 * RFC 4180 CSV with a UTF-8 BOM (Excel opens Hindi names correctly). Cells that a spreadsheet would run as a formula
 * (= + - @ tab CR at the start) are prefixed with ' so an exported lead can never execute in someone's Excel.
 */
export function csvCell(v: unknown): string {
  if (v === null || v === undefined) return "";
  let s = typeof v === "object" ? JSON.stringify(v) : String(v);
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** One CSV line per row, each ending in CRLF. */
export function csvLines(columns: readonly string[], rows: Record<string, unknown>[]): string {
  return rows.map((r) => `${columns.map((c) => csvCell(r[c])).join(",")}\r\n`).join("");
}

/** The whole file: BOM, header and rows. */
export function toCsv(columns: readonly string[], rows: Record<string, unknown>[]): string {
  return `﻿${columns.map(csvCell).join(",")}\r\n${csvLines(columns, rows)}`;
}

/** Columns of the lead download (b2b.leads_export_page; the Addendum 3 columns follow m31l leads_export). */
export const EXPORT_COLUMNS = [
  "id", "created_at", "student_name", "phone", "email", "city", "state", "interested_course", "interested_specialization",
  "university", "program_level", "study_mode_preference", "highest_qualification", "lead_status", "stage", "sub_stage",
  "lead_source", "channel", "campaign", "utm_source", "utm_medium", "utm_campaign", "destination", "partner", "reference",
  "allocation_status", "b2c_lane", "partner_barred_at", "partner_bar_reason", "other_providers", "hold_kind", "paid_platform",
  "partner_stage_raw", "consent_partner_share_at", "last_activity_at", "deleted_at", "is_test",
] as const;

/** Most rows one download may hold (the database stops there too). */
export const EXPORT_CAP = 50000;
