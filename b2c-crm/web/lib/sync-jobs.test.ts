import { beforeEach, describe, expect, it, vi } from "vitest";

// The job list of /api/internal/sync with every job replaced by a stand-in: the order, the deadlines and the answer.
const state = vi.hoisted(() => ({ ran: [] as string[], deadlines: {} as Record<string, number>, t: 0, cost: {} as Record<string, number>, fail: "" }));
const stand = (name: string, value: unknown = { n: 1 }) => async (...args: unknown[]) => {
  const budget = args.find((a) => typeof a === "object" && a !== null && "deadline" in a) as { deadline: number };
  state.ran.push(name);
  state.deadlines[name] = budget.deadline;
  state.t += state.cost[name] ?? 100;
  if (state.fail === name) throw new Error(`${name} broke`);
  return value;
};

vi.mock("server-only", () => ({}));
vi.mock("@/lib/sync", () => ({ runSends: stand("messages", { sent: 2, dry_run: 0, send_failed: 0, released: 0, held: 0 }), runOutbox: stand("b2b", { taken: 3, ok: 3, failed: 0, outbox_released: 0 }) }));
vi.mock("@/lib/push", () => ({ runPush: stand("push", { pushed: 1, failed: 0, gone: 0 }) }));
vi.mock("@/lib/classify", () => ({ runClassify: stand("classify", { classified: 0 }) }));
vi.mock("@/lib/wa-media-jobs", () => ({ runWaMediaJobs: stand("media", { stored: 0, failed: 0 }) }));
vi.mock("@/lib/support-jobs", () => ({ sendSupportMail: stand("support", 2) }));
vi.mock("@/lib/phase4-jobs", () => ({ runPhase4Jobs: stand("phase4", { recordings: 0 }) }));
vi.mock("@/lib/analytics-jobs", () => ({ runAnalyticsJobs: stand("analytics", { alert_emails: 0 }) }));
vi.mock("@/lib/lead-jobs", () => ({
  runLeadJobs: async (budget: { deadline: number }, parts: string[]) => stand(parts[0]!, { [parts[0]!]: 1 })(budget),
}));

const { syncAnswer, syncJobs } = await import("./sync-jobs");
const { runJobs } = await import("./job-budget");

const LIMIT = 60_000;
const go = (mode: "urgent" | "batch") => runJobs(syncJobs(mode), { startedAt: 0, limitMs: LIMIT, now: () => state.t });

beforeEach(() => Object.assign(state, { ran: [], deadlines: {}, t: 0, cost: {}, fail: "" }));

describe("the jobs of the every-minute call", () => {
  it("run most urgent first: messages, then the B2B CRM, staff alerts and students' replies and files; analytics last", async () => {
    await go("urgent");
    expect(state.ran).toEqual(["messages", "b2b", "push", "classify", "media", "erased_files", "support", "phase4", "exports", "analytics"]);
    expect(syncJobs("urgent").map((j) => j.name)).toEqual(state.ran);
  });

  it("the 15-minute run sends messages and the B2B batch only", async () => {
    await go("batch");
    expect(state.ran).toEqual(["messages", "b2b"]);
  });

  it("each has its own deadline: sends stop 20 s before the limit at the latest, every later job keeps its share, nothing starts in the last 10 s", async () => {
    await go("urgent");
    expect(state.deadlines).toEqual({ messages: 36_000, b2b: 42_000, push: 43_000, classify: 44_000, media: 45_000, erased_files: 46_000, support: 47_000, phase4: 48_000, exports: 49_000, analytics: 50_000 });
    Object.assign(state, { ran: [], deadlines: {}, t: 0 });
    await go("batch");
    expect(state.deadlines).toEqual({ messages: 35_000, b2b: 50_000 });
    for (const mode of ["urgent", "batch"] as const) {
      const jobs = syncJobs(mode);
      expect(jobs.slice(1).reduce((sum, j) => sum + j.reserveMs, 0)).toBeLessThanOrEqual(15_000); // messages keep at least 35 s
      expect(jobs.every((j) => j.minMs <= Math.max(j.reserveMs, 2_000))).toBe(true); // a job is not skipped while its share is whole
    }
  });

  it("when the messages take all their time, every later job still runs", async () => {
    state.cost = { messages: 36_500 }; // to its deadline, and the last send half a second over
    const run = await go("urgent");
    expect(run.jobs.every((j) => j.status === "ran")).toBe(true);
    expect(state.ran.length).toBe(10);
  });

  it("when an early job overruns badly, the later jobs are skipped and say so; nothing is started to be cut off", async () => {
    state.cost = { messages: 36_000, b2b: 13_800 }; // a B2B call that hangs
    const run = await go("urgent");
    expect(state.ran).toEqual(["messages", "b2b"]);
    expect(run.jobs.slice(2).map((j) => j.status)).toEqual(Array(8).fill("skipped"));
    const { status, body } = syncAnswer("urgent", run);
    expect(status).toBe(200);
    expect(body.push).toEqual({ skipped: expect.stringMatching(/^no time left/) });
    expect(body.leads).toEqual({ skipped: expect.stringMatching(/^no time left/) });
    expect((body.jobs as { name: string; status: string; ms: number }[])[1]).toEqual({ name: "b2b", status: "ran", ms: 13_800 });
  });
});

describe("the route's answer", () => {
  it("keeps every field it had and adds the per-job report", async () => {
    const { status, body } = syncAnswer("urgent", await go("urgent"));
    expect(status).toBe(200);
    expect(body).toMatchObject({
      mode: "urgent", taken: 3, ok: 3, failed: 0, sent: 2, dry_run: 0, send_failed: 0, released: 0,
      push: { pushed: 1, failed: 0, gone: 0 }, classify: { classified: 0 }, analytics: { alert_emails: 0 }, phase4: { recordings: 0 }, support: 2,
      leads: { erased_files: 1, exports: 1 }, media: { stored: 0, failed: 0 },
    });
    const jobs = body.jobs as { name: string; status: string; ms: number }[];
    expect(jobs.map((j) => j.name)).toEqual(state.ran);
    expect(jobs.every((j) => j.status === "ran" && j.ms === 100)).toBe(true);
  });

  it("batch: the other jobs' entries stay empty, as before", async () => {
    const { body } = syncAnswer("batch", await go("batch"));
    expect(body).toMatchObject({ mode: "batch", push: {}, classify: {}, analytics: {}, phase4: {}, support: {}, leads: {}, media: {} });
  });

  it("a job that fails is named with its error and the others still answer", async () => {
    state.fail = "push";
    const { status, body } = syncAnswer("urgent", await go("urgent"));
    expect(status).toBe(200);
    expect(body.push).toEqual({ push_error: "push broke" });
    expect(body.classify).toEqual({ classified: 0 });
    expect((body.jobs as { name: string; status: string }[]).find((j) => j.name === "push")).toMatchObject({ status: "failed", reason: "push broke" });
  });

  it("a failure of the messages or the B2B sync still answers 500, with the other jobs run and reported", async () => {
    state.fail = "messages";
    const { status, body } = syncAnswer("urgent", await go("urgent"));
    expect(status).toBe(500);
    expect(body).toMatchObject({ ok: false, error: "messages: messages broke", taken: 3, push: { pushed: 1 } });
    expect(state.ran.length).toBe(10);
  });
});
