/** The B2C CRM link screen (/b2c): the B2C CRM reads and writes leads only through the B2B CRM (m22). */

export type FieldKind = "text" | "email" | "phone" | "int" | "numeric" | "pct" | "ts" | "date" | "uuid" | "stage" | "temperature" | "bool" | "json";
export type LinkField = { field: string; column: string; group: string; kind: FieldKind; write: "b2c" | "b2b"; max: number | null };
export type LinkSettings = { enabled: boolean; scope: "held" | "all"; writable: string[]; delivery?: "realtime" | "batched" };

export type LinkLogRow =
  | { dir: "out"; at: string; lead_id: number; name: string | null; type: "upserted" | "released"; version: number; origin: string | null;
      delivery: { status: string; error: string | null; attempts: number } | null }
  | { dir: "in"; at: string; lead_id: number | null; name: string | null; type: "update" | "activity"; status: "applied" | "unchanged" | "conflict" | "rejected";
      http_status: number; error: string | null; actor: Record<string, string>; changes: Record<string, unknown>; request_id: string; version: number | null };

export type LinkChecks = { endpoint: boolean; secret: boolean; subscribed: boolean; ping: boolean; active: boolean; key: boolean; key_used: boolean;
                           first_delivery: boolean; first_write: boolean; production?: boolean };

/** What syncs when (b2b.sync_cadence). */
export type SyncCadence = {
  interval_minutes: number;
  b2c: { delivery: "realtime" | "batched"; last_batch_at: string | null; last_batch_leads: number | null; last_batch_parts: number | null;
         next_batch_at: string | null; waiting: number | null };
  partners: { id: number; name: string; adapter: string; live: boolean; poll: boolean; live_minutes: number; sandbox_minutes: number;
              own_minutes: boolean; last_poll_at: string | null }[];
};

export type LinkOverview = {
  settings: LinkSettings;
  fields: LinkField[];
  endpoint: null | { id: number; name: string; url: string; active: boolean; events: string[]; has_secret: boolean; last_success_at: string | null;
                     last_failure_at: string | null; last_error: string | null; subscribed: boolean };
  keys: { id: number; name: string; prefix: string; scopes: string[]; last_used_at: string | null }[];
  checks: LinkChecks;
  sync: { in_scope: number; held_now: number; changes_24h: number; last_change_at: string | null; last_seq: number | null;
          tick: { at?: string; last_run?: string; scanned?: number; changed?: number } | null };
  deliveries: { by_status: Record<string, number>; waiting: number; lag_seconds_avg: number | null; lag_seconds_max: number | null };
  writes: { by_status: Record<string, number>; last_at: string | null };
  log: LinkLogRow[];
};

export type LinkLead = {
  lead_id: number; name: string | null; held_by_b2c: boolean; shared: boolean; version: number | null; seq: number | null; changed_at: string | null;
  origin: string | null; record: Record<string, unknown>;
  deliveries: { id: number; type: string; version: number; status: string; attempts: number; error: string | null; created_at: string; delivered_at: string | null }[];
  writes: { at: string; kind: string; status: string; http_status: number; error: string | null; actor: Record<string, string>; changes: Record<string, unknown>; version: number | null }[];
};

/** The connection checklist, in the order the Admin and the B2C developer work through it. */
export const CHECK_STEPS: { key: keyof LinkChecks; label: string; hint: string; where: string }[] = [
  { key: "endpoint", label: "B2C CRM's webhook address registered", hint: "The HTTPS address that receives lead changes.", where: "/system?tab=integrations" },
  { key: "secret", label: "Signing secret issued", hint: "Shared with the B2C developer through a secure channel.", where: "/system?tab=integrations" },
  { key: "subscribed", label: "Subscribed to lead sync", hint: "b2c.* (or b2c.lead_upserted and b2c.lead_released).", where: "/system?tab=integrations" },
  { key: "ping", label: "Test ping delivered", hint: "Send test on the endpoint; the B2C CRM must verify the signature.", where: "/system?tab=integrations" },
  { key: "active", label: "Endpoint switched on", hint: "Nothing is delivered before this.", where: "/system?tab=integrations" },
  { key: "key", label: "API key with the B2C link scope", hint: "For reads, the change feed, updates and activities.", where: "/system?tab=integrations" },
  { key: "key_used", label: "The B2C CRM has called the API", hint: "Usually the first feed call that builds its copy.", where: "" },
  { key: "first_delivery", label: "First lead change delivered", hint: "A lead handed to B2C arrives within seconds.", where: "" },
  { key: "first_write", label: "First update written back", hint: "A counsellor's change reached the lead through the API.", where: "" },
  { key: "production", label: "Switched to the production cadence", hint: "After full testing: changes go in one batch every sync interval, to save API calls.", where: "/b2c#cadence" },
];

