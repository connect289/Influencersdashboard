import { describe, expect, it } from "vitest";
import { runTests, safeMessage, type TestRow, type TestsDb, type TestsState } from "./runner.ts";
import { type Identities, type Run, type TestDef, Unsafe } from "./types.ts";

const identities: Identities = {
  phone_prefix: "910000",
  whatsapp_number: null,
  mailbox: null,
  website_preview_url: null,
  spark_test_user_email: null,
  partner_slug: null,
  creator_referral_code: null,
  run_phone_prefix: "9100009",
  runner_email: null,
  spark_test_journey_id: null,
  whatsapp_phone_number_id: null,
  witty_number: null,
};

class FakeDb implements TestsDb {
  tests: TestRow[];
  runs: Array<Run & { finished?: { ok: boolean; error: string | null } }> = [];
  keys = new Set<string>();
  saves = 0;
  constructor(tests: Array<Partial<TestRow> & { id: string }>) {
    this.tests = tests.map((t) => ({
      enabled: true,
      schedule: "0 * * * *",
      timeout_s: 600,
      run_requested_at: null,
      last_started_at: null,
      inflight: false,
      ...t,
    }));
  }
  async testsState(): Promise<TestsState> {
    const inflight = this.runs.filter((r) => !r.finished);
    return {
      tests: this.tests.map((t) => ({ ...t, inflight: inflight.some((r) => r.testId === t.id) })),
      identities,
      runs: inflight.map((r) => structuredClone(r)),
    };
  }
  async runStart(testId: string, _trigger: string, key: string): Promise<Run | null> {
    if (this.keys.has(key) || this.runs.some((r) => r.testId === testId && !r.finished)) return null;
    this.keys.add(key);
    const run: Run = {
      id: this.runs.length + 1,
      testId,
      startedAt: new Date(clock.t).toISOString(),
      steps: [],
      artefacts: {},
      state: { step: 0, stepStartedAt: new Date(clock.t).toISOString(), acted: false },
    };
    this.runs.push(structuredClone(run));
    const t = this.tests.find((x) => x.id === testId);
    if (t) {
      t.last_started_at = run.startedAt;
      t.run_requested_at = null;
    }
    return run;
  }
  private put(run: Run) {
    const i = this.runs.findIndex((r) => r.id === run.id);
    this.runs[i] = { ...structuredClone(run), finished: this.runs[i]?.finished };
  }
  async runSave(run: Run) {
    this.saves++;
    this.put(run);
  }
  async runFinish(run: Run, ok: boolean, error: string | null) {
    this.put(run);
    const stored = this.runs.find((r) => r.id === run.id);
    if (stored) stored.finished = { ok, error };
  }
}

const clock = { t: Date.parse("2026-10-23T10:00:30Z") };
const now = () => clock.t;
const sleep = async (ms: number) => {
  clock.t += ms;
};

type Io = { acts: string[]; ready: () => boolean };

function journey(id: string, io: Io, over: Partial<TestDef<Io>> = {}): TestDef<Io> {
  return {
    id,
    needs: [],
    guard: async () => null,
    steps: [
      { key: "send", title: "Send", timeoutS: 10, act: async (c) => (c.io.acts.push("send"), { lead_ids: [7] }) },
      {
        key: "see",
        title: "See the reply",
        timeoutS: 60,
        until: async (c) => ({ done: c.io.ready(), detail: "seen" }),
      },
    ],
    ...over,
  };
}

