import { NextResponse, type NextRequest } from "next/server";
import { internalKeyOk } from "@/lib/internal";
import { runReconcile } from "@/lib/sync";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/** Called by pg_cron (b2c-reconcile, every 5 minutes): catches up on hand-offs and record changes from the B2B feeds. */
export async function POST(request: NextRequest) {
  if (!internalKeyOk(request.headers.get("x-internal-key"), process.env.B2C_INTERNAL_KEY)) {
    return NextResponse.json({ ok: false, error: "unauthorised" }, { status: 401 });
  }
  try {
    return NextResponse.json({ ok: true, ...(await runReconcile()) });
  } catch (e) {
    console.error("reconcile failed", e);
    return NextResponse.json({ ok: false, error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
}
