import { NextResponse, type NextRequest } from "next/server";
import { sweep } from "@/lib/attribution/sync";
import { hasInternalKey } from "@/lib/internal-auth";
import { errorMessage, log } from "@/lib/log";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/** The lead sweep, called every minute by pg_cron (inf-lead-sync) with the internal key. */
export async function POST(request: NextRequest) {
  if (!hasInternalKey(request.headers))
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const batches = await sweep(Date.now() + 40_000);
    const total = batches.reduce(
      (a, b) => ({
        scanned: a.scanned + b.scanned,
        decisions: a.decisions + b.decisions,
        unmapped: a.unmapped + b.unmapped,
        flags: a.flags + b.flags,
      }),
      { scanned: 0, decisions: 0, unmapped: 0, flags: 0 },
    );
    if (total.unmapped) log.warn("leads.stage_unmapped", { count: total.unmapped });
    return NextResponse.json({ batches: batches.length, ...total });
  } catch (e) {
    log.error("leads.sweep_failed", { error: errorMessage(e) });
    return NextResponse.json({ error: "sweep_failed" }, { status: 503 });
  }
}
