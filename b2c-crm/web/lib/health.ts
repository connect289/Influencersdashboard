// Spark's health (GET /api/health), as pure functions so the rules are unit-tested. The route gathers three readings
// (the configuration, the database's b2c.health() report, file storage) and this module turns them into one answer.
//
// ok (HTTP 200) means Spark can do its work: its configuration is complete, its database and file storage answer
// within 3 seconds, its timers run and the app answers them. status adds the rest: "degraded" when a queue, a
// connector, the programme cache, Claude or a bulk job needs a look (Eduwit One's B2C-* checks name it), "down" when ok
// is false. Public callers see only the levels; the counts need the internal key. Nothing here names a student.

export type Level = "ok" | "warn" | "bad";
export type Check = { level: Level } & Record<string, unknown>;

/** The parts the route reads itself; the database's report adds the rest (b2c.health(), migration b53). */
export const CORE = ["config", "database", "storage", "timers", "app"] as const;
export const REPORTED = ["timers", "app", "outbox", "inbox", "sending", "connectors", "programmes", "ai", "jobs"] as const;

const REQUIRED = [
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
  "NEXT_PUBLIC_SITE_URL",
  "B2C_INTERNAL_KEY",
] as const;
const B2B = ["B2B_API_URL", "B2B_API_KEY", "B2B_SIGNING_SECRET"] as const;

/** The buckets Spark keeps files in (documents, call recordings, support attachments). */
export const BUCKETS = ["b2c-documents", "b2c-recordings", "b2c-support"] as const;

/** Which variables are missing or malformed: names only, never a value. */
export function configCheck(env: Record<string, string | undefined>): Check {
  const missing = REQUIRED.filter((n) => !env[n]);
  const weak: string[] = [];
  if (env.B2C_INTERNAL_KEY && env.B2C_INTERNAL_KEY.length < 32) weak.push("B2C_INTERNAL_KEY (shorter than 32 characters: the timers' calls are refused)");
  const gmailKey = env.GMAIL_TOKEN_KEY?.trim();
  if (gmailKey) {
    const bytes = /^[0-9a-f]{64}$/i.test(gmailKey) ? 32 : Buffer.from(gmailKey.replace(/-/g, "+").replace(/_/g, "/"), "base64").length;
    if (bytes !== 32) weak.push("GMAIL_TOKEN_KEY (not 32 bytes)");
  }
  const b2bMissing = B2B.filter((n) => !env[n]);
  const b2bLink = b2bMissing.length === 0;
  const level: Level = missing.length > 0 || weak.length > 0 ? "bad" : !b2bLink ? "warn" : "ok";
  return { level, missing: [...missing, ...(b2bLink ? [] : b2bMissing)], invalid: weak, b2b_link: b2bLink, live_mode: env.LIVE_MODE === "on" };
}

/** File storage: the call answered and Spark's buckets exist. */
export function storageCheck(buckets: string[] | null): Check {
  if (buckets === null) return { level: "bad", answered: false };
  const missing = BUCKETS.filter((b) => !buckets.includes(b));
  return { level: missing.length > 0 ? "warn" : "ok", answered: true, missing_buckets: missing };
}

const isLevel = (v: unknown): v is Level => v === "ok" || v === "warn" || v === "bad";

/** The database's report, or a "bad" database when it did not answer (or answered something else). */
export function reportChecks(report: unknown): { database: Check; checks: Record<string, Check> } {
  const r = report as { checks?: Record<string, unknown> } | null;
  const raw = r && typeof r === "object" && r.checks && typeof r.checks === "object" ? r.checks : null;
  if (!raw) return { database: { level: "bad", answered: false }, checks: {} };
  const checks: Record<string, Check> = {};
  for (const key of REPORTED) {
    const c = raw[key] as Record<string, unknown> | undefined;
    checks[key] = c && isLevel(c.level) ? ({ ...c, level: c.level } as Check) : { level: "warn", reported: false };
  }
  return { database: { level: "ok", answered: true }, checks };
}

export type Health = {
  ok: boolean;
  status: "ok" | "degraded" | "down";
  checks: Record<string, Check>;
};

/** One answer from the three readings. */
export function combine(config: Check, storage: Check, report: unknown): Health {
  const { database, checks: reported } = reportChecks(report);
  const checks: Record<string, Check> = { config, database, storage, ...reported };
  // With no answer from the database, the timers and the app are not reported (the database is the bad part).
  const ok = CORE.every((k) => checks[k]?.level !== "bad");
  const anyIssue = Object.values(checks).some((c) => c.level !== "ok");
  return { ok, status: !ok ? "down" : anyIssue ? "degraded" : "ok", checks };
}

/** What a caller without the internal key sees: the levels only. */
export function publicView(h: Health): { ok: boolean; status: Health["status"]; checks: Record<string, Level> } {
  return { ok: h.ok, status: h.status, checks: Object.fromEntries(Object.entries(h.checks).map(([k, c]) => [k, c.level])) };
}
