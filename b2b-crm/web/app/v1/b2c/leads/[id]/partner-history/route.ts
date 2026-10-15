import { callB2c, fail, leadIdFrom, requireKey } from "@/lib/b2c-api";

/**
 * GET /v1/b2c/leads/{id}/partner-history (Addendum 4 §5.2): what partners did with a lead the B2C CRM now holds, usually
 * a partner-lost lead. Answers { lead_id, contract_version, last_partner_status, last_partner_sub_status,
 * history: [{ partner_name, kind, outcome, at, note? }] }, newest first, never a partner counsellor's name.
 * 404 for a lead the B2C CRM does not hold (b2b.api_b2c_partner_history).
 */
export const dynamic = "force-dynamic";

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const key = requireKey(request);
  if (typeof key !== "string") return key;
  const id = leadIdFrom((await params).id);
  if (id === null) return fail(404, "no such lead");
  return callB2c("api_b2c_partner_history", { p_key: key, p_lead_id: id });
}
