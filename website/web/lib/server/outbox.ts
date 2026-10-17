import "server-only";
import { revalidateTag } from "next/cache";
import { rpc } from "./db";
import { errorFields, log } from "./log";

/**
 * Outbox worker (spec 3A "never lose a lead"): claims due jobs, runs the handler for each kind, and marks them done or
 * failed (the database applies backoff and the dead-letter state). Handlers must be idempotent.
 */
interface OutboxJob {
  id: number;
  kind: string;
  dedupe_key: string;
  payload: Record<string, unknown>;
  attempts: number;
  request_id: string | null;
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

export async function runOutbox(limit = 20): Promise<{ claimed: number; done: number; failed: number }> {
  const kinds = Object.keys(handlers);
  const jobs = await rpc<OutboxJob[]>("web_outbox_claim", { p_limit: limit, p_kinds: kinds });
  let done = 0;
  let failed = 0;
  for (const job of jobs ?? []) {
    try {
      await handlers[job.kind]!(job);
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
