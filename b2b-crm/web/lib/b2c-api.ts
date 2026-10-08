import { createClient } from "@supabase/supabase-js";
import { apiKeyFrom } from "@/lib/integrations";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * The B2C CRM link's machine endpoints (/v1/b2c/*, contract in docs/b2c-contract.md). Every b2b.api_b2c_* function
 * checks the API key's 'b2c' scope itself and answers { ok, status, result | error }; this passes that through.
 */

export const MAX_BODY_BYTES = 64 * 1024;
export const MAX_BATCH_BYTES = 1024 * 1024;
const LEAD_ID = /^\d{1,18}$/;

export const fail = (status: number, error: string, extra?: Record<string, unknown>) => Response.json({ ok: false, error, ...extra }, { status });

/** The key from the headers, or a 401 answer. */
export function requireKey(request: Request): string | Response {
  const key = apiKeyFrom(request.headers);
  return key ? key : fail(401, "send the API key as Authorization: Bearer <key>");
}

export function leadIdFrom(id: string): number | null {
  return LEAD_ID.test(id) ? Number(id) : null;
}

/** A JSON object body (64 KB unless said otherwise), or the answer explaining why not. */
export async function jsonBody(request: Request, max = MAX_BODY_BYTES): Promise<Record<string, unknown> | Response> {
  const text = await request.text();
  if (new TextEncoder().encode(text).length > max) return fail(413, `body is larger than ${Math.round(max / 1024)} KB`);
  let json: unknown;
  try { json = JSON.parse(text); } catch { return fail(400, "body is not JSON"); }
  if (!json || typeof json !== "object" || Array.isArray(json)) return fail(400, "body must be a JSON object");
  return json as Record<string, unknown>;
}

type DbAnswer = { ok: boolean; status?: number; result?: unknown; error?: string; replayed?: boolean } & Record<string, unknown>;

/** Calls one b2b.api_b2c_* function and turns its answer into the HTTP response. */
export async function callB2c(fn: string, args: Record<string, unknown>): Promise<Response> {
  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) return fail(503, "the B2B CRM could not answer, try again shortly");
  const r = data as DbAnswer;
  const status = r.status ?? (r.ok ? 200 : 400);
  if (r.ok) return Response.json({ ok: true, ...(r.replayed ? { replayed: true } : {}), result: r.result }, { status });
  const { ok: _ok, status: _s, ...rest } = r;
  return Response.json({ ok: false, ...rest }, { status });
}

export type FeedQuery = { after: number; limit: number };
export type LookupQuery = { phone: string | null; email: string | null };

/** GET /v1/b2c/leads: either a lookup (?phone= or ?email=) or the change feed (?after=&limit=). */
export function parseLeadsQuery(params: URLSearchParams):
  { ok: true; kind: "lookup"; q: LookupQuery } | { ok: true; kind: "feed"; q: FeedQuery } | { ok: false; error: string } {
  const phone = params.get("phone");
  const email = params.get("email");
  if (phone !== null || email !== null) {
    const digits = (phone ?? "").replace(/\D/g, "");
    if (phone !== null && (digits.length < 10 || digits.length > 15)) return { ok: false, error: "phone must have 10 to 15 digits" };
    if (email !== null && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) return { ok: false, error: "email is not an email address" };
    return { ok: true, kind: "lookup", q: { phone: phone === null ? null : digits, email: email === null ? null : email.trim().toLowerCase() } };
  }
  const after = params.get("after");
  const limit = params.get("limit");
  if (after !== null && !/^\d{1,18}$/.test(after)) return { ok: false, error: "after must be the next_after value of the previous page (0 to start)" };
  if (limit !== null && !/^\d{1,3}$/.test(limit)) return { ok: false, error: "limit must be 1 to 500" };
  const n = limit === null ? 100 : Number(limit);
  if (n < 1 || n > 500) return { ok: false, error: "limit must be 1 to 500" };
  return { ok: true, kind: "feed", q: { after: after === null ? 0 : Number(after), limit: n } };
}
