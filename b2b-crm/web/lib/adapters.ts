/** Partner CRM adapters (m19): what the Admin sets per CRM and environment, and what the status read returns. */

export const CRM_ADAPTERS = ["leadsquared", "zoho", "salesforce", "hubspot", "meritto", "inhouse"] as const;
export type CrmAdapter = (typeof CRM_ADAPTERS)[number];
export const isCrmAdapter = (a: string): a is CrmAdapter => (CRM_ADAPTERS as readonly string[]).includes(a);

export type Env = "live" | "sandbox";

/** Labels, placeholders and hints for every setting and secret key the database asks for. */
export const SETTING_FIELD: Record<string, { label: string; placeholder?: string; hint?: string; optional?: boolean; options?: { value: string; label: string }[] }> = {
  host: { label: "API host", placeholder: "api-in21.leadsquared.com", hint: "LeadSquared → Settings → API and Webhooks shows the host for your region." },
  api_domain: { label: "API domain", placeholder: "www.zohoapis.in", hint: "Data centre of the Zoho account (zohoapis.in for India).", optional: true },
  accounts_domain: { label: "Accounts domain", placeholder: "accounts.zoho.in", optional: true },
  client_id: { label: "OAuth client ID", hint: "From the partner's connected app (Zoho API console / Salesforce connected app)." },
  login_url: { label: "Login URL", placeholder: "https://login.salesforce.com", hint: "Use https://test.salesforce.com for a Salesforce sandbox, or the org's My Domain.", optional: true },
  api_version: { label: "API version", placeholder: "v60.0", optional: true },
  base_url: { label: "API base URL", placeholder: "https://api.nopaperforms.io", optional: true },
  source: { label: "Source name in Meritto", placeholder: "Eduwit", hint: "The lead source Meritto shows for Eduwit's leads.", optional: true },
  // in-house CRM (the partner's own system)
  create_url: { label: "Create-lead address", placeholder: "https://crm.partner.com/api/leads", hint: "The partner's API address that creates a lead (POST, JSON)." },
  auth_type: { label: "How the CRM checks Eduwit's key", hint: "As the partner's API documentation says.", options: [
    { value: "bearer", label: "Bearer token (Authorization: Bearer …)" }, { value: "header", label: "API key in a header" },
    { value: "basic", label: "Basic auth (user:password)" }, { value: "query", label: "API key in the address (?api_key=…)" }, { value: "none", label: "No key (IP allow-list)" }] },
  auth_name: { label: "Header or parameter name", placeholder: "x-api-key", hint: "For a key in a header or in the address.", optional: true },
  wrap_key: { label: "Wrap the lead in", placeholder: "lead", hint: "If the API expects {\"lead\": {…}}. Empty: the fields are sent at the top level.", optional: true },
  record_id_path: { label: "Record ID in the answer", placeholder: "data.id", hint: "Where the new lead's ID is in the CRM's answer. Empty: id, lead_id or data.id are tried.", optional: true },
  duplicate_status: { label: "HTTP status for a duplicate", placeholder: "409", hint: "The code the CRM answers when the student already exists (409 is always read as duplicate).", optional: true },
  poll_url: { label: "Changed-leads address", placeholder: "https://crm.partner.com/api/leads?updated_since={since}",
              hint: "Optional. A GET address listing leads changed since a time; {since} is replaced. Without it, status comes by webhook or the partner's export.", optional: true },
  since_param: { label: "Since parameter", placeholder: "updated_since", hint: "Used when the address has no {since}.", optional: true },
};

export const AUTH_TYPES = ["bearer", "header", "basic", "query", "none"] as const;

export const SECRET_FIELD: Record<string, { label: string; hint: string }> = {
  access_key: { label: "Access key", hint: "Given by the partner; stored in the vault." },
  secret_key: { label: "Secret key", hint: "Given by the partner; stored in the vault." },
  client_secret: { label: "OAuth client secret", hint: "Stored in the vault." },
  refresh_token: { label: "Refresh token", hint: "For an API user the partner created for Eduwit. The access token is renewed from it automatically." },
  token: { label: "Private app token", hint: "HubSpot → Settings → Integrations → Private apps, with contacts read and write scopes." },
};

/** A secret's label for one adapter (the in-house CRM's token is whatever key the partner issues). */
export function secretField(adapter: string, k: string): { label: string; hint: string } {
  if (adapter === "inhouse" && k === "token") return { label: "API key or token", hint: "Issued by the partner for Eduwit; for Basic auth enter user:password. Stored in the vault." };
  return SECRET_FIELD[k] ?? { label: k, hint: "" };
}

