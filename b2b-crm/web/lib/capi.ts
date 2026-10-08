/** Conversion feedback to Meta and Google (spec B11; Addendum 3 D38): labels, types, the attribution helpers and the
 *  settings forms' checks. 'Paid' is one Meta/Google-only label (b2b.lead_attribution) shared with routing, campaigns and
 *  analytics; it changes no routing. */
import type { z } from "zod";
import { AttributionSchema, type AttributionSettings } from "@/lib/routing";

/** Signals, strongest first. CAPI tells Meta and Google how far each paid lead got, so they bid for students who enrol:
 * enrolled (verified) → applicant → interested → qualified. The weak ones below are off by default. */
export const STAGES = ["verified", "enrolled", "applied", "interested", "qualified", "contacted", "partner_accepted", "lead", "disqualified"] as const;
export type Stage = (typeof STAGES)[number];
export type Platform = "meta" | "google";

export const STAGE_LABEL: Record<Stage, { label: string; hint: string; strength?: "strongest" | "strong" | "medium" | "early" }> = {
  verified: { label: "Enrolment verified", strength: "strongest", hint: "Proof checked. Value: the realised net commission (₹)." },
  enrolled: { label: "Enrolled", strength: "strongest", hint: "Enrolment reported. Value: the expected net commission (₹)." },
  applied: { label: "Applicant", strength: "strong", hint: "The student applied to the programme. Value: a share of the expected commission." },
  interested: { label: "Interested", strength: "medium", hint: "Counselled or further, as the partner's CRM or the B2C CRM reports. Value: a share of the expected commission." },
  qualified: { label: "Qualified lead", strength: "early",
    hint: "Classed as qualified: the engine decided it (to a partner or to Eduwit's B2C sales team), a partner-sharing consent was requested, or a partner received it. A nurture hand-off alone does not count, nor does junk. Value: a share of the expected commission." },
  contacted: { label: "Contacted", hint: "Weak signal: the first call or message reached the student." },
  partner_accepted: { label: "Accepted", hint: "Weak signal: a partner accepted the lead, or Eduwit's B2C team took it." },
  lead: { label: "Lead received", hint: "The enquiry itself. Off: the ad platform already counts its own leads." },
  disqualified: { label: "Disqualified (junk)", hint: "Sent only when the junk signal is on (Routing → Hand-off rules)." },
};

export const STRENGTH_LABEL: Record<NonNullable<(typeof STAGE_LABEL)[Stage]["strength"]>, string> = {
  strongest: "Strongest", strong: "Strong", medium: "Medium", early: "Early",
};

/** Signals whose value is a share of the lead's expected commission (enrolled and verified carry the commission itself). */
export const VALUE_STAGES = ["applied", "interested", "qualified"] as const;
export type ValueStage = (typeof VALUE_STAGES)[number];
export type SignalValues = { values: Record<ValueStage, number>; base_value_inr: number };
export const DEFAULT_VALUES: SignalValues = { values: { qualified: 0.05, interested: 0.15, applied: 0.4 }, base_value_inr: 15000 };

/** Problems with the values form (shares as percentages). Mirrors b2b.capi_settings_save. */
export function valuesProblems(v: { pct: Record<ValueStage, string>; base: string }): Record<string, string> {
  const e: Record<string, string> = {};
  for (const k of VALUE_STAGES) {
    const n = Number(v.pct[k]);
    if (v.pct[k].trim() === "" || !Number.isFinite(n) || n < 0 || n > 100) e[`values.${k}`] = "A percentage from 0 to 100.";
  }
  const b = Number(v.base);
  if (v.base.trim() === "" || !Number.isFinite(b) || b < 0 || b > 10_000_000) e.base = "Rupees, up to 1,00,00,000.";
  const [ap, int, qu] = VALUE_STAGES.map((k) => Number(v.pct[k])) as [number, number, number];
  if (!e["values.applied"] && !e["values.interested"] && !e["values.qualified"] && !(ap >= int && int >= qu)) {
    e.order = "Stronger signals should be worth at least as much: applicant ≥ interested ≥ qualified.";
  }
  return e;
}

export type CampaignRow = {
  platform: "meta" | "google" | "other"; campaign_key: string; campaign_id: string | null; campaign_name: string | null;
  leads: number; matchable: number; qualified: number; interested: number; applied: number; enrolled: number; verified: number; junk: number;
  commission: number; events_sent: number; last_lead_at: string | null;
};
/** b2b.capi_campaigns: paid campaigns only; `unpaid` counts the period's leads that are not paid (UTM only, organic,
 *  influencer or referral, no ad), which are never reported. */
export type CapiCampaigns = { days: number; campaigns: CampaignRow[]; unpaid: number };

