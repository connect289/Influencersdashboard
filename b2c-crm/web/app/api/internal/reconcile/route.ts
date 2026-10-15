import { NextResponse, type NextRequest } from "next/server";
import { internalKeyOk } from "@/lib/internal";
import { readMarketingInbox } from "@/lib/gmail-inbox";
import { readSupportInbox } from "@/lib/support-jobs";
import { runReconcile } from "@/lib/sync";
import { syncTemplates } from "@/lib/wa-templates";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/** Called by pg_cron (b2c-reconcile, every 5 minutes): catches up on hand-offs and record changes from the B2B feeds,
 *  reads replies to marketing email, and (hourly) syncs WhatsApp template statuses and the quality rating. */
export async function POST(request: NextRequest) {
  if (!internalKeyOk(request.headers.get("x-internal-key"), process.env.B2C_INTERNAL_KEY)) {
    return NextResponse.json({ ok: false, error: "unauthorised" }, { status: 401 });
  }
  try {
    const feeds = await runReconcile();
    const fail = (e: unknown) => ({ error: e instanceof Error ? e.message : String(e) });
    const [inbox, templates, support] = await Promise.all([readMarketingInbox().catch(fail), syncTemplates().catch(fail), readSupportInbox().catch(fail)]);
    return NextResponse.json({ ok: true, ...feeds, inbox, templates, support });
  } catch (e) {
    console.error("reconcile failed", e);
    return NextResponse.json({ ok: false, error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
}
