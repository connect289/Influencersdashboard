import { callB2c, fail, parseLeadsQuery, requireKey } from "@/lib/b2c-api";

/**
 * GET /v1/b2c/leads
 *   ?after=<seq>&limit=<n>   the change feed: every lead shared with the B2C CRM, in order, with its current record
 *   ?phone=… or ?email=…     lookup
 */
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const key = requireKey(request);
  if (typeof key !== "string") return key;
  const p = parseLeadsQuery(new URL(request.url).searchParams);
  if (!p.ok) return fail(400, p.error);
  return p.kind === "lookup"
    ? callB2c("api_b2c_lead_lookup", { p_key: key, p_phone: p.q.phone, p_email: p.q.email })
    : callB2c("api_b2c_leads_feed", { p_key: key, p_after: p.q.after, p_limit: p.q.limit });
}
