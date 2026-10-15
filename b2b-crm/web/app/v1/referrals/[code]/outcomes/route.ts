import { callB2c, requireKey } from "@/lib/b2c-api";

/**
 * GET /v1/referrals/{code}/outcomes?after=&limit= (M33d): masked progress of the leads a referral code brought in, for the
 * influencer dashboard. API key with the 'referrals' scope. Answers { referral_code, outcomes: [{ lead_ref, enquired_on,
 * stage, enrolled, programme, enrolled_program, updated_on, cursor }], next_after }; never a name, phone or email.
 */
export const dynamic = "force-dynamic";

export async function GET(request: Request, { params }: { params: Promise<{ code: string }> }) {
  const key = requireKey(request);
  if (typeof key !== "string") return key;
  const { code } = await params;
  if (!/^[A-Za-z0-9_-]{1,60}$/.test(code)) return Response.json({ ok: false, error: "unknown referral code" }, { status: 404 });
  const u = new URL(request.url);
  const after = u.searchParams.get("after");
  const limit = u.searchParams.get("limit");
  if (after !== null && !/^\d{1,18}$/.test(after)) return Response.json({ ok: false, error: "after must be the next_after of the previous page" }, { status: 400 });
  if (limit !== null && !/^\d{1,3}$/.test(limit)) return Response.json({ ok: false, error: "limit must be 1 to 500" }, { status: 400 });
  return callB2c("api_referral_outcomes", { p_key: key, p_code: code, p_after: after ? Number(after) : null, p_limit: limit ? Number(limit) : 100 });
}
