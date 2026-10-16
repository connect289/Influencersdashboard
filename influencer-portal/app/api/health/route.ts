import { NextResponse } from "next/server";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

/**
 * Liveness for the oversight system (spec 18). Public, so it returns booleans only, never details.
 * 200 when the database and storage answer and the job queue isn't stuck; 503 otherwise.
 */
export async function GET() {
  const db = adminClient();
  const [health, storage] = await Promise.all([
    db.rpc("health").then(
      (r) => (r.error ? null : (r.data as { db: boolean; queue_ok: boolean })),
      () => null,
    ),
    db.storage.listBuckets().then(
      (r) => !r.error,
      () => false,
    ),
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
