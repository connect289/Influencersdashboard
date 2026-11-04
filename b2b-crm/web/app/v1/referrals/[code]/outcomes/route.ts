import { callB2c, requireKey } from "@/lib/b2c-api";
import { parseReferralQuery } from "@/lib/integrations";

/**
 * GET /v1/referrals/{code}/outcomes?after=&limit= (M33d, M34d): masked progress of the leads a referral code brought in, for the
 * influencer dashboard. API key with the 'referrals' scope, linked to the code (or a prefix of it): any other code answers an
 * empty list. Answers { referral_code, outcomes: [{ lead_ref, enquired_on, stage, enrolled, programme, enrolled_program,
 * updated_on, cursor }], next_after }; never a name, phone, email or lead id (lead_ref is a keyed hash, cursors are opaque).
 */
export const dynamic = "force-dynamic";

export async function GET(request: Request, { params }: { params: Promise<{ code: string }> }) {
  const key = requireKey(request);
  if (typeof key !== "string") return key;
  const { code } = await params;
  if (!/^[A-Za-z0-9_-]{1,60}$/.test(code)) return Response.json({ ok: false, error: "unknown referral code" }, { status: 404 });
  const q = parseReferralQuery(new URL(request.url).searchParams);
  if (!q.ok) return Response.json({ ok: false, error: q.error }, { status: 400 });
  return callB2c("api_referral_outcomes_v2", { p_key: key, p_code: code, p_after: q.q.after, p_limit: q.q.limit });
}
