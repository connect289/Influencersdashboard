/** Partner CRM adapters (m19): what the Admin sets per CRM and environment, and what the status read returns. */

export const CRM_ADAPTERS = ["leadsquared", "zoho", "salesforce", "hubspot", "meritto"] as const;
export type CrmAdapter = (typeof CRM_ADAPTERS)[number];
export const isCrmAdapter = (a: string): a is CrmAdapter => (CRM_ADAPTERS as readonly string[]).includes(a);

export type Env = "live" | "sandbox";

/** Labels, placeholders and hints for every setting and secret key the database asks for. */
export const SETTING_FIELD: Record<string, { label: string; placeholder?: string; hint?: string; optional?: boolean }> = {
  host: { label: "API host", placeholder: "api-in21.leadsquared.com", hint: "LeadSquared → Settings → API and Webhooks shows the host for your region." },
  api_domain: { label: "API domain", placeholder: "www.zohoapis.in", hint: "Data centre of the Zoho account (zohoapis.in for India).", optional: true },
  accounts_domain: { label: "Accounts domain", placeholder: "accounts.zoho.in", optional: true },
  client_id: { label: "OAuth client ID", hint: "From the partner's connected app (Zoho API console / Salesforce connected app)." },
  login_url: { label: "Login URL", placeholder: "https://login.salesforce.com", hint: "Use https://test.salesforce.com for a Salesforce sandbox, or the org's My Domain.", optional: true },
  api_version: { label: "API version", placeholder: "v60.0", optional: true },
  base_url: { label: "API base URL", placeholder: "https://api.nopaperforms.io", optional: true },
  source: { label: "Source name in Meritto", placeholder: "Eduwit", hint: "The lead source Meritto shows for Eduwit's leads.", optional: true },
};

export const SECRET_FIELD: Record<string, { label: string; hint: string }> = {
  access_key: { label: "Access key", hint: "Given by the partner; stored in the vault." },
  secret_key: { label: "Secret key", hint: "Given by the partner; stored in the vault." },
  client_secret: { label: "OAuth client secret", hint: "Stored in the vault." },
  refresh_token: { label: "Refresh token", hint: "For an API user the partner created for Eduwit. The access token is renewed from it automatically." },
  token: { label: "Private app token", hint: "HubSpot → Settings → Integrations → Private apps, with contacts read and write scopes." },
};

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
};

export type AdapterPreview = { reference: string; sample: boolean; url: string | null; headers: Record<string, string>; body: unknown; error: string | null };

/** Where each CRM's reference field must be created by the partner (a custom text field). */
export const REFERENCE_HELP: Record<CrmAdapter, string> = {
  leadsquared: "Create a custom lead field (text) such as mx_Eduwit_Reference.",
  zoho: "Create a single-line custom field on Leads, API name Eduwit_Reference. Mark Phone as unique so duplicates are refused.",
  salesforce: "Create a text field Eduwit_Reference__c on Lead and turn on a duplicate rule for Leads (Phone or Email) that blocks.",
  hubspot: "Create a single-line text contact property eduwit_reference.",
  meritto: "Ask Meritto to add an eduwit_reference field to the lead form used for the API.",
};

export const CRM_FIELD_RE = /^[A-Za-z_][A-Za-z0-9_]{0,79}$/;

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
  }
  for (const k of spec.secrets) {
    const v = f.secrets[k] ?? "";
    if (!v && !f.secretsSet.includes(k)) e[`secrets.${k}`] = "Required.";
    if (v && (v.length < 8 || v.length > 4000)) e[`secrets.${k}`] = "8 to 4,000 characters.";
  }
  for (const k of ["reference_field", "status_field"] as const) if (f[k] && !CRM_FIELD_RE.test(f[k].trim())) e[k] = "Letters, digits and underscores.";
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
