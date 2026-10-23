// Pure helpers for the middleware, the sign-in routes and the server actions (Spark's lib/security.ts, trimmed to
// what Eduwit One uses). Unit-tested in security.test.ts.

/** Cookie that remembers the last request, for the idle sign-out (access.idle_hours, default 12). */
export const SEEN_COOKIE = "one_seen";
/** Trusted-device cookie: skips the emailed code on this browser for access.trusted_days (spec §13: 30). */
export const DEVICE_COOKIE = "one_device";
/** Theme choice: light, dark, or absent for the system's. */
export const THEME_COOKIE = "one_theme";
export const DEFAULT_IDLE_SECONDS = 12 * 60 * 60;

/**
 * A redirect target from user input (?next=…): only same-origin absolute paths, so the app can never bounce someone to
 * another site ("//evil.test", "/\\evil.test", "https://…" are all refused).
 */
export function safeNext(next: string | null | undefined, fallback = "/"): string {
  if (!next || next.length > 512) return fallback;
  if (!next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return fallback;
  if (next.includes("\\") || [...next].some((c) => c.charCodeAt(0) < 32)) return fallback;
  return next;
}

/** True when the last-seen time (epoch seconds) is older than the idle limit. A missing or bad value is not idle. */
export function isIdleExpired(lastSeen: string | undefined, nowSeconds: number, limit = DEFAULT_IDLE_SECONDS): boolean {
  if (!lastSeen) return false;
  const seen = Number(lastSeen);
  if (!Number.isFinite(seen) || seen <= 0) return false;
  return nowSeconds - seen > limit;
}

/** How long after signing in a request may arrive without the idle cookie (the first pages after the callback). */
export const SIGN_IN_GRACE_SECONDS = 10 * 60;

async function hmac(key: string, text: string): Promise<string> {
  const k = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(text)));
  return btoa(String.fromCharCode(...sig))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

/** The idle cookie's value: the last-seen time, signed and bound to this session, so it cannot be made up or reused. */
export async function seenValue(key: string, sessionId: string, at: number): Promise<string> {
  return `${at}.${await hmac(key, `one_seen|${sessionId}|${at}`)}`;
}

/**
 * Whether a signed-in request is still within the idle limit (security review S5). The cookie must be this session's
 * and signed; a missing or forged one counts as idle, except within SIGN_IN_GRACE_SECONDS of the sign-in itself (the
 * JWT's amr time, which a token refresh does not move), when the cookie has not been set yet.
 */
export async function seenFresh(opts: {
  key: string;
  sessionId: string;
  value: string | undefined;
  now: number;
  limit: number;
  signedInAt: number | null;
}): Promise<boolean> {
  const { key, sessionId, value, now, limit, signedInAt } = opts;
  const at = Number(value?.split(".")[0]);
  if (value && Number.isFinite(at) && at > 0 && value === (await seenValue(key, sessionId, at)))
    return now - at <= limit;
  return signedInAt !== null && now - signedInAt >= 0 && now - signedInAt <= SIGN_IN_GRACE_SECONDS;
}

/** The latest authentication time in a Supabase JWT's amr claim (epoch seconds), or null. */
export function signedInAt(claims: { amr?: unknown } | null | undefined): number | null {
  const amr = Array.isArray(claims?.amr) ? (claims.amr as Array<{ timestamp?: unknown }>) : [];
  const times = amr.map((a) => Number(a?.timestamp)).filter((t) => Number.isFinite(t) && t > 0);
  return times.length ? Math.max(...times) : null;
}

/**
 * Content-Security-Policy for one request: scripts only with the per-request nonce; the browser talks to this app
 * alone (every database call is made by the server), so connect-src is 'self'. authOrigin is the Supabase project,
 * where the Google sign-in form's redirect goes first.
 */
export function buildCsp(nonce: string, isDev: boolean, authOrigin?: string): string {
  const directives: Record<string, string[]> = {
    "default-src": ["'self'"],
    "script-src": ["'self'", `'nonce-${nonce}'`, "'strict-dynamic'", ...(isDev ? ["'unsafe-eval'"] : [])],
    "style-src": ["'self'", "'unsafe-inline'"],
    "img-src": ["'self'", "data:", "blob:"],
    "font-src": ["'self'"],
    "connect-src": ["'self'"],
    "frame-src": ["'none'"],
    "frame-ancestors": ["'none'"],
    "object-src": ["'none'"],
    "base-uri": ["'self'"],
    // Sign-in posts to /auth/google, which redirects to Supabase Auth and on to Google.
    "form-action": ["'self'", ...(authOrigin ? [authOrigin] : []), "https://accounts.google.com"],
  };
  const parts = Object.entries(directives).map(([k, v]) => `${k} ${v.join(" ")}`);
  if (!isDev) parts.push("upgrade-insecure-requests");
  return parts.join("; ");
}

/** Client address for the sign-in log, from the platform's forwarding header (Vercel sets x-forwarded-for). */
export function clientIp(headers: Headers): string | null {
  const forwarded = headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ip = forwarded || headers.get("x-real-ip") || null;
  return ip && /^[0-9a-fA-F:.]{3,45}$/.test(ip) ? ip : null;
}

/** The company domain check, on the server, after Google (whose hd parameter only narrows the account picker). */
export function isAllowedEmail(email: string | null | undefined, domain = "eduwit.in"): boolean {
  return (
    typeof email === "string" && email.toLowerCase().endsWith(`@${domain.toLowerCase()}`) && email.indexOf("@") > 0
  );
}
