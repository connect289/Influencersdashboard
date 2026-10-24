import { testDue } from "./cron.ts";
import {
  type Artefacts,
  type Identities,
  type Run,
  type StepResult,
  type TestContext,
  type TestDef,
  Unsafe,
} from "./types.ts";

// The test runner (spec §10), called each minute after the probes and the alert sender. It first moves on the runs
// already in flight (claimed with a lease, so two overlapping invocations never act twice), then starts the tests that
// are due or that someone asked to run now. A step's result is saved as soon as it is known; a step still waiting is
// saved and picked up by the next tick. Nothing here knows an app: the steps do (lib/tests/journeys).

export type TestRow = {
  id: string;
  enabled: boolean;
  schedule: string;
  timeout_s: number;
  run_requested_at: string | null;
  last_started_at: string | null;
  inflight: boolean;
};

export type TestsState = { tests: TestRow[]; identities: Identities; runs: Run[] };

export interface TestsDb {
  /** The catalogue, the identities, and the in-flight runs this holder now leases (their lease had expired). */
  testsState(holder: string, leaseS: number): Promise<TestsState>;
  /** A new run, or null when one is in flight, the test is off, or this slot already ran (the idempotency key). */
  runStart(
    testId: string,
    trigger: "schedule" | "manual",
    key: string,
    holder: string,
    leaseS: number,
  ): Promise<Run | null>;
  runSave(run: Run, holder: string, leaseS: number): Promise<void>;
  runFinish(run: Run, ok: boolean, error: string | null, holder: string): Promise<void>;
}

export type RunnerOptions<Io> = {
  db: TestsDb;
  defs: ReadonlyArray<TestDef<Io>>;
  io: Io;
  holder: string;
  /** Wall-clock end of this invocation's budget (epoch ms). */
  deadline: number;
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
  pollMs?: number;
};

export type RunnerSummary = {
  advanced: number;
  started: number;
  finished: Array<{ test: string; ok: boolean }>;
  waiting: number;
};

const LEASE_S = 90;

/** A refusal or an app error as a short sentence, without anything that could be a contact or a secret. */
export function safeMessage(e: unknown): string {
  const raw = e instanceof Error ? e.message : String(e);
  return raw
    .replace(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/gi, "[email]")
    .replace(/\+?\d[\d\s().-]{8,}\d/g, "[number]")
    .replace(/(bearer|key|token|secret|signature)[=: ]+\S+/gi, "$1 [hidden]")
    .slice(0, 300);
}

function merge(into: Artefacts, more: Artefacts | undefined) {
  if (!more) return;
  for (const [k, v] of Object.entries(more)) {
    const prev = into[k];
    into[k] = Array.isArray(prev) && Array.isArray(v) ? [...new Set([...prev, ...v])] : v;
  }
}

/** Advances one run as far as the budget allows. Returns "finished" or "waiting". */
export async function advanceRun<Io>(
  def: TestDef<Io>,
  run: Run,
  ctx: TestContext<Io>,
  timeoutS: number,
  opts: Required<Pick<RunnerOptions<Io>, "db" | "holder" | "deadline" | "sleep" | "pollMs">>,
): Promise<{ status: "finished"; ok: boolean } | { status: "waiting" }> {
  const { db, holder, deadline, sleep, pollMs } = opts;
  const finish = async (ok: boolean, error: string | null) => {
    try {
      await db.runFinish(run, ok, error, holder);
    } finally {
      await def.cleanup?.(ctx).catch(() => undefined);
    }
    return { status: "finished" as const, ok };
  };
  const record = (ok: boolean, detail: string | null) => {
    const step = def.steps[run.state.step];
    const result: StepResult = {
      key: step?.key ?? "run",
      title: step?.title ?? "The run",
      ok,
      ms: Math.max(0, ctx.now() - Date.parse(run.state.stepStartedAt)),
      detail,
      at: new Date(ctx.now()).toISOString(),
    };
    run.steps = [...run.steps, result];
  };
  const next = () => {
    run.state = { step: run.state.step + 1, stepStartedAt: new Date(ctx.now()).toISOString(), acted: false };
  };

  for (;;) {
    const step = def.steps[run.state.step];
    if (!step) return finish(true, null);
    if (ctx.now() - Date.parse(run.startedAt) > timeoutS * 1000) {
      record(false, `the run took longer than ${timeoutS} s`);
      return finish(false, "timeout");
    }
    try {
      if (!run.state.acted) {
        merge(run.artefacts, step.act ? await step.act(ctx) : undefined);
        run.state = { ...run.state, acted: true };
        await db.runSave(run, holder, LEASE_S);
      }
      if (!step.until) {
        record(true, null);
        next();
        continue;
      }
      const poll = await step.until(ctx);
      merge(run.artefacts, poll.artefacts);
      if (poll.done) {
        record(true, poll.detail ?? null);
        next();
        await db.runSave(run, holder, LEASE_S);
        continue;
      }
      if (ctx.now() - Date.parse(run.state.stepStartedAt) > step.timeoutS * 1000) {
        record(false, `not seen within ${step.timeoutS} s${poll.detail ? `: ${poll.detail}` : ""}`);
        return finish(false, `${step.key}: timeout`);
      }
      if (ctx.now() + pollMs >= deadline) {
        await db.runSave(run, holder, LEASE_S);
        return { status: "waiting" };
      }
      await sleep(pollMs);
    } catch (e) {
      record(false, safeMessage(e));
      return finish(false, e instanceof Unsafe ? `${step.key}: refused` : `${step.key}: error`);
    }
  }
}

