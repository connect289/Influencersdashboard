import { NextResponse, type NextRequest } from "next/server";
import { QUALS } from "@/lib/search/params";
import { offeringDetails } from "@/lib/server/search";
import { errorFields, log } from "@/lib/server/log";

/** GET /api/offerings/:id?qual= — the offering panel's data (spec 6.6). Only catalogue facts, never internal fields. */
export async function GET(req: NextRequest, ctx: RouteContext<"/api/offerings/[id]">) {
  const { id } = await ctx.params;
  const n = Number(id);
  if (!Number.isInteger(n) || n <= 0) return NextResponse.json({ error: "not_found" }, { status: 404 });
  const q = req.nextUrl.searchParams.get("qual");
  const qual = q && (QUALS as readonly string[]).includes(q) ? q : undefined;
  try {
    const d = await offeringDetails(n, qual);
    if (!d) return NextResponse.json({ error: "not_found" }, { status: 404, headers: { "Cache-Control": "public, s-maxage=60" } });
    return NextResponse.json(d, { headers: { "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600" } });
  } catch (err) {
    log("error", "offering.failed", { id: n, ...errorFields(err) });
    return NextResponse.json({ error: "unavailable" }, { status: 503 });
  }
}
