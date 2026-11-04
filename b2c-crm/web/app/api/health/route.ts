import { NextResponse, type NextRequest } from "next/server";
import { BUCKETS, combine, configCheck, publicView, storageCheck, type Health } from "@/lib/health";
import { internalKeyOk } from "@/lib/internal";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
// A health call never outlives its caller's patience: Eduwit One waits 5 s, and a function left waiting on a slow
// database runs (and is billed) up to Vercel's ceiling. The database and storage each get 3 s, the call 10 s.
export const maxDuration = 10;
const READ_TIMEOUT_MS = 3_000;
// One reading serves every caller for 15 s, so a flood of calls cannot become a flood of database queries.
const CACHE_MS = 15_000;

let cached: { at: number; health: Health } | null = null;

/** The promise's value, or `fallback` when it has not settled within READ_TIMEOUT_MS (or failed). */
async function within<T>(p: PromiseLike<T>, fallback: T): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<T>((resolve) => {
    timer = setTimeout(() => resolve(fallback), READ_TIMEOUT_MS);
  });
  try {
    return await Promise.race([Promise.resolve(p).catch(() => fallback), late]);
  } finally {
    clearTimeout(timer);
  }
}

async function read(): Promise<Health> {
  const config = configCheck(process.env);
  let db: ReturnType<typeof adminClient> | null = null;
  try {
    db = adminClient();
  } catch {
    db = null; // the service role key is missing: config says so, and the database and storage count as down
  }
  const [report, buckets] = await Promise.all([
    db ? within(db.rpc("health").then((r) => (r.error ? null : (r.data as unknown))), null) : Promise.resolve(null),
    db
      ? within(
          db.storage.listBuckets().then((r) => (r.error ? null : (r.data ?? []).map((b) => b.name).filter((n) => (BUCKETS as readonly string[]).includes(n)))),
          null,
        )
      : Promise.resolve(null),
  ]);
  return combine(config, storageCheck(buckets), report);
}

/**
 * Spark's health, for Eduwit One (every 5 minutes) and uptime checks: the configuration, the database, file storage,
 * the timers and the app answering them, the feeds to and from the master lead table, sending, connectors, the
 * programme cache, Claude and bulk jobs (lib/health.ts, b2c.health()). 200 when Spark can work, 503 when it cannot.
 * Public callers get the levels; the counts need x-internal-key (the timers' key). No student data either way.
 */
export async function GET(request: NextRequest) {
  const now = Date.now();
  if (!cached || now - cached.at > CACHE_MS) cached = { at: now, health: await read() };
  const health = cached.health;
  const detail = internalKeyOk(request.headers.get("x-internal-key"), process.env.B2C_INTERNAL_KEY);
  return NextResponse.json(
    {
      ...(detail ? health : publicView(health)),
      version: process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? "dev",
      time: new Date(cached.at).toISOString(),
    },
    { status: health.ok ? 200 : 503, headers: { "cache-control": "no-store" } },
  );
}
