import { NextResponse, type NextRequest } from "next/server";
import { internalKeyOk } from "@/lib/internal";
import { runClassify } from "@/lib/classify";
import { runPush } from "@/lib/push";
import { runSync } from "@/lib/sync";
import { runAnalyticsJobs } from "@/lib/analytics-jobs";
import { runPhase4Jobs } from "@/lib/phase4-jobs";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/** Called by pg_cron (b2c-sync-urgent every minute, b2c-sync-batch every 15 minutes) with x-internal-key. */
export async function POST(request: NextRequest) {
  if (!internalKeyOk(request.headers.get("x-internal-key"), process.env.B2C_INTERNAL_KEY)) {
    return NextResponse.json({ ok: false, error: "unauthorised" }, { status: 401 });
  }
  const mode = request.nextUrl.searchParams.get("mode") === "batch" ? "batch" : "urgent";
  try {
    const sync = await runSync(mode);
    const push = mode === "urgent" ? await runPush().catch((e) => ({ push_error: e instanceof Error ? e.message : String(e) })) : {};
    const classify = mode === "urgent" ? await runClassify().catch((e) => ({ classify_error: e instanceof Error ? e.message : String(e) })) : {};
    const analytics = mode === "urgent" ? await runAnalyticsJobs().catch((e) => ({ analytics_error: e instanceof Error ? e.message : String(e) })) : {};
    const phase4 = mode === "urgent" ? await runPhase4Jobs().catch((e) => ({ phase4_error: e instanceof Error ? e.message : String(e) })) : {};
    return NextResponse.json({ ok: true, mode, ...sync, push, classify, analytics, phase4 });
  } catch (e) {
    console.error("sync failed", e);
    return NextResponse.json({ ok: false, error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
}
