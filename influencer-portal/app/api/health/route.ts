import { NextResponse } from "next/server";
import { envProblems } from "@/lib/env";
import { errorMessage, log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

/**
 * Liveness for the oversight system (spec 18). Public, so it returns booleans only, never details.
 * 200 when the database and storage answer and the job queue isn't stuck; 503 otherwise. When the server environment
 * is invalid every check is false and `env` lists the variable names and the rule each breaks (never values), so a
 * misconfigured deployment can be diagnosed without access to the hosting logs.
 */
export async function GET() {
  let db: ReturnType<typeof adminClient> | null = null;
  let envIssues: string[] = [];
  try {
    db = adminClient();
  } catch (e) {
    envIssues = envProblems(process.env);
    log.error("health.config_invalid", { error: errorMessage(e) });
  }
  const [health, storage] = await Promise.all([
    db?.rpc("health").then(
      (r) => (r.error ? null : (r.data as { db: boolean; queue_ok: boolean })),
      () => null,
    ) ?? null,
    db?.storage.listBuckets().then(
      (r) => !r.error,
      () => false,
    ) ?? false,
  ]);
  const checks = { db: health?.db === true, storage, queue: health?.queue_ok === true };
  const ok = checks.db && checks.storage && checks.queue;
  return NextResponse.json(
    {
      status: ok ? "ok" : "degraded",
      checks,
      ...(envIssues.length > 0 ? { env: envIssues } : {}),
      version: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? "dev",
      time: new Date().toISOString(),
    },
    { status: ok ? 200 : 503, headers: { "cache-control": "no-store" } },
  );
}