export type AdapterEnvStatus = {
  configured: boolean;
  settings: Record<string, unknown> & { reference_field?: string | null; status_field?: string | null; poll?: boolean; poll_minutes?: number; fixed?: Record<string, string> };
  secrets_set: string[];
  state: null | {
    token_valid: boolean | null; token_expires_at: string | null; token_error: string | null; token_failed_at: string | null; instance_url: string | null;
    last_poll_at: string | null; last_poll_result: Record<string, number> | null; last_poll_error: string | null; poll_since: string | null; polling: boolean;
    last_schema_at: string | null; last_schema_error: string | null; fetching_schema: boolean;
  };
};

export type AdapterStatus = {
  adapter: CrmAdapter;
  spec: { label: string; settings: string[]; secrets: string[]; oauth: boolean; poll: boolean; schema: boolean; status_field: string; reference_field: string;
          record_field: string; default_fields: Record<string, string> };
  envs: Record<Env, AdapterEnvStatus>;
  polled_events_7d: number;
  /**
   * D37: whether the Admin confirmed that this CRM refuses a duplicate in the create call (partners.dedupe_confirmed_at). Optional
   * because b2b.partner_adapter_status (m19e) does not return it yet: ConnectionTab fills both from partner_detail's partner row
   * (withDedupe). Partner-wide, not per environment.
   */
  dedupe_confirmed?: boolean;
  dedupe_confirmed_at?: string | null;
};

/** The AdapterStatus with the partner's duplicate-blocking confirmation attached (from partners.dedupe_confirmed_at). */
export function withDedupe<T extends AdapterStatus>(s: T, partner: { dedupe_confirmed_at: string | null } | null | undefined): T {
  if (!partner) return s;
  return { ...s, dedupe_confirmed: partner.dedupe_confirmed_at !== null, dedupe_confirmed_at: partner.dedupe_confirmed_at };
}

// ---------- duplicate handling (D37, rulebook PART 5.1) ----------

/** engine.a3_fixed hold_minutes_sync / hold_minutes_async: 0 minutes for a CRM that refuses duplicates on create, 30 for the rest. */
export const ADAPTER_HOLD_MINUTES = { confirmed: 0, unconfirmed: 30 } as const;
export const DEDUPE_CONFIRM_LABEL = "This CRM blocks duplicates on create";
export const DEDUPE_CONFIRM_HINT = "Tick only if the CRM refuses a duplicate on create; the hold window then drops from 30 to 0 minutes";

/** The hold window partner_adapter_save will set for this answer (confirmed → 'sync', 0 min; otherwise 'async', 30 min). */
export const adapterHoldMinutes = (confirmed: boolean | null | undefined): number => (confirmed ? ADAPTER_HOLD_MINUTES.confirmed : ADAPTER_HOLD_MINUTES.unconfirmed);
export const holdWindowLabel = (confirmed: boolean | null | undefined): string => `Hold window: ${adapterHoldMinutes(confirmed)} min`;

/** What the Admin typed in the adapter form (one environment) plus the partner-wide duplicate-blocking answer. */
export type AdapterSaveForm = {
  env: Env;
  settings: Record<string, string>;
  secrets: Record<string, string>;
  reference_field: string;
  status_field: string;
  poll: boolean;
  poll_minutes: string;
  fixed: { k: string; v: string }[];
  /** The checkbox's answer. Absent or null: the key is not sent and partner_adapter_save keeps the stored confirmation. */
  dedupe_confirmed?: boolean | null;
};

/** The `p` argument of b2b.partner_adapter_save(p_partner_id, p). Empty secrets are left out (the stored ones are kept). */
export function adapterSavePayload(d: AdapterSaveForm): Record<string, unknown> {
  return {
    env: d.env,
    settings: d.settings,
    secrets: Object.fromEntries(Object.entries(d.secrets).filter(([, v]) => v)),
    reference_field: d.reference_field || null,
    status_field: d.status_field || null,
    poll: d.poll,
    ...(d.poll_minutes ? { poll_minutes: Number(d.poll_minutes) } : {}),
    fixed: Object.fromEntries(d.fixed.filter((x) => x.k).map((x) => [x.k, x.v])),
    ...(typeof d.dedupe_confirmed === "boolean" ? { dedupe_confirmed: d.dedupe_confirmed } : {}),
  };
}

export type AdapterPreview = { reference: string; sample: boolean; url: string | null; headers: Record<string, string>; body: unknown; error: string | null };

