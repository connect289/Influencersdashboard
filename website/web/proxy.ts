import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { encodeTouch, touchFromUrl } from "@/lib/attribution";
import { BOOT_SCRIPT } from "@/lib/client/boot-script";
import { buildCsp } from "@/lib/security/csp";
import { findRedirect, recordRedirectHit } from "@/lib/server/redirects";
import { createHash } from "node:crypto";

const BOOT_HASH = `sha256-${createHash("sha256").update(BOOT_SCRIPT).digest("base64")}`;

/**
 * Runs before every page request (not static assets):
 * - request id (propagated to logs, DB calls and the outbox) — spec 3A observability
 * - attribution: first-touch / last-touch cookies when the URL carries UTM, click ids or a creator code — spec 9.2
 * - per-request nonce CSP on the dynamic, sensitive areas (/account, /admin); static pages use the header from
 *   next.config.ts (D-025)
 */
const NONCE_AREAS = /^\/(account|admin)(\/|$)/;
const MAX_AGE = 60 * 60 * 24 * 90;

export async function proxy(req: NextRequest) {
  // Admin-managed redirects (old URLs, renamed slugs) before anything else.
  const redirect = await findRedirect(req.nextUrl.pathname);
  if (redirect) {
    recordRedirectHit(req.nextUrl.pathname.replace(/\/+$/, "") || "/");
    const to = redirect.to.startsWith("/") ? new URL(redirect.to + req.nextUrl.search, req.url) : new URL(redirect.to);
    return NextResponse.redirect(to, redirect.code);
  }
  // Signed-out visitors to the account area go straight to sign-in (a real 307 instead of a streamed redirect).
  const path = req.nextUrl.pathname;
  if (path.startsWith("/account") && !path.startsWith("/account/sign-in") && !req.cookies.get("ew_sid")) {
    const to = new URL("/account/sign-in", req.url);
    to.searchParams.set("next", path);
    return NextResponse.redirect(to, 307);
  }
  const requestId = req.headers.get("x-request-id") ?? req.headers.get("x-vercel-id") ?? crypto.randomUUID();
  const reqHeaders = new Headers(req.headers);
  reqHeaders.set("x-request-id", requestId);

  let nonce: string | null = null;
  let csp: string | null = null;
  if (NONCE_AREAS.test(req.nextUrl.pathname)) {
    nonce = Buffer.from(crypto.randomUUID()).toString("base64");
    csp = buildCsp({
      nonce,
      hashes: [BOOT_HASH],
      dev: process.env.NODE_ENV === "development",
      supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL,
    });
    // Next reads the nonce from the request's CSP header while rendering and stamps it on its scripts.
    reqHeaders.set("x-nonce", nonce);
    reqHeaders.set("Content-Security-Policy", csp);
  }

  const res = NextResponse.next({ request: { headers: reqHeaders } });
  res.headers.set("x-request-id", requestId);
  if (csp) {
    // Same policy (same nonce) on the response as Next saw on the request.
    res.headers.set("Content-Security-Policy", csp);
    res.headers.set("Cache-Control", "private, no-store");
    res.headers.set("X-Robots-Tag", "noindex, nofollow");
  }

  // Staff session refresh for the admin area (Server Components cannot write cookies).
  if (req.nextUrl.pathname.startsWith("/admin") && process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY) {
    const auth = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
      {
        cookies: {
          getAll: () => req.cookies.getAll(),
          setAll: (list) => {
            for (const { name, value, options } of list) res.cookies.set(name, value, options);
          },
        },
      },
    );
    await auth.auth.getClaims();
  }

  const touch = touchFromUrl(req.nextUrl, req.headers.get("referer"));
  if (touch) {
    const value = encodeTouch(touch);
    const opts = {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax" as const,
      path: "/",
      maxAge: MAX_AGE,
    };
    if (!req.cookies.get("ew_ft")) res.cookies.set("ew_ft", value, opts);
    res.cookies.set("ew_lt", value, opts);
  }
  return res;
}

export const config = {
  matcher: [
    {
      source:
        "/((?!api|_next/static|_next/image|brand|fonts|favicon.ico|robots.txt|sitemap.xml|.*\\.(?:svg|png|jpg|jpeg|webp|avif|ico|woff2|txt|xml)$).*)",
      missing: [
        { type: "header", key: "next-router-prefetch" },
        { type: "header", key: "purpose", value: "prefetch" },
      ],
    },
  ],
};
