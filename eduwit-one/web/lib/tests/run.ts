import "server-only";
import type { Clients } from "../clients/types.ts";
import { log } from "../log.ts";
import { SupabaseTestsDb } from "./db.ts";
import { journeys } from "./journeys/index.ts";
import { runTests, type RunnerSummary } from "./runner.ts";

/**
 * One pass of the synthetic tests within the rest of this invocation (D-068). Never throws: a test problem must not
 * stop the tick's probes or alerts, which ran before it.
 */
export async function runTestsPass(
  clients: Clients,
  requestId: string,
  deadline: number,
): Promise<RunnerSummary | null> {
  const db = SupabaseTestsDb.fromEnv();
  if (!db || Date.now() >= deadline) return null;
  try {
    return await runTests({
      db,
      defs: journeys,
      io: { seams: db, email: clients.email.client },
      holder: requestId,
      deadline,
    });
  } catch (e) {
    log("error", "tests.failed", { requestId, error: e instanceof Error ? e.message : "error" });
    return null;
  }
}
