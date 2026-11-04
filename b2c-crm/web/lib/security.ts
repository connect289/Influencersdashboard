// Pure helpers shared by proxy.ts, route handlers and server actions. Unit-tested in security.test.ts.
import { createHash } from "node:crypto";

/** Seconds of inactivity after which a session is signed out (spec B3: 12 hours). */
export const IDLE_LIMIT_SECONDS = 12 * 60 * 60;
export const SEEN_COOKIE = "b2c_seen";
/** Trusted-device cookie (30 days): skips the emailed code on this browser (spec B2). */
export const DEVICE_COOKIE = "b2c_device";

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

/**
 * The same-origin check for a cookie-signed POST to a route handler (server actions get Next's own): the browser's Origin
 * must be this deployment (the request's host, or the configured site URL), and Sec-Fetch-Site, when the browser sends
 * it, must say same-origin. A missing or opaque ("null") Origin is refused.
 */
export function sameOrigin(headers: Headers, site?: string | null): boolean {
  const origin = headers.get("origin");
  if (!origin || origin === "null") return false;
  let host: string;
  try {
    host = new URL(origin).host;
  } catch {
    return false;
  }
  const fetchSite = headers.get("sec-fetch-site");
  if (fetchSite && fetchSite !== "same-origin") return false;
  const own = [headers.get("x-forwarded-host")?.split(",")[0]?.trim(), headers.get("host")?.trim()];
  try {
    if (site) own.push(new URL(site).host);
  } catch {
    // a malformed site URL adds nothing
  }
  return own.some((h) => !!h && h.toLowerCase() === host.toLowerCase());
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
    // Any https image: Workspace profile photos and university logos come from other hosts.
    "img-src": ["'self'", "data:", "blob:", "https:"],
    "font-src": ["'self'"],
    // Call recordings play from short-lived signed links on the storage host.
    "media-src": ["'self'", supabaseOrigin, "blob:"],
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

// ---------- rate limits on the public endpoints (D14, b2c.rate_check) ----------

/** Per-IP limits as [hits, seconds]: the B2B and WhatsApp machine endpoints get more room than pages people open. */
export const RATE_LIMITS = {
  v1: [120, 60],
  webhook: [600, 60],
  page: [60, 60],
  tracking: [600, 60],
  qualify_submit: [10, 60],
} as const satisfies Record<string, readonly [number, number]>;
export type RateScope = keyof typeof RATE_LIMITS;

/** Full eight-group form of an IPv6 address, or null when it is not one. */
function expandIpv6(ip: string): string[] | null {
  if (!/^[0-9a-f:]+$/i.test(ip) || (ip.match(/::/g) ?? []).length > 1) return null;
  const [head, tail] = ip.includes("::") ? ip.split("::") : [ip, null];
  const h = head ? head.split(":") : [];
  const t = tail ? tail.split(":") : [];
  const fill = tail === null ? 0 : 8 - h.length - t.length;
  if (fill < 0 || (tail === null && h.length !== 8)) return null;
  const groups = [...h, ...Array<string>(fill).fill("0"), ...t];
  if (groups.length !== 8 || groups.some((g) => !/^[0-9a-f]{1,4}$/i.test(g))) return null;
  return groups.map((g) => g.toLowerCase().replace(/^0+(?=.)/, ""));
}

/**
 * The caller's address for rate limiting. The platform's own header first (Vercel sets x-vercel-forwarded-for and
 * x-real-ip and overwrites x-forwarded-for, so a client cannot choose its key). IPv6 is cut to its /64, because one
 * connection usually owns a whole /64 and could otherwise rotate addresses. Anything unreadable is "unknown".
 */
export function rateIp(headers: Headers): string {
  const first = (v: string | null) => v?.split(",")[0]?.trim() || null;
  let ip = first(headers.get("x-vercel-forwarded-for")) ?? first(headers.get("x-real-ip")) ?? first(headers.get("x-forwarded-for")) ?? "";
  ip = ip.replace(/^\[|\]$/g, "").replace(/%.*$/, "");
  const mapped = ip.match(/^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i);
  if (mapped) ip = mapped[1]!;
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(ip) && ip.split(".").every((o) => Number(o) <= 255)) return ip;
  const v6 = ip.includes(":") ? expandIpv6(ip) : null;
  return v6 ? `${v6.slice(0, 4).join(":")}::/64` : "unknown";
}

/** The b2c.rate_check key: scope (e.g. "v1:handoffs"), then the address. At most 200 characters, like the column. */
export function rateKey(scope: string, ip: string): string {
  return `${scope.replace(/[^a-z0-9:_-]/gi, "_")}:${ip}`.slice(0, 200);
}

/** Seconds until the fixed window b2c.rate_check counts in ends (it starts at floor(epoch / seconds) * seconds). */
export function retryAfter(seconds: number, nowMs = Date.now()): number {
  const s = Math.floor(nowMs / 1000);
  return seconds - (s % seconds);
}

// ---------- breached passwords (E11): Have I Been Pwned, k-anonymity ----------

/** SHA-1 of the password, upper-case hex, split into the 5 characters sent and the 35 kept here. */
export function pwnedParts(password: string): { prefix: string; suffix: string } {
  const hex = createHash("sha1").update(password, "utf8").digest("hex").toUpperCase();
  return { prefix: hex.slice(0, 5), suffix: hex.slice(5) };
}

/** How often the suffix appears in a range answer ("SUFFIX:COUNT" per line). Padding lines have a count of 0. */
export function pwnedCount(rangeBody: string, suffix: string): number {
  const want = suffix.toUpperCase();
  for (const line of rangeBody.split(/\r?\n/)) {
    const [s, n] = line.trim().split(":");
    if (s?.toUpperCase() === want) return Number(n) || 0;
  }
  return 0;
}

/**
 * Whether a password is in a known breach. Only the first 5 hex characters of its SHA-1 leave the server, with padding
 * asked for so the answer's size says nothing either. Fails open (checked: false) when the service cannot be reached:
 * the length rule still holds, and a sign-in must not depend on a third party being up.
 */
export async function breachedPassword(password: string, fetchImpl: typeof fetch = fetch): Promise<{ checked: boolean; breached: boolean; count: number }> {
  const { prefix, suffix } = pwnedParts(password);
  try {
    const res = await fetchImpl(`https://api.pwnedpasswords.com/range/${prefix}`, {
      headers: { "Add-Padding": "true", "user-agent": "Eduwit-Spark" }, signal: AbortSignal.timeout(4000), cache: "no-store",
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const count = pwnedCount(await res.text(), suffix);
    return { checked: true, breached: count > 0, count };
  } catch (e) {
    console.warn("[password] breach check unavailable, allowed without it:", e instanceof Error ? e.message : String(e));
    return { checked: false, breached: false, count: 0 };
  }
}
