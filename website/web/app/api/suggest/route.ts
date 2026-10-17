import { NextResponse, type NextRequest } from "next/server";
import { suggest } from "@/lib/server/search";
import { ipFrom } from "@/lib/server/request";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { errorFields, log } from "@/lib/server/log";

/** GET /api/suggest?q= — instant suggestions grouped as programmes · specialisations · universities (spec 6.1). */
export async function GET(req: NextRequest) {
  const q = (req.nextUrl.searchParams.get("q") ?? "").replace(/\s+/g, " ").trim().toLowerCase().slice(0, 80);
  if (!q) return NextResponse.json({ programmes: [], groups: [], universities: [] });
  const limited = await rateLimit(LIMITS.searchPerIp, ipFrom(req));
  if (!limited.ok) return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  try {
    const s = await suggest(q);
    return NextResponse.json(s, { headers: { "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600" } });
  } catch (err) {
    log("error", "suggest.failed", errorFields(err));
    return NextResponse.json({ programmes: [], groups: [], universities: [] }, { headers: { "Cache-Control": "no-store" } });
  }
}
