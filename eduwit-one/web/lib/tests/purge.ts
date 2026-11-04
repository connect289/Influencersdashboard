import { z } from "zod";
import type { RunnerApi } from "./apps.ts";
import { safeMessage } from "./runner.ts";

// The purge (spec §10, D-071): runs finished more than tests.purge_after_days ago lose what they created, through each
// app's own delete path. Spark first (b2c.lead_delete, reason "test": its recycle bin), then B2B (b2b.leads_soft_delete,
// reason "test"), both as the test runner login; one.test_run_purge records the outcome. Nothing is hard-deleted: B2B's
// and Spark's rows have no foreign key to the lead and would be left pointing at nothing. A lead that went to a partner
// is kept: B2B allows "test" only for leads without one (proposal p5-b2b-delete-sandbox-test-leads). A run whose leads
// need the runner login waits while the login is not configured; the others go on. A run whose deletes failed stays due
// and is tried again later (one.test_run_purge backs off; ONE-PURGE reports it).

const dueSchema = z.array(
  z.object({
    run: z.number(),
    test: z.string(),
    leads: z.array(
      z.object({ id: z.number(), deleted: z.boolean(), with_partner: z.boolean(), in_spark: z.boolean() }),
    ),
  }),
);
export type DueRun = z.infer<typeof dueSchema>[number];

export interface PurgeDb {
  purgeDue(limit: number): Promise<DueRun[]>;
  /** True when the run is marked purged; false when a delete failed and it stays due. */
  runPurge(run: number, report: Record<string, unknown>): Promise<boolean>;
}

export const parseDue = (v: unknown): DueRun[] => dueSchema.parse(v ?? []);

export type PurgeSummary = { purged: number; retry: number; waiting: string | null };

export async function purgePass(
  db: PurgeDb,
  runner: RunnerApi | null,
  deadline: number,
  now: () => number = Date.now,
): Promise<PurgeSummary> {
  const summary: PurgeSummary = { purged: 0, retry: 0, waiting: null };
  for (const r of await db.purgeDue(50)) {
    if (now() >= deadline) break;
    const kept = r.leads.filter((l) => l.with_partner).map((l) => l.id);
    const spark = r.leads.filter((l) => l.in_spark && !l.with_partner).map((l) => l.id);
    const b2b = r.leads.filter((l) => !l.deleted && !l.with_partner).map((l) => l.id);
    const report: Record<string, unknown> = { kept };
    if (spark.length || b2b.length) {
      if (!runner) {
        summary.waiting = "the test runner login is not configured";
        continue;
      }
      const step = async (name: string, schema: "b2b" | "b2c", fn: string, args: Record<string, unknown>) => {
        try {
          report[name] = await runner.rpc(schema, fn, args);
        } catch (e) {
          report[name] = { error: safeMessage(e) };
        }
      };
      if (spark.length) await step("spark", "b2c", "lead_delete", { p_leads: spark, p_reason: "test" });
      if (b2b.length) await step("b2b", "b2b", "leads_soft_delete", { p_ids: b2b, p_reason: "test" });
    }
    try {
      // Another invocation may have purged it meanwhile (22023): that run is done either way.
      if (await db.runPurge(r.run, report)) summary.purged++;
      else summary.retry++;
    } catch {
      summary.retry++;
    }
  }
  return summary;
}
