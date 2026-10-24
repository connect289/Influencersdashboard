import "server-only";
import type { Credentials } from "../clients/credentials.ts";
import type { Clients } from "../clients/types.ts";
import { bootEnv, secretEnv } from "../env.ts";
import { log } from "../log.ts";
import type { Settings } from "../state.ts";
import { type TestApps, testAppsFor } from "./apps.ts";
import { SupabaseTestsDb } from "./db.ts";
import { journeys } from "./journeys/index.ts";
import { purgePass, type PurgeSummary } from "./purge.ts";
import { runTests, type RunnerSummary } from "./runner.ts";
import type { Identities } from "./types.ts";

/** What the pass needs from the tick: the vendor clients, the settings and the credentials they were built from. */
export type TestsPassInput = { clients: Clients; settings: Settings; credentials: Credentials };

/** The end of the budget is the purge's: the tests stop this long before it. */
const PURGE_RESERVE_MS = 8_000;

/**
 * One pass of the synthetic tests within the rest of this invocation (D-068), then the purge of runs whose artefacts
 * are due (D-071) when time is left. Never throws: a test problem must not stop the tick's probes or alerts, which ran
 * before it.
 */
export async function runTestsPass(
  input: TestsPassInput,
  requestId: string,
  deadline: number,
): Promise<{ tests: RunnerSummary | null; purge: PurgeSummary | null } | null> {
  const db = SupabaseTestsDb.fromEnv();
  if (!db || Date.now() >= deadline) return null;
  const env = bootEnv();
  const appsEnv = {
    supabaseUrl: env.ONE_SUPABASE_URL,
    anonKey: env.ONE_SUPABASE_ANON_KEY,
    n8nBase: secretEnv("ONE_N8N_BASE_URL"),
  };
  // Built once per identities: the runner login keeps its two-factor session across the pass.
  let built: { key: string; apps: TestApps } | undefined;
  const apps = (identities: Identities) => {
    const key = JSON.stringify(identities);
    if (built?.key !== key) built = { key, apps: testAppsFor(input.settings, input.credentials, identities, appsEnv) };
    return built.apps;
  };
  let tests: RunnerSummary | null = null;
  let identities: Identities | undefined;
  try {
    tests = await runTests({
      db: {
        // The identities the pass reads, kept for the purge after it.
        testsState: async (holder, leaseS) => {
          const s = await db.testsState(holder, leaseS);
          identities = s.identities;
          return s;
        },
        runStart: db.runStart.bind(db),
        runSave: db.runSave.bind(db),
        runFinish: db.runFinish.bind(db),
      },
      defs: journeys,
      io: { seams: db, email: input.clients.email.client, apps },
      holder: requestId,
      deadline: deadline - PURGE_RESERVE_MS,
    });
  } catch (e) {
    log("error", "tests.failed", { requestId, error: e instanceof Error ? e.message : "error" });
  }
  let purge: PurgeSummary | null = null;
  if (identities) {
    try {
      purge = await purgePass(db, apps(identities).runner, deadline);
    } catch (e) {
      log("error", "tests.purge_failed", { requestId, error: e instanceof Error ? e.message : "error" });
    }
    // The login's session ends with the pass, so no session outlives the invocation (D-070).
    await apps(identities).runner?.signOut();
  }
  return { tests, purge };
}
