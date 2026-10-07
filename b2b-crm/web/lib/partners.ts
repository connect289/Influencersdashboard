import { z } from "zod";

/** Partners: types, labels and form parsing. Pure, so the server action and the tests share one definition. */

export const ADAPTERS = ["leadsquared", "salesforce", "zoho", "meritto", "hubspot", "inhouse", "generic_rest", "webhook"] as const;
export const DEDUPE_MODES = ["async", "sync", "none"] as const;
export const STATUSES = ["onboarding", "active", "paused", "closed"] as const;
export const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

export type Adapter = (typeof ADAPTERS)[number];
export type DedupeMode = (typeof DEDUPE_MODES)[number];
export type PartnerStatus = (typeof STATUSES)[number];
export type Day = (typeof DAYS)[number];
export type WorkingHours = Record<Day, { open: string; close: string } | null>;

export type Sla = {
  first_contact_hours: number;
  first_connect_days: number;
  status_update_days: number;
  outcome_days: number;
  proof_days: number;
  duplicate_hours: number;
};

export type LeadCriteria = { states_include?: string[]; states_exclude?: string[]; sources_exclude?: string[]; other?: string };

export type Partner = {
  id: number;
  slug: string;
  name: string;
  display_name: string | null;
  logo_url: string | null;
  brand_color: string | null;
  status: PartnerStatus;
  adapter_type: Adapter;
  api_base_url: string | null;
  test_endpoint: string | null;
  dedupe_mode: DedupeMode;
  hold_minutes: number;
  duplicate_window_hours: number;
  notify_enabled: boolean;
  daily_cap: number | null;
  monthly_cap: number | null;
  contract_min_monthly: number | null;
  working_hours: Partial<WorkingHours>;
  holidays: string[];
  sla: Partial<Sla>;
  lead_criteria: LeadCriteria;
  paused_reason: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
  live: boolean;
  has_outbound_credentials: boolean;
  // billing (m20a): the invoice recipient
  legal_name?: string | null;
  gstin?: string | null;
  billing_address?: string | null;
  billing_state_code?: string | null;
  billing_email?: string | null;
  payment_terms_days?: number;
};

export type PartnerListItem = Partner & { leads_today: number; leads_month: number; ncpl_month: number | null; checklist_done: number; checklist_total: number };
export type ChecklistItem = { key: string; done: boolean; available: boolean };
export type PartnerDetail = {
  partner: Partner;
  checklist: ChecklistItem[];
  leads_month: number;
  leads_total: number;
  events: { at: string; type: string; actor: string; payload: Record<string, unknown> }[];
};

// ---------- labels ----------

export const ADAPTER_LABEL: Record<Adapter, string> = {
  leadsquared: "LeadSquared",
  salesforce: "Salesforce",
  zoho: "Zoho CRM",
  meritto: "Meritto (NoPaperForms)",
  hubspot: "HubSpot",
  inhouse: "In-house CRM (partner's own API)",
  generic_rest: "Eduwit's API contract (partner builds it)",
  webhook: "Webhook",
};

export const DEDUPE_LABEL: Record<DedupeMode, { label: string; hint: string }> = {
  async: { label: "Later, by webhook or poll", hint: "Duplicates arrive after the push; a hold window re-routes them." },
  sync: { label: "At once, on create", hint: "The partner refuses a duplicate in the create call; no hold window." },
  none: { label: "Never", hint: "The partner does not report duplicates." },
};

export const STATUS_LABEL: Record<PartnerStatus, string> = { onboarding: "Onboarding", active: "Active", paused: "Paused", closed: "Closed" };
export const STATUS_TONE: Record<PartnerStatus, "info" | "success" | "warning" | "neutral"> = {
  onboarding: "info",
  active: "success",
  paused: "warning",
  closed: "neutral",
};

export const DAY_LABEL: Record<Day, string> = { mon: "Monday", tue: "Tuesday", wed: "Wednesday", thu: "Thursday", fri: "Friday", sat: "Saturday", sun: "Sunday" };

export const SLA_FIELDS: { key: keyof Sla; label: string; unit: "hours" | "days"; def: number; max: number }[] = [
  { key: "first_contact_hours", label: "First contact attempt", unit: "hours", def: 2, max: 72 },
  { key: "first_connect_days", label: "First connected conversation", unit: "days", def: 1, max: 30 },
  { key: "status_update_days", label: "Status update while open", unit: "days", def: 7, max: 60 },
  { key: "outcome_days", label: "Counselling outcome recorded", unit: "days", def: 5, max: 60 },
  { key: "proof_days", label: "Enrollment proof after enrolled", unit: "days", def: 7, max: 90 },
  { key: "duplicate_hours", label: "Duplicate claim window", unit: "hours", def: 24, max: 720 },
];

