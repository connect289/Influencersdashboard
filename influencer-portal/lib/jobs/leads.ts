import "server-only";
import { z } from "zod";
import { BATCH, syncBatch } from "@/lib/attribution/sync";
import { adminClient } from "@/lib/supabase/admin";
import type { JobHandler } from "./types";

const rerunPayload = z.object({ lead_ids: z.array(z.number().int()).min(1).max(BATCH) });
const backfillPayload = z.object({
  from: z.string(),
  to: z.string(),
  after: z.number().int().min(0),
});

/** Re-runs attribution for specific leads (after a staff override or fraud decision). */
export const leadsRerun: JobHandler = async (job) => {
  const p = rerunPayload.parse(job.payload);
  await syncBatch({ lead_ids: p.lead_ids }, "override");
};

/** Re-runs attribution for leads created in a range, one page per job; queues the next page until done. */
export const leadsBackfill: JobHandler = async (job) => {
  const p = backfillPayload.parse(job.payload);
  const r = await syncBatch(p, "backfill");
  if (r.scanned >= BATCH && r.last_id !== null) {
    const next = await adminClient().rpc("job_enqueue", {
      p_kind: "leads.backfill",
      p_payload: { ...p, after: r.last_id },
      p_run_at: new Date().toISOString(),
      p_idem_key: `leads_backfill:${p.from}:${p.to}:${String(r.last_id)}`,
    });
    if (next.error) throw new Error(next.error.message);
  }
};