export const GROUP_LABEL: Record<string, string> = {
  student: "Student", education: "Education", interest: "Interest", consent: "Consent", source: "Source and campaign",
  qualification: "Qualification", pipeline: "Pipeline", application: "Application", enrolment: "Enrolment", lost: "Lost", other: "Other",
};

export const KIND_LABEL: Record<FieldKind, string> = {
  text: "text", email: "email", phone: "phone", int: "whole number", numeric: "number", pct: "percentage", ts: "date and time", date: "date",
  uuid: "user ID (UUID)", stage: "stage key", temperature: "hot / warm / cold", bool: "true / false", json: "object",
};

/** Fields grouped in catalogue order. */
export function groupFields(fields: LinkField[]): { group: string; fields: LinkField[] }[] {
  const out: { group: string; fields: LinkField[] }[] = [];
  for (const f of fields) {
    const g = out.find((x) => x.group === f.group);
    if (g) g.fields.push(f); else out.push({ group: f.group, fields: [f] });
  }
  return out;
}

/** One badge for the whole link. */
export function linkHealth(o: Pick<LinkOverview, "checks" | "settings" | "deliveries" | "endpoint">): { label: string; tone: "success" | "warning" | "danger" | "neutral" } {
  if (!o.settings.enabled) return { label: "Switched off", tone: "neutral" };
  if (!o.checks.endpoint || !o.checks.secret || !o.checks.active) return { label: "Not connected", tone: "neutral" };
  if ((o.deliveries.by_status.dead ?? 0) > 0) return { label: "Deliveries gave up", tone: "danger" };
  const failing = o.endpoint?.last_failure_at && (!o.endpoint.last_success_at || o.endpoint.last_failure_at > o.endpoint.last_success_at);
  if (failing) return { label: "Failing", tone: "warning" };
  if (!o.checks.subscribed) return { label: "Not subscribed to sync", tone: "warning" };
  return { label: "Live", tone: "success" };
}

export function lagText(s: number | null | undefined): string {
  if (s === null || s === undefined) return "—";
  if (s < 60) return `${s < 10 ? s.toFixed(1) : Math.round(s)} s`;
  return `${Math.round(s / 60)} min`;
}

/** "stage: assigned → counselled, owner_user_id: set" for a write's change list. */
export function describeChanges(changes: Record<string, unknown>, max = 4): string {
  const parts = Object.entries(changes).map(([k, v]) => {
    if (v && typeof v === "object" && "to" in (v as Record<string, unknown>)) {
      const to = (v as { to: unknown }).to;
      const show = to === null ? "cleared" : typeof to === "object" ? "updated" : String(to).length > 24 ? String(to).slice(0, 24) + "…" : String(to);
      return `${k} → ${show}`;
    }
    return k;
  });
  return parts.slice(0, max).join(", ") + (parts.length > max ? ` +${parts.length - max}` : "");
}

export function actorText(a: Record<string, string> | null | undefined): string {
  if (!a) return "—";
  return a.name || a.email || a.id || "B2C CRM";
}

/** "call · connected · Wants the weekend batch" for an activity's stored fields. */
export function describeActivity(a: Record<string, unknown>): string {
  const parts = [a.kind, a.outcome, typeof a.note === "string" ? (a.note.length > 40 ? a.note.slice(0, 40) + "…" : a.note) : null];
  return parts.filter((x) => typeof x === "string" && x).join(" · ");
}
