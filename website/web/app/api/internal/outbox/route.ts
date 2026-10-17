import { NextResponse } from "next/server";
import { isInternal } from "@/lib/server/internal-auth";
import { rpc } from "@/lib/server/db";
import { runOutbox } from "@/lib/server/outbox";
import "@/lib/server/outbox-handlers";
import { errorFields, log } from "@/lib/server/log";

/**
 * Outbox worker endpoint, called every minute by the Supabase pg_cron job web_outbox_worker (pg_net POST with the internal
 * key, D-082). GET is kept for manual runs and for Vercel Cron should the project move to a paid plan.
 */
async function handle(req: Request) {
  if (!isInternal(req)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const result = await runOutbox(25);
    // Optional push of unverified gate attempts (setting push_unverified_gate_leads, default off).
    const unverified = await rpc<Record<string, unknown>>("web_push_unverified").catch(() => null);
    return NextResponse.json({ ...result, unverified });
  } catch (err) {
    log("error", "outbox.run_failed", errorFields(err));
    return NextResponse.json({ error: "failed" }, { status: 500 });
  }
}
export const GET = handle;
export const POST = handle;
