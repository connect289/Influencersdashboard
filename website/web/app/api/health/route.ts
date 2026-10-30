import { connection } from "next/server";
import { env, isDeployed } from "@/lib/server/env";
import { dbConfigured, rpc } from "@/lib/server/db";
import { emailProvider } from "@/lib/server/email";
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
      // Outbox worker (pg_cron web_outbox_worker, every minute, D-082): dead letters, or a job waiting 10+ minutes, means trouble.
      const oldest = Number(h.outbox_oldest_pending_seconds ?? 0);
      checks.outbox = { ok: Number(h.outbox_dead) === 0 && oldest < 600, dead: h.outbox_dead, pending: h.outbox_pending, oldest_pending_seconds: oldest };
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
  // The provider that actually sends ("smtp" without EMAIL_SMTP_HOST sends nothing): a deployed site cannot email codes
  // through the console.
  const sender = emailProvider();
  checks.email = { ok: sender !== "console" || !isDeployed(), provider: sender, chosen: e.EMAIL_PROVIDER };
  const live = e.GEMINI_API_KEY ? "gemini" : e.ANTHROPIC_API_KEY ? "claude" : null;
  checks.ai = { ok: true, configured: !!live, mode: live ? "live" : "mock", provider: live };
  // Both halves are needed: the site key (read at build time) renders the widget, the secret verifies its token.
  checks.turnstile = { configured: !!e.TURNSTILE_SECRET_KEY, site_key: !!e.NEXT_PUBLIC_TURNSTILE_SITE_KEY };
  return Response.json(
    detail ? { ok, env: e.APP_ENV, ms: Math.round(performance.now() - started), checks } : { ok },
    { status: ok ? 200 : 503, headers: { "cache-control": "no-store" } },
  );
}
