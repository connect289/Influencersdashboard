import { env } from "./env";

/**
 * Admin-managed redirects (web_redirects) applied by the proxy at request time, after the static legacy map in
 * next.config.ts. The table is small; it is cached in memory for 60 seconds per server instance.
 */
type Map = Record<string, { to: string; code: number }>;
let cache: { at: number; map: Map } | null = null;
let inflight: Promise<Map> | null = null;

async function load(): Promise<Map> {
  const e = env();
  if (!e.SUPABASE_SECRET_KEY) return {};
  const res = await fetch(`${e.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/web_redirects_all`, {
    method: "POST",
    headers: { apikey: e.SUPABASE_SECRET_KEY, authorization: `Bearer ${e.SUPABASE_SECRET_KEY}`, "content-type": "application/json" },
    body: "{}",
    signal: AbortSignal.timeout(1500),
  });
  if (!res.ok) throw new Error(`redirects ${res.status}`);
  return (await res.json()) as Map;
}

export async function findRedirect(pathname: string): Promise<{ to: string; code: number } | null> {
  const now = Date.now();
  if (!cache || now - cache.at > 60_000) {
    try {
      inflight ??= load();
      cache = { at: now, map: await inflight };
    } catch {
      // Keep serving the last good map and try again only after a full interval: the proxy runs before every page, so
      // while the database is unreachable each request would otherwise wait for the 1.5 s timeout.
      cache = { at: now, map: cache?.map ?? {} };
    } finally {
      inflight = null;
    }
  }
  const key = pathname.length > 1 ? pathname.replace(/\/+$/, "") : pathname;
  return cache.map[key] ?? null;
}

/** Counts a hit without delaying the response. */
export function recordRedirectHit(pathname: string) {
  const e = env();
  if (!e.SUPABASE_SECRET_KEY) return;
  void fetch(`${e.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/web_redirect_hit`, {
    method: "POST",
    headers: { apikey: e.SUPABASE_SECRET_KEY, authorization: `Bearer ${e.SUPABASE_SECRET_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ p_from: pathname }),
  }).catch(() => undefined);
}