/** Where each CRM's reference field must be created by the partner (a custom text field). */
export const REFERENCE_HELP: Record<CrmAdapter, string> = {
  leadsquared: "Create a custom lead field (text) such as mx_Eduwit_Reference.",
  zoho: "Create a single-line custom field on Leads, API name Eduwit_Reference. Mark Phone as unique so duplicates are refused.",
  salesforce: "Create a text field Eduwit_Reference__c on Lead and turn on a duplicate rule for Leads (Phone or Email) that blocks.",
  hubspot: "Create a single-line text contact property eduwit_reference.",
  meritto: "Ask Meritto to add an eduwit_reference field to the lead form used for the API.",
  inhouse: "Ask the partner's developer to store eduwit_reference on each lead and return it, with the lead's status, in the changed-leads list. Field names are the CRM's own; a nested one is written as stage.name.",
};

/** A CRM field name; an in-house CRM may use a dotted path (stage.name). */
export const CRM_FIELD_RE = /^[A-Za-z_][A-Za-z0-9_]{0,79}(\.[A-Za-z0-9_]{1,60}){0,4}$/;
const HTTPS_RE = /^https:\/\/[A-Za-z0-9.-]+(:\d+)?(\/\S*)?$/;
const PATH_RE = /^[A-Za-z_][A-Za-z0-9_]{0,59}(\.[A-Za-z0-9_]{1,60}){0,4}$/;

/** What is wrong with an adapter form before it is sent. Mirrors b2b.partner_adapter_save. */
export function adapterProblems(spec: AdapterStatus["spec"], f: { settings: Record<string, string>; secrets: Record<string, string>; secretsSet: string[];
                                                                  reference_field: string; status_field: string; poll_minutes: string; fixed: { k: string; v: string }[] }): Record<string, string> {
  const e: Record<string, string> = {};
  for (const k of spec.settings) {
    const v = (f.settings[k] ?? "").trim();
    if (!v && !SETTING_FIELD[k]?.optional) e[`settings.${k}`] = "Required.";
    if (v && k === "host" && !/^[a-z0-9.-]+\.leadsquared\.com$/.test(v)) e[`settings.${k}`] = "Looks like api-in21.leadsquared.com.";
    if (v && (k === "login_url" || k === "base_url") && !/^https:\/\/[A-Za-z0-9.-]+(\/[A-Za-z0-9._/-]*)?$/.test(v)) e[`settings.${k}`] = "An https address.";
    if (v && k === "api_version" && !/^v\d{2}\.\d$/.test(v)) e[`settings.${k}`] = "Looks like v60.0.";
    if (v && (k === "create_url" || k === "poll_url") && (!HTTPS_RE.test(v) || v.length > 500)) e[`settings.${k}`] = "An https address.";
    if (k === "auth_type" && !(AUTH_TYPES as readonly string[]).includes(v)) e[`settings.${k}`] = "Choose one.";
    if (v && (k === "auth_name" || k === "since_param") && !/^[A-Za-z][A-Za-z0-9_-]{0,59}$/.test(v)) e[`settings.${k}`] = "Letters, digits, - and _.";
    if (v && (k === "wrap_key" || k === "record_id_path") && !PATH_RE.test(v)) e[`settings.${k}`] = "Like data or data.lead.id.";
    if (v && k === "duplicate_status" && !(/^\d{3}$/.test(v) && Number(v) >= 200 && Number(v) <= 599)) e[`settings.${k}`] = "An HTTP code such as 409.";
  }
  const noKey = spec.settings.includes("auth_type") && (f.settings.auth_type ?? "") === "none";
  for (const k of spec.secrets) {
    const v = f.secrets[k] ?? "";
    if (!v && !f.secretsSet.includes(k) && !noKey) e[`secrets.${k}`] = "Required.";
    if (v && (v.length < 8 || v.length > 4000)) e[`secrets.${k}`] = "8 to 4,000 characters.";
  }
  for (const k of ["reference_field", "status_field"] as const) if (f[k] && !CRM_FIELD_RE.test(f[k].trim())) e[k] = "Letters, digits and underscores (a path like stage.name for nested fields).";
  const m = Number(f.poll_minutes);
  if (spec.poll && f.poll_minutes && (!Number.isInteger(m) || m < 2 || m > 1440)) e.poll_minutes = "2 to 1,440 minutes.";
  if (f.fixed.filter((x) => x.k.trim()).length > 20) e.fixed = "At most 20 fixed values.";
  return e;
}

export function pollSummary(r: Record<string, number> | null | undefined): string {
  if (!r) return "—";
  const parts = [`${r.records ?? 0} changed`];
  if (r.applied) parts.push(`${r.applied} applied`);
  if (r.unchanged) parts.push(`${r.unchanged} unchanged`);
  if (r.unmatched) parts.push(`${r.unmatched} not Eduwit's`);
  if (r.error) parts.push(`${r.error} failed`);
  return parts.join(" · ");
}
