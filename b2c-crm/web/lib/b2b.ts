import "server-only";
import { b2bConfig } from "@/lib/env";
import { signedHeaders } from "@/lib/b2b-sign";
import type { IntakeBody } from "@/lib/b2b-map";

/**
 * Client for the B2B CRM API (contract v3, docs/b2c-contract.md §3–4). Every call answers { status, body }; it never
 * throws on an HTTP error, so the sync job can hand each answer to b2c.outbox_done as it came.
 */
export type B2bAnswer = { status: number; body: Record<string, unknown> };

const TIMEOUT_MS = 20_000;

export function b2bReady(): boolean {
  return b2bConfig() !== null;
}

async function call(method: string, path: string, body?: unknown, signed = false, extra: Record<string, string> = {}): Promise<B2bAnswer> {
  const cfg = b2bConfig();
  if (!cfg) return { status: 503, body: { ok: false, error: "The B2B link is not configured (B2B_API_URL, B2B_API_KEY, B2B_SIGNING_SECRET)." } };
  const raw = body === undefined ? undefined : JSON.stringify(body);
  const headers: Record<string, string> = signed && raw !== undefined
    ? signedHeaders(raw, cfg.secret)
    : { authorization: `Bearer ${cfg.key}`, ...(raw !== undefined ? { "content-type": "application/json" } : {}), ...extra };
  try {
    const res = await fetch(cfg.url + path, { method, headers, body: raw, signal: AbortSignal.timeout(TIMEOUT_MS), cache: "no-store" });
    let parsed: Record<string, unknown> = {};
    try {
      parsed = (await res.json()) as Record<string, unknown>;
    } catch {
      parsed = { ok: false, error: `HTTP ${res.status}` };
    }
    return { status: res.status, body: parsed };
  } catch (e) {
    return { status: 0, body: { ok: false, error: e instanceof Error ? e.message : String(e) } };
  }
}

export type Actor = { id?: string; email?: string; name?: string } | null;

/** §3.4: write B2C's fields on a lead it holds. */
export function patchLead(leadId: number, requestId: string, set: Record<string, unknown>, actor: Actor, ifVersion?: number) {
  return call("PATCH", `/v1/b2c/leads/${leadId}`, { request_id: requestId, set, actor: actor ?? undefined, ...(ifVersion ? { if_version: ifVersion } : {}) });
}

/** §3.8: up to 200 updates and activities in one call (the 15-minute batch). */
export function batch(items: Record<string, unknown>[]) {
  return call("POST", "/v1/b2c/leads/batch", { items });
}

/** §3.5: a call, message or note on the B2B timeline. */
export function postActivity(leadId: number, requestId: string, body: Record<string, unknown>, actor: Actor) {
  return call("POST", `/v1/b2c/leads/${leadId}/activities`, { request_id: requestId, ...body, actor: actor ?? undefined });
}

/** §4: a signed event (consent answer, consent request sent, opt-out, erasure, stage changes for the timeline). */
export function postEvent(event: Record<string, unknown>) {
  return call("POST", "/v1/events/b2ccrm", event, true);
}

/** §3.2: hand a lead back to the engine to find a partner. */
export function routeToPartners(leadId: number, reason: string) {
  return call("POST", `/v1/leads/${leadId}/route-to-partners`, { reason });
}

/** §3.6 and docs/intake-api.md: a new student through the Intake API, routed straight back to B2C (sales lane).
 *  `requestId` is the Idempotency-Key, so a retry returns the first answer. */
export function intake(body: IntakeBody, requestId: string) {
  return call("POST", "/v1/leads", body, false, { "idempotency-key": requestId });
}

/** §3.3: look a student up before creating one, to avoid a duplicate. */
export function lookupByPhone(phone: string) {
  return call("GET", `/v1/b2c/leads?phone=${encodeURIComponent(phone)}`);
}

export function getLead(leadId: number) {
  return call("GET", `/v1/b2c/leads/${leadId}`);
}

/** §3.1: the hand-off news feed (catch-up for missed webhooks). */
export function handoffs(after: number | null, limit = 200) {
  const q = new URLSearchParams({ limit: String(limit) });
  if (after !== null) q.set("after", String(after));
  return call("GET", `/v1/handoffs?${q}`);
}

/** §2.3: the lead change feed. */
export function changes(after: number | null, limit = 200) {
  const q = new URLSearchParams({ limit: String(limit) });
  if (after !== null) q.set("after", String(after));
  return call("GET", `/v1/b2c/leads?${q}`);
}

export function schema() {
  return call("GET", "/v1/b2c/schema");
}
