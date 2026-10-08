import { z } from "zod";
import { isCrmAdapter } from "@/lib/adapters";
import type { EffortDetail, Stage } from "@/lib/segments";

/** Partners: types, labels and form parsing. Pure, so the server action and the tests share one definition. */

export const ADAPTERS = ["leadsquared", "salesforce", "zoho", "meritto", "hubspot", "inhouse", "generic_rest", "webhook"] as const;
export const DEDUPE_MODES = ["async", "sync", "none"] as const;
export const STATUSES = ["onboarding", "active", "paused", "closed"] as const;
export const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;
export const CRITERIA_UNKNOWN = ["pass", "fail"] as const;

export type Adapter = (typeof ADAPTERS)[number];
export type DedupeMode = (typeof DEDUPE_MODES)[number];
export type PartnerStatus = (typeof STATUSES)[number];
export type Day = (typeof DAYS)[number];
export type CriteriaUnknown = (typeof CRITERIA_UNKNOWN)[number];
export type WorkingHours = Record<Day, { open: string; close: string } | null>;

export type Sla = {
  first_contact_hours: number;
  first_connect_days: number;
  status_update_days: number;
  outcome_days: number;
  proof_days: number;
  duplicate_hours: number;
};

/**
 * partners.lead_criteria (m31i partner_save validates the same keys). Lists are names (≤ 100 of ≤ 80 chars); `unknown` says what
 * happens when the lead's state, city, qualification, score or experience is not known: 'pass' sends the lead anyway, 'fail' does
 * not; absent → the engine setting (criteria_unknown, default 'fail') applies (D32).
 */
export type LeadCriteria = {
  states_include?: string[];
  states_exclude?: string[];
  cities_include?: string[];
  cities_exclude?: string[];
  qualifications_include?: string[];
  min_academic_pct?: number | null;
  min_work_experience_years?: number | null;
  sources_exclude?: string[];
  unknown?: CriteriaUnknown;
  other?: string;
};

/** partners.push_options (m31a). interests_array: send the structured `interests[]` with the push (D44); the note always lists them. */
export type PushOptions = { interests_array?: boolean };

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
  /** Derived by the database from dedupe_mode (D37): 0 for sync, 30 otherwise. */
  hold_minutes: number;
  /** Always 24 (D37). */
  duplicate_window_hours: number;
  /** When the Admin confirmed that this CRM blocks duplicates on create (Connection tab); required before a CRM adapter is 'sync'. */
  dedupe_confirmed_at: string | null;
  agreement_confirmed_at?: string | null;
  agreement_confirmed_by?: string | null;
  agreement_note?: string | null;
  push_options: PushOptions;
  notify_enabled: boolean;
  daily_cap: number | null;
  monthly_cap: number | null;
  contract_min_monthly: number | null;
  working_hours: Partial<WorkingHours>;
  holidays: string[];
  sla: Partial<Sla>;
  lead_criteria: LeadCriteria;
  paused_reason: string | null;
  /** Set when the engine paused the partner (m31c guard_tick); cleared by the next status change. */
  auto_paused_at: string | null;
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

/** partner_detail.auto_pause (m31l): why the engine paused the partner; active while the status is still 'paused'. */
export type AutoPause = { reason: string | null; at: string; active: boolean };

/** One 3-part segment row of partner_segment_stats (variant 'base') the partner received leads in (m31l partner_detail.factors.segments). */
export type PartnerSegmentFactors = {
  segment: string;
  auto_stage: Stage | null;
  n_received: number;
  first_lead_at: string | null;
  n_matured_c: number;
  leads_30d: number;
  p_hat: number | null;
  effort_factor: number | null;
  has_activity: boolean | null;
  effort_detail: EffortDetail | null;
  sla_adherence: number | null;
  sla_factor: number | null;
  refund_rate: number | null;
};

/** partner_detail.factors (m31l): the Stage B/C factors the engine applies to this partner, partner-wide and per segment. */
export type PartnerFactors = {
  sla_adherence: number | null;
  sla_factor: number | null;
  sla_met: number | null;
  sla_total: number | null;
  /** n_received-weighted over the partner's 3-part segment rows; null before the first refresh. */
  effort_factor: number | null;
  /** False when no call or activity data was synced in the window: the effort factor is capped at 1.0 (D27). */
  has_activity: boolean;
  n_received: number;
  stats_at: string | null;
  segments: PartnerSegmentFactors[];
};

