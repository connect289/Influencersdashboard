import "server-only";
import type { Json } from "@/lib/database.types";
import type { adminClient } from "@/lib/supabase/admin";

type Db = ReturnType<typeof adminClient>;

export interface FanOutJob {
  kind: string;
  payload: Record<string, Json>;
  idemKey: string;
}

/**
 * Queues one job per item (as inf.job_enqueue does: an existing idempotency key is left alone), 500 rows per request,
 * so a long run (a digest for every creator, a month's scorecards) becomes many short jobs that each fit the runner's
 * budget and resume one by one after a failure. Returns how many rows were sent.
 */
export async function enqueueMany(db: Db, jobs: readonly FanOutJob[]): Promise<number> {
  for (let i = 0; i < jobs.length; i += 500) {
    const rows = jobs.slice(i, i + 500).map((j) => ({ kind: j.kind, payload: j.payload, idem_key: j.idemKey }));
    const { error } = await db.from("jobs").upsert(rows, { onConflict: "idem_key", ignoreDuplicates: true });
    if (error) throw new Error(`could not queue ${jobs[0]?.kind ?? "jobs"}: ${error.message}`);
  }
  return jobs.length;
}
