import { describe, expect, it } from "vitest";
import type { RunnerApi } from "./apps.ts";
import { type DueRun, purgePass, type PurgeDb } from "./purge.ts";

function fakeDb(due: DueRun[]) {
  const purged: Array<{ run: number; report: Record<string, unknown> }> = [];
  const db: PurgeDb = {
    purgeDue: async () => due,
    runPurge: async (run, report) => {
      purged.push({ run, report });
      return !JSON.stringify(report).includes('"error"');
    },
  };
  return { db, purged };
}

function fakeRunner(fail: string[] = []) {
  const calls: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const runner: RunnerApi = {
    rpc: async (schema, fn, args) => {
      calls.push({ fn: `${schema}.${fn}`, args });
      if (fail.includes(`${schema}.${fn}`)) throw new Error("status 400 for +91 98111 22334");
      return { deleted: 1 };
    },
    signOut: async () => undefined,
  };
  return { runner, calls };
}

const lead = (id: number, over: Partial<DueRun["leads"][number]> = {}) => ({
  id,
  deleted: false,
  with_partner: false,
  in_spark: false,
  ...over,
});

describe("the purge", () => {
  it("deletes in Spark, then in B2B, as the runner with reason test; keeps partner-routed leads", async () => {
    const { db, purged } = fakeDb([
      { run: 1, test: "T-HANDOFF", leads: [lead(10, { in_spark: true })] },
      { run: 2, test: "T-B2B-PUSH", leads: [lead(20, { with_partner: true, in_spark: true })] },
    ]);
    const r = fakeRunner();
    const s = await purgePass(db, r.runner, Date.now() + 10_000);
    expect(s).toEqual({ purged: 2, retry: 0, waiting: null });
    expect(r.calls).toEqual([
      { fn: "b2c.lead_delete", args: { p_leads: [10], p_reason: "test" } },
      { fn: "b2b.leads_soft_delete", args: { p_ids: [10], p_reason: "test" } },
    ]);
    expect(purged).toEqual([
      { run: 1, report: { kept: [], spark: { deleted: 1 }, b2b: { deleted: 1 } } },
      { run: 2, report: { kept: [20] } },
    ]);
  });

  it("purges runs without leads with no login, and keeps the others waiting for it", async () => {
    const { db, purged } = fakeDb([
      { run: 1, test: "T-ALERT", leads: [] },
      { run: 2, test: "T-B2B-INTAKE", leads: [lead(30)] },
    ]);
    const s = await purgePass(db, null, Date.now() + 10_000);
    expect(s).toEqual({ purged: 1, retry: 0, waiting: "the test runner login is not configured" });
    expect(purged.map((p) => p.run)).toEqual([1]);
  });

  it("records an app's refusal without its detail, and the run stays due for a retry", async () => {
    const { db, purged } = fakeDb([{ run: 3, test: "T-HANDOFF", leads: [lead(40, { in_spark: true })] }]);
    const s = await purgePass(db, fakeRunner(["b2c.lead_delete"]).runner, Date.now() + 10_000);
    expect(purged[0]?.report).toEqual({ kept: [], spark: { error: "status 400 for [number]" }, b2b: { deleted: 1 } });
    expect(s).toEqual({ purged: 0, retry: 1, waiting: null });
  });

  it("goes on past a run another invocation purged first", async () => {
    const { db, purged } = fakeDb([
      { run: 7, test: "T-ALERT", leads: [] },
      { run: 8, test: "T-ALERT", leads: [] },
    ]);
    const first = db.runPurge;
    db.runPurge = async (run, report) => {
      if (run === 7) throw new Error("run 7 is not waiting for its purge");
      return first(run, report);
    };
    const s = await purgePass(db, null, Date.now() + 10_000);
    expect(s).toEqual({ purged: 1, retry: 1, waiting: null });
    expect(purged.map((p) => p.run)).toEqual([8]);
  });

  it("does not touch a lead B2B already deleted, and stops at the deadline", async () => {
    const { db, purged } = fakeDb([
      { run: 4, test: "T-B2B-INTAKE", leads: [lead(50, { deleted: true })] },
      { run: 5, test: "T-B2B-INTAKE", leads: [lead(60)] },
      { run: 6, test: "T-B2B-INTAKE", leads: [lead(70)] },
    ]);
    const clock = { t: 0 };
    const r = fakeRunner();
    r.runner.rpc = async (schema, fn, args) => {
      clock.t = 100;
      r.calls.push({ fn: `${schema}.${fn}`, args });
      return {};
    };
    await purgePass(db, r.runner, 50, () => clock.t);
    expect(purged.map((p) => p.run)).toEqual([4, 5]);
    expect(r.calls).toEqual([{ fn: "b2b.leads_soft_delete", args: { p_ids: [60], p_reason: "test" } }]);
  });
});
