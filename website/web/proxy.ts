import { NextResponse, type NextRequest } from "next/server";
import { encodeTouch, touchFromUrl } from "@/lib/attribution";
import { buildCsp } from "@/lib/security/csp";

/**
 * Runs before every page request (not static assets):
 * - request id (propagated to logs, DB calls and the outbox) — spec 3A observability
 * - attribution: first-touch / last-touch cookies when the URL carries UTM, click ids or a creator code — spec 9.2
 * - per-request nonce CSP on the dynamic, sensitive areas (/account, /admin); static pages use the header from
 *   next.config.ts (D-025)
 */
const NONCE_AREAS = /^\/(account|admin)(\/|$)/;
const MAX_AGE = 60 * 60 * 24 * 90;

export function proxy(req: NextRequest) {
  const requestId = req.headers.get("x-request-id") ?? req.headers.get("x-vercel-id") ?? crypto.randomUUID();
  const reqHeaders = new Headers(req.headers);
  reqHeaders.set("x-request-id", requestId);

  let nonce: string | null = null;
  if (NONCE_AREAS.test(req.nextUrl.pathname)) {
    nonce = Buffer.from(crypto.randomUUID()).toString("base64");
    reqHeaders.set("x-nonce", nonce);
  }

  const res = NextResponse.next({ request: { headers: reqHeaders } });
  res.headers.set("x-request-id", requestId);
  if (nonce) {
    res.headers.set(
      "Content-Security-Policy",
      buildCsp({
        nonce,
        dev: process.env.NODE_ENV === "development",
        supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL,
      }),
    );
    res.headers.set("Cache-Control", "private, no-store");
    res.headers.set("X-Robots-Tag", "noindex, nofollow");
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
