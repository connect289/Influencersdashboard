import { NextResponse, type NextRequest } from "next/server";
import { parseFinderParams, toQueryString } from "@/lib/search/params";
import { parseQuery } from "@/lib/search/parse";
import { dbConfigured, rpc } from "@/lib/server/db";
import { ipFrom } from "@/lib/server/request";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { errorFields, log } from "@/lib/server/log";

interface Resolved {
  programme: string[];
  spec: string[];
  level: string[];
  category: string[];
  mode: string[];
  uni: string[];
  text: string[];
  ignored?: string[];
}

/**
 * GET /api/search/resolve?q= — turns free text into finder filters (spec 6.4): budgets, durations, qualification and
 * goals by the deterministic parser; programmes, specialisations, universities, levels and modes by the synonym table.
 * Returns the canonical finder query string, so the finder opens with removable chips instead of a raw query.
 */
export async function GET(req: NextRequest) {
  const q = (req.nextUrl.searchParams.get("q") ?? "").slice(0, 120);
  const limited = await rateLimit(LIMITS.searchPerIp, ipFrom(req));
  if (!limited.ok) return NextResponse.json({ error: "rate_limited" }, { status: 429 });
  const parsed = parseQuery(q);
  const base = parseFinderParams({});
  let r: Resolved = { programme: [], spec: [], level: [], category: [], mode: [], uni: [], text: parsed.rest ? parsed.rest.split(" ") : [] };
  if (dbConfigured() && parsed.rest) {
    try {
      r = await rpc<Resolved>("web_resolve_to_filters", { p_q: parsed.rest });
    } catch (err) {
      log("warn", "search.resolve_failed", errorFields(err));
    }
  }
  const structuredFromText = r.programme.length + r.spec.length + r.level.length + r.category.length + r.mode.length + r.uni.length;
  const fromParser = [parsed.fee_min, parsed.fee_max, parsed.duration, parsed.qual, parsed.goal, parsed.workex].filter(Boolean).length;
  // Nothing recognisable at all: keep the text so the finder shows "no match" with the closest programmes.
  const nothing = structuredFromText + fromParser === 0 && r.text.length === 0;
  const params = {
    ...base,
    q: r.text.length ? r.text.join(" ") : nothing && parsed.rest ? parsed.rest : undefined,
    programme: r.programme, spec: r.spec, level: r.level, category: r.category, mode: r.mode as typeof base.mode, uni: r.uni,
    fee_min: parsed.fee_min, fee_max: parsed.fee_max, duration: parsed.duration ? [parsed.duration] : [],
    qual: parsed.qual, goal: parsed.goal, workex: parsed.workex,
  };
  const structured = structuredFromText + fromParser;
  return NextResponse.json(
    { qs: toQueryString(params), parsed: structured },
    { headers: { "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600" } },
  );
}
