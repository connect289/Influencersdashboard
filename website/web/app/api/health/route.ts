import { connection } from "next/server";
import { env, isDeployed } from "@/lib/server/env";
import { dbConfigured, rpc } from "@/lib/server/db";
import { isInternal } from "@/lib/server/internal-auth";
import { kv, kvShared } from "@/lib/server/kv";
import { LIMITS, rateLimit } from "@/lib/server/rate-limit";
import { ipFrom } from "@/lib/server/request";

/**
 * Health for uptime checks and the future oversight system (spec 9.4, 15): database, read model, outbox backlog,
 * email provider, AI provider and key-value store. 200 when the site can take leads; 503 when the database is down.
 * Public callers get only { ok }; the detail (configuration state, never secrets) needs the internal bearer key.
 */
export async function GET(req: Request) {
  await connection();
  const detail = isInternal(req);
  if (!detail && !(await rateLimit(LIMITS.beaconPerIp, ipFrom(req))).ok) return Response.json({ ok: true }, { status: 429 });
  const started = performance.now();
  const e = env();
  const checks: Record<string, unknown> = {};
  let ok = true;
  if (dbConfigured()) {
    try {
      const t = performance.now();
      const h = await rpc<Record<string, unknown>>("web_health");
      checks.db = { ok: true, ms: Math.round(performance.now() - t), ...h };
      if (Number(h.outbox_dead) > 0) checks.outbox = { ok: false, dead: h.outbox_dead };
      // Catalogue sync (D-081): the poll runs every minute; over 10 minutes without a check means it has stopped.
      const age = h.catalog_checked_seconds_ago == null ? null : Number(h.catalog_checked_seconds_ago);
      checks.catalog = { ok: age !== null && age < 600, checked_seconds_ago: age, refreshed_at: h.catalog_refreshed_at, unmapped: h.catalog_unmapped };
    } catch (err) {
      ok = false;
      checks.db = { ok: false, error: err instanceof Error ? err.name : "error" };
    }
  } else {
    ok = false;
    checks.db = { ok: false, error: "not configured" };
  }
  try {
    await kv().set("health:ping", Date.now(), 60);
    checks.kv = { ok: true, store: kvShared() ? "upstash" : isDeployed() ? "memory (rate limits use Postgres)" : "memory" };
  } catch {
    checks.kv = { ok: false };
  }
  checks.email = { ok: e.EMAIL_PROVIDER !== "console" || e.APP_ENV !== "production", provider: e.EMAIL_PROVIDER };
  checks.ai = { ok: true, configured: !!e.ANTHROPIC_API_KEY, mode: e.ANTHROPIC_API_KEY ? "live" : "mock" };
  checks.turnstile = { configured: !!e.TURNSTILE_SECRET_KEY };
  return Response.json(
    detail ? { ok, env: e.APP_ENV, ms: Math.round(performance.now() - started), checks } : { ok },
    { status: ok ? 200 : 503, headers: { "cache-control": "no-store" } },
  );
}
