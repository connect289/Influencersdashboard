import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { RATE_LIMITS, rateIp, rateKey, retryAfter, type RateScope } from "@/lib/security";

/**
 * Rate limits on the public endpoints (spec B18, D14): one b2c.rate_check hit per request, per address and route, in a
 * fixed window. Used by proxy.ts (the token pages and the email tracking links), the /v1 route handlers and the
 * qualification form's submit. No "server-only" import, so proxy.ts can use it; it still runs on the server only.
 * A database failure lets the request through (logged): a limit must never take the endpoints down.
 */
type Db = ReturnType<typeof make>;
let client: Db | null = null;

function make() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }, db: { schema: "b2c" } });
}

export type RateResult = { ok: true } | { ok: false; retryAfter: number };

export async function rateCheck(scope: string, headers: Headers, kind: RateScope): Promise<RateResult> {
  const [limit, seconds] = RATE_LIMITS[kind];
  client ??= make();
  if (!client) return { ok: true };
  try {
    const { data, error } = await client.rpc("rate_check", { p_key: rateKey(scope, rateIp(headers)), p_limit: limit, p_seconds: seconds });
    if (error) throw new Error(error.message);
    return data === false ? { ok: false, retryAfter: retryAfter(seconds) } : { ok: true };
  } catch (e) {
    console.warn(`[rate] ${scope}: check failed, allowed:`, e instanceof Error ? e.message : String(e));
    return { ok: true };
  }
}

export function tooMany(retry: number, json = true): NextResponse {
  const headers = { "retry-after": String(retry), "cache-control": "no-store" };
  return json
    ? NextResponse.json({ ok: false, error: "too many requests" }, { status: 429, headers })
    : new NextResponse("Too many requests. Try again in a minute.", { status: 429, headers: { ...headers, "content-type": "text/plain; charset=utf-8" } });
}

/** For a route handler: null to go on, or the 429 answer. */
export async function limit(request: Request, scope: string, kind: RateScope): Promise<NextResponse | null> {
  const r = await rateCheck(scope, request.headers, kind);
  return r.ok ? null : tooMany(r.retryAfter);
}
