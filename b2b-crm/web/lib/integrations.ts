import { z } from "zod";

/** The System screen and the machine endpoints for other products (the B2C CRM first). Contract: docs/b2c-contract.md. */

export type ApiKeyRow = {
  id: number;
  name: string;
  scopes: Scope[];
  prefix: string;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
};

export type Consumer = "b2c_crm" | "influencer_dashboard" | "website" | "other";

export type EndpointRow = {
  id: number;
  name: string;
  consumer: Consumer;
  url: string;
  events: string[];
  active: boolean;
  has_secret: boolean;
  last_success_at: string | null;
  last_failure_at: string | null;
  last_error: string | null;
  pending: number;
  dead: number;
  delivered_24h: number;
  created_at: string;
};

export type DeliveryStatus = "pending" | "sending" | "delivered" | "failed" | "dead";

export type DeliveryRow = {
  id: number;
  event_type: string;
  endpoint_id: number;
  endpoint: string | null;
  status: DeliveryStatus;
  attempts: number;
  response_status: number | null;
  last_error: string | null;
  created_at: string;
  delivered_at: string | null;
  next_attempt_at: string | null;
  lead_id: number | null;
};

export type ProductEventRow = {
  id: number;
  source: "b2c_crm";
  event_type: string;
  lead_id: number | null;
  status: "received" | "applied" | "ignored" | "error";
  result: string | null;
  received_at: string;
};

export type JobRow = {
  name: string;
  schedule: string;
  active: boolean;
  last_status: string | null;
  last_run: string | null;
  last_error: string | null;
  failed_24h: number;
};

export type SystemOverview = {
  api_keys: ApiKeyRow[];
  endpoints: EndpointRow[];
  deliveries: DeliveryRow[];
  product_events: ProductEventRow[];
  erasure_open: number;
  jobs: JobRow[];
};

export type ErasureRow = { id: number; lead_id: number; source: string; requested_at: string; note: string | null; name: string | null };

export const SCOPES = ["intake", "referrals", "events"] as const;
export type Scope = (typeof SCOPES)[number];
export const SCOPE_LABEL: Record<Scope, string> = {
  intake: "Lead intake",
  referrals: "Referrals",
  events: "Product integrations (B2C CRM)",
};

export const CONSUMER_LABEL: Record<Consumer, string> = {
  b2c_crm: "B2C CRM",
  influencer_dashboard: "Influencer dashboard",
  website: "Website",
  other: "Other",
};

/** Event types an endpoint can subscribe to (b2b.webhook_endpoint_save keeps the same allow-list). */
export const PUBLISHED_EVENTS = [
  { type: "b2c.lead_handed_off", label: "A lead is handed to B2C (sales or nurture lane)" },
  { type: "b2c.lead_reenquired", label: "A B2C lead enquires again" },
  { type: "b2c.lead_flagged", label: "A B2C lead is flagged (e.g. partner lost it)" },
  { type: "b2c.lead_close_agreed", label: "A partner agreed to close a lead B2C now holds" },
  { type: "b2b.lead_routed_to_partner", label: "A lead B2C sent to partners was accepted by one" },
  { type: "lead.allocated", label: "Any lead is allocated (partner or B2C)" },
  { type: "lead.accepted", label: "A partner accepted a lead" },
  { type: "lead.status_changed", label: "A partner moved a lead to a new stage" },
  { type: "lead.enrolled", label: "A lead enrolled" },
] as const;
export const WILDCARDS = ["b2c.*", "b2b.*", "lead.*", "*"] as const;
const KNOWN_EVENTS: readonly string[] = [...PUBLISHED_EVENTS.map((e) => e.type), ...WILDCARDS];

/** What the B2C CRM needs: everything addressed to it. */
export const B2C_DEFAULT_EVENTS = ["b2c.*", "b2b.*"];

