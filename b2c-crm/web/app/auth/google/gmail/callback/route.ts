import { type NextRequest } from "next/server";
import { assertUser, type Me } from "@/lib/auth";
import { gmailTokenKey, googleOAuthClient, siteUrl } from "@/lib/env";
import { backToMe, toLogin } from "@/lib/gmail-connect";
import { CALLBACK_PATH, exchangeCode, GMAIL_SCOPES, grantedScopes, idTokenEmail, OAUTH_COOKIE, sameState, sealToken, tokenAad } from "@/lib/gmail-oauth";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

/**
 * "Connect my Gmail", step 2: Google sends the person back with a code. The state must match the cookie set for this
 * same person; the code is exchanged with the PKCE verifier; the account must be the person's own mailbox; the refresh
 * token is sealed (AES-256-GCM, GMAIL_TOKEN_KEY) and stored by b2c.connection_save. Tokens are never logged.
 */
export async function GET(request: NextRequest) {
  let me: Me;
  try {
    me = await assertUser();
  } catch {
    return toLogin();
  }
  const p = request.nextUrl.searchParams;
  let saved: { s?: string; v?: string; u?: string } = {};
  try { saved = JSON.parse(request.cookies.get(OAUTH_COOKIE)?.value ?? "{}") as typeof saved; } catch { saved = {}; }
  if (!saved.v || saved.u !== me.user_id || !sameState(p.get("state"), saved.s)) return backToMe(me, "expired");
  if (p.get("error")) return backToMe(me, "cancelled");
  const code = p.get("code");
  if (!code) return backToMe(me, "failed");

  const client = googleOAuthClient();
  let key: Buffer | null = null;
  try { key = gmailTokenKey(); } catch (e) { console.error("[gmail-connect]", (e as Error).message); }
  if (!client || !key) return backToMe(me, "not_configured");

  const tok = await exchangeCode({ ...client, redirectUri: siteUrl() + CALLBACK_PATH, code, verifier: saved.v }).catch(() => null);
  if (!tok?.access_token) {
    console.error("[gmail-connect] code exchange refused:", tok?.error ?? "no answer");
    return backToMe(me, "failed");
  }
  let email = idTokenEmail(tok.id_token, client.clientId);
  if (!email) {
    const prof = await fetch("https://gmail.googleapis.com/gmail/v1/users/me/profile", { headers: { authorization: `Bearer ${tok.access_token}` }, signal: AbortSignal.timeout(15_000), cache: "no-store" })
      .then((r) => (r.ok ? (r.json() as Promise<{ emailAddress?: string }>) : null)).catch(() => null);
    email = prof?.emailAddress?.toLowerCase() ?? null;
  }
  const revoke = () => fetch("https://oauth2.googleapis.com/revoke", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ token: tok.refresh_token ?? tok.access_token! }), signal: AbortSignal.timeout(10_000) }).catch(() => null);
  if (!email || email !== (me.email ?? "").toLowerCase()) {
    await revoke(); // not this person's mailbox: give the grant back at once
    return backToMe(me, "mismatch");
  }
  const scopes = grantedScopes(tok.scope);
  if (!scopes.includes(GMAIL_SCOPES[0])) {
    await revoke();
    return backToMe(me, "no_send");
  }
  if (!tok.refresh_token) return backToMe(me, "no_refresh");

  const { error } = await adminClient().rpc("connection_save", {
    p_user: me.user_id, p_provider: "gmail", p_email: email, p_scopes: scopes, p_token_sealed: sealToken(tok.refresh_token, key, tokenAad(me.user_id!)),
  });
  if (error) {
    console.error("[gmail-connect] connection_save failed:", error.message);
    return backToMe(me, /own/.test(error.message) ? "mismatch" : /permission to send/.test(error.message) ? "no_send" : "failed");
  }
  return backToMe(me, "connected");
}
