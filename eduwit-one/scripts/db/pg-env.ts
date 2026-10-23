// libpq settings from a Postgres connection URL. The password travels in PGPASSWORD, never in argv, so it cannot
// appear in a process listing or a log line. Shared by the preflight and the scripts in scripts/db/.

export type Target = "production" | "staging" | "other";

/** PG* variables for psql and pg_dump, or undefined when the value is not a postgres URL. */
export function pgEnv(url: string): Record<string, string> | undefined {
  try {
    const u = new URL(url);
    if (!u.protocol.startsWith("postgres")) return undefined;
    return {
      PGHOST: u.hostname, PGPORT: u.port || "5432", PGUSER: decodeURIComponent(u.username),
      PGPASSWORD: decodeURIComponent(u.password), PGDATABASE: u.pathname.slice(1) || "postgres",
      PGSSLMODE: "require", PGCONNECT_TIMEOUT: "10",
    };
  } catch {
    return undefined;
  }
}

/** Which Supabase project a URL reaches: the ref is in the host (db.<ref>.supabase.co) or the pooler user (postgres.<ref>). */
export function targetOf(url: string, refs: { production_ref: string; staging_ref: string }): Target {
  const env = pgEnv(url);
  if (!env) return "other";
  const where = `${env.PGHOST} ${env.PGUSER}`;
  if (where.includes(refs.production_ref)) return "production";
  if (where.includes(refs.staging_ref)) return "staging";
  return "other";
}
