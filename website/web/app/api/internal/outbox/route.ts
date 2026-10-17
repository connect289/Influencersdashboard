import { NextResponse } from "next/server";
import { isInternal } from "@/lib/server/internal-auth";
import { runOutbox } from "@/lib/server/outbox";
import { errorFields, log } from "@/lib/server/log";

/**
 * Outbox worker endpoint, called every minute (Vercel Cron with CRON_SECRET, or pg_cron + pg_net with the internal key).
 * GET for Vercel Cron, POST for everything else.
 */
async function handle(req: Request) {
  if (!isInternal(req)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    return NextResponse.json(await runOutbox(25));
  } catch (err) {
    log("error", "outbox.run_failed", errorFields(err));
    return NextResponse.json({ error: "failed" }, { status: 500 });
  }
}
export const GET = handle;
export const POST = handle;
