/** Conversion feedback to Meta and Google (spec B11): labels, types and the settings form's checks. */

export const STAGES = ["lead", "ready_to_route", "partner_accepted", "contacted", "applied", "enrolled", "verified", "disqualified"] as const;
export type Stage = (typeof STAGES)[number];
export type Platform = "meta" | "google";

export const STAGE_LABEL: Record<Stage, { label: string; hint: string }> = {
  lead: { label: "Lead received", hint: "The enquiry itself. Off by default: the ad platform already counts its own leads." },
  ready_to_route: { label: "Ready to route", hint: "The lead was qualified and sent to a partner or to B2C." },
  partner_accepted: { label: "Accepted", hint: "A partner accepted the lead, or Eduwit's B2C team took it." },
  contacted: { label: "Contacted", hint: "The first call or message reached the student." },
  applied: { label: "Applied", hint: "The student applied to the programme." },
  enrolled: { label: "Enrolled", hint: "Enrolment reported. Value: the expected net commission (₹)." },
  verified: { label: "Enrolment verified", hint: "Proof checked. Value: the realised net commission (₹)." },
  disqualified: { label: "Disqualified (junk)", hint: "Sent only when the junk signal is on (Routing → Hand-off rules)." },
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
