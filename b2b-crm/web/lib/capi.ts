/** Conversion feedback to Meta and Google (spec B11): labels, types and the settings form's checks. */

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
  qualified: { label: "Qualified lead", strength: "early", hint: "Routed to a partner or to Eduwit's B2C sales team (not nurture, not junk). Value: a share of the expected commission." },
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
export type CapiCampaigns = { days: number; campaigns: CampaignRow[]; unpaid: number };

/** a ÷ b as a whole percentage, or null when b is 0. */
export function rate(a: number, b: number): number | null {
  return b > 0 ? Math.round((a / b) * 100) : null;
}

export type LeadCampaign = {
  platform: "meta" | "google" | "other" | "none"; paid: boolean; matchable: boolean; origin?: string | null; click_key?: string | null;
  campaign_id?: string | null; campaign_name?: string | null; adset_id?: string | null; adset_name?: string | null; ad_id?: string | null; ad_name?: string | null;
  form_id?: string | null; utm?: Record<string, string | null>; at?: string | null;
};

export const EVENT_STATUS: Record<string, { label: string; tone: "success" | "info" | "warning" | "danger" | "neutral" | "brand"; hint: string }> = {
  pending: { label: "Due", tone: "info", hint: "Goes out on the next run (every minute)." },
  sending: { label: "Sending", tone: "info", hint: "Sent; waiting for the platform's answer." },
  sent: { label: "Sent", tone: "success", hint: "The platform accepted it." },
  failed: { label: "Retrying", tone: "warning", hint: "Failed; tried again after 1, 5 and 30 minutes, 2 and 6 hours." },
  rejected: { label: "Rejected", tone: "danger", hint: "The platform refused it (for example the click is too old). Not retried." },
  dead: { label: "Gave up", tone: "danger", hint: "Failed six times." },
  held: { label: "Held", tone: "warning", hint: "Waiting: the platform is switched off or not set up. Goes once it can, if still recent enough." },
  dry_run: { label: "Dry run", tone: "brand", hint: "A test lead: built and logged, never sent." },
  skipped: { label: "Skipped", tone: "neutral", hint: "Not sent: no consent, or older than the platform accepts." },
};

export const MATCH_KEY_LABEL: Record<string, string> = {
  lead_id: "Meta lead ID", email: "Email (hashed)", phone: "Phone (hashed)", fbc: "Click (fbc)", fbp: "Browser (fbp)",
  gclid: "gclid", gbraid: "gbraid", wbraid: "wbraid",
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
