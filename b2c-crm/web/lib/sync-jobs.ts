import "server-only";
import { runAnalyticsJobs } from "@/lib/analytics-jobs";
import { runClassify } from "@/lib/classify";
import type { Job, JobsRun } from "@/lib/job-budget";
import { runLeadJobs } from "@/lib/lead-jobs";
import { runPhase4Jobs } from "@/lib/phase4-jobs";
import { runPush } from "@/lib/push";
import { sendSupportMail } from "@/lib/support-jobs";
import { runOutbox, runSends } from "@/lib/sync";
import { runWaMediaJobs } from "@/lib/wa-media-jobs";

/**
 * The jobs of one call to /api/internal/sync, most urgent first; lib/job-budget.ts gives each its own deadline.
 * Messages to students and staff go first and stop starting sends 20 seconds before the limit (a send has 15 to answer,
 * then its outcome is recorded). Then what must reach the B2B CRM at once (consent, opt-out, erasure, new students; the
 * 15-minute batch has more to send, so more time is kept for it), phone alerts, replies waiting for their class, files
 * students sent, files of erased students, support mail, recordings and calendars, large exports (one can take a whole
 * run), and analytics last. reserveMs is what the earlier jobs must leave a job; with less than minMs before its
 * deadline a job is skipped until the next run. The batch run sends messages and the B2B batch only, as before.
 */
export function syncJobs(mode: "urgent" | "batch"): Job[] {
  const small = { reserveMs: 1_000, minMs: 500 };
  const jobs: Job[] = [
    { name: "messages", reserveMs: 0, minMs: 2_000, tailMs: 20_000, run: (b) => runSends(b) }, // first: no job runs before it
    { name: "b2b", reserveMs: mode === "batch" ? 15_000 : 6_000, minMs: 2_000, run: (b) => runOutbox(mode, b) },
  ];
  if (mode === "batch") return jobs;
  return [
    ...jobs,
    { name: "push", ...small, run: (b) => runPush(b) },
    { name: "classify", ...small, run: (b) => runClassify(b) },
    { name: "media", ...small, run: (b) => runWaMediaJobs(10, b) },
    { name: "erased_files", ...small, run: (b) => runLeadJobs(b, ["erased_files"]) },
    { name: "support", ...small, run: (b) => sendSupportMail(10, b) },
    { name: "phase4", ...small, run: (b) => runPhase4Jobs(b) },
    { name: "exports", ...small, run: (b) => runLeadJobs(b, ["exports"]) },
    { name: "analytics", ...small, run: (b) => runAnalyticsJobs(new Date(), b) },
  ];
}

/** The two jobs whose failure makes the route answer 500, as a failed sync always did. */
const CORE = new Set(["messages", "b2b"]);

/**
 * The route's answer. Every field it had keeps its name and shape (the counts of the B2B sync and of the messages at the
 * top, one entry per job with the job's own answer, or <name>_error when it failed); new are `jobs` (per job: ran,
 * skipped, stopped_early or failed, its milliseconds, and the parts stopped or not started) and `skipped` on the entry
 * of a job that had no time left.
 */
export function syncAnswer(mode: "urgent" | "batch", run: JobsRun): { status: number; body: Record<string, unknown> } {
  const entry = (name: string, key = name): unknown => {
    const j = run.jobs.find((x) => x.name === name);
    if (!j) return {};
    if (j.status === "failed") return { [`${key}_error`]: j.reason };
    if (j.status === "skipped") return { skipped: j.reason };
    return run.results[name];
  };
  const fields = (v: unknown): Record<string, unknown> => (typeof v === "object" && v !== null ? (v as Record<string, unknown>) : {});
  const counts = (name: string) => (run.jobs.some((j) => j.name === name && j.status !== "failed" && j.status !== "skipped") ? fields(run.results[name]) : {});
  const body: Record<string, unknown> = {
    ok: true, mode, taken: 0, failed: 0, sent: 0, dry_run: 0, send_failed: 0, released: 0, ...counts("b2b"), ...counts("messages"),
    push: entry("push"), classify: entry("classify"), analytics: entry("analytics"), phase4: entry("phase4"), support: entry("support"),
    leads: { ...fields(entry("erased_files", "leads")), ...fields(entry("exports", "leads")) }, media: entry("media"), jobs: run.jobs,
  };
  const broken = run.jobs.find((j) => CORE.has(j.name) && j.status === "failed");
  if (broken) return { status: 500, body: { ...body, ok: false, error: `${broken.name}: ${broken.reason}` } };
  return { status: 200, body };
}