/** a ÷ b as a whole percentage, or null when b is 0. */
export function rate(a: number, b: number): number | null {
  return b > 0 ? Math.round((a / b) * 100) : null;
}

// ---------- attribution (Addendum 3, D38): 'paid' means a Meta or Google ad brought the lead, nothing else ----------

/** b2b.lead_attribution's signal (m31b): what made the lead paid, or why it is not. */
export const ATTRIBUTION_SIGNALS = [
  "meta_lead_form", "ctwa_clid", "witty_ad_referral", "fbclid", "fbc", "google_lead_form", "gclid", "gbraid", "wbraid",
  "influencer_referral", "excluded_campaign", "organic_form", "utm_only", "none",
] as const;
export type AttributionSignal = (typeof ATTRIBUTION_SIGNALS)[number];

export const SIGNAL_LABEL: Record<AttributionSignal, string> = {
  meta_lead_form: "Meta lead form (not organic)",
  ctwa_clid: "Meta click-to-WhatsApp ad (ctwa_clid)",
  witty_ad_referral: "Meta click-to-WhatsApp ad (Witty referral)",
  fbclid: "Meta ad click (fbclid with a Meta ad parameter)",
  fbc: "Meta ad click (fbc cookie with a Meta ad parameter)",
  google_lead_form: "Google Ads lead form",
  gclid: "Google ad click (gclid)",
  gbraid: "Google ad click (gbraid)",
  wbraid: "Google ad click (wbraid)",
  influencer_referral: "Influencer or referral marker",
  excluded_campaign: "Campaign on the never-paid list",
  organic_form: "Organic Meta form",
  utm_only: "UTM tags only",
  none: "No ad signal",
};

/** Why a lead is not paid, in the lead check. Paid signals have no entry. */
export const NOT_PAID_HINT: Partial<Record<AttributionSignal, string>> = {
  influencer_referral: "An influencer or referral marker always means not paid, whatever else the lead carries.",
  excluded_campaign: "Its campaign name is on the never-paid list (Setup → Attribution).",
  organic_form: "Meta marks this lead form organic: no ad was paid for it.",
  utm_only: "UTM tags alone do not make a lead paid (Addendum 3): only a Meta lead form, a Meta or Google click ID or a click-to-WhatsApp ad does.",
  none: "No ad identifier, lead form or UTM tag was found on the lead or its touchpoints.",
};
export const NOT_MATCHABLE_HINT = "Paid, but there is no lead ID or click ID CAPI can send (a click-to-WhatsApp lead carries none), so nothing is reported.";

/** b2b.lead_campaign_detect (m31g) as capi_lead_check returns it: the attribution (from b2b.lead_attribution) plus the
 *  touch that carried it. `origin` is where it was read: 'meta_lead_form' | 'google_lead_form' (intake), a touchpoint's
 *  source_system, 'touchpoint', or 'lead' (the lead row). */
export type LeadCampaign = {
  platform: "meta" | "google" | "other" | "none"; paid: boolean; matchable: boolean;
  signal: AttributionSignal | null;
  /** 'Meta Lead Ads' | 'Meta click-to-WhatsApp' | 'Meta ad click' | 'Google lead form' | 'Google ad click'; null when not paid. */
  label: string | null;
  origin: string | null;
  /** The click key CAPI matches on (leadgen_id, fbclid, fbc, google_lead_id, gclid, gbraid, wbraid; ctwa_clid is paid but unmatchable); paid only. */
  click_key?: string | null; kind?: string | null; is_organic?: boolean | null; leadgen_id?: string | null; google_lead_id?: string | null;
  click_ids?: Record<string, string | null> | null;
  campaign_id?: string | null; campaign_name?: string | null; adset_id?: string | null; adset_name?: string | null; ad_id?: string | null; ad_name?: string | null;
  form_id?: string | null; utm?: Record<string, string | null>; at?: string | null; touched_at?: string | null;
};

type AttributionLike = { paid: boolean; platform: LeadCampaign["platform"]; label?: string | null; signal?: string | null };

/** One line for a lead's attribution: "Paid: Meta Lead Ads", "Not paid: UTM only", "Not paid: influencer or referral"… */
export function attributionLabel(c: AttributionLike): string {
  if (c.paid) return `Paid: ${c.label ?? (c.platform === "meta" ? "Meta ad" : c.platform === "google" ? "Google ad" : "ad")}`;
  switch (c.signal) {
    case "utm_only": return "Not paid: UTM only";
    case "influencer_referral": return "Not paid: influencer or referral";
    case "excluded_campaign": return "Not paid: excluded campaign";
    case "organic_form": return "Not paid: organic";
    default: return "Not paid: no ad";
  }
}

