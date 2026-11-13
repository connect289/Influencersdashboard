/**
 * Time for the jobs of one call to /api/internal/sync. The platform ends the function at the route's maxDuration, and the
 * timer that calls it listens for 55 seconds (b46), so no job may start work later than SAFETY_MS before that limit.
 *
 * The route lists its jobs in order of urgency and runJobs gives each its own deadline, worked out when the job starts
 * from the time really left: the limit, less the safety margin, less the time kept for the jobs still to come
 * (reserveMs), so a slow job cannot use up the time of the ones after it. A job with less than minMs before its deadline
 * is not started and is reported as skipped. A job that loops asks hasTime() before each unit of work (one message, one
 * file, one email, one Claude call); past the deadline it starts nothing more, hands back what it took but did not start
 * (b2c.send_release, b2c.job_release: the attempt is not counted) and is reported as stopped early. A unit that has
 * started is left to finish: the safety margin is for that, and for recording its outcome.
 */
export const SAFETY_MS = 10_000;

export class JobBudget {
  /** The parts of the job that stopped between two units, and the parts that were not started at all. */
  readonly stopped: string[] = [];
  readonly notStarted: string[] = [];

  /** Without a deadline (a job called outside the route, or a test) there is always time. */
  constructor(readonly deadline: number = Number.POSITIVE_INFINITY, private readonly now: () => number = Date.now) {}

  left(): number {
    return this.deadline - this.now();
  }
  /** True while a unit of work that needs about needMs may still start. */
  hasTime(needMs = 0): boolean {
    return this.left() > needMs;
  }
  stopEarly(part: string): void {
    if (!this.stopped.includes(part)) this.stopped.push(part);
  }
  skip(part: string): void {
    if (!this.notStarted.includes(part)) this.notStarted.push(part);
  }
}

export type Job = {
  name: string;
  /** Kept for this job while the jobs before it run. */
  reserveMs: number;
  /** With less than this before its deadline the job is not started. */
  minMs: number;
  /** How long before the limit the job stops starting work, when one unit can need more than SAFETY_MS. */
  tailMs?: number;
  run: (budget: JobBudget) => Promise<unknown>;
};

export type JobStatus = "ran" | "skipped" | "stopped_early" | "failed";
export type JobReport = { name: string; status: JobStatus; ms: number; reason?: string; stopped?: string[]; not_started?: string[] };
export type JobsRun = { results: Record<string, unknown>; jobs: JobReport[] };

/** The latest moment job i may start a unit of work: the later jobs keep their reserves, the limit keeps its margin. */
export function jobDeadline(jobs: readonly Job[], i: number, startedAt: number, limitMs: number): number {
  const later = jobs.slice(i + 1).reduce((sum, j) => sum + j.reserveMs, 0);
  const end = startedAt + limitMs;
  return Math.min(end - SAFETY_MS - later, end - Math.max(jobs[i]?.tailMs ?? 0, SAFETY_MS));
}

/**
 * Runs the jobs in order, each to its own deadline. A job that throws is reported as failed and never stops the others;
 * a job with no time left is reported as skipped, with nothing taken and nothing written.
 */
export async function runJobs(jobs: readonly Job[], opts: { startedAt: number; limitMs: number; now?: () => number }): Promise<JobsRun> {
  const now = opts.now ?? Date.now;
  const run: JobsRun = { results: {}, jobs: [] };
  for (const [i, job] of jobs.entries()) {
    const began = now();
    const deadline = jobDeadline(jobs, i, opts.startedAt, opts.limitMs);
    const left = Math.max(0, Math.round(deadline - began));
    if (deadline - began < job.minMs) {
      run.jobs.push({ name: job.name, status: "skipped", ms: 0, reason: `no time left: ${left} ms before its deadline, it needs ${job.minMs}` });
      continue;
    }
    const budget = new JobBudget(deadline, now);
    const parts = () => ({ ...(budget.stopped.length ? { stopped: budget.stopped } : {}), ...(budget.notStarted.length ? { not_started: budget.notStarted } : {}) });
    try {
      run.results[job.name] = await job.run(budget);
      const early = budget.stopped.length + budget.notStarted.length > 0;
      run.jobs.push({ name: job.name, status: early ? "stopped_early" : "ran", ms: now() - began, ...parts() });
    } catch (e) {
      run.jobs.push({ name: job.name, status: "failed", ms: now() - began, reason: e instanceof Error ? e.message : String(e), ...parts() });
    }
  }
  return run;
}

/**
 * One named part of a job: not started (and listed) when the job's time is up, or when less than needMs is left for a
 * part that needs that long; its error is kept on the job's result and never stops the other parts.
 */
export async function runPart(budget: JobBudget, out: Record<string, unknown>, name: string, fn: () => Promise<unknown>, needMs = 0): Promise<void> {
  if (!budget.hasTime(needMs)) return void budget.skip(name);
  try {
    out[name] = await fn();
  } catch (e) {
    out[`${name}_error`] = e instanceof Error ? e.message : String(e);
  }
}

/** Runs fn over the items in order while there is time for one more; returns the items it did not start. */
export async function whileTime<T>(budget: JobBudget, items: readonly T[], fn: (item: T) => Promise<void>, needMs = 0): Promise<T[]> {
  for (const [i, item] of items.entries()) {
    if (!budget.hasTime(needMs)) return items.slice(i);
    await fn(item);
  }
  return [];
}

/** What b2c.job_release (b56) can hand back: each is the queue one job takes from. */
export type ReleaseKind = "outbox" | "erase_files" | "exports" | "wa_media" | "push" | "support_mail" | "recordings" | "calendar" | "alert_emails" | "schedules" | "briefs";

type ReleaseDb = { rpc: (fn: "job_release", args: { p_kind: ReleaseKind; p_ids: number[] }) => PromiseLike<{ error: { message: string } | null }> };

/**
 * Hands back work a part took but had no time to start, so it is due again on the next run with no attempt spent, and
 * lists the part as stopped early. Does nothing when everything was started.
 */
export async function handBack(db: ReleaseDb, budget: JobBudget, part: string, kind: ReleaseKind, ids: number[]): Promise<number> {
  if (!ids.length) return 0;
  budget.stopEarly(part);
  const { error } = await db.rpc("job_release", { p_kind: kind, p_ids: ids });
  if (error) throw new Error(`job_release (${kind}): ${error.message}`);
  return ids.length;
}
