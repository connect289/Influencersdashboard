import { NextResponse, type NextRequest } from "next/server";
import { QUALS } from "@/lib/search/params";
import { MAX_OFFERING_CARDS, offeringCards, offeringIdSet } from "@/lib/server/search";
import { ipFrom } from "@/lib/server/request";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { errorFields, log } from "@/lib/server/log";

/**
 * GET /api/offerings?ids=1,2,3 — cards for the shortlist (up to 100 distinct ids, order kept, hidden ones skipped).
 * Rate-limited like /api/search; the cache entry is keyed on the sorted set of ids (D-095).
 */
export async function GET(req: NextRequest) {
  const limited = await rateLimit(LIMITS.searchPerIp, ipFrom(req));
  if (!limited.ok) return NextResponse.json({ error: "rate_limited" }, { status: 429, headers: { "Retry-After": "60" } });
  // Read at most a little more than the cap, so a huge list costs nothing to parse.
  const raw = (req.nextUrl.searchParams.get("ids") ?? "").split(",", MAX_OFFERING_CARDS * 2).map(Number);
  const { ordered } = offeringIdSet(raw);
  const q = req.nextUrl.searchParams.get("qual");
  const qual = q && (QUALS as readonly string[]).includes(q) ? q : undefined;
  if (!ordered.length) return NextResponse.json([]);
  try {
    return NextResponse.json(await offeringCards(ordered, qual), { headers: { "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600" } });
  } catch (err) {
    log("error", "offerings.batch_failed", errorFields(err));
    return NextResponse.json({ error: "unavailable" }, { status: 503 });
  }
}
