/**
 * Leads screen: URL state, labels and CSV. Pure functions (no server or browser APIs) so they are unit tested and
 * shared by the page, the client table and the export route. The URL is the only state: every view is a link.
 */

export const SORTS = ["created_at", "last_activity", "name"] as const;
export const DESTINATIONS = ["unrouted", "partner", "in_house"] as const;
export const DELETE_REASONS = ["junk", "test", "duplicate entry", "spam", "student request", "other"] as const;
/** A lead with a partner can only be removed for these reasons (the partner already has it). */
export const PARTNER_DELETE_REASONS: readonly DeleteReason[] = ["junk", "spam", "student request"];
export const PAGE_SIZE = 50;

export type Sort = (typeof SORTS)[number];
export type Destination = (typeof DESTINATIONS)[number];
export type DeleteReason = (typeof DELETE_REASONS)[number];
export type Cursor = { v: string; id: string };

export type LeadQuery = {
  q: string;
  stage: string[];
  source: string[];
  status: string[];
  dest: Destination | null;
  sort: Sort;
  dir: "asc" | "desc";
  test: boolean;
  bin: boolean;
};

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
};

export type LeadPage = { rows: LeadRow[]; next: Cursor | null; total: number | null };
export type Facets = {
  stage: Record<string, number>;
  source: Record<string, number>;
  status: Record<string, number>;
  destination: Record<string, number>;
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
  return {
    q: one(sp.q).trim().slice(0, 100),
    stage: list(sp.stage),
    source: list(sp.source),
    status: list(sp.status).map((s) => s.toUpperCase()),
    dest: DESTINATIONS.includes(dest) ? dest : null,
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

/** Arguments for b2b.leads_list / leads_facets / leads_export. */
export function toRpcParams(q: LeadQuery, extra: { after?: Cursor | null; limit?: number; masked?: boolean } = {}) {
  return {
    q: q.q || undefined,
    stage: q.stage,
    source: q.source,
    status: q.status,
    destination: q.dest ?? undefined,
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

export function hasFilters(q: LeadQuery): boolean {
  return Boolean(q.q || q.stage.length || q.source.length || q.status.length || q.dest);
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

export const DESTINATION_LABEL: Record<string, string> = { unrouted: "Not routed", partner: "Partner", in_house: "In-house" };

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

// ---------- CSV ----------

/**
 * RFC 4180 CSV with a UTF-8 BOM (Excel opens Hindi names correctly). Cells that a spreadsheet would run as a formula
 * (= + - @ tab CR at the start) are prefixed with ' so an exported lead can never execute in someone's Excel.
 */
export function toCsv(columns: string[], rows: Record<string, unknown>[]): string {
  const cell = (v: unknown): string => {
    if (v === null || v === undefined) return "";
    let s = typeof v === "object" ? JSON.stringify(v) : String(v);
    if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
    return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [columns.map(cell).join(",")];
  for (const r of rows) lines.push(columns.map((c) => cell(r[c])).join(","));
  return `﻿${lines.join("\r\n")}\r\n`;
}

export const EXPORT_COLUMNS = [
  "id", "created_at", "student_name", "phone", "email", "city", "state", "interested_course", "interested_specialization",
  "program_level", "study_mode_preference", "highest_qualification", "lead_status", "stage", "lead_source", "channel",
  "campaign", "utm_source", "utm_medium", "utm_campaign", "destination_type", "partner_id", "consent_partner_share_at",
  "last_activity_at", "is_test",
] as const;
