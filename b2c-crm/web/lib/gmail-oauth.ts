import { createCipheriv, createDecipheriv, createHash, randomBytes, timingSafeEqual } from "node:crypto";

/**
 * Each person's own Gmail, connected by OAuth (spec B16–B18, D6). Google's authorization-code flow with PKCE (S256) and a
 * state cookie; offline access gives a refresh token, which is sealed here with AES-256-GCM (key GMAIL_TOKEN_KEY) and
 * stored by b2c.connection_save. A send unseals it, asks Google for a fresh access token and sends as the person.
 * No "server-only" import so the helpers are unit-tested (gmail-oauth.test.ts); the routes and the job use them on the
 * server only.
 */
export const GMAIL_SCOPES = [
  "https://www.googleapis.com/auth/gmail.send",
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/gmail.metadata",
] as const;
export const OAUTH_COOKIE = "b2c_gmail_oauth";
export const FLASH_COOKIE = "b2c_gmail_flash";
export const CALLBACK_PATH = "/auth/google/gmail/callback";

const b64url = (b: Buffer) => b.toString("base64url");

// ---------- sealing the refresh token ----------

/**
 * "v1." + base64url(iv | tag | ciphertext). The additional data binds the token to one person and provider, so a sealed
 * token copied onto another person's row does not open.
 */
export function sealToken(plain: string, key: Buffer, aad: string): string {
  if (key.length !== 32) throw new Error("the token key must be 32 bytes");
  const iv = randomBytes(12);
  const c = createCipheriv("aes-256-gcm", key, iv);
  c.setAAD(Buffer.from(aad, "utf8"));
  const ct = Buffer.concat([c.update(plain, "utf8"), c.final()]);
  return "v1." + b64url(Buffer.concat([iv, c.getAuthTag(), ct]));
}

export function unsealToken(sealed: string, key: Buffer, aad: string): string {
  if (!sealed.startsWith("v1.")) throw new Error("unknown sealed token format");
  const raw = Buffer.from(sealed.slice(3), "base64url");
  if (raw.length < 12 + 16 + 1) throw new Error("sealed token too short");
  const d = createDecipheriv("aes-256-gcm", key, raw.subarray(0, 12));
  d.setAAD(Buffer.from(aad, "utf8"));
  d.setAuthTag(raw.subarray(12, 28));
  return Buffer.concat([d.update(raw.subarray(28)), d.final()]).toString("utf8");
}

export const tokenAad = (userId: string, provider = "gmail") => `${provider}:${userId}`;

// ---------- the authorization request ----------

export function pkce(): { verifier: string; challenge: string } {
  const verifier = b64url(randomBytes(32));
  return { verifier, challenge: b64url(createHash("sha256").update(verifier).digest()) };
}

export function newState(): string {
  return randomBytes(24).toString("hex");
}

export function sameState(a: string | null | undefined, b: string | null | undefined): boolean {
  if (!a || !b || a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a), Buffer.from(b));
}

export function authUrl(o: { clientId: string; redirectUri: string; state: string; challenge: string; email?: string | null }): string {
  const q = new URLSearchParams({
    client_id: o.clientId,
    redirect_uri: o.redirectUri,
    response_type: "code",
    scope: ["openid", "email", ...GMAIL_SCOPES].join(" "),
    access_type: "offline",
    prompt: "consent", // a refresh token every time, also on a reconnect
    include_granted_scopes: "true",
    hd: "eduwit.in",
    state: o.state,
    code_challenge: o.challenge,
    code_challenge_method: "S256",
    ...(o.email ? { login_hint: o.email } : {}),
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${q}`;
}

// ---------- Google's token endpoint ----------

export type TokenAnswer = { access_token?: string; refresh_token?: string; id_token?: string; scope?: string; expires_in?: number; error?: string; error_description?: string };

export async function exchangeCode(o: { clientId: string; clientSecret: string; redirectUri: string; code: string; verifier: string }, fetchImpl: typeof fetch = fetch): Promise<TokenAnswer> {
  const res = await fetchImpl("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "authorization_code", code: o.code, client_id: o.clientId, client_secret: o.clientSecret, redirect_uri: o.redirectUri, code_verifier: o.verifier }),
    signal: AbortSignal.timeout(15_000),
    cache: "no-store",
  });
  return (await res.json().catch(() => ({ error: `HTTP ${res.status}` }))) as TokenAnswer;
}

/** A fresh access token from the refresh token. Google answers invalid_grant once the person revoked access. */
export async function refreshAccess(o: { clientId: string; clientSecret: string; refreshToken: string }, fetchImpl: typeof fetch = fetch): Promise<{ ok: true; token: string } | { ok: false; error: string }> {
  try {
    const res = await fetchImpl("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: o.refreshToken, client_id: o.clientId, client_secret: o.clientSecret }),
      signal: AbortSignal.timeout(15_000),
      cache: "no-store",
    });
    const t = (await res.json().catch(() => ({}))) as TokenAnswer;
    if (t.access_token) return { ok: true, token: t.access_token };
    return { ok: false, error: `${t.error ?? `HTTP ${res.status}`}${t.error_description ? `: ${t.error_description}` : ""}` };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

/**
 * The account's email from the id_token Google returned on the token call. It came straight from Google over TLS, so
 * (as OpenID Connect allows for the token endpoint) the signature is not checked again; the audience and the issuer are.
 */
export function idTokenEmail(idToken: string | undefined, clientId: string): string | null {
  const part = idToken?.split(".")[1];
  if (!part) return null;
  try {
    const c = JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as { email?: string; email_verified?: boolean | string; aud?: string; iss?: string };
    if (c.aud !== clientId || !["https://accounts.google.com", "accounts.google.com"].includes(c.iss ?? "")) return null;
    if (!(c.email_verified === true || c.email_verified === "true")) return null;
    return typeof c.email === "string" ? c.email.trim().toLowerCase() : null;
  } catch {
    return null;
  }
}

export const grantedScopes = (scope: string | undefined) => (scope ?? "").split(/\s+/).filter(Boolean);

/** The flash message the Connect flow leaves for the Me page (a short-lived cookie: GmailConnection reads it). */
export const FLASH: Record<string, string> = {
  connected: "Gmail connected: your emails to students now go from your own mailbox.",
  cancelled: "Gmail was not connected (Google sign-in was cancelled).",
  mismatch: "Connect your own @eduwit.in mailbox: the Google account you chose is a different one.",
  no_refresh: "Google did not give Spark lasting access. Remove Spark at myaccount.google.com/permissions and connect again.",
  no_send: "Spark needs permission to send from Gmail: tick every box Google shows and connect again.",
  expired: "The connection took too long or was started in another tab. Try again.",
  not_configured: "Connecting Gmail is not set up yet (Google OAuth client and GMAIL_TOKEN_KEY). Ask the Admin.",
  failed: "Gmail could not be connected. Try again; if it keeps failing, raise a support ticket.",
};