export const CHECKLIST_LABEL: Record<string, { title: string; pending: string }> = {
  agreement: { title: "Agreement and data-processing terms uploaded", pending: "Partner documents come with the next build" },
  programmes: { title: "Programme file published in the Programme Repository", pending: "" },
  credentials: { title: "Endpoint, API credential and signing secret set", pending: "" },
  mapping: { title: "Stage and field mapping published, every gate at 100%", pending: "" },
  sla_hours: { title: "SLAs and working hours set", pending: "" },
  branding: { title: "Student-facing brand: display name, logo and colour", pending: "" },
  test_leads: { title: "A test lead accepted by the partner's sandbox", pending: "" },
};

export const DEFAULT_WORKING_HOURS: WorkingHours = {
  mon: { open: "10:00", close: "19:00" },
  tue: { open: "10:00", close: "19:00" },
  wed: { open: "10:00", close: "19:00" },
  thu: { open: "10:00", close: "19:00" },
  fri: { open: "10:00", close: "19:00" },
  sat: { open: "10:00", close: "17:00" },
  sun: null,
};

/** Display name first: it is what students see. */
export const partnerTitle = (p: Pick<Partner, "display_name" | "name">) => p.display_name || p.name;

/** Black or white text, whichever reads better on a #RRGGBB background (WCAG relative luminance). */
export function textOn(hex: string | null | undefined): "#0F1729" | "#FFFFFF" {
  if (!hex || !/^#[0-9a-f]{6}$/i.test(hex)) return "#FFFFFF";
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  }) as [number, number, number];
  const L = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return (L + 0.05) / 0.05 > 1.05 / (L + 0.05) ? "#0F1729" : "#FFFFFF";
}

/** Up to two initials for the logo placeholder. */
export function initials(name: string): string {
  const words = name.replace(/[^\p{L}\p{N} ]/gu, " ").trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) return "?";
  return (words.length === 1 ? words[0]!.slice(0, 2) : words[0]![0]! + words[1]![0]!).toUpperCase();
}

/** "Mon–Fri 10:00–19:00 · Sat 10:00–17:00" from working hours; consecutive days with the same hours collapse. */
export function summariseHours(w: Partial<WorkingHours>): string {
  const parts: string[] = [];
  let i = 0;
  while (i < DAYS.length) {
    const h = w[DAYS[i]!];
    if (!h) { i++; continue; }
    let j = i;
    while (j + 1 < DAYS.length && w[DAYS[j + 1]!]?.open === h.open && w[DAYS[j + 1]!]?.close === h.close) j++;
    const name = (d: Day) => DAY_LABEL[d].slice(0, 3);
    parts.push(`${i === j ? name(DAYS[i]!) : `${name(DAYS[i]!)}–${name(DAYS[j]!)}`} ${h.open}–${h.close}`);
    i = j + 1;
  }
  return parts.length ? parts.join(" · ") : "Closed every day";
}

// ---------- form ----------

