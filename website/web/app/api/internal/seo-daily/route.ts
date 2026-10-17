import { NextResponse } from "next/server";
import { rpc } from "@/lib/server/db";
import { isInternal } from "@/lib/server/internal-auth";
import { errorFields, log } from "@/lib/server/log";
import { refreshLinkSuggestions, runOnPageChecks, syncSearchConsole } from "@/lib/server/seo/toolkit";

/**
 * Daily SEO jobs (spec 13.4): Search Console sync, on-page checks, internal-link suggestions, and pruning 404 log rows
 * not seen for 90 days. Called daily at 03:00 IST by the Supabase pg_cron job web_seo_daily (D-082). Bearer-protected.
 */
export const maxDuration = 300;

async function handle(req: Request) {
  if (!isInternal(req)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const gsc = await syncSearchConsole(7);
    const checks = await runOnPageChecks();
    const links = await refreshLinkSuggestions();
    const pruned404 = await rpc<number>("web_404_prune", { p_days: 90 });
    return NextResponse.json({ gsc, checks, links, pruned404 });
  } catch (err) {
    log("error", "seo.daily_failed", errorFields(err));
    return NextResponse.json({ error: "failed" }, { status: 500 });
  }
}
export const GET = handle;
export const POST = handle;
