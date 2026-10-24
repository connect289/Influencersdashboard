import { z } from "zod";
import type { AppHealthClient, N8nClient } from "../clients/types.ts";

// The app's two fixes (spec §8, D-079, D-080). The database decides when one runs (the switch, the window, the
// cooldown, the rate limit, verification) and queues it; the app makes the call the database cannot and reports:
//   FIX-N8N-RETRY       retries each failed execution of the Witty workflow once through the n8n API;
//   FIX-WEBHOOK-REKICK  checks that Spark's handoff endpoint answers; the database then kicks B2B's outbox with the
//                       fixer's rights, or does nothing and keeps the P1.
// Never more than the run names: the execution ids and the URL come from the database's plan.

const runSchema = z.object({
  action_id: z.number(),
  fix_id: z.string(),
  incident_id: z.number().nullable(),
  target: z.record(z.string(), z.unknown()).default({}),
});
export const claimSchema = z.object({ runs: z.array(runSchema) });
export const reportSchema = z.object({ status: z.string(), action: z.number().nullable().optional() });
export type FixRun = z.infer<typeof runSchema>;

export interface FixesDb {
  claim(holder: string): Promise<FixRun[]>;
  report(actionId: number, ok: boolean, result: Record<string, unknown>): Promise<z.infer<typeof reportSchema>>;
}

export type FixesDeps = {
  db: FixesDb;
  n8n: N8nClient | null;
  web: AppHealthClient;
  holder: string;
  /** Epoch ms: no new call starts after it. */
  deadline: number;
  now?: () => number;
};

export type FixesSummary = {
  claimed: number;
  reported: Array<{ action_id: number; fix_id: string; ok: boolean; status: string }>;
  errors: string[];
};

const executionIds = z.array(z.string().regex(/^[0-9A-Za-z_-]{1,64}$/)).max(500);
const BAD = new Set(["error", "crashed"]);

type Skipped = { id: string; why: string };

/**
 * Retries each execution the run names, once. Before each POST it reads the execution and skips it when it belongs to
 * another workflow, is no longer in error, or is itself a retry (phase 7 review M9). Every id it never POSTed is in
 * `skipped`, so the database plans it again; an id it POSTed is never retried again, whatever the answer.
 */
async function retryExecutions(n8n: N8nClient | null, target: Record<string, unknown>, deps: FixesDeps) {
  const ids = executionIds.safeParse(target.rows);
  if (!ids.success) return { ok: false, result: { error: "the run names no valid execution id" } };
  if (!n8n) {
    const skipped = ids.data.map((id) => ({ id, why: "n8n is not configured" }));
    return {
      ok: false,
      result: { error: "n8n is not configured (Setup item n8n_api)", retried: [], failed: [], skipped },
    };
  }
  const workflow = typeof target.workflow_id === "string" ? target.workflow_id : null;
  const retried: Array<{ id: string; new_id: string | null; status: string | null }> = [];
  const failed: Array<{ id: string; error: string }> = [];
  const skipped: Skipped[] = [];
  for (const id of ids.data) {
    if ((deps.now ?? Date.now)() >= deps.deadline) {
      skipped.push({ id, why: "out of time in this invocation" });
      continue;
    }
    let why: string | null;
    try {
      const x = await n8n.execution(id);
      why =
        workflow && x.workflowId && x.workflowId !== workflow
          ? "another workflow's execution"
          : !BAD.has(x.status)
            ? `no longer in error (${x.status.slice(0, 20)})`
            : x.retryOf || x.mode === "retry"
              ? "a retry"
              : null;
    } catch (e) {
      why = `could not read it: ${e instanceof Error ? e.message.slice(0, 100) : "error"}`;
    }
    if (why) {
      skipped.push({ id, why });
      continue;
    }
    try {
      const r = await n8n.retry(id);
      retried.push({ id, new_id: r.id, status: r.status });
    } catch (e) {
      failed.push({ id, error: e instanceof Error ? e.message.slice(0, 120) : "error" });
    }
  }
  return { ok: retried.length > 0, result: { retried, failed, skipped } };
}

async function checkSpark(web: AppHealthClient, target: Record<string, unknown>) {
  const url = z.url({ protocol: /^https$/ }).safeParse(target.url);
  if (!url.success) return { ok: false, result: { error: "the run names no https URL" } };
  const r = await web.answers(url.data);
  return { ok: r.answered, result: { url: url.data, status: r.status, method: r.method, ms: r.ms } };
}

/** Claims the runs waiting for the app, carries each out and reports it. Never throws. */
export async function runFixes(deps: FixesDeps): Promise<FixesSummary> {
  const summary: FixesSummary = { claimed: 0, reported: [], errors: [] };
  // A claimed run is never claimed again, so nothing is claimed that this invocation has no time for.
  if ((deps.now ?? Date.now)() >= deps.deadline) return summary;
  let runs: FixRun[];
  try {
    runs = await deps.db.claim(deps.holder);
  } catch (e) {
    summary.errors.push(`claim: ${e instanceof Error ? e.message : "error"}`);
    return summary;
  }
  summary.claimed = runs.length;
  for (const run of runs) {
    // Out of time, a retry run is still reported, every id skipped; a reachability check is left, and the next claim
    // closes it as unknown.
    if ((deps.now ?? Date.now)() >= deps.deadline && run.fix_id !== "FIX-N8N-RETRY") {
      summary.errors.push(`${run.fix_id} ${run.action_id}: out of time`);
      continue;
    }
    try {
      const done =
        run.fix_id === "FIX-N8N-RETRY"
          ? await retryExecutions(deps.n8n, run.target, deps)
          : run.fix_id === "FIX-WEBHOOK-REKICK"
            ? await checkSpark(deps.web, run.target)
            : null;
      if (!done) {
        summary.errors.push(`${run.fix_id}: not an app fix`);
        continue;
      }
      const r = await deps.db.report(run.action_id, done.ok, done.result);
      summary.reported.push({ action_id: run.action_id, fix_id: run.fix_id, ok: done.ok, status: r.status });
    } catch (e) {
      summary.errors.push(`${run.fix_id} ${run.action_id}: ${e instanceof Error ? e.message : "error"}`);
    }
  }
  return summary;
}
