import { NextResponse, type NextRequest } from "next/server";
import { reportConnector } from "@/lib/connector-status";
import { internalKeyOk } from "@/lib/internal";
import { adminClient } from "@/lib/supabase/admin";
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
    await reportExternal(inbox, templates);
    return NextResponse.json({ ok: true, ...feeds, inbox, templates, support });
  } catch (e) {
    console.error("reconcile failed", e);
    return NextResponse.json({ ok: false, error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
}

/** Connector health (D5): the marketing mailbox read (Gmail) and the hourly template and quality sync (WhatsApp), with
 *  the number's quality rating and messaging tier that sync stores in settings.wa_quality. Skipped parts report nothing. */
async function reportExternal(inbox: Record<string, unknown>, templates: Record<string, unknown>) {
  if (typeof inbox.error === "string") await reportConnector("gmail_marketing", false, null, inbox.error);
  else if (typeof inbox.skipped === "string" && /refused/.test(inbox.skipped)) await reportConnector("gmail_marketing", false, null, inbox.skipped);
  else if (!inbox.skipped) await reportConnector("gmail_marketing", true, { inbox: { replies: inbox.replies, bounces: inbox.bounces } });

  if (typeof templates.error === "string") await reportConnector("whatsapp", false, null, `template sync: ${templates.error}`);
  else if (!templates.skipped) {
    const { data } = await adminClient().from("settings").select("value").eq("key", "wa_quality").maybeSingle();
    const q = (data?.value ?? {}) as { rating?: string | null; tier?: string | null; at?: string };
    await reportConnector("whatsapp", true, { templates_synced: templates.synced, quality_rating: q.rating ?? null, messaging_tier: q.tier ?? null, quality_at: q.at ?? null });
  }
}
