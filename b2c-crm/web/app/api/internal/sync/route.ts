import { NextResponse, type NextRequest } from "next/server";
import { internalKeyOk } from "@/lib/internal";
import { runJobs } from "@/lib/job-budget";
import { syncAnswer, syncJobs } from "@/lib/sync-jobs";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/** Called by pg_cron (b2c-sync-urgent every minute, b2c-sync-batch every 15 minutes) with x-internal-key. The urgent run
 *  also removes erased students' files and writes large lead exports (lib/lead-jobs.ts), and stores files students send
 *  on WhatsApp in the private bucket (lib/wa-media-jobs.ts). The jobs and their order are in lib/sync-jobs.ts; each gets
 *  its own deadline inside maxDuration (lib/job-budget.ts), and the answer says per job (`jobs`) whether it ran, was
 *  skipped for lack of time, stopped early or failed, and how long it took. A failure of the messages or of the B2B
 *  sync still answers 500. */
export async function POST(request: NextRequest) {
  const startedAt = Date.now();
  if (!internalKeyOk(request.headers.get("x-internal-key"), process.env.B2C_INTERNAL_KEY)) {
    return NextResponse.json({ ok: false, error: "unauthorised" }, { status: 401 });
  }
  const mode = request.nextUrl.searchParams.get("mode") === "batch" ? "batch" : "urgent";
  try {
    const { status, body } = syncAnswer(mode, await runJobs(syncJobs(mode), { startedAt, limitMs: maxDuration * 1000 }));
    if (status !== 200) console.error("sync failed", body.error);
    return NextResponse.json(body, { status });
  } catch (e) {
    console.error("sync failed", e);
    return NextResponse.json({ ok: false, error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
}
