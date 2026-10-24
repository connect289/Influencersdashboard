import { sendPending } from "@/lib/alerts/sender.ts";
import { internalAuthorized } from "@/lib/auth.ts";
import { runTick } from "@/lib/checks/runner.ts";
import { credentialsFrom, vaultSecrets } from "@/lib/clients/credentials.ts";
import { clientsFor } from "@/lib/clients/index.ts";
import { SupabaseOneDb } from "@/lib/db.ts";
import { SupabaseFixesDb } from "@/lib/fixes/db.ts";
import { runFixes } from "@/lib/fixes/run.ts";
import { log } from "@/lib/log.ts";
import { runTestsPass } from "@/lib/tests/run.ts";

// Called every minute by one.tick_job() through one.job_call('/api/internal/tick') (spec §5 data flow). Runs the HTTP
// probes the database cannot make, writes their heartbeats and results in one call, sends the alert deliveries the
// database queued (escalations and suppression are decided there), carries out the fix runs the database queued for
// the app (n8n retries, the Spark check before a kick: D-079), then moves the synthetic tests on within the rest of the
// minute (D-068).
export const dynamic = "force-dynamic";
export const maxDuration = 55;

export async function POST(request: Request) {
  if (!internalAuthorized(request)) return Response.json({ error: "unauthorized" }, { status: 401 });
  const db = SupabaseOneDb.fromEnv();
  if (!db) return Response.json({ error: "not_configured" }, { status: 503 });
  const requestId = crypto.randomUUID();
  const started = Date.now();
  try {
    let clients: ReturnType<typeof clientsFor> | undefined;
    let settings: Parameters<typeof clientsFor>[0] | undefined;
    const credentials = credentialsFrom(await vaultSecrets(db));
    const summary = await runTick({
      db,
      clients: (state) => {
        settings = state.settings;
        clients = clientsFor(state.settings, credentials);
        return clients;
      },
      requestId,
    });
    const alerts =
      clients && settings
        ? await sendPending({ db, email: clients.email, from: settings.alerts.email_from, oneHost: settings.hosts.one })
        : null;
    const fixesDb = SupabaseFixesDb.fromEnv();
    const fixes =
      clients && fixesDb
        ? await runFixes({
            db: fixesDb,
            n8n: clients.n8n.client,
            web: clients.appHealth.client,
            holder: `tick:${requestId}`,
            deadline: started + 30_000,
          })
        : null;
    const tests =
      clients && settings ? await runTestsPass({ clients, settings, credentials }, requestId, started + 45_000) : null;
    log("info", "tick.done", { requestId, probes: summary.probes, alerts, fixes, tests });
    return Response.json({ requestId, ...summary, alerts, fixes, tests });
  } catch (e) {
    log("error", "tick.failed", { requestId, error: e instanceof Error ? e.message : "error" });
    return Response.json({ requestId, error: "tick_failed" }, { status: 500 });
  }
}
