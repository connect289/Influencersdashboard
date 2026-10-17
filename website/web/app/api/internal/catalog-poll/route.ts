import { NextResponse } from "next/server";
import { isInternal } from "@/lib/server/internal-auth";
import { rpc } from "@/lib/server/db";
import { runOutbox } from "@/lib/server/outbox";
import { errorFields, log } from "@/lib/server/log";

/**
 * Fallback catalogue poller for environments without pg_cron (production uses pg_cron every minute). Detects catalogue
 * changes, refreshes the read model if needed, then processes the queued revalidation.
 */
async function handle(req: Request) {
  if (!isInternal(req)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const poll = await rpc<Record<string, unknown>>("web_catalog_poll");
    const outbox = poll.changed ? await runOutbox(10) : null;
    return NextResponse.json({ poll, outbox });
  } catch (err) {
    log("error", "catalog.poll_failed", errorFields(err));
    return NextResponse.json({ error: "failed" }, { status: 500 });
  }
}
export const GET = handle;
export const POST = handle;