/** Where the attribution was read from (lead_campaign_detect.origin), as words. */
export function originLabel(origin: string | null | undefined): string {
  switch (origin) {
    case null: case undefined: case "": return "—";
    case "meta_lead_form": return "Meta lead form intake";
    case "google_lead_form": return "Google lead form intake";
    case "lead": return "the lead record";
    case "touchpoint": return "a touchpoint";
    case "witty": return "a Witty touchpoint";
    default: return `a ${origin} touchpoint`;
  }
}

/** The stored `attribution` setting with its version (b2b.settings 'attribution': m31a seed, m31g attribution_settings_save). */
export type CapiAttribution = { value: AttributionSettings; version: number | null; updated_at: string | null };

/** The Attribution card's fields: each list as comma- or line-separated text (lib/routing AttributionSchema), plus the reason. */
export type AttributionForm = z.input<typeof AttributionSchema>;
export const ATTRIBUTION_LIST_FIELDS = ["influencer_lead_sources", "influencer_utm_values", "exclude_campaigns", "meta_ad_params"] as const;
export type AttributionListField = (typeof ATTRIBUTION_LIST_FIELDS)[number];

const joinList = (a: unknown): string => (Array.isArray(a) ? a.filter((s): s is string => typeof s === "string").join(", ") : "");

/** The card's starting text from the stored setting (missing keys read as empty). */
export function attributionDefaults(s: AttributionSettings | null | undefined): Record<AttributionListField, string> {
  return {
    influencer_lead_sources: joinList(s?.influencer_markers?.lead_sources),
    influencer_utm_values: joinList(s?.influencer_markers?.utm_values),
    exclude_campaigns: joinList(s?.exclude_campaigns),
    meta_ad_params: joinList(s?.meta_ad_params),
  };
}

/** What is wrong with the Attribution card, field by field (AttributionSchema, which mirrors b2b.attribution_settings_save:
 *  up to 50 entries of at most 60 characters each, meta_ad_params as parameter names, a reason of 3 to 300 characters). */
export function attributionProblems(f: AttributionForm): Record<string, string> {
  const p = AttributionSchema.safeParse(f);
  if (p.success) return {};
  const e: Record<string, string> = {};
  for (const i of p.error.issues) {
    const k = String(i.path[0] ?? "form");
    if (!e[k]) e[k] = i.message;
  }
  return e;
}

export const EVENT_STATUS: Record<string, { label: string; tone: "success" | "info" | "warning" | "danger" | "neutral" | "brand"; hint: string }> = {
  pending: { label: "Due", tone: "info", hint: "Goes out on the next run (every minute)." },
  sending: { label: "Sending", tone: "info", hint: "Sent; waiting for the platform's answer." },
  sent: { label: "Sent", tone: "success", hint: "The platform accepted it." },
  failed: { label: "Retrying", tone: "warning", hint: "Failed; tried again after 1, 5 and 30 minutes, 2 and 6 hours." },
  rejected: { label: "Rejected", tone: "danger", hint: "The platform refused it (for example the click is too old). Not retried." },
  dead: { label: "Gave up", tone: "danger", hint: "Failed six times." },
  held: { label: "Held", tone: "warning", hint: "Waiting: the platform is switched off or not set up. Goes once it can, if still recent enough." },
  dry_run: { label: "Dry run", tone: "brand", hint: "A test lead: built and logged, never sent." },
  skipped: { label: "Skipped", tone: "neutral", hint: "Not sent: no consent, not paid, or older than the platform accepts." },
};

export const MATCH_KEY_LABEL: Record<string, string> = {
  lead_id: "Meta lead ID", leadgen_id: "Meta lead ID", email: "Email (hashed)", phone: "Phone (hashed)", fbc: "Click (fbc)", fbp: "Browser (fbp)", fbclid: "Click (fbclid)",
  gclid: "gclid", gbraid: "gbraid", wbraid: "wbraid", google_lead_id: "Google lead ID", ctwa_clid: "Click-to-WhatsApp (ctwa_clid)",
};

export const BLOCKER_LABEL: Record<string, string> = {
  "no dataset ID": "Add the Meta dataset (pixel) ID",
  "no access token": "Add the Conversions API access token",
  "no customer ID": "Add the Google Ads customer ID",
  "no developer token": "Add the Google Ads developer token",
  "no OAuth client or refresh token": "Add the OAuth client ID, client secret and refresh token",
};

export type MetaMap = Record<Stage, { event: string; enabled: boolean }>;
export type GoogleMap = Record<Stage, { action: string | null; enabled: boolean }>;

