// The job runner's loop, apart from the route so it can be tested: claim one job at a time and stop claiming when
// less than `reserveMs` of the invocation's `budgetMs` is left, so a job that starts always has that long to finish
// before the platform stops the function (a job killed mid-run waits 10 minutes and burns an attempt).
import { PermanentJobError, type Job, type JobHandler } from "./types";

export const JOB_BUDGET_MS = 60_000;
export const JOB_RESERVE_MS = 15_000;

export interface RunnerDeps {
  claim: () => Promise<Job[]>;
  finish: (job: Job, ok: boolean, error?: string) => Promise<void>;
  /** A permanent failure: no attempts left, so the job goes dead at once. */
  markPermanent: (job: Job) => Promise<void>;
  handlers: Readonly<Record<string, JobHandler>>;
  now: () => number;
  onFailed?: (job: Job, error: string) => void;
}

export async function runJobs(
  deps: RunnerDeps,
  opts: { startedAt: number; budgetMs?: number; reserveMs?: number },
): Promise<{ done: number; failed: number; stoppedForTime: boolean }> {
  const stopAt = opts.startedAt + (opts.budgetMs ?? JOB_BUDGET_MS) - (opts.reserveMs ?? JOB_RESERVE_MS);
  let done = 0;
  let failed = 0;
  for (;;) {
    if (deps.now() >= stopAt) return { done, failed, stoppedForTime: true };
    const [job] = await deps.claim();
    if (!job) return { done, failed, stoppedForTime: false };
    const handler = deps.handlers[job.kind];
    try {
      if (!handler) throw new PermanentJobError(`no handler for ${job.kind}`);
      await handler(job);
      await deps.finish(job, true);
      done++;
    } catch (e) {
      failed++;
      const message = e instanceof Error ? e.message : String(e);
      if (e instanceof PermanentJobError) await deps.markPermanent(job);
      await deps.finish(job, false, message);
      deps.onFailed?.(job, message);
    }
  }
}
