import { describe, expect, it } from "vitest";
import { handBack, JobBudget, jobDeadline, runJobs, runPart, SAFETY_MS, whileTime, type Job } from "./job-budget";

/** A clock the test moves by hand. */
const clock = (t = 0) => ({ now: () => t, add: (ms: number) => { t += ms; } });
const job = (name: string, run: Job["run"], more: Partial<Job> = {}): Job => ({ name, reserveMs: 1_000, minMs: 500, run, ...more });
const LIMIT = 60_000;

describe("a job's own deadline", () => {
  const jobs = [job("a", async () => 0, { tailMs: 20_000 }), job("b", async () => 0, { reserveMs: 6_000 }), job("c", async () => 0), job("d", async () => 0)];

  it("is the limit less the safety margin less what the later jobs keep", () => {
    expect(jobDeadline(jobs, 3, 0, LIMIT)).toBe(LIMIT - SAFETY_MS);
    expect(jobDeadline(jobs, 2, 0, LIMIT)).toBe(LIMIT - SAFETY_MS - 1_000);
    expect(jobDeadline(jobs, 1, 0, LIMIT)).toBe(LIMIT - SAFETY_MS - 2_000);
    expect(jobDeadline(jobs.slice(1), 0, 5_000, LIMIT)).toBe(5_000 + LIMIT - SAFETY_MS - 2_000); // counted from the run's start
  });

  it("is earlier still for a job whose unit of work needs a longer tail, and never later than the safety margin", () => {
    expect(jobDeadline([jobs[0]!], 0, 0, LIMIT)).toBe(LIMIT - 20_000);
    expect(jobDeadline(jobs, 0, 0, LIMIT)).toBe(LIMIT - 20_000); // the later jobs keep 8 s: the tail is the stricter of the two
    expect(jobDeadline([jobs[0]!, job("big", async () => 0, { reserveMs: 15_000 })], 0, 0, LIMIT)).toBe(LIMIT - SAFETY_MS - 15_000);
    expect(jobDeadline([job("x", async () => 0, { tailMs: 1_000 })], 0, 0, LIMIT)).toBe(LIMIT - SAFETY_MS);
  });
});

describe("runJobs", () => {
  it("runs the jobs in the order given and reports each with its time", async () => {
    const c = clock();
    const order: string[] = [];
    const run = await runJobs(
      [job("first", async () => { order.push("first"); c.add(300); return { n: 1 }; }), job("second", async () => { order.push("second"); c.add(50); return 7; })],
      { startedAt: 0, limitMs: LIMIT, now: c.now },
    );
    expect(order).toEqual(["first", "second"]);
    expect(run.jobs).toEqual([{ name: "first", status: "ran", ms: 300 }, { name: "second", status: "ran", ms: 50 }]);
    expect(run.results).toEqual({ first: { n: 1 }, second: 7 });
  });

  it("gives each job a deadline from the time really left, so a slow job cannot use the later jobs' time", async () => {
    const c = clock();
    const seen: Record<string, number> = {};
    const jobs = [
      job("slow", async (b) => { seen.slow = b.deadline; while (b.hasTime()) c.add(1_000); }),
      job("next", async (b) => { seen.next = b.deadline; seen.nextLeft = b.left(); c.add(200); }),
      job("last", async (b) => { seen.last = b.deadline; seen.lastLeft = b.left(); }),
    ];
    const run = await runJobs(jobs, { startedAt: 0, limitMs: LIMIT, now: c.now });
    expect(seen).toMatchObject({ slow: 48_000, next: 49_000, nextLeft: 1_000, last: 50_000, lastLeft: 1_800 });
    expect(run.jobs.map((j) => [j.name, j.status, j.ms])).toEqual([["slow", "ran", 48_000], ["next", "ran", 200], ["last", "ran", 0]]);
  });

  it("skips a job that has no time left, cleanly: it is never called and is not a failure", async () => {
    const c = clock();
    let called = 0;
    const run = await runJobs(
      [job("overruns", async () => { c.add(49_700); }), job("late", async () => { called++; }), job("later", async () => { called++; })],
      { startedAt: 0, limitMs: LIMIT, now: c.now },
    );
    expect(called).toBe(0);
    expect(run.jobs).toEqual([
      { name: "overruns", status: "ran", ms: 49_700 },
      { name: "late", status: "skipped", ms: 0, reason: "no time left: 0 ms before its deadline, it needs 500" },
      { name: "later", status: "skipped", ms: 0, reason: "no time left: 300 ms before its deadline, it needs 500" },
    ]);
    expect(run.results).toEqual({ overruns: undefined });
  });

  it("starts no job in the safety margin, however little the job says it needs", async () => {
    const c = clock(LIMIT - SAFETY_MS + 1);
    let called = 0;
    const run = await runJobs([job("any", async () => { called++; }, { minMs: 0, reserveMs: 0 })], { startedAt: 0, limitMs: LIMIT, now: c.now });
    expect(called).toBe(0);
    expect(run.jobs[0]).toMatchObject({ status: "skipped" });
  });

  it("reports a job that stopped between items as stopped_early, with the parts", async () => {
    const c = clock();
    const done: number[] = [];
    const run = await runJobs(
      [job("loop", async (b) => {
        const rest = await whileTime(b, [1, 2, 3, 4, 5], async (n) => { done.push(n); c.add(20_000); });
        if (rest.length) b.stopEarly("items");
        return { done: done.length, rest };
      })],
      { startedAt: 0, limitMs: LIMIT, now: c.now },
    );
    expect(done).toEqual([1, 2, 3]); // 0 s, 20 s and 40 s are before the deadline at 50 s; 60 s is not
    expect(run.results.loop).toEqual({ done: 3, rest: [4, 5] });
    expect(run.jobs).toEqual([{ name: "loop", status: "stopped_early", ms: 60_000, stopped: ["items"] }]);
  });

  it("keeps a failure to its own job: reported as failed, the next job still runs", async () => {
    const c = clock();
    const run = await runJobs(
      [job("breaks", async () => { c.add(10); throw new Error("database is away"); }), job("fine", async () => "ok")],
      { startedAt: 0, limitMs: LIMIT, now: c.now },
    );
    expect(run.jobs).toEqual([{ name: "breaks", status: "failed", ms: 10, reason: "database is away" }, { name: "fine", status: "ran", ms: 0 }]);
    expect(run.results).toEqual({ fine: "ok" });
  });
});

