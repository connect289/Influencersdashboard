import "server-only";
import { NextResponse } from "next/server";
import type { Me } from "@/lib/auth";
import { siteUrl } from "@/lib/env";
import { FLASH_COOKIE, OAUTH_COOKIE } from "@/lib/gmail-oauth";

/** Shared by the two "Connect my Gmail" routes: back to the person's Me page with a short-lived flash message. */
export function backToMe(me: Pick<Me, "role"> | null, flash: string): NextResponse {
  const path = me?.role === "marketing" ? "/w" : "/s/me?tab=availability#connections";
  const res = NextResponse.redirect(new URL(path, siteUrl()), 303);
  res.cookies.set(FLASH_COOKIE, flash, { httpOnly: true, secure: process.env.NODE_ENV !== "development", sameSite: "lax", path: "/", maxAge: 60 });
  res.cookies.set(OAUTH_COOKIE, "", { httpOnly: true, secure: process.env.NODE_ENV !== "development", sameSite: "lax", path: "/auth/google/gmail", maxAge: 0 });
  return res;
}

export function toLogin(): NextResponse {
  return NextResponse.redirect(new URL(`/login?next=${encodeURIComponent("/s/me?tab=availability")}`, siteUrl()), 303);
}
