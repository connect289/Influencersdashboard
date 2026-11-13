import { NextResponse } from "next/server";
import { env, envProblems, envWarnings } from "@/lib/env";
import { errorMessage, log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
// A health call never outlives the caller's patience: Eduwit One gives up after 5 s, and a function that kept waiting
// on a slow database ran up to Vercel's 300 s ceiling and was billed for it (the Vercel pause of 3 Nov 2026).
export const maxDuration = 10;
const CHECK_TIMEOUT_MS = 3_000;

/** The promise's value, or `fallback` when it has not settled within CHECK_TIMEOUT_MS. */
async function within<T>(p: PromiseLike<T>, fallback: T): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<T>((resolve) => {
    timer = setTimeout(() => resolve(fallback), CHECK_TIMEOUT_MS);
  });
  try {
    return await Promise.race([p, late]);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Liveness for the oversight system (spec 18). Public, so it returns booleans only, never details.
 * 200 when the database and storage answer within 3 s and the job queue isn't stuck; 503 otherwise. When the server
 * environment is invalid every check is false and `env` lists the variable names and the rule each breaks (never
 * values), so a misconfigured deployment can be diagnosed without access to the hosting logs. `warnings` names
 * recommended variables that are missing and what that costs (the unsubscribe signing secret); it never changes the
 * status.
 */
export async function GET() {
  let db: ReturnType<typeof adminClient> | null = null;
  let envIssues: string[] = [];
  let warnings: string[] = [];
  try {
    db = adminClient();
    warnings = envWarnings(env());
  } catch (e) {
    envIssues = envProblems(process.env);
    log.error("health.config_invalid", { error: errorMessage(e) });
  }
  const [health, storage] = await Promise.all([
    within(
      db?.rpc("health").then(
        (r) => (r.error ? null : (r.data as { db: boolean; queue_ok: boolean })),
        () => null,
      ) ?? Promise.resolve(null),
      null,
    ),
    within(
      db?.storage.listBuckets().then(
        (r) => !r.error,
        () => false,
      ) ?? Promise.resolve(false),
      false,
    ),
  ]);
  const checks = { db: health?.db === true, storage, queue: health?.queue_ok === true };
  const ok = checks.db && checks.storage && checks.queue;
  return NextResponse.json(
    {
      status: ok ? "ok" : "degraded",
      checks,
      ...(envIssues.length > 0 ? { env: envIssues } : {}),
      ...(warnings.length > 0 ? { warnings } : {}),
      version: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? "dev",
      time: new Date().toISOString(),
    },
    { status: ok ? 200 : 503, headers: { "cache-control": "no-store" } },
  );
}