export type PartnerDetail = {
  partner: Partner;
  checklist: ChecklistItem[];
  leads_month: number;
  leads_total: number;
  events: { at: string; type: string; actor: string; payload: Record<string, unknown> }[];
  auto_pause?: AutoPause | null;
  factors?: PartnerFactors | null;
};

// ---------- fixed by Addendum 3 (engine.a3_fixed; D37) ----------

/** The hold window follows dedupe_mode: a CRM that refuses duplicates in the create call needs none, every other partner gets 30 minutes. */
export const HOLD_MINUTES: Record<DedupeMode, number> = { sync: 0, async: 30, none: 30 };
/** Duplicate claims after acceptance count as commission disputes only inside this window (PART 5.8). */
export const DUPLICATE_WINDOW_HOURS = 24;

export const derivedHoldMinutes = (mode: DedupeMode): number => HOLD_MINUTES[mode];

/** "0 min (confirmed duplicate-blocking CRM)" / "0 min (duplicates refused on create)" / "30 min". */
export function holdWindowText(p: Pick<Partner, "dedupe_mode"> & Partial<Pick<Partner, "dedupe_confirmed_at">>): string {
  if (p.dedupe_mode !== "sync") return `${HOLD_MINUTES[p.dedupe_mode]} min`;
  return p.dedupe_confirmed_at ? "0 min (confirmed duplicate-blocking CRM)" : "0 min (duplicates refused on create)";
}

export const duplicateWindowText = () => `${DUPLICATE_WINDOW_HOURS} hours, fixed by Addendum 3`;

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
  async: { label: "Later, by webhook or poll", hint: "Duplicates arrive after the push; a 30-minute hold window re-routes them before the student is told." },
  sync: {
    label: "At once, on create",
    hint: "The CRM refuses a duplicate in the create call, so there is no hold window. A CRM adapter becomes 'at once' only after you confirm in the Connection tab that the CRM blocks duplicates on create.",
  },
  none: { label: "Never", hint: "The partner does not report duplicates. The 30-minute hold window still applies." },
};

export const STATUS_LABEL: Record<PartnerStatus, string> = { onboarding: "Onboarding", active: "Active", paused: "Paused", closed: "Closed" };
export const STATUS_TONE: Record<PartnerStatus, "info" | "success" | "warning" | "neutral"> = {
  onboarding: "info",
  active: "success",
  paused: "warning",
  closed: "neutral",
};

export const DAY_LABEL: Record<Day, string> = { mon: "Monday", tue: "Tuesday", wed: "Wednesday", thu: "Thursday", fri: "Friday", sat: "Saturday", sun: "Sunday" };

export const CRITERIA_UNKNOWN_LABEL: Record<CriteriaUnknown, { label: string; hint: string }> = {
  pass: { label: "Send the lead", hint: "A lead whose state, city, qualification, score or experience is not known still counts as meeting the criteria." },
  fail: { label: "Do not send", hint: "Unknown data cannot be shown to meet the criteria, so the lead goes to another partner or to B2C." },
};

/**
 * SLA fields. `rulebook` is the bound Addendum 3 fixes (PART 4: first call within 2 working hours, a status update every 7 days,
 * enrolment proof within 7 days): a partner may promise less time, never more, and partner_save refuses a looser value. `fixed`
 * marks a value the Admin cannot change (the 24-hour duplicate claim window, D37).
 */
export type SlaField = { key: keyof Sla; label: string; unit: "hours" | "days"; def: number; max: number; rulebook?: number; fixed?: number };
export const SLA_FIELDS: SlaField[] = [
  { key: "first_contact_hours", label: "First contact attempt", unit: "hours", def: 2, max: 72, rulebook: 2 },
  { key: "first_connect_days", label: "First connected conversation", unit: "days", def: 1, max: 30 },
  { key: "status_update_days", label: "Status update while open", unit: "days", def: 7, max: 60, rulebook: 7 },
  { key: "outcome_days", label: "Counselling outcome recorded", unit: "days", def: 5, max: 60 },
  { key: "proof_days", label: "Enrollment proof after enrolled", unit: "days", def: 7, max: 90, rulebook: 7 },
  { key: "duplicate_hours", label: "Duplicate claim window", unit: "hours", def: DUPLICATE_WINDOW_HOURS, max: DUPLICATE_WINDOW_HOURS, fixed: DUPLICATE_WINDOW_HOURS },
];

/** The upper bound an SLA input accepts: the rulebook's when it has one. */
export const slaMax = (f: SlaField): number => (f.rulebook === undefined ? f.max : Math.min(f.max, f.rulebook));

