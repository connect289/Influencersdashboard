import { NextResponse } from "next/server";
import { assertUser, type Me } from "@/lib/auth";
import { gmailTokenKey, googleOAuthClient, siteUrl } from "@/lib/env";
import { backToMe, toLogin } from "@/lib/gmail-connect";
import { authUrl, CALLBACK_PATH, newState, OAUTH_COOKIE, pkce } from "@/lib/gmail-oauth";

export const dynamic = "force-dynamic";

/**
 * "Connect my Gmail" (spec B17, D6), step 1: the signed-in person goes to Google's consent screen for gmail.send,
 * gmail.readonly and gmail.metadata with offline access. The state and the PKCE verifier wait in an http-only cookie
 * bound to this person, for ten minutes, and only for the callback's path.
 */
export async function GET() {
  let me: Me;
  try {
    me = await assertUser();
  } catch {
    return toLogin();
  }
  const client = googleOAuthClient();
  let key: Buffer | null = null;
  try { key = gmailTokenKey(); } catch (e) { console.error("[gmail-connect]", (e as Error).message); }
  if (!client || !key) return backToMe(me, "not_configured");

  const { verifier, challenge } = pkce();
  const state = newState();
  const res = NextResponse.redirect(authUrl({ clientId: client.clientId, redirectUri: siteUrl() + CALLBACK_PATH, state, challenge, email: me.email }), 303);
  res.cookies.set(OAUTH_COOKIE, JSON.stringify({ s: state, v: verifier, u: me.user_id }), {
    httpOnly: true, secure: process.env.NODE_ENV !== "development", sameSite: "lax", path: "/auth/google/gmail", maxAge: 600,
  });
  return res;
}
