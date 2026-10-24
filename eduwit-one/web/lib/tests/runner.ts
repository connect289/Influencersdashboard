import { testDue } from "./cron.ts";
import {
  type Artefacts,
  Failed,
  type Identities,
  type Run,
  type StepResult,
  type TestContext,
  type TestDef,
  Unsafe,
} from "./types.ts";

// The test runner (spec §10), called each minute after the probes and the alert sender. It claims the runs already in
// flight (with a lease, so two overlapping invocations never act twice), starts the tests that are due or that someone
// asked to run now, then polls every run in turn until each is finished or the budget ends. A run still waiting is
// saved with its lease released, so the next invocation takes it up at once. Nothing here knows an app: the steps do
// (lib/tests/journeys).

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
  /** The catalogue, the identities, and the in-flight runs this holder now leases (theirs had expired or was released). */
  testsState(holder: string, leaseS: number): Promise<TestsState>;
  /** A new run, or null when one is in flight, the test is off, or this slot already ran (the idempotency key). */
  runStart(
    testId: string,
    trigger: "schedule" | "manual",
    key: string,
    holder: string,
    leaseS: number,
  ): Promise<Run | null>;
  /** Saves the run; a lease of 0 releases it. */
  runSave(run: Run, holder: string, leaseS: number): Promise<void>;
  runFinish(run: Run, ok: boolean, error: string | null, holder: string): Promise<void>;
}

export type RunnerOptions<Io> = {
  db: TestsDb;
  defs: ReadonlyArray<TestDef<Io>>;
  io: Io;
  holder: string;
  /** Wall-clock end of this invocation's budget for tests (epoch ms). */
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

type Advance = { status: "finished"; ok: boolean } | { status: "waiting" };

/**
 * Moves one run on as far as it can go without waiting: each step acts once, then is polled; the first poll that is
 * not done returns "waiting" (the caller polls again later). A poll's error is retried until the step's own timeout,
 * except a Failed or Unsafe one, which ends the run.
 */
export async function advanceRun<Io>(
  def: TestDef<Io>,
  run: Run,
  ctx: TestContext<Io>,
  timeoutS: number,
  opts: { db: TestsDb; holder: string },
): Promise<Advance> {
  const { db, holder } = opts;
  const finish = async (ok: boolean, error: string | null): Promise<Advance> => {
    try {
      await db.runFinish(run, ok, error, holder);
    } finally {
      await def.cleanup?.(ctx).catch(() => undefined);
    }
    return { status: "finished", ok };
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
  const fail = (e: unknown, key: string) => {
    record(false, safeMessage(e));
    return finish(false, e instanceof Unsafe ? `${key}: refused` : `${key}: error`);
  };

  for (;;) {
    const step = def.steps[run.state.step];
    if (!step) return finish(true, null);
    if (ctx.now() - Date.parse(run.startedAt) > timeoutS * 1000) {
      record(false, `the run took longer than ${timeoutS} s`);
      return finish(false, "timeout");
    }
    if (!run.state.acted) {
      if (run.state.acting) {
        record(false, "the runner stopped during this step's action; it is not repeated");
        return finish(false, `${step.key}: interrupted`);
      }
      if (step.act) {
        run.state = { ...run.state, acting: true };
        await db.runSave(run, holder, LEASE_S);
        try {
          merge(run.artefacts, await step.act(ctx));
        } catch (e) {
          return fail(e, step.key);
        }
        run.state = { ...run.state, acted: true, acting: false };
        await db.runSave(run, holder, LEASE_S);
      } else {
        run.state = { ...run.state, acted: true };
      }
    }
    if (!step.until) {
      record(true, null);
      next();
      continue;
    }
    let detail: string | undefined;
    try {
      const poll = await step.until(ctx);
      merge(run.artefacts, poll.artefacts);
      if (poll.done) {
        record(true, poll.detail ?? null);
        next();
        await db.runSave(run, holder, LEASE_S);
        continue;
      }
      detail = poll.detail;
    } catch (e) {
      if (e instanceof Unsafe || e instanceof Failed) return fail(e, step.key);
      detail = `retrying after: ${safeMessage(e)}`;
    }
    if (ctx.now() - Date.parse(run.state.stepStartedAt) > step.timeoutS * 1000) {
      record(false, `not seen within ${step.timeoutS} s${detail ? `: ${detail}` : ""}`);
      return finish(false, `${step.key}: timeout`);
    }
    return { status: "waiting" };
  }
}

/** One pass: claim the runs in flight, start the tests that are due, then poll them all in turn. */
export async function runTests<Io>(o: RunnerOptions<Io>): Promise<RunnerSummary> {
  const now = o.now ?? Date.now;
  const sleep = o.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const pollMs = o.pollMs ?? 3000;
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
  let active: Array<{ def: TestDef<Io>; run: Run }> = [];

  for (const run of state.runs) {
    const def = byId.get(run.testId);
    summary.advanced++;
    if (!def) {
      await o.db.runFinish(run, false, "no journey is defined for this test", o.holder);
      summary.finished.push({ test: run.testId, ok: false });
      continue;
    }
    active.push({ def, run });
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
    active.push({ def, run });
  }

  // Rounds: every run gets a turn before any gets a second, so one slow run never starves the others.
  while (active.length) {
    const still: typeof active = [];
    for (const a of active) {
      if (now() >= o.deadline) {
        still.push(a);
        continue;
      }
      const r = await advanceRun(a.def, a.run, ctxFor(a.run), rowOf.get(a.def.id)?.timeout_s ?? 900, {
        db: o.db,
        holder: o.holder,
      });
      if (r.status === "finished") summary.finished.push({ test: a.def.id, ok: r.ok });
      else still.push(a);
    }
    active = still;
    if (!active.length || now() + pollMs >= o.deadline) break;
    await sleep(pollMs);
  }

  for (const a of active) {
    await o.db.runSave(a.run, o.holder, 0);
    summary.waiting++;
  }
  return summary;
}