export const DELIVERY_LABEL: Record<DeliveryStatus, string> = {
  pending: "Waiting", sending: "Sending", delivered: "Delivered", failed: "Retrying", dead: "Gave up",
};
export const DELIVERY_TONE: Record<DeliveryStatus, "neutral" | "success" | "warning" | "danger" | "info"> = {
  pending: "neutral", sending: "info", delivered: "success", failed: "warning", dead: "danger",
};
export const PRODUCT_EVENT_TONE: Record<ProductEventRow["status"], "neutral" | "success" | "warning" | "danger"> = {
  received: "neutral", applied: "success", ignored: "warning", error: "danger",
};

export const JOB_LABEL: Record<string, string> = {
  "b2b-route-ready-leads": "Route ready leads",
  "b2b-push-tick": "Push leads to partners",
  "b2b-notify-tick": "Student notifications",
  "b2b-outbox-tick": "Webhook deliveries",
};

export const ApiKeySchema = z.object({
  name: z.string().trim().min(2, "Give the key a name (2 to 80 characters).").max(80, "Give the key a name (2 to 80 characters)."),
  scopes: z.array(z.enum(SCOPES)).min(1, "Choose at least one scope."),
});

export const EndpointSchema = z.object({
  name: z.string().trim().min(2, "2 to 80 characters.").max(80, "2 to 80 characters."),
  consumer: z.enum(["b2c_crm", "influencer_dashboard", "website", "other"]),
  url: z.string().trim().max(500, "At most 500 characters.").regex(/^https:\/\/\S+$/, "The URL must start with https://"),
  events: z.array(z.string()).min(1, "Choose at least one event.")
    .refine((xs) => xs.every((x) => KNOWN_EVENTS.includes(x)), "Unknown event."),
});

/** "Bearer ewk_…" or a bare x-api-key header. */
export function apiKeyFrom(headers: Headers): string {
  const auth = headers.get("authorization") ?? "";
  const m = /^Bearer\s+(\S+)$/i.exec(auth.trim());
  return (m?.[1] ?? headers.get("x-api-key") ?? "").trim();
}

export type HandoffsQuery = { since: string | null; after: number | null; limit: number };

/** Query of GET /v1/handoffs. `after` is the cursor from the previous page; `since` an ISO time for the first call. */
export function parseHandoffsQuery(params: URLSearchParams): { ok: true; q: HandoffsQuery } | { ok: false; error: string } {
  const since = params.get("since");
  const after = params.get("after");
  const limit = params.get("limit");
  if (since !== null && (since.trim() === "" || Number.isNaN(Date.parse(since)))) return { ok: false, error: "since must be an ISO 8601 time" };
  if (after !== null && !/^\d{1,18}$/.test(after)) return { ok: false, error: "after must be the next_after value of the previous page" };
  if (limit !== null && !/^\d{1,3}$/.test(limit)) return { ok: false, error: "limit must be 1 to 500" };
  const n = limit === null ? 200 : Number(limit);
  if (n < 1 || n > 500) return { ok: false, error: "limit must be 1 to 500" };
  return { ok: true, q: { since: since === null ? null : new Date(since).toISOString(), after: after === null ? null : Number(after), limit: n } };
}

/** Collapses wildcard coverage for display: ["b2c.*", "b2c.lead_flagged"] shows only "b2c.*". */
export function describeEvents(events: string[]): string {
  if (events.includes("*")) return "All events";
  const wild = events.filter((e) => e.endsWith(".*")).map((e) => e.slice(0, -1));
  const rest = events.filter((e) => !e.endsWith(".*") && !wild.some((w) => e.startsWith(w)));
  return [...events.filter((e) => e.endsWith(".*")), ...rest].join(", ");
}

/** Health of one endpoint for its badge. */
export function endpointHealth(e: EndpointRow): { label: string; tone: "neutral" | "success" | "warning" | "danger" } {
  if (!e.has_secret) return { label: "No secret yet", tone: "neutral" };
  if (!e.active) return { label: "Paused", tone: "neutral" };
  if (e.dead > 0) return { label: `${e.dead} gave up`, tone: "danger" };
  const failing = e.last_failure_at && (!e.last_success_at || e.last_failure_at > e.last_success_at);
  if (failing) return { label: "Failing", tone: "warning" };
  return { label: "Healthy", tone: "success" };
}
