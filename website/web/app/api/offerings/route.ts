import { NextResponse, type NextRequest } from "next/server";
import { QUALS } from "@/lib/search/params";
import { offeringCards } from "@/lib/server/search";
import { errorFields, log } from "@/lib/server/log";

/** GET /api/offerings?ids=1,2,3 — cards for the shortlist (up to 100 ids, order kept, hidden ones skipped). */
export async function GET(req: NextRequest) {
  const ids = (req.nextUrl.searchParams.get("ids") ?? "").split(",").map(Number).filter((n) => Number.isInteger(n) && n > 0).slice(0, 100);
  const q = req.nextUrl.searchParams.get("qual");
  const qual = q && (QUALS as readonly string[]).includes(q) ? q : undefined;
  if (!ids.length) return NextResponse.json([]);
  try {
    return NextResponse.json(await offeringCards(ids, qual), { headers: { "Cache-Control": "public, s-maxage=300, stale-while-revalidate=3600" } });
  } catch (err) {
    log("error", "offerings.batch_failed", errorFields(err));
    return NextResponse.json({ error: "unavailable" }, { status: 503 });
  }
}
