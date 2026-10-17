import { randomUUID } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { hasInternalKey } from "@/lib/internal-auth";
import { JOB_HANDLERS } from "@/lib/jobs/registry";
import { PermanentJobError, type Job } from "@/lib/jobs/types";
import { errorMessage, log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/** Job runner, called every minute by pg_cron (inf-jobs) with the internal key. Processes due jobs for ~45 s. */
export async function POST(request: NextRequest) {
  if (!hasInternalKey(request.headers)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const db = adminClient();
  const worker = `web:${randomUUID().slice(0, 8)}`;
  const deadline = Date.now() + 45_000;
  let done = 0;
  let failed = 0;
  while (Date.now() < deadline) {
    const { data, error } = await db.rpc("job_claim", {
      p_worker: worker,
      p_limit: 10,
      p_kinds: Object.keys(JOB_HANDLERS),
    });
    if (error) {
      log.error("jobs.claim_failed", { error: error.message });
      return NextResponse.json({ error: "claim_failed" }, { status: 503 });
    }
    const jobs = data as Job[];
    if (jobs.length === 0) break;
    for (const job of jobs) {
      const handler = JOB_HANDLERS[job.kind];
      try {
        if (!handler) throw new PermanentJobError(`no handler for ${job.kind}`);
        await handler(job);
        await db.rpc("job_finish", { p_id: job.id, p_ok: true, p_error: undefined });
        done++;
      } catch (e) {
        failed++;
        if (e instanceof PermanentJobError)
          await db.from("jobs").update({ max_attempts: job.attempts }).eq("id", job.id);
        await db.rpc("job_finish", { p_id: job.id, p_ok: false, p_error: errorMessage(e) });
        log.warn("jobs.failed", { id: job.id, kind: job.kind, error: errorMessage(e) });
      }
    }
  }
  return NextResponse.json({ worker, done, failed });
}
