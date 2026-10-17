import "server-only";
// The app's entry points to the lead sweep (sync-core.ts), run with the service-role client: the every-minute sweep,
// staff re-runs and backfills.
import { adminClient } from "@/lib/supabase/admin";
import { BATCH, syncBatchWith, type SyncMode, type SyncResult } from "./sync-core";

export { BATCH, type SyncMode, type SyncResult };

export function syncBatch(
  mode: SyncMode,
  source: "sweep" | "backfill" | "override",
): Promise<SyncResult> {
  return syncBatchWith(adminClient(), mode, source);
}

/** The every-minute sweep: batches from the watermark until nothing is left or the time is up. */
export async function sweep(deadline: number): Promise<SyncResult[]> {
  const db = adminClient();
  const out: SyncResult[] = [];
  while (Date.now() < deadline) {
    const since = await db.rpc("lead_sync_since");
    if (since.error) throw new Error(since.error.message);
    const r = await syncBatch({ since: since.data }, "sweep");
    out.push(r);
    if (r.scanned < BATCH) break;
  }
  return out;
}
