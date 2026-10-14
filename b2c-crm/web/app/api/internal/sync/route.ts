import { NextResponse, type NextRequest } from "next/server";
import { internalKeyOk } from "@/lib/internal";
import { runPush } from "@/lib/push";
import { runSync } from "@/lib/sync";

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
    return NextResponse.json({ ok: true, mode, ...sync, push });
  } catch (e) {
    console.error("sync failed", e);
    return NextResponse.json({ ok: false, error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
}
