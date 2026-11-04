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

const n8n = new MockN8nClient({
  workflows: {},
  executions: {
    wf1: {
      data: [
        { id: "9001", status: "error", startedAt: null, stoppedAt: null },
        { id: "9002", status: "crashed", startedAt: null, stoppedAt: null },
        { id: "9003", status: "success", startedAt: null, stoppedAt: null },
        { id: "9004", status: "error", startedAt: null, stoppedAt: null, retryOf: "8000" },
        { id: "9005", status: "error", startedAt: null, stoppedAt: null, mode: "retry" },
      ],
    },
    other: { data: [{ id: "7001", status: "error", startedAt: null, stoppedAt: null }] },
  },
});
const web = new MockAppHealthClient({
  "spark.eduwit.in": { ok: false, status: 405 },
  "down.example.com": { ok: false, status: 503 },
  "moved.example.com": { ok: false, status: 302 },
  "gone.example.com": { ok: false, status: 404 },
});
const base = { n8n, web, holder: "test", deadline: Date.now() + 60_000 };

describe("the app's fixes (D-079)", () => {
  it("retries each execution the run names, once", async () => {
    const calls: string[] = [];
    const counting: N8nClient = {
      ...n8n,
      workflow: n8n.workflow.bind(n8n),
      executions: n8n.executions.bind(n8n),
      execution: n8n.execution.bind(n8n),
      retry: async (id) => (calls.push(id), { id: `${id}-r`, status: "running" }),
    };
    const db = new FakeDb([
      { action_id: 1, fix_id: "FIX-N8N-RETRY", incident_id: 7, target: { workflow_id: "wf1", rows: ["9001", "9002"] } },
    ]);
    const s = await runFixes({ ...base, db, n8n: counting });
    expect(calls).toEqual(["9001", "9002"]);
    expect(db.reports[0]).toMatchObject({
      actionId: 1,
      ok: true,
      result: { retried: [{ id: "9001", new_id: "9001-r" }, { id: "9002" }], failed: [], skipped: [] },
    });
    expect(s).toMatchObject({ claimed: 1, reported: [{ action_id: 1, ok: true, status: "done" }], errors: [] });
  });

  it("never POSTs an execution of another workflow, one no longer in error, or a retry", async () => {
    const calls: string[] = [];
    const counting: N8nClient = {
      workflow: n8n.workflow.bind(n8n),
      executions: n8n.executions.bind(n8n),
      execution: n8n.execution.bind(n8n),
      retry: async (id) => (calls.push(id), { id: `${id}-r`, status: "running" }),
    };
    const db = new FakeDb([
      {
        action_id: 11,
        fix_id: "FIX-N8N-RETRY",
        incident_id: 7,
        target: { workflow_id: "wf1", rows: ["7001", "9003", "9004", "9005"] },
      },
    ]);
    await runFixes({ ...base, db, n8n: counting });
    expect(calls).toEqual([]);
    expect(db.reports[0]).toMatchObject({
      ok: false,
      result: {
        retried: [],
        skipped: [
          { id: "7001", why: "another workflow's execution" },
          { id: "9003", why: "no longer in error (success)" },
          { id: "9004", why: "a retry" },
          { id: "9005", why: "a retry" },
        ],
      },
    });
  });

  it("reports the ids it had no time for as skipped, so the database plans them again", async () => {
    let t = 0;
    const db = new FakeDb([
      {
        action_id: 12,
        fix_id: "FIX-N8N-RETRY",
        incident_id: 7,
        target: { workflow_id: "wf1", rows: ["9001", "9002"] },
      },
    ]);
    // Clock reads: before the claim, before the run, then one per id; the second id is past the deadline.
    await runFixes({ ...base, db, deadline: 1_000, now: () => (t++ < 3 ? 0 : 2_000) });
    expect(db.reports[0]?.result).toMatchObject({
      retried: [{ id: "9001" }],
      skipped: [{ id: "9002", why: "out of time in this invocation" }],
    });
  });

  it("reports a failed retry, and refuses ids that are not execution ids", async () => {
    const failing: N8nClient = {
      ...n8n,
      workflow: n8n.workflow.bind(n8n),
      executions: n8n.executions.bind(n8n),
      execution: n8n.execution.bind(n8n),
      retry: async () => Promise.reject(new Error("status 409")),
    };
    const db = new FakeDb([
      { action_id: 2, fix_id: "FIX-N8N-RETRY", incident_id: 7, target: { workflow_id: "wf1", rows: ["9001"] } },
      { action_id: 3, fix_id: "FIX-N8N-RETRY", incident_id: 7, target: { rows: ["../workflows/x"] } },
    ]);
    await runFixes({ ...base, db, n8n: failing });
    expect(db.reports[0]).toMatchObject({
      actionId: 2,
      ok: false,
      result: { retried: [], failed: [{ id: "9001", error: "status 409" }], skipped: [] },
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
    expect(db.reports[0]).toMatchObject({
      ok: false,
      result: {
        error: "n8n is not configured (Setup item n8n_api)",
        skipped: [{ id: "1", why: "n8n is not configured" }],
      },
    });
  });

  it("checks that Spark's route answers (a 2xx, or a 400, 401, 403, 405, 415 or 422) before the database kicks", async () => {
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
      { action_id: 13, fix_id: "FIX-WEBHOOK-REKICK", incident_id: 8, target: { url: "https://moved.example.com/h" } },
      { action_id: 14, fix_id: "FIX-WEBHOOK-REKICK", incident_id: 8, target: { url: "https://gone.example.com/h" } },
    ]);
    await runFixes({ ...base, db });
    expect(db.reports.map((r) => [r.actionId, r.ok])).toEqual([
      [5, true],
      [6, false],
      [7, false],
      [13, false],
      [14, false],
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

  it("claims nothing after its deadline", async () => {
    const db = new FakeDb([
      {
        action_id: 10,
        fix_id: "FIX-WEBHOOK-REKICK",
        incident_id: 1,
        target: { url: "https://spark.eduwit.in/v1/handoffs" },
      },
    ]);
    const s = await runFixes({ ...base, db, deadline: Date.now() - 1 });
    expect(s).toEqual({ claimed: 0, reported: [], errors: [] });
    expect(db.reports).toEqual([]);
  });
});
