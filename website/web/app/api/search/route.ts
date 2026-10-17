import { after, NextResponse, type NextRequest } from "next/server";
import { parseFinderParams, toQueryString } from "@/lib/search/params";
import { mergeParsed, parseQuery } from "@/lib/search/parse";
import { logSearch, searchOfferings } from "@/lib/server/search";
import { ipFrom } from "@/lib/server/request";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { errorFields, log } from "@/lib/server/log";

/**
 * GET /api/search?<finder params> — results + facets in one call (spec 6.4). Responses are keyed on the canonical query
 * string and cached at the edge briefly with stale-while-revalidate (spec 3A).
 */
export async function GET(req: NextRequest) {
  const limited = await rateLimit(LIMITS.searchPerIp, ipFrom(req));
  if (!limited.ok) return NextResponse.json({ error: "rate_limited" }, { status: 429, headers: { "Retry-After": "60" } });

  const sp = req.nextUrl.searchParams;
  const raw = parseFinderParams(sp);
  const params = raw.q ? mergeParsed(raw, parseQuery(raw.q)) : raw;
  // Extras that are not part of the shareable URL state: one group's offerings (expanding a card) and the page size
  // (the mobile filter sheet asks for counts only).
  const group = sp.get("group");
  const size = Number(sp.get("page_size"));
  const extra = {
    ...(group && /^[a-z0-9-]+:[a-z0-9+-]+$/.test(group) ? { group_key: group } : {}),
    ...(Number.isInteger(size) && size >= 1 && size <= 100 ? { page_size: size } : {}),
  };
  const started = performance.now();
  try {
    const result = await searchOfferings(params, extra);
    const latencyMs = Math.round(performance.now() - started);
    after(() => logSearch({ q: raw.q, filters: JSON.parse(JSON.stringify(params)), results: result.total, latencyMs, source: "api" }));
    return NextResponse.json(
      { ...result, canonical: toQueryString(params) },
      { headers: { "Cache-Control": "public, s-maxage=60, stale-while-revalidate=600", "Server-Timing": `db;dur=${latencyMs}` } },
    );
  } catch (err) {
    log("error", "search.failed", errorFields(err));
    return NextResponse.json({ error: "search_unavailable" }, { status: 503, headers: { "Cache-Control": "no-store" } });
  }
}
