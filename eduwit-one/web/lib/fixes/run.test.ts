import { describe, expect, it } from "vitest";
import { MockAppHealthClient } from "../clients/app-health.ts";
import { MockN8nClient } from "../clients/n8n.ts";
import type { N8nClient } from "../clients/types.ts";
import { type FixesDb, type FixRun, runFixes } from "./run.ts";

class FakeDb implements FixesDb {
  readonly reports: Array<{ actionId: number; ok: boolean; result: Record<string, unknown> }> = [];
  constructor(private readonly runs: FixRun[]) {}
  async claim() {
    return this.runs;
  }
  async report(actionId: number, ok: boolean, result: Record<string, unknown>) {
    this.reports.push({ actionId, ok, result });
    return { status: ok ? "done" : "failed", action: actionId + 1000 };
  }
}

const n8n = new MockN8nClient({ workflows: {}, executions: {} });
const web = new MockAppHealthClient({
  "spark.eduwit.in": { ok: false, status: 405 },
  "down.example.com": { ok: false, status: 503 },
});
const base = { n8n, web, holder: "test", deadline: Date.now() + 60_000 };

describe("the app's fixes (D-079)", () => {
  it("retries each execution the run names, once", async () => {
    const calls: string[] = [];
    const counting: N8nClient = {
      ...n8n,
      workflow: n8n.workflow,
      executions: n8n.executions,
      retry: async (id) => (calls.push(id), { id: `${id}-r`, status: "running" }),
    };
    const db = new FakeDb([
      { action_id: 1, fix_id: "FIX-N8N-RETRY", incident_id: 7, target: { rows: ["9001", "9002"] } },
    ]);
    const s = await runFixes({ ...base, db, n8n: counting });
    expect(calls).toEqual(["9001", "9002"]);
    expect(db.reports[0]).toMatchObject({
      actionId: 1,
      ok: true,
      result: { retried: [{ id: "9001", new_id: "9001-r" }, { id: "9002" }], failed: [] },
    });
    expect(s).toMatchObject({ claimed: 1, reported: [{ action_id: 1, ok: true, status: "done" }], errors: [] });
  });

  it("reports a failed retry, and refuses ids that are not execution ids", async () => {
    const failing: N8nClient = {
      ...n8n,
      workflow: n8n.workflow,
      executions: n8n.executions,
      retry: async () => Promise.reject(new Error("status 409")),
    };
    const db = new FakeDb([
      { action_id: 2, fix_id: "FIX-N8N-RETRY", incident_id: 7, target: { rows: ["9001"] } },
      { action_id: 3, fix_id: "FIX-N8N-RETRY", incident_id: 7, target: { rows: ["../workflows/x"] } },
    ]);
    await runFixes({ ...base, db, n8n: failing });
    expect(db.reports[0]).toMatchObject({
      actionId: 2,
      ok: false,
      result: { retried: [], failed: [{ id: "9001", error: "status 409" }] },
    });
    expect(db.reports[1]).toMatchObject({
      actionId: 3,
      ok: false,
      result: { error: "the run names no valid execution id" },
    });
  });

  it("without n8n configured, reports the run as failed rather than leaving it", async () => {
    const db = new FakeDb([{ action_id: 4, fix_id: "FIX-N8N-RETRY", incident_id: 7, target: { rows: ["1"] } }]);
    await runFixes({ ...base, db, n8n: null });
    expect(db.reports[0]).toMatchObject({ ok: false, result: { error: "n8n is not configured (Setup item n8n_api)" } });
  });

  it("checks that Spark answers (any status below 500) before the database kicks", async () => {
    const db = new FakeDb([
      {
        action_id: 5,
        fix_id: "FIX-WEBHOOK-REKICK",
        incident_id: 8,
        target: { url: "https://spark.eduwit.in/v1/handoffs" },
      },
      {
        action_id: 6,
        fix_id: "FIX-WEBHOOK-REKICK",
        incident_id: 8,
        target: { url: "https://down.example.com/v1/handoffs" },
      },
      {
        action_id: 7,
        fix_id: "FIX-WEBHOOK-REKICK",
        incident_id: 8,
        target: { url: "http://spark.eduwit.in/v1/handoffs" },
      },
    ]);
    await runFixes({ ...base, db });
    expect(db.reports.map((r) => [r.actionId, r.ok])).toEqual([
      [5, true],
      [6, false],
      [7, false],
    ]);
    expect(db.reports[0]?.result).toMatchObject({ status: 405, method: "HEAD" });
    expect(db.reports[2]?.result).toEqual({ error: "the run names no https URL" });
  });

  it("never throws: a failing claim or report is in the summary", async () => {
    const broken: FixesDb = {
      claim: () => Promise.reject(new Error("database app_fixes_claim failed")),
      report: () => Promise.reject(new Error("x")),
    };
    expect(await runFixes({ ...base, db: broken })).toEqual({
      claimed: 0,
      reported: [],
      errors: ["claim: database app_fixes_claim failed"],
    });
    const half: FixesDb = {
      claim: async () => [
        {
          action_id: 9,
          fix_id: "FIX-WEBHOOK-REKICK",
          incident_id: 1,
          target: { url: "https://spark.eduwit.in/v1/handoffs" },
        },
      ],
      report: () => Promise.reject(new Error("database app_fix_report failed (22023)")),
    };
    expect((await runFixes({ ...base, db: half })).errors).toEqual([
      "FIX-WEBHOOK-REKICK 9: database app_fix_report failed (22023)",
    ]);
  });

  it("starts nothing after its deadline", async () => {
    const db = new FakeDb([
      {
        action_id: 10,
        fix_id: "FIX-WEBHOOK-REKICK",
        incident_id: 1,
        target: { url: "https://spark.eduwit.in/v1/handoffs" },
      },
    ]);
    const s = await runFixes({ ...base, db, deadline: Date.now() - 1 });
    expect(s.reported).toEqual([]);
    expect(db.reports).toEqual([]);
  });
});
