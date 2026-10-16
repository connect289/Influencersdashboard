import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { buildCsp, IDLE_LIMIT_SECONDS, isIdleExpired, safeNext, SEEN_COOKIE } from "@/lib/security";

/**
 * Runs before every page request (Next 16's request hook):
 *  1. refreshes the Supabase session cookie (JWT verified by getClaims);
 *  2. signs out a browser idle past 12 hours (the database also enforces the configured idle limit);
 *  3. sends signed-out visitors on protected pages to the right sign-in page;
 *  4. sets a strict Content-Security-Policy with a fresh nonce, and passes the path to server code for redirects.
 * This is a cheap early check. The real gates are requireStaff()/requireCreator() and the inf.* functions.
 */

const PUBLIC_EXACT = new Set(["/", "/login", "/login/staff", "/login/code", "/no-access", "/offline"]);
const PUBLIC_PREFIX = ["/auth/", "/password/", "/api/health", "/api/public/", "/r/"];
const isPublic = (path: string) => PUBLIC_EXACT.has(path) || PUBLIC_PREFIX.some((p) => path.startsWith(p));

type Cookie = { name: string; value: string; options?: Parameters<NextResponse["cookies"]["set"]>[2] };

export async function proxy(request: NextRequest) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "";
  const isDev = process.env.NODE_ENV === "development";
  const nonce = btoa(crypto.randomUUID());
  const csp = buildCsp(nonce, url ? new URL(url).origin : "'self'", isDev);
  const requestId = request.headers.get("x-request-id") ?? crypto.randomUUID();

  const pending: Cookie[] = [];
  let noStore: Record<string, string> = {};
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(toSet, headers) {
        for (const c of toSet) {
          request.cookies.set(c.name, c.value);
          pending.push(c);
        }
        noStore = { ...noStore, ...headers };
      },
    },
  });

  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims.sub ?? null;
  const path = request.nextUrl.pathname;
  const now = Math.floor(Date.now() / 1000);
  const seen = request.cookies.get(SEEN_COOKIE)?.value;
  const loginFor = (p: string) => (p.startsWith("/admin") || p === "/verify" ? "/login/staff" : "/login");

  const finish = (res: NextResponse) => {
    for (const c of pending) res.cookies.set(c.name, c.value, c.options);
    for (const [k, v] of Object.entries(noStore)) res.headers.set(k, v);
    res.headers.set("Content-Security-Policy", csp);
    res.headers.set("x-request-id", requestId);
    return res;
  };

  if (userId && isIdleExpired(seen, now)) {
    await supabase.auth.signOut({ scope: "local" });
    const res = NextResponse.redirect(new URL(`${loginFor(path)}?reason=idle`, request.url));
    res.cookies.delete(SEEN_COOKIE);
    return finish(res);
  }

  if (!userId && !isPublic(path)) {
    const login = new URL(loginFor(path), request.url);
    login.searchParams.set("next", safeNext(path + request.nextUrl.search));
    const res = NextResponse.redirect(login);
    if (seen) res.cookies.delete(SEEN_COOKIE);
    return finish(res);
  }

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("x-inf-path", path + request.nextUrl.search);
  requestHeaders.set("x-request-id", requestId);
  requestHeaders.set("Content-Security-Policy", csp);
  const res = NextResponse.next({ request: { headers: requestHeaders } });
  if (userId) {
    res.cookies.set(SEEN_COOKIE, String(now), { httpOnly: true, secure: !isDev, sameSite: "lax", path: "/", maxAge: IDLE_LIMIT_SECONDS * 2 });
  } else if (seen) {
    res.cookies.delete(SEEN_COOKIE);
  }
  return finish(res);
}

export const config = {
  matcher: [
    {
      // Machine endpoints authenticate their own callers (internal key, HMAC) and get no session handling.
      source: "/((?!_next/static|_next/image|favicon.ico|icon.png|apple-icon.png|brand/|manifest.webmanifest|sw.js|api/internal/|api/metrics/).*)",
      missing: [
        { type: "header", key: "next-router-prefetch" },
        { type: "header", key: "purpose", value: "prefetch" },
      ],
    },
  ],
};