export type CapiOverview = {
  settings: {
    consent: "marketing" | "sales";
    junk_signal: boolean;
    meta: { dataset_id: string | null; api_version: string | null; test_event_code: string | null; window_days: number | null; token: boolean; map: MetaMap };
    google: { customer_id: string | null; login_customer_id: string | null; api_version: string | null; client_id: string | null; window_days: number | null;
              developer_token: boolean; client_secret: boolean; refresh_token: boolean; token_error: string | null; map: GoogleMap };
  };
  switches: Record<Platform, { live: boolean; blockers: string[]; switched_at: string | null }>;
  status: Record<string, number>;
  events: { platform: Platform; stage: Stage; event_name: string; sent: number; sent_7d: number; waiting: number; failed: number; value_inr: number | null }[];
  match: Partial<Record<Platform, { events: number; keys: Record<string, number> }>>;
  log: CapiEvent[];
  /** The 'attribution' setting (what counts as paid), read beside b2b.capi_overview by lib/capi-data. */
  attribution: CapiAttribution;
};

export type CapiEvent = {
  id: number; lead_id: number; name: string | null; platform: Platform; stage: Stage; event_name: string; event_id: string; occurred_at: string;
  value_inr: number | null; is_test: boolean; status: string; reason: string | null; error: string | null; attempts: number; match_keys: string[];
  created_at: string; sent_at: string | null;
};

export type LeadCheck = {
  lead: { id: number; name: string | null; is_test: boolean; cycle_no: number; has_email: boolean; deleted: boolean };
  ids: Record<string, string>;
  campaign: LeadCampaign;
  consent: { rule: "marketing" | "sales"; sales_at: string | null; marketing_at: string | null; opted_out: boolean };
  milestones: { stage: Stage; at: string; value_inr: number | null; meta: { name: string; match_keys: string[]; payload: unknown } | null;
                google: { name: string; match_keys: string[]; payload: unknown } | null }[];
  events: { id: number; platform: Platform; stage: Stage; status: string; reason: string | null; error: string | null; sent_at: string | null }[];
  written: number | null;
};

/** Share of logged events carrying a match key, as a whole percentage. */
export function keyShare(m: { events: number; keys: Record<string, number> } | undefined, key: string): number {
  if (!m || m.events === 0) return 0;
  return Math.round(((m.keys[key] ?? 0) / m.events) * 100);
}

/** Totals for one platform from the status counts ("meta.sent": 12, …). */
export function platformTotals(status: Record<string, number>, p: Platform) {
  const get = (s: string) => status[`${p}.${s}`] ?? 0;
  return { sent: get("sent"), waiting: get("pending") + get("sending") + get("held"), problems: get("failed") + get("dead") + get("rejected"),
           dry_run: get("dry_run"), skipped: get("skipped") };
}

export const GOOGLE_ACTION_RE = /^customers\/\d{10}\/conversionActions\/\d{1,20}$/;
export const CUSTOMER_ID_RE = /^\d{3}-?\d{3}-?\d{4}$/;

/** What is wrong with the setup form, field by field. Mirrors b2b.capi_settings_save. */
export function settingsProblems(f: { meta: { dataset_id: string; api_version: string; map: MetaMap }; google: { customer_id: string; login_customer_id: string; api_version: string; map: GoogleMap } }): Record<string, string> {
  const e: Record<string, string> = {};
  if (f.meta.dataset_id && !/^\d{5,25}$/.test(f.meta.dataset_id.trim())) e["meta.dataset_id"] = "The dataset (pixel) ID is a number.";
  if (f.meta.api_version && !/^v\d{1,2}\.\d$/.test(f.meta.api_version.trim())) e["meta.api_version"] = "Looks like v21.0.";
  if (f.google.api_version && !/^v\d{1,3}$/.test(f.google.api_version.trim())) e["google.api_version"] = "Looks like v21.";
  if (f.google.customer_id && !CUSTOMER_ID_RE.test(f.google.customer_id.trim())) e["google.customer_id"] = "10 digits, like 123-456-7890.";
  if (f.google.login_customer_id && !CUSTOMER_ID_RE.test(f.google.login_customer_id.trim())) e["google.login_customer_id"] = "10 digits, like 123-456-7890.";
  for (const s of STAGES) {
    const m = f.meta.map[s];
    if (m && (!m.event.trim() || m.event.trim().length > 50)) e[`meta.map.${s}`] = "An event name of up to 50 characters.";
    const g = f.google.map[s];
    if (g?.action && !GOOGLE_ACTION_RE.test(g.action.trim())) e[`google.map.${s}`] = "Like customers/1234567890/conversionActions/987654321.";
  }
  return e;
}

export function formatInr(v: number | null | undefined): string {
  if (v === null || v === undefined) return "—";
  return "₹" + Math.round(v).toLocaleString("en-IN");
}
