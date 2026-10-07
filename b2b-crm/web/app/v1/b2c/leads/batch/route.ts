import { MAX_BATCH_BYTES, callB2c, jsonBody, requireKey } from "@/lib/b2c-api";

/**
 * POST /v1/b2c/leads/batch: up to 200 updates and activities in one call, for the B2C CRM's own every-15-minutes sync.
 *   { "items": [ { "op": "update", "lead_id": 949, "request_id": "…", "if_version": 7, "actor": { … }, "set": { … } },
 *                { "op": "activity", "lead_id": 950, "request_id": "…", "kind": "call", … } ] }
 * Each item is applied on its own and answered in order (b2b.api_b2c_batch).
 */
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const key = requireKey(request);
  if (typeof key !== "string") return key;
  const body = await jsonBody(request, MAX_BATCH_BYTES);
  if (body instanceof Response) return body;
  return callB2c("api_b2c_batch", { p_key: key, p: body });
}
