// Pure helpers shared by proxy.ts, route handlers and server actions. Unit-tested in security.test.ts.

/** Seconds of inactivity after which a session is signed out (spec B3: 12 hours). */
export const IDLE_LIMIT_SECONDS = 12 * 60 * 60;
export const SEEN_COOKIE = "b2b_seen";

/**
 * A redirect target from user input (?next=…). Only same-origin absolute paths are allowed, so the app can never be
 * used to bounce someone to another site ("//evil.com", "/\\evil.com", "https://…" are all rejected).
 */
export function safeNext(next: string | null | undefined, fallback = "/"): string {
  if (!next || typeof next !== "string" || next.length > 512) return fallback;
  if (!next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return fallback;
  if (/[\u0000-\u001f\\]/.test(next)) return fallback;
  return next;
}

/** True when the last-seen timestamp (epoch seconds) is older than the idle limit. A missing or bad value is not idle. */
export function isIdleExpired(lastSeen: string | undefined, nowSeconds: number, limit = IDLE_LIMIT_SECONDS): boolean {
  if (!lastSeen) return false;
  const seen = Number(lastSeen);
  if (!Number.isFinite(seen) || seen <= 0) return false;
  return nowSeconds - seen > limit;
}

/** Content-Security-Policy for one request. Scripts need the per-request nonce; nothing else may run. */
export function buildCsp(nonce: string, supabaseOrigin: string, isDev: boolean): string {
  const wsOrigin = supabaseOrigin.replace(/^https:/, "wss:");
  const directives: Record<string, string[]> = {
    "default-src": ["'self'"],
    "script-src": ["'self'", `'nonce-${nonce}'`, "'strict-dynamic'", ...(isDev ? ["'unsafe-eval'"] : [])],
    // Inline style attributes are used by UI libraries; style injection cannot run code.
    "style-src": ["'self'", "'unsafe-inline'"],
    "img-src": ["'self'", "data:", "blob:", supabaseOrigin, "https://lh3.googleusercontent.com"],
    "font-src": ["'self'"],
    "connect-src": ["'self'", supabaseOrigin, wsOrigin],
    "frame-src": ["'none'"],
    "frame-ancestors": ["'none'"],
    "object-src": ["'none'"],
    "base-uri": ["'self'"],
    "form-action": ["'self'"],
    "manifest-src": ["'self'"],
    "worker-src": ["'self'", "blob:"],
  };
  const parts = Object.entries(directives).map(([k, v]) => `${k} ${v.join(" ")}`);
  if (!isDev) parts.push("upgrade-insecure-requests");
  return parts.join("; ");
}

/** Client IP for the sign-in log, from the platform's forwarding header (Vercel sets x-forwarded-for). */
export function clientIp(headers: Headers): string | null {
  const forwarded = headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ip = forwarded || headers.get("x-real-ip") || null;
  return ip && /^[0-9a-fA-F:.]{3,45}$/.test(ip) ? ip : null;
}

export const PASSWORD_MIN = 12;
export const PASSWORD_MAX = 128;

export function passwordProblem(password: string, confirm?: string): string | null {
  if (password.length < PASSWORD_MIN) return `Use at least ${PASSWORD_MIN} characters.`;
  if (password.length > PASSWORD_MAX) return `Use at most ${PASSWORD_MAX} characters.`;
  if (confirm !== undefined && password !== confirm) return "The two passwords do not match.";
  return null;
}
