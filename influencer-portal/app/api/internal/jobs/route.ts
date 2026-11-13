import { randomUUID } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { hasInternalKey } from "@/lib/internal-auth";
import { JOB_HANDLERS } from "@/lib/jobs/registry";
import { JOB_BUDGET_MS, runJobs } from "@/lib/jobs/runner";
import type { Job } from "@/lib/jobs/types";
import { log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

class ClaimFailed extends Error {}

/**
 * Job runner, called every minute by pg_cron (inf-jobs) with the internal key. Claims one due job at a time and stops
 * claiming once less than 15 s of the 60 s budget is left (lib/jobs/runner.ts).
 */
export async function POST(request: NextRequest) {
  const startedAt = Date.now();
  if (!hasInternalKey(request.headers)) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const db = adminClient();
  const worker = `web:${randomUUID().slice(0, 8)}`;
  try {
    const r = await runJobs(
      {
        claim: async () => {
          const { data, error } = await db.rpc("job_claim", {
            p_worker: worker,
            p_limit: 1,
            p_kinds: Object.keys(JOB_HANDLERS),
          });
          if (error) throw new ClaimFailed(error.message);
          return data as Job[];
        },
        finish: async (job, ok, error) => {
          const { error: e } = await db.rpc("job_finish", { p_id: job.id, p_ok: ok, p_error: error });
          if (e) log.error("jobs.finish_failed", { id: job.id, kind: job.kind, error: e.message });
        },
        markPermanent: async (job) => {
          await db.from("jobs").update({ max_attempts: job.attempts }).eq("id", job.id);
        },
        handlers: JOB_HANDLERS,
        now: Date.now,
        onFailed: (job, error) => log.warn("jobs.failed", { id: job.id, kind: job.kind, error }),
      },
      { startedAt, budgetMs: JOB_BUDGET_MS },
    );
    return NextResponse.json({ worker, done: r.done, failed: r.failed, stopped_for_time: r.stoppedForTime });
  } catch (e) {
    if (!(e instanceof ClaimFailed)) throw e;
    log.error("jobs.claim_failed", { error: e.message });
    return NextResponse.json({ error: "claim_failed" }, { status: 503 });
  }
}
