import { connection } from "next/server";
import { env } from "@/lib/server/env";
import { dbConfigured, rpc } from "@/lib/server/db";
import { kv } from "@/lib/server/kv";

/**
 * Health for uptime checks and the future oversight system (spec 9.4, 15): database, read model, outbox backlog,
 * email provider, AI provider and key-value store. 200 when the site can take leads; 503 when the database is down.
 * Reports configuration state only — never secrets.
 */
export async function GET() {
  await connection();
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
    checks.kv = { ok: true, store: e.UPSTASH_REDIS_REST_URL ? "upstash" : "memory" };
  } catch {
    checks.kv = { ok: false };
  }
  checks.email = { ok: e.EMAIL_PROVIDER !== "console" || e.APP_ENV !== "production", provider: e.EMAIL_PROVIDER };
  checks.ai = { ok: true, configured: !!e.ANTHROPIC_API_KEY, mode: e.ANTHROPIC_API_KEY ? "live" : "mock" };
  checks.turnstile = { configured: !!e.TURNSTILE_SECRET_KEY };
  return Response.json(
    { ok, env: e.APP_ENV, ms: Math.round(performance.now() - started), checks },
    { status: ok ? 200 : 503, headers: { "cache-control": "no-store" } },
  );
}
