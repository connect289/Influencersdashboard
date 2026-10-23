import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { buildCsp, DEFAULT_IDLE_SECONDS, isIdleExpired, safeNext, SEEN_COOKIE } from "./lib/security.ts";

/**
 * Before every page request (Spark's proxy.ts, adapted):
 *  1. refreshes the Supabase session cookie (getClaims verifies the JWT);
 *  2. signs out a session idle for 12 hours;
 *  3. sends signed-out visitors to /login;
 *  4. sets a strict Content-Security-Policy with a fresh nonce.
 * An early, cheap check only: the real gate is requireUser() on the server and one.ui_require() in the database.
 * The /api routes are outside the matcher: each authenticates its own caller (bearer key) or is public and detail-free.
 */

const isPublic = (path: string) => path === "/login" || path === "/pending" || path.startsWith("/auth/");

type Cookie = { name: string; value: string; options?: Parameters<NextResponse["cookies"]["set"]>[2] };

export async function middleware(request: NextRequest) {
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

  if (userId && isIdleExpired(seen, now, DEFAULT_IDLE_SECONDS)) {
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
    res.cookies.set(SEEN_COOKIE, String(now), {
      httpOnly: true,
      secure: !isDev,
      sameSite: "lax",
      path: "/",
      maxAge: DEFAULT_IDLE_SECONDS * 2,
    });
  } else if (seen) {
    res.cookies.delete(SEEN_COOKIE);
  }
  return finish(res);
}

export const config = {
  matcher: [
    {
      source: "/((?!_next/static|_next/image|favicon.ico|icon.png|apple-icon.png|brand/|api/).*)",
      missing: [
        { type: "header", key: "next-router-prefetch" },
        { type: "header", key: "purpose", value: "prefetch" },
      ],
    },
  ],
};
