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

/**
 * Optional Supabase read replica for the heavy, read-only catalogue calls (search, suggestions, details). An ad spike
 * then never competes with Witty and the CRMs on the shared primary. Unset → the primary (D-080).
 */
let readClient: SupabaseClient | null = null;

function readDb(): SupabaseClient {
  const e = env();
  if (!e.SUPABASE_READ_REPLICA_URL) return db();
  if (readClient) return readClient;
  if (!e.SUPABASE_SECRET_KEY) throw new DbUnavailableError("SUPABASE_SECRET_KEY is not set");
  readClient = createClient(e.SUPABASE_READ_REPLICA_URL, e.SUPABASE_SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { "x-client-info": "eduwit-website-read" } },
  });
  return readClient;
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
  return call<T>(db(), fn, args);
}

/** Same as rpc() for read-only catalogue functions; uses the read replica when one is configured. */
export async function rpcRead<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  return call<T>(readDb(), fn, args);
}

/**
 * Per-instance cap on concurrent database calls. The PostgREST connection pool is shared with Witty and the CRMs, so
 * one busy website instance queues here (and fails fast after 3 s) instead of taking every pooled connection (load
 * tests, D-080). WEB_DB_MAX_CONCURRENCY changes the cap.
 */
const gate = globalThis as unknown as { __ewDbGate?: { active: number; queue: (() => void)[] } };
async function acquire(): Promise<() => void> {
  const g = (gate.__ewDbGate ??= { active: 0, queue: [] });
  const max = env().WEB_DB_MAX_CONCURRENCY;
  if (g.active >= max) {
    await new Promise<void>((resolve, reject) => {
      const t = setTimeout(() => {
        const i = g.queue.indexOf(go);
        if (i !== -1) g.queue.splice(i, 1);
        reject(new DbUnavailableError("database busy"));
      }, 3000);
      const go = () => {
        clearTimeout(t);
        resolve();
      };
      g.queue.push(go);
    });
  }
  g.active++;
  return () => {
    g.active--;
    g.queue.shift()?.();
  };
}

async function call<T>(c: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<T> {
  let release: () => void;
  try {
    release = await acquire();
  } catch (err) {
    log("warn", "db.busy", { fn });
    throw err;
  }
  try {
    return await callNow<T>(c, fn, args);
  } finally {
    release();
  }
}

async function callNow<T>(c: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<T> {
  const started = performance.now();
  const { data, error } = await c.rpc(fn, args);
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