describe("the test runner", () => {
  it("runs a due test, acts once, and finishes when the reply is seen within the budget", async () => {
    clock.t = Date.parse("2026-10-23T10:00:30Z");
    const db = new FakeDb([{ id: "T-A" }]);
    let polls = 0;
    const io: Io = { acts: [], ready: () => ++polls >= 3 };
    const s = await runTests({
      db,
      defs: [journey("T-A", io)],
      io,
      holder: "h",
      deadline: clock.t + 40_000,
      now,
      sleep,
      pollMs: 2000,
    });
    expect(s.finished).toEqual([{ test: "T-A", ok: true }]);
    expect(io.acts).toEqual(["send"]);
    const run = db.runs[0];
    expect(run?.steps.map((x) => [x.key, x.ok])).toEqual([
      ["send", true],
      ["see", true],
    ]);
    expect(run?.steps[1]?.ms).toBe(4000);
    expect(run?.artefacts).toEqual({ lead_ids: [7] });
  });

  it("saves a waiting step and finishes it on a later tick without acting again", async () => {
    clock.t = Date.parse("2026-10-23T10:00:30Z");
    const db = new FakeDb([{ id: "T-A" }]);
    let ready = false;
    const io: Io = { acts: [], ready: () => ready };
    const first = await runTests({
      db,
      defs: [journey("T-A", io)],
      io,
      holder: "h",
      deadline: clock.t + 5_000,
      now,
      sleep,
      pollMs: 2000,
    });
    expect(first.waiting).toBe(1);
    clock.t += 30_000;
    ready = true;
    const second = await runTests({
      db,
      defs: [journey("T-A", io)],
      io,
      holder: "h",
      deadline: clock.t + 40_000,
      now,
      sleep,
      pollMs: 2000,
    });
    expect(second.finished).toEqual([{ test: "T-A", ok: true }]);
    expect(io.acts).toEqual(["send"]);
    expect(second.started).toBe(0);
  });

  it("fails a step that is not seen in time, with the step's own timeout", async () => {
    clock.t = Date.parse("2026-10-23T10:00:30Z");
    const db = new FakeDb([{ id: "T-A" }]);
    const io: Io = { acts: [], ready: () => false };
    await runTests({
      db,
      defs: [journey("T-A", io)],
      io,
      holder: "h",
      deadline: clock.t + 120_000,
      now,
      sleep,
      pollMs: 5000,
    });
    const run = db.runs[0];
    expect(run?.finished).toEqual({ ok: false, error: "see: timeout" });
    expect(run?.steps[1]?.detail).toMatch(/^not seen within 60 s/);
  });

  it("refuses to start when an identity is not a test identity, and sends nothing", async () => {
    clock.t = Date.parse("2026-10-23T10:00:30Z");
    const db = new FakeDb([{ id: "T-A" }]);
    const io: Io = { acts: [], ready: () => true };
    await runTests({
      db,
      defs: [journey("T-A", io, { guard: async () => "the phone is not in w2_trusted with is_test" })],
      io,
      holder: "h",
      deadline: clock.t + 40_000,
      now,
      sleep,
    });
    expect(io.acts).toEqual([]);
    expect(db.runs[0]?.finished).toEqual({ ok: false, error: "safety: refused" });
    expect(db.runs[0]?.steps[0]?.key).toBe("safety");
  });

  it("stops a run on an unsafe step, and does not repeat a slot that already ran", async () => {
    clock.t = Date.parse("2026-10-23T10:00:30Z");
    const db = new FakeDb([{ id: "T-A" }]);
    const io: Io = { acts: [], ready: () => true };
    const def = journey("T-A", io, {
      steps: [
        {
          key: "send",
          title: "Send",
          timeoutS: 10,
          act: async () => {
            throw new Unsafe("lead 9 is not is_test");
          },
        },
      ],
    });
    await runTests({ db, defs: [def], io, holder: "h", deadline: clock.t + 40_000, now, sleep });
    expect(db.runs[0]?.finished).toEqual({ ok: false, error: "send: refused" });
    clock.t += 60_000;
    const again = await runTests({ db, defs: [def], io, holder: "h", deadline: clock.t + 40_000, now, sleep });
    expect(again.started).toBe(0);
  });

  it("runs a test on request even when it is not due, and never an off test", async () => {
    clock.t = Date.parse("2026-10-23T10:30:30Z");
    const db = new FakeDb([
      { id: "T-A", last_started_at: "2026-10-23T10:00:10Z", run_requested_at: "2026-10-23T10:30:00Z" },
      { id: "T-B", enabled: false, run_requested_at: "2026-10-23T10:30:00Z" },
    ]);
    const io: Io = { acts: [], ready: () => true };
    const s = await runTests({
      db,
      defs: [journey("T-A", io), journey("T-B", io)],
      io,
      holder: "h",
      deadline: clock.t + 40_000,
      now,
      sleep,
    });
    expect(s.finished).toEqual([{ test: "T-A", ok: true }]);
  });

  it("keeps contacts and secrets out of step details", () => {
    expect(safeMessage(new Error("lead +91 98111 22334 / asha@x.in rejected; Bearer abc.def"))).toBe(
      "lead [number] / [email] rejected; Bearer [hidden]",
    );
  });
});