/** One pass: in-flight runs first, then the tests that are due. */
export async function runTests<Io>(o: RunnerOptions<Io>): Promise<RunnerSummary> {
  const now = o.now ?? Date.now;
  const opts = {
    db: o.db,
    holder: o.holder,
    deadline: o.deadline,
    sleep: o.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms))),
    pollMs: o.pollMs ?? 3000,
  };
  const summary: RunnerSummary = { advanced: 0, started: 0, finished: [], waiting: 0 };
  const state = await o.db.testsState(o.holder, LEASE_S);
  const byId = new Map(o.defs.map((d) => [d.id, d]));
  const rowOf = new Map(state.tests.map((t) => [t.id, t]));
  const ctxFor = (run: Run): TestContext<Io> => ({
    run,
    artefacts: run.artefacts,
    identities: state.identities,
    io: o.io,
    now,
  });

  const drive = async (def: TestDef<Io>, run: Run) => {
    const r = await advanceRun(def, run, ctxFor(run), rowOf.get(def.id)?.timeout_s ?? 900, opts);
    if (r.status === "finished") summary.finished.push({ test: def.id, ok: r.ok });
    else summary.waiting++;
  };

  for (const run of state.runs) {
    if (now() >= o.deadline) break;
    const def = byId.get(run.testId);
    summary.advanced++;
    if (!def) {
      await o.db.runFinish(run, false, "no journey is defined for this test", o.holder);
      summary.finished.push({ test: run.testId, ok: false });
      continue;
    }
    await drive(def, run);
  }

  for (const t of state.tests) {
    if (now() >= o.deadline) break;
    const def = byId.get(t.id);
    if (!def || !t.enabled || t.inflight) continue;
    let due = Boolean(t.run_requested_at);
    let trigger: "manual" | "schedule" = "manual";
    if (!due) {
      try {
        due = testDue(t.schedule, t.last_started_at, new Date(now()));
        trigger = "schedule";
      } catch {
        continue; // an unreadable schedule is refused when it is saved; never run on a guess
      }
    }
    if (!due) continue;
    const slot =
      trigger === "manual" ? `manual:${t.run_requested_at}` : `schedule:${new Date(now()).toISOString().slice(0, 16)}`;
    const run = await o.db.runStart(t.id, trigger, `${t.id}:${slot}`, o.holder, LEASE_S);
    if (!run) continue;
    summary.started++;
    const refusal = await def.guard(ctxFor(run)).catch((e: unknown) => safeMessage(e));
    if (refusal) {
      run.steps = [
        {
          key: "safety",
          title: "Every identity is a test identity",
          ok: false,
          ms: 0,
          detail: refusal,
          at: new Date(now()).toISOString(),
        },
      ];
      await o.db.runFinish(run, false, "safety: refused", o.holder);
      summary.finished.push({ test: t.id, ok: false });
      continue;
    }
    await drive(def, run);
  }
  return summary;
}
