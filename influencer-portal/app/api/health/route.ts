import { NextResponse } from "next/server";
import { errorMessage, log } from "@/lib/log";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

/**
 * Liveness for the oversight system (spec 18). Public, so it returns booleans only, never details.
 * 200 when the database and storage answer and the job queue isn't stuck; 503 otherwise (also when the server
 * environment is invalid: every check is false and the log names the variables).
 */
export async function GET() {
  let db: ReturnType<typeof adminClient> | null = null;
  try {
    db = adminClient();
  } catch (e) {
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
      version: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? "dev",
      time: new Date().toISOString(),
    },
    { status: ok ? 200 : 503, headers: { "cache-control": "no-store" } },
  );
}
