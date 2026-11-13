import "server-only";
import { revalidateTag } from "next/cache";
import { rpc } from "./db";
import { errorFields, log } from "./log";

/**
 * Outbox worker (spec 3A "never lose a lead"): claims due jobs, runs the handler for each kind, and marks them done or
 * failed (the database applies backoff and the dead-letter state). Handlers must be idempotent; a step that cannot be
 * made idempotent by the provider (an SMTP email) goes through `onceOnly`, which records it on the job as soon as it has
 * happened, so a retry after a lost "done" skips it (D-095).
 */
export interface OutboxJob {
  id: number;
  kind: string;
  dedupe_key: string;
  payload: Record<string, unknown>;
  attempts: number;
  request_id: string | null;
  /** Steps already done on an earlier attempt (web16). */
  sent_steps?: string[] | null;
}

type Handler = (job: OutboxJob) => Promise<void>;

const handlers: Record<string, Handler> = {
  async revalidate(job) {
    const tags = Array.isArray(job.payload.tags) ? (job.payload.tags as unknown[]).filter((t): t is string => typeof t === "string") : [];
    for (const t of tags) revalidateTag(t, "max");
  },
};

export function registerOutboxHandler(kind: string, handler: Handler) {
  handlers[kind] = handler;
}

/**
 * Runs `step` of a job at most once across retries: skipped when an earlier attempt recorded it, recorded right after it
 * succeeds. If recording fails the job still goes on (the step happened); only then can a later retry repeat it.
 */
export async function onceOnly(job: OutboxJob, step: string, run: () => Promise<unknown>): Promise<void> {
  if (job.sent_steps?.includes(step)) {
    log("info", "outbox.step_already_done", { id: job.id, kind: job.kind, step });
    return;
  }
  await run();
  try {
    await rpc("web_outbox_mark_sent", { p_id: job.id, p_step: step });
    job.sent_steps = [...(job.sent_steps ?? []), step];
  } catch (err) {
    log("warn", "outbox.mark_sent_failed", { id: job.id, kind: job.kind, step, ...errorFields(err) });
  }
}

/** True for a job whose payload was emptied because its person's data was erased (`{"erased": true}`). */
export function isErased(job: Pick<OutboxJob, "payload">): boolean {
  return job.payload?.erased === true;
}

export async function runOutbox(limit = 20): Promise<{ claimed: number; done: number; failed: number }> {
  const kinds = Object.keys(handlers);
  const jobs = await rpc<OutboxJob[]>("web_outbox_claim", { p_limit: limit, p_kinds: kinds });
  let done = 0;
  let failed = 0;
  for (const job of jobs ?? []) {
    try {
      // A job emptied by a privacy erasure (web17, D-096) has nothing left to send: it is only closed.
      if (!isErased(job)) await handlers[job.kind]!(job);
      await rpc("web_outbox_done", { p_id: job.id });
      done++;
    } catch (err) {
      failed++;
      const message = err instanceof Error ? err.message : String(err);
      log("warn", "outbox.job_failed", { id: job.id, kind: job.kind, attempts: job.attempts, ...errorFields(err) });
      await rpc("web_outbox_fail", { p_id: job.id, p_error: message.slice(0, 500) }).catch(() => undefined);
    }
  }
  return { claimed: jobs?.length ?? 0, done, failed };
}
