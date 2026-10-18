import "server-only";
// The app's entry points to the lead sweep (sync-core.ts), run with the service-role client: the every-minute sweep,
// staff re-runs and backfills. Nothing reads the shared lead tables unless LEAD_SYNC=on: connecting attribution to live
// leads is a separate, owner-approved go-live step (HARD STOP 6, RUNBOOK G-14).
import { env } from "@/lib/env";
import { adminClient } from "@/lib/supabase/admin";
import { BATCH, syncBatchWith, type SyncMode, type SyncResult } from "./sync-core";

export { BATCH, type SyncMode, type SyncResult };

export function leadSyncEnabled(): boolean {
  return env().LEAD_SYNC === "on";
}

const IDLE: SyncResult = {
  scanned: 0,
  leads: 0,
  decisions: 0,
  unmapped: 0,
  flags: 0,
  last_id: null,
};

export async function syncBatch(mode: SyncMode, source: "sweep" | "backfill" | "override"): Promise<SyncResult> {
  if (!leadSyncEnabled()) return IDLE;
  return syncBatchWith(adminClient(), mode, source);
}

/** The every-minute sweep: batches from the watermark until nothing is left or the time is up. */
export async function sweep(deadline: number): Promise<SyncResult[]> {
  if (!leadSyncEnabled()) return [];
  const db = adminClient();
  const out: SyncResult[] = [];
  while (Date.now() < deadline) {
    const since = await db.rpc("lead_sync_since");
    if (since.error) throw new Error(since.error.message);
    const r = await syncBatch({ since: since.data }, "sweep");
    out.push(r);
    if (r.scanned < BATCH) break;
  }
  // Eduwit's commission receipts for attributed leads (INTEGRATION_CONTRACTS §3); a row is written only on change.
  const receipts = await db.rpc("commission_receipts_sync");
  if (receipts.error) throw new Error(receipts.error.message);
  return out;
}
