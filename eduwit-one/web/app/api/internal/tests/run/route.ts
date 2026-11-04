import { internalAuthorized } from "@/lib/auth.ts";
import { credentialsFrom, vaultSecrets } from "@/lib/clients/credentials.ts";
import { clientsFor } from "@/lib/clients/index.ts";
import { SupabaseOneDb } from "@/lib/db.ts";
import { log } from "@/lib/log.ts";
import { settingsSchema } from "@/lib/state.ts";
import { runTestsPass } from "@/lib/tests/run.ts";

// The synthetic tests on their own (spec §10: /api/internal/tests/run), for an operator with the internal key. The
// minute tick runs the same pass after its probes and alerts; a run already in flight is leased, so the two never
// drive it at once (D-068).
export const dynamic = "force-dynamic";
export const maxDuration = 55;

export async function POST(request: Request) {
  if (!(await internalAuthorized(request))) return Response.json({ error: "unauthorized" }, { status: 401 });
  const db = SupabaseOneDb.fromEnv();
  if (!db) return Response.json({ error: "not_configured" }, { status: 503 });
  const requestId = crypto.randomUUID();
  const started = Date.now();
  const state = await db.tickState();
  // The tests read across the settings: a bad key fails this call with a message naming it (F6).
  const settings = settingsSchema.parse(state.settings);
  const credentials = credentialsFrom(await vaultSecrets(db));
  const clients = clientsFor(settings, credentials);
  const tests = await runTestsPass({ clients, settings, credentials }, requestId, started + 45_000);
  log("info", "tests.done", { requestId, tests });
  return Response.json({ requestId, tests });
}
