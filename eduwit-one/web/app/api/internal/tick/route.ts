import { sendPending, type SendSummary } from "@/lib/alerts/sender.ts";
import { internalAuthorized } from "@/lib/auth.ts";
import { runTick } from "@/lib/checks/runner.ts";
import { credentialsFrom, vaultSecrets } from "@/lib/clients/credentials.ts";
import { clientsFor } from "@/lib/clients/index.ts";
import type { Clients } from "@/lib/clients/types.ts";
import { SupabaseOneDb } from "@/lib/db.ts";
import { SupabaseFixesDb } from "@/lib/fixes/db.ts";
import { runFixes } from "@/lib/fixes/run.ts";
import { log } from "@/lib/log.ts";
import { alertSettingsSchema, clientSettingsSchema, readSettings, settingsSchema } from "@/lib/state.ts";
import { runTestsPass } from "@/lib/tests/run.ts";

// Called every minute by one.tick_job() through one.job_call('/api/internal/tick') (spec §5 data flow). Runs the HTTP
// probes the database cannot make, writes their heartbeats and results in one call, sends the alert deliveries the
// database queued (escalations and suppression are decided there), carries out the fix runs the database queued for
// the app (n8n retries, the Spark check before a kick: D-079), then moves the synthetic tests on within the rest of the
// minute (D-068). Each step has its own deadline and the route answers within 50 s, before pg_net's 55 s wait (F8).
// Each step parses the settings it reads (F6): a bad key stops that step with an error naming it, not the tick.
export const dynamic = "force-dynamic";
export const maxDuration = 50;

type Skipped = { skipped: string };

export async function POST(request: Request) {
  if (!(await internalAuthorized(request))) return Response.json({ error: "unauthorized" }, { status: 401 });
  const db = SupabaseOneDb.fromEnv();
  if (!db) return Response.json({ error: "not_configured" }, { status: 503 });
  const requestId = crypto.randomUUID();
  const started = Date.now();
  try {
    let clients: Clients | undefined;
    let raw: Record<string, unknown> = {};
    const credentials = credentialsFrom(await vaultSecrets(db));
    const summary = await runTick({
      db,
      clients: (state) => {
        raw = state.settings;
        const forClients = readSettings(clientSettingsSchema, raw);
        clients = clientsFor(forClients.ok ? forClients.value : null, credentials);
        return clients;
      },
      requestId,
    });
    const forAlerts = readSettings(alertSettingsSchema, raw);
    const alerts: SendSummary | Skipped | null = !clients
      ? null
      : forAlerts.ok
        ? await sendPending({
            db,
            email: clients.email,
            from: forAlerts.value.alerts.email_from,
            oneHost: forAlerts.value.hosts.one,
            deadline: started + 25_000,
          })
        : { skipped: forAlerts.error };
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
    const all = readSettings(settingsSchema, raw);
    const tests = !clients
      ? null
      : all.ok
        ? await runTestsPass({ clients, settings: all.value, credentials }, requestId, started + 45_000)
        : { skipped: all.error };
    const settingsError = all.ok ? null : all.error;
    log("info", "tick.done", { requestId, probes: summary.probes, alerts, fixes, tests, settingsError });
    return Response.json({ requestId, ...summary, alerts, fixes, tests, settings_error: settingsError });
  } catch (e) {
    log("error", "tick.failed", { requestId, error: e instanceof Error ? e.message : "error" });
    return Response.json({ requestId, error: "tick_failed" }, { status: 500 });
  }
}
