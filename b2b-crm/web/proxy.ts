import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { buildCsp, IDLE_LIMIT_SECONDS, isIdleExpired, safeNext, SEEN_COOKIE } from "@/lib/security";

/**
 * Runs before every page request:
 *  1. refreshes the Supabase session cookie (JWT verified by getClaims);
 *  2. signs out sessions idle for 12 hours (spec B3);
 *  3. sends signed-out visitors to /login;
 *  4. sets a strict Content-Security-Policy with a fresh nonce.
 * This is an early, cheap check. The real gate is requireAdmin() on the server and b2b.is_admin() in the database.
 */

const PUBLIC = ["/login", "/forgot"];
const isPublic = (path: string) => PUBLIC.includes(path) || path.startsWith("/auth/");

type Cookie = { name: string; value: string; options?: Parameters<NextResponse["cookies"]["set"]>[2] };

export async function proxy(request: NextRequest) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;
  const isDev = process.env.NODE_ENV === "development";
  const nonce = btoa(crypto.randomUUID());
  const csp = buildCsp(nonce, new URL(url).origin, isDev);

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
        noStore = { ...noStore, ...headers }; // keeps auth cookies out of shared caches
      },
    },
  });

  const { data } = await supabase.auth.getClaims();
  const userId = data?.claims?.sub ?? null;
  const path = request.nextUrl.pathname;
  const now = Math.floor(Date.now() / 1000);
  const seen = request.cookies.get(SEEN_COOKIE)?.value;

  const finish = (res: NextResponse) => {
    for (const c of pending) res.cookies.set(c.name, c.value, c.options);
    for (const [k, v] of Object.entries(noStore)) res.headers.set(k, v);
    res.headers.set("Content-Security-Policy", csp);
    return res;
  };

  if (userId && isIdleExpired(seen, now)) {
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

  if (userId && path === "/login") return finish(NextResponse.redirect(new URL("/", request.url)));

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", csp);
  const res = NextResponse.next({ request: { headers: requestHeaders } });
  if (userId) {
    res.cookies.set(SEEN_COOKIE, String(now), {
      httpOnly: true,
      secure: !isDev,
      sameSite: "lax",
      path: "/",
      maxAge: IDLE_LIMIT_SECONDS * 2,
    });
  } else if (seen) {
    res.cookies.delete(SEEN_COOKIE); // a stale timer must not sign out the next sign-in
  }
  return finish(res);
}

export const config = {
  matcher: [
    {
      source: "/((?!_next/static|_next/image|favicon.ico|icon.png|apple-icon.png|brand/).*)",
      missing: [
        { type: "header", key: "next-router-prefetch" },
        { type: "header", key: "purpose", value: "prefetch" },
      ],
    },
  ],
};