export const CHECKLIST_LABEL: Record<string, { title: string; pending: string }> = {
  agreement: { title: "Signed agreement and data-processing terms confirmed", pending: "" },
  programmes: { title: "Programme file published in the Programme Repository", pending: "" },
  credentials: { title: "Endpoint, API credential and signing secret set", pending: "" },
  dedupe: { title: "Confirm whether the CRM blocks duplicates on create", pending: "" },
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

/** True when the partner's lead_criteria restricts anything (the unknown-data rule alone does not). */
export function hasCriteria(c: LeadCriteria | null | undefined): boolean {
  if (!c) return false;
  return Boolean(
    c.states_include?.length || c.states_exclude?.length || c.cities_include?.length || c.cities_exclude?.length || c.qualifications_include?.length
    || c.sources_exclude?.length || c.min_academic_pct != null || c.min_work_experience_years != null || c.other,
  );
}

// ---------- form ----------

const https = z.string().trim().max(500).refine((v) => v === "" || /^https:\/\/[^\s/$.?#].[^\s]*$/i.test(v), "Must start with https://");
const optInt = (max: number) =>
  z.string().trim().refine((v) => v === "" || (/^\d+$/.test(v) && Number(v) <= max), `Whole number up to ${max}`)
    .transform((v) => (v === "" ? null : Number(v)));
/** An optional number with up to one decimal inside [0, max] ("" → null). */
const optNum = (max: number, what: string) =>
  z.string().trim().refine((v) => v === "" || (/^\d{1,3}(\.\d)?$/.test(v) && Number(v) <= max), `${what}: 0 to ${max}`)
    .transform((v) => (v === "" ? null : Number(v)));
/** A list of names: comma- or newline-separated, de-duplicated, ≤ 100 of ≤ 80 characters (partner_save's limits). */
const list = z.string().max(4000).transform((v, ctx) => {
  const out = [...new Set(v.split(/[,\n]/).map((s) => s.trim()).filter(Boolean))];
  const long = out.find((s) => s.length > 80);
  if (long) { ctx.addIssue({ code: "custom", message: `Each name is at most 80 characters: ${long.slice(0, 30)}…` }); return z.NEVER; }
  if (out.length > 100) { ctx.addIssue({ code: "custom", message: "At most 100 names" }); return z.NEVER; }
  return out;
});
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
  /** Shown only for a partner on Eduwit's API contract or a webhook that reports duplicates at once; CRM adapters confirm in the Connection tab. */
  dedupe_confirmed: z.string().optional().transform((v) => v === "on"),
  notify_enabled: z.string().optional().transform((v) => v === "on"),
  push_interests_array: z.string().optional().transform((v) => v === "on"),
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
  cities_include: list,
  cities_exclude: list,
  qualifications_include: list,
  min_academic_pct: optNum(100, "Minimum academic score"),
  min_work_experience_years: optNum(40, "Minimum work experience"),
  sources_exclude: list,
  /** '' = follow the engine setting (D32). */
  criteria_unknown: z.enum(["", "pass", "fail"]),
  criteria_other: z.string().trim().max(2000),
  notes: z.string().trim().max(4000),
});

/** The field names the form posts; checkboxes are read raw (absent = off). */
export const PARTNER_FIELDS = Object.keys(Base.shape) as (keyof typeof Base.shape)[];
const CHECKBOXES: ReadonlySet<string> = new Set(["dedupe_confirmed", "notify_enabled", "push_interests_array"]);

/**
 * Whether the partner form asks the Admin to confirm, itself, that duplicates are refused in the create call: only for a 'sync'
 * partner without a CRM adapter (Eduwit's API contract or a webhook). A CRM adapter is confirmed in the Connection tab
 * (partner_adapter_save), so the form leaves its stamp alone (D37).
 */
export const asksDedupeConfirmation = (adapter: string, dedupe: string): boolean => dedupe === "sync" && !isCrmAdapter(adapter);

export type PartnerPayload = Record<string, unknown> & { id: number | null; slug: string; name: string };
export type FieldErrors = Partial<Record<string, string>>;

/**
 * FormData from the partner form → the b2b.partner_save payload, or field errors. The hold window and the duplicate claim window
 * are never read from the form: the hold follows dedupe_mode (D37) and the window is 24 hours, as the database also enforces.
 */
export function parsePartnerForm(form: FormData): { ok: true; data: PartnerPayload } | { ok: false; errors: FieldErrors } {
  const get = (k: string) => {
    const v = form.get(k);
    return typeof v === "string" ? v : "";
  };
  const raw = Object.fromEntries(PARTNER_FIELDS.map((k) => [k, CHECKBOXES.has(k) ? (form.get(k) ?? undefined) : get(k)]));
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
    if (f.fixed !== undefined) { sla[f.key] = f.fixed; continue; }
    const v = get(`sla_${f.key}`).trim();
    if (!/^\d+$/.test(v) || Number(v) < 1 || Number(v) > f.max) { errors[`sla_${f.key}`] = `1 to ${slaMax(f)} ${f.unit}`; continue; }
    if (f.rulebook !== undefined && Number(v) > f.rulebook) {
      errors[`sla_${f.key}`] = `Cannot be looser than the rulebook: at most ${f.rulebook} ${f.unit}`;
      continue;
    }
    sla[f.key] = Number(v);
  }

  if (!parsed.success || Object.keys(errors).length) return { ok: false, errors };
  const d = parsed.data;
  const criteria: LeadCriteria = {};
  if (d.states_include.length) criteria.states_include = d.states_include;
  if (d.states_exclude.length) criteria.states_exclude = d.states_exclude;
  if (d.cities_include.length) criteria.cities_include = d.cities_include;
  if (d.cities_exclude.length) criteria.cities_exclude = d.cities_exclude;
  if (d.qualifications_include.length) criteria.qualifications_include = d.qualifications_include;
  if (d.min_academic_pct !== null) criteria.min_academic_pct = d.min_academic_pct;
  if (d.min_work_experience_years !== null) criteria.min_work_experience_years = d.min_work_experience_years;
  if (d.sources_exclude.length) criteria.sources_exclude = d.sources_exclude;
  if (d.criteria_unknown) criteria.unknown = d.criteria_unknown;
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
      // the key is sent only when the form asked: absent, partner_save keeps the existing dedupe_confirmed_at
      ...(asksDedupeConfirmation(d.adapter_type, d.dedupe_mode) ? { dedupe_confirmed: d.dedupe_confirmed } : {}),
      hold_minutes: derivedHoldMinutes(d.dedupe_mode),
      duplicate_window_hours: DUPLICATE_WINDOW_HOURS,
      push_options: { interests_array: d.push_interests_array },
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

/**
 * The form field a b2b.partner_save refusal (errcode 22023) belongs to, so the message lands next to the input it is about. The
 * messages are m31i's; null when the message is about the whole form.
 */
export function partnerSaveErrorField(message: string): string | null {
  const m = message.trim().toLowerCase();
  const starts = (...p: string[]) => p.some((s) => m.startsWith(s));
  if (starts("slug", "the slug")) return "slug";
  if (starts("name is required")) return "name";
  if (starts("duplicate handling", "confirm that the crm rejects duplicates")) return "dedupe_mode";
  if (starts("the first-contact sla")) return "sla_first_contact_hours";
  if (starts("the status-update sla")) return "sla_status_update_days";
  if (starts("enrolment proof is due", "enrollment proof is due")) return "sla_proof_days";
  const slaKey = /^sla ([a-z_]+):/.exec(m);
  if (slaKey) return `sla_${slaKey[1]}`;
  if (starts("minimum academic score")) return "min_academic_pct";
  if (starts("minimum work experience")) return "min_work_experience_years";
  if (starts("unknown lead data")) return "criteria_unknown";
  if (starts("lead criteria other")) return "criteria_other";
  const crit = /^(?:lead criteria|unknown lead criterion:) ([a-z_ ]+?)(?::|$)/.exec(m);
  if (crit) {
    const key = crit[1]!.trim().replace(/ /g, "_");
    if (["states_include", "states_exclude", "cities_include", "cities_exclude", "sources_exclude", "qualifications_include"].includes(key)) return key;
    if (key === "min_academic_pct" || key === "min_work_experience_years") return key;
    if (key === "unknown") return "criteria_unknown";
    if (key === "other") return "criteria_other";
    return null;
  }
  if (starts("push options")) return "push_interests_array";
  return null;
}

/** A URL-safe slug suggestion from a name: "Acme Edu Pvt. Ltd." → "acme-edu-pvt-ltd". */
export function slugify(name: string): string {
  return name.toLowerCase().normalize("NFKD").replace(/[^\w\s-]/g, "").replace(/[\s_]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "").slice(0, 40);
}