const https = z.string().trim().max(500).refine((v) => v === "" || /^https:\/\/[^\s/$.?#].[^\s]*$/i.test(v), "Must start with https://");
const optInt = (max: number) =>
  z.string().trim().refine((v) => v === "" || (/^\d+$/.test(v) && Number(v) <= max), `Whole number up to ${max}`)
    .transform((v) => (v === "" ? null : Number(v)));
const list = z.string().max(2000).transform((v) => [...new Set(v.split(/[,\n]/).map((s) => s.trim()).filter(Boolean))].slice(0, 100));
const time = /^([01]\d|2[0-3]):[0-5]\d$/;

const Base = z.object({
  id: z.string().regex(/^\d*$/).transform((v) => (v ? Number(v) : null)),
  name: z.string().trim().min(1, "Required").max(120),
  slug: z.string().trim().toLowerCase().regex(/^[a-z0-9][a-z0-9-]{1,39}$/, "2 to 40 lowercase letters, digits or hyphens"),
  display_name: z.string().trim().max(120),
  logo_url: https,
  brand_color: z.string().trim().refine((v) => v === "" || /^#[0-9a-f]{6}$/i.test(v), "A colour like #0B2F5E"),
  adapter_type: z.enum(ADAPTERS),
  api_base_url: https,
  test_endpoint: https,
  dedupe_mode: z.enum(DEDUPE_MODES),
  hold_minutes: optInt(1440),
  duplicate_window_hours: optInt(720),
  notify_enabled: z.string().optional().transform((v) => v === "on"),
  daily_cap: optInt(100000),
  monthly_cap: optInt(1000000),
  contract_min_monthly: optInt(1000000),
  holidays: z.string().max(4000).transform((v, ctx) => {
    const out = new Set<string>();
    for (const raw of v.split(/[,\n]/).map((s) => s.trim()).filter(Boolean)) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(raw) || Number.isNaN(Date.parse(`${raw}T00:00:00Z`))) {
        ctx.addIssue({ code: "custom", message: `Not a date (YYYY-MM-DD): ${raw.slice(0, 20)}` });
        return z.NEVER;
      }
      out.add(raw);
    }
    return [...out].sort();
  }),
  states_include: list,
  states_exclude: list,
  sources_exclude: list,
  criteria_other: z.string().trim().max(2000),
  notes: z.string().trim().max(4000),
});

export type PartnerPayload = Record<string, unknown> & { id: number | null; slug: string; name: string };
export type FieldErrors = Partial<Record<string, string>>;

/** FormData from the partner form → the b2b.partner_save payload, or field errors. */
export function parsePartnerForm(form: FormData): { ok: true; data: PartnerPayload } | { ok: false; errors: FieldErrors } {
  const get = (k: string) => {
    const v = form.get(k);
    return typeof v === "string" ? v : "";
  };
  const raw = Object.fromEntries(Object.keys(Base.shape).map((k) => [k, k === "notify_enabled" ? (form.get(k) ?? undefined) : get(k)]));
  const parsed = Base.safeParse(raw);
  const errors: FieldErrors = {};
  if (!parsed.success) for (const i of parsed.error.issues) errors[String(i.path[0])] ??= i.message;

  const hours = {} as WorkingHours;
  for (const d of DAYS) {
    if (form.get(`wh_${d}_on`) !== "on") { hours[d] = null; continue; }
    const open = get(`wh_${d}_open`), close = get(`wh_${d}_close`);
    if (!time.test(open) || !time.test(close) || open >= close) { errors[`wh_${d}`] = "Opening time must be before closing time"; hours[d] = null; continue; }
    hours[d] = { open, close };
  }

  const sla: Partial<Sla> = {};
  for (const f of SLA_FIELDS) {
    const v = get(`sla_${f.key}`).trim();
    if (!/^\d+$/.test(v) || Number(v) < 1 || Number(v) > f.max) { errors[`sla_${f.key}`] = `1 to ${f.max} ${f.unit}`; continue; }
    sla[f.key] = Number(v);
  }

  if (!parsed.success || Object.keys(errors).length) return { ok: false, errors };
  const d = parsed.data;
  const criteria: LeadCriteria = {};
  if (d.states_include.length) criteria.states_include = d.states_include;
  if (d.states_exclude.length) criteria.states_exclude = d.states_exclude;
  if (d.sources_exclude.length) criteria.sources_exclude = d.sources_exclude;
  if (d.criteria_other) criteria.other = d.criteria_other;

  return {
    ok: true,
    data: {
      id: d.id,
      name: d.name,
      slug: d.slug,
      display_name: d.display_name,
      logo_url: d.logo_url,
      brand_color: d.brand_color.toUpperCase(),
      adapter_type: d.adapter_type,
      api_base_url: d.api_base_url,
      test_endpoint: d.test_endpoint,
      dedupe_mode: d.dedupe_mode,
      hold_minutes: d.dedupe_mode === "sync" ? 0 : (d.hold_minutes ?? 30),
      duplicate_window_hours: d.duplicate_window_hours ?? 24,
      notify_enabled: d.notify_enabled,
      daily_cap: d.daily_cap,
      monthly_cap: d.monthly_cap,
      contract_min_monthly: d.contract_min_monthly,
      working_hours: hours,
      holidays: d.holidays,
      sla,
      lead_criteria: criteria,
      notes: d.notes,
    },
  };
}

/** A URL-safe slug suggestion from a name: "Acme Edu Pvt. Ltd." → "acme-edu-pvt-ltd". */
export function slugify(name: string): string {
  return name.toLowerCase().normalize("NFKD").replace(/[^\w\s-]/g, "").replace(/[\s_]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
}