describe("inside a job", () => {
  it("whileTime starts an item only while there is time, and returns the ones it did not start", async () => {
    const c = clock();
    const b = new JobBudget(100, c.now);
    const done: string[] = [];
    expect(await whileTime(b, ["a", "b", "c", "d"], async (x) => { done.push(x); c.add(60); })).toEqual(["c", "d"]);
    expect(done).toEqual(["a", "b"]); // b started at 60 ms, before the deadline, and was left to finish
    expect(await whileTime(b, ["e"], async (x) => { done.push(x); })).toEqual(["e"]);
    expect(await whileTime(new JobBudget(), ["f"], async (x) => { done.push(x); })).toEqual([]); // no deadline: always time
    expect(done).toEqual(["a", "b", "f"]);
  });

  it("whileTime starts a long unit only with time to finish it", async () => {
    const c = clock();
    const b = new JobBudget(25_000, c.now);
    const done: number[] = [];
    expect(await whileTime(b, [1, 2, 3], async (n) => { done.push(n); c.add(8_000); }, 10_000)).toEqual([3]); // at 16 s only 9 s are left
    expect(done).toEqual([1, 2]);
  });

  it("runPart skips a part with no time (or not enough for it), keeps an error to the part, and notes what was not started", async () => {
    const c = clock();
    const b = new JobBudget(1_000, c.now);
    const out: Record<string, unknown> = {};
    await runPart(b, out, "one", async () => { c.add(400); return 3; });
    await runPart(b, out, "two", async () => { throw new Error("mail server refused"); });
    await runPart(b, out, "long", async () => "never", 20_000);
    c.add(700);
    await runPart(b, out, "three", async () => "never");
    expect(out).toEqual({ one: 3, two_error: "mail server refused" });
    expect(b.notStarted).toEqual(["long", "three"]);
    expect(b.stopped).toEqual([]);
  });

  it("handBack releases what was not started, the attempt not counted, and marks the part; nothing to release, nothing called", async () => {
    const calls: unknown[] = [];
    const db = { rpc: async (fn: "job_release", args: { p_kind: string; p_ids: number[] }) => { calls.push([fn, args]); return { error: null }; } };
    const b = new JobBudget();
    expect(await handBack(db, b, "push", "push", [])).toBe(0);
    expect(calls).toEqual([]);
    expect(b.stopped).toEqual([]);
    expect(await handBack(db, b, "push", "push", [4, 5])).toBe(2);
    expect(calls).toEqual([["job_release", { p_kind: "push", p_ids: [4, 5] }]]);
    expect(b.stopped).toEqual(["push"]);
    const refuses = { rpc: async () => ({ error: { message: "permission denied" } }) };
    await expect(handBack(refuses, b, "push", "push", [6])).rejects.toThrow("job_release (push): permission denied");
  });
});
