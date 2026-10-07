import { callB2c, fail, jsonBody, leadIdFrom, requireKey } from "@/lib/b2c-api";

/**
 * POST /v1/b2c/leads/{id}/activities: a counsellor's call, message, meeting or note on a lead the B2C CRM holds.
 *   { "request_id": "…", "kind": "call", "at": "2026-10-07T11:02:00+05:30", "outcome": "connected", "duration_seconds": 240,
 *     "note": "…", "actor": { "id": "…", "email": "…" } }
 * Contact fields (first / last contacted, attempts, last activity) follow; the B2B lead timeline shows it.
 */
export const dynamic = "force-dynamic";

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const key = requireKey(request);
  if (typeof key !== "string") return key;
  const id = leadIdFrom((await params).id);
  if (id === null) return fail(404, "no such lead");
  const body = await jsonBody(request);
  if (body instanceof Response) return body;
  return callB2c("api_b2c_activity", { p_key: key, p_lead_id: id, p: body });
}
