import { internalAuthorized } from "@/lib/auth.ts";
import { runTick } from "@/lib/checks/runner.ts";
import { clientsFor } from "@/lib/clients/index.ts";
import { SupabaseOneDb } from "@/lib/db.ts";
import { log } from "@/lib/log.ts";

// Called every minute by one.tick_job() through one.job_call('/api/internal/tick') (spec §5 data flow). Runs the HTTP
// probes the database cannot make and writes their heartbeats and results in one call. Phase 3 adds the alert sender.
export const dynamic = "force-dynamic";
export const maxDuration = 55;

export async function POST(request: Request) {
  if (!internalAuthorized(request)) return Response.json({ error: "unauthorized" }, { status: 401 });
  const db = SupabaseOneDb.fromEnv();
  if (!db) return Response.json({ error: "not_configured" }, { status: 503 });
  const requestId = crypto.randomUUID();
  try {
    const summary = await runTick({ db, clients: (state) => clientsFor(state.settings), requestId });
    log("info", "tick.done", { requestId, probes: summary.probes });
    return Response.json({ requestId, ...summary });
  } catch (e) {
    log("error", "tick.failed", { requestId, error: e instanceof Error ? e.message : "error" });
    return Response.json({ requestId, error: "tick_failed" }, { status: 500 });
  }
}
