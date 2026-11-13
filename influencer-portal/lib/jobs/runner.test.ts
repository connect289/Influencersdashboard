import { describe, expect, it, vi } from "vitest";
import { runJobs, type RunnerDeps } from "./runner";
import { PermanentJobError, type Job } from "./types";

const job = (id: number, kind = "k"): Job => ({ id, kind, payload: {}, attempts: 1, max_attempts: 3 });

function deps(
  jobs: Job[],
  clock: { t: number },
  handlers: RunnerDeps["handlers"],
): RunnerDeps & { finished: unknown[] } {
  const queue = [...jobs];
  const finished: unknown[] = [];
  return {
    finished,
    claim: vi.fn(() => Promise.resolve(queue.length ? [queue.shift() as Job] : [])),
    finish: vi.fn((j: Job, ok: boolean, error?: string) => {
      finished.push([j.id, ok, error]);
      return Promise.resolve();
    }),
    markPermanent: vi.fn(() => Promise.resolve()),
    handlers,
    now: () => clock.t,
  };
}

describe("job runner", () => {
  it("runs jobs until the queue is empty", async () => {
    const clock = { t: 0 };
    const d = deps([job(1), job(2)], clock, { k: () => Promise.resolve() });
    expect(await runJobs(d, { startedAt: 0 })).toEqual({ done: 2, failed: 0, stoppedForTime: false });
    expect(d.claim).toHaveBeenCalledTimes(3);
  });

  it("stops claiming when less than 15 s of the 60 s budget is left", async () => {
    const clock = { t: 0 };
    // Each job takes 20 s: the third starts at 40 s (20 s left, more than the reserve); at 60 s no fourth starts.
    const d = deps([job(1), job(2), job(3), job(4)], clock, {
      k: () => {
        clock.t += 20_000;
        return Promise.resolve();
      },
    });
    const r = await runJobs(d, { startedAt: 0 });
    expect(r).toEqual({ done: 3, failed: 0, stoppedForTime: true });
    expect(d.claim).toHaveBeenCalledTimes(3);
  });

  it("does not start a job with less than 15 s left", async () => {
    const clock = { t: 45_000 };
    const d = deps([job(1)], clock, { k: () => Promise.resolve() });
    expect(await runJobs(d, { startedAt: 0 })).toEqual({ done: 0, failed: 0, stoppedForTime: true });
    expect(d.claim).not.toHaveBeenCalled();
  });

  it("fails a job that throws and makes an unknown kind permanent", async () => {
    const clock = { t: 0 };
    const d = deps([job(1), job(2, "nope"), job(3)], clock, {
      k: (j) => (j.id === 3 ? Promise.reject(new PermanentJobError("bad payload")) : Promise.reject(new Error("boom"))),
    });
    expect(await runJobs(d, { startedAt: 0 })).toEqual({ done: 0, failed: 3, stoppedForTime: false });
    expect(d.finished).toEqual([
      [1, false, "boom"],
      [2, false, "no handler for nope"],
      [3, false, "bad payload"],
    ]);
    expect(d.markPermanent).toHaveBeenCalledTimes(2);
  });
});
