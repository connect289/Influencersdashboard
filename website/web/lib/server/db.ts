import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { env } from "./env";
import { log } from "./log";

/**
 * Service-role Supabase client — server only. The website talks to Postgres exclusively through web_* SECURITY DEFINER
 * functions (and the shared functions they wrap); it never queries shared tables directly from the app.
 */
let client: SupabaseClient | null = null;

export function db(): SupabaseClient {
  if (client) return client;
  const e = env();
  if (!e.SUPABASE_SECRET_KEY) throw new DbUnavailableError("SUPABASE_SECRET_KEY is not set");
  client = createClient(e.NEXT_PUBLIC_SUPABASE_URL, e.SUPABASE_SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { "x-client-info": "eduwit-website" } },
  });
  return client;
}

export class DbUnavailableError extends Error {
  override name = "DbUnavailableError";
}

export class DbError extends Error {
  override name = "DbError";
  constructor(
    message: string,
    readonly fn: string,
    readonly code?: string,
  ) {
    super(message);
  }
}

/** Calls a Postgres function and returns its result, throwing a typed error (logged without PII). */
export async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const started = performance.now();
  const { data, error } = await db().rpc(fn, args);
  const ms = Math.round(performance.now() - started);
  if (error) {
    // Next's request-time prerender aborts in-flight fetches when it completes; that is not a database failure.
    const aborted = error.message.includes("During prerendering, fetch() rejects");
    log(aborted ? "debug" : "error", aborted ? "db.rpc_prerender_aborted" : "db.rpc_failed", { fn, ms, code: error.code, message: aborted ? undefined : error.message });
    throw new DbError(error.message, fn, error.code);
  }
  if (ms > 300) log("warn", "db.rpc_slow", { fn, ms });
  return data as T;
}

/** Whether a database is configured (lets pages degrade gracefully at build time or in mock mode). */
export function dbConfigured(): boolean {
  return !!env().SUPABASE_SECRET_KEY;
}
