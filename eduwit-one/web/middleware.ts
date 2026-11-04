import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import {
  buildCsp,
  DEFAULT_IDLE_SECONDS,
  isIdleExpired,
  safeNext,
  SEEN_COOKIE,
  seenFresh,
  seenKey,
  seenValue,
  signedInAt,
} from "./lib/security.ts";

/**
 * Before every page request (Spark's proxy.ts, adapted):
 *  1. refreshes the Supabase session cookie (getClaims verifies the JWT);
 *  2. signs out a session idle for access.idle_hours (a signed, per-session cookie; a missing one counts as idle);
 *  3. sends signed-out visitors to /login;
 *  4. sets a strict Content-Security-Policy with a fresh nonce.
 * An early, cheap check only: the real gate is requireUser() on the server and one.ui_require() in the database.
 * The /api routes are outside the matcher: each authenticates its own caller (bearer key) or is public and detail-free.
 */

const isPublic = (path: string) => path === "/login" || path === "/pending" || path.startsWith("/auth/");

type Cookie = { name: string; value: string; options?: Parameters<NextResponse["cookies"]["set"]>[2] };

// access.idle_hours, read through one.me() at most once a minute per server instance (the setting is the same for
// everyone; me() is the one function a signed-in session may call before the second step).
const idlePolicy = { seconds: DEFAULT_IDLE_SECONDS, at: 0 };
async function idleSeconds(url: string, key: string, token: string | undefined): Promise<number> {
  if (!token || Date.now() - idlePolicy.at < 60_000) return idlePolicy.seconds;
  idlePolicy.at = Date.now();
  try {
    const res = await fetch(`${url}/rest/v1/rpc/me`, {
      method: "POST",
      headers: {
        apikey: key,
        authorization: `Bearer ${token}`,
        "content-profile": "one",
        "content-type": "application/json",
      },
      body: "{}",
      cache: "no-store",
    });
    const hours = res.ok ? Number(((await res.json()) as { idle_hours?: unknown }).idle_hours) : NaN;
    if (Number.isFinite(hours) && hours > 0 && hours <= 720) idlePolicy.seconds = Math.round(hours * 3600);
  } catch {
    // keep the last known value
  }
  return idlePolicy.seconds;
}

// The idle cookie's signing key, derived from ONE_INTERNAL_KEY once per process (security review m6).
const cookieKeys = { from: "", key: "" };
async function cookieKey(internalKey: string | undefined): Promise<string | undefined> {
  if (!internalKey) return undefined;
  if (cookieKeys.from !== internalKey) {
    cookieKeys.key = await seenKey(internalKey);
    cookieKeys.from = internalKey;
  }
  return cookieKeys.key;
}

export async function middleware(request: NextRequest) {
  // Prefetches skip the middleware (Vercel accepts only string matchers, so the exclusion lives here, not in the
  // matcher's `missing`): a background prefetch must not redirect or count as activity for the idle rule.
  if (request.headers.get("next-router-prefetch") !== null || request.headers.get("purpose") === "prefetch") {
    return NextResponse.next();
  }
  const url = process.env.ONE_SUPABASE_URL;
  const key = process.env.ONE_SUPABASE_ANON_KEY;
  const isDev = process.env.NODE_ENV === "development";
  const nonce = btoa(crypto.randomUUID());
  const csp = buildCsp(nonce, isDev, url ? new URL(url).origin : undefined);
  const path = request.nextUrl.pathname;

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", csp);
  // The page's own path, for the layout's sign-in redirect (layouts are not told their path).
  requestHeaders.set("x-path", safeNext(path + request.nextUrl.search));
  const pending: Cookie[] = [];
  let noStore: Record<string, string> = {};
  const finish = (res: NextResponse) => {
    for (const c of pending) res.cookies.set(c.name, c.value, c.options);
    for (const [k, v] of Object.entries(noStore)) res.headers.set(k, v);
    res.headers.set("Content-Security-Policy", csp);
    return res;
  };

  // Not configured yet (Setup item one_app_env): only the sign-in page, which says what is missing.
  if (!url || !key) {
    if (path === "/login") return finish(NextResponse.next({ request: { headers: requestHeaders } }));
    return finish(NextResponse.redirect(new URL("/login?error=not_configured", request.url)));
  }

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(toSet, headers) {
        for (const c of toSet) {
          request.cookies.set(c.name, c.value);
          pending.push(c);
        }
        noStore = { ...noStore, ...headers }; // keeps auth cookies out of shared caches
      },
    },
  });
  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub ?? null;
  const now = Math.floor(Date.now() / 1000);
  const seen = request.cookies.get(SEEN_COOKIE)?.value;
  const limit = userId
    ? await idleSeconds(url, key, (await supabase.auth.getSession()).data.session?.access_token)
    : DEFAULT_IDLE_SECONDS;
  // The idle cookie is signed with a key derived from the internal key (m6) and bound to the session (S5). Without the
  // key (a local build), the plain timestamp is kept and a missing cookie is not idle, as before.
  const signKey = await cookieKey(process.env.ONE_INTERNAL_KEY);
  const sessionId = typeof data?.claims?.session_id === "string" ? data.claims.session_id : "";
  const idle = userId
    ? signKey && sessionId
      ? !(await seenFresh({ key: signKey, sessionId, value: seen, now, limit, signedInAt: signedInAt(data?.claims) }))
      : isIdleExpired(seen, now, limit)
    : false;

  if (idle) {
    await supabase.auth.signOut({ scope: "local" });
    const res = NextResponse.redirect(new URL("/login?reason=idle", request.url));
    res.cookies.delete(SEEN_COOKIE);
    return finish(res);
  }
  if (!userId && !isPublic(path)) {
    const login = new URL("/login", request.url);
    if (path !== "/") login.searchParams.set("next", safeNext(path + request.nextUrl.search));
    const res = NextResponse.redirect(login);
    if (seen) res.cookies.delete(SEEN_COOKIE);
    return finish(res);
  }

  const res = NextResponse.next({ request: { headers: requestHeaders } });
  if (userId) {
    res.cookies.set(SEEN_COOKIE, signKey && sessionId ? await seenValue(signKey, sessionId, now) : String(now), {
      httpOnly: true,
      secure: !isDev,
      sameSite: "lax",
      path: "/",
      maxAge: limit * 2,
    });
  } else if (seen) {
    res.cookies.delete(SEEN_COOKIE);
  }
  return finish(res);
}

export const config = {
  // A plain path matcher: Vercel's build rejects the object form (source + missing); prefetches are skipped in code above.
  matcher: ["/((?!_next/static|_next/image|favicon.ico|icon.png|apple-icon.png|brand/|api/).*)"],
};
