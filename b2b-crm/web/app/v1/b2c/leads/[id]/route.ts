import { callB2c, fail, jsonBody, leadIdFrom, requireKey } from "@/lib/b2c-api";

/**
 * GET   /v1/b2c/leads/{id}   one lead's current record and version
 * PATCH /v1/b2c/leads/{id}   the B2C CRM writes its fields on a lead it holds:
 *       { "request_id": "…", "if_version": 7, "actor": { "id": "…", "email": "…", "name": "…" }, "set": { "stage": "assigned", … } }
 * b2b.api_b2c_lead_update validates every field against the catalogue, applies, audits and answers the new version.
 */
export const dynamic = "force-dynamic";

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const key = requireKey(request);
  if (typeof key !== "string") return key;
  const id = leadIdFrom((await params).id);
  if (id === null) return fail(404, "no such lead");
  return callB2c("api_b2c_lead_get", { p_key: key, p_lead_id: id });
}

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const key = requireKey(request);
  if (typeof key !== "string") return key;
  const id = leadIdFrom((await params).id);
  if (id === null) return fail(404, "no such lead");
  const body = await jsonBody(request);
  if (body instanceof Response) return body;
  return callB2c("api_b2c_lead_update", { p_key: key, p_lead_id: id, p: body });
}
