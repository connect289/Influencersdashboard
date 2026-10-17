// Pure security helpers shared by proxy.ts, route handlers and server actions. Unit-tested in security.test.ts.
// Adapted from the B2C CRM (b2c-crm/web/lib/security.ts) so all Eduwit apps behave the same.
import { createHash } from "node:crypto";

export const IDLE_LIMIT_SECONDS = 12 * 60 * 60;
export const SEEN_COOKIE = "inf_seen";
/** Trusted-device cookie for staff (skips the emailed code on this browser). */
export const DEVICE_COOKIE = "inf_device";
export const DEVICE_COOKIE_DAYS = 30;

/** A same-origin path from user input (?next=…), or the fallback. Blocks //evil.com, /\evil.com, absolute URLs. */
export function safeNext(next: string | null | undefined, fallback = "/"): string {
  if (!next || typeof next !== "string" || next.length > 512) return fallback;
  if (!next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return fallback;
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\\]/.test(next)) return fallback;
  return next;
}

export function isIdleExpired(lastSeen: string | undefined, nowSeconds: number, limit = IDLE_LIMIT_SECONDS): boolean {
  if (!lastSeen) return false;
  const seen = Number(lastSeen);
  if (!Number.isFinite(seen) || seen <= 0) return false;
  return nowSeconds - seen > limit;
}

/** Content-Security-Policy for one request: scripts need the per-request nonce; nothing else may run. */
export function buildCsp(nonce: string, supabaseOrigin: string, isDev: boolean, upgradeInsecure = !isDev): string {
  const wsOrigin = supabaseOrigin.replace(/^http/, "ws");
  const directives: Record<string, string[]> = {
    "default-src": ["'self'"],
    "script-src": ["'self'", `'nonce-${nonce}'`, "'strict-dynamic'", ...(isDev ? ["'unsafe-eval'"] : [])],
    "style-src": ["'self'", "'unsafe-inline'"],
    "img-src": ["'self'", "data:", "blob:", supabaseOrigin, "https:"],
    "font-src": ["'self'", "data:"],
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
  if (upgradeInsecure) parts.push("upgrade-insecure-requests");
  return parts.join("; ");
}

/** The browser's IP from the platform's header (Vercel overwrites these, so a client can't choose them). */
export function clientIp(headers: Headers): string | null {
  const first = (v: string | null) => v?.split(",")[0]?.trim() || null;
  const ip =
    first(headers.get("x-vercel-forwarded-for")) ??
    first(headers.get("x-real-ip")) ??
    first(headers.get("x-forwarded-for"));
  return ip && /^[0-9a-fA-F:.]{3,45}$/.test(ip) ? ip : null;
}

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

/** Rate-limit identity of the caller: IPv4 as is, IPv6 cut to its /64 (one client usually owns a whole /64). */
export function rateIp(headers: Headers): string {
  let ip = (clientIp(headers) ?? "").replace(/^\[|\]$/g, "").replace(/%.*$/, "");
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(ip);
  if (mapped?.[1]) ip = mapped[1];
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(ip) && ip.split(".").every((o) => Number(o) <= 255)) return ip;
  const v6 = ip.includes(":") ? expandIpv6(ip) : null;
  return v6 ? `${v6.slice(0, 4).join(":")}::/64` : "unknown";
}

/** Per-scope limits as [hits, window seconds]. */
// Per-IP limits are generous because many creators share one network (colleges, offices, mobile carrier NAT);
// per-email limits and the database lockout stop guessing against one account.
export const RATE_LIMITS = {
  staff_sign_in: [30, 300],
  creator_otp_send_ip: [30, 600],
  creator_otp_send_email: [5, 600],
  creator_otp_verify: [10, 600],
  code_send: [5, 600],
  code_verify: [10, 600],
  password_link: [3, 3600],
  signup_ip: [10, 3600],
  signup_email: [3, 3600],
  redirect: [120, 60],
  public_api: [60, 60],
  internal: [600, 60],
} as const satisfies Record<string, readonly [number, number]>;
export type RateScope = keyof typeof RATE_LIMITS;

export function rateKey(scope: RateScope, subject: string): string {
  return `${scope}:${subject.replace(/[^a-z0-9:._@/-]/gi, "_")}`.slice(0, 200);
}

export function retryAfter(seconds: number, nowMs = Date.now()): number {
  const s = Math.floor(nowMs / 1000);
  return seconds - (s % seconds);
}

/** Constant-time comparison for shared secrets (internal API key). */
export function safeEqual(a: string, b: string): boolean {
  const ha = createHash("sha256").update(a).digest();
  const hb = createHash("sha256").update(b).digest();
  let diff = a.length === b.length ? 0 : 1;
  for (let i = 0; i < ha.length; i++) diff |= (ha[i] ?? 0) ^ (hb[i] ?? 0);
  return diff === 0;
}

export const PASSWORD_MIN = 12;
export const PASSWORD_MAX = 128;

export function pwnedParts(password: string): { prefix: string; suffix: string } {
  const hex = createHash("sha1").update(password, "utf8").digest("hex").toUpperCase();
  return { prefix: hex.slice(0, 5), suffix: hex.slice(5) };
}

export function pwnedCount(rangeBody: string, suffix: string): number {
  const want = suffix.toUpperCase();
  for (const line of rangeBody.split(/\r?\n/)) {
    const [s, n] = line.trim().split(":");
    if (s?.toUpperCase() === want) return Number(n) || 0;
  }
  return 0;
}

/** Have I Been Pwned range check (k-anonymity: only 5 hex characters leave the server). Fails open. */
export async function breachedPassword(
  password: string,
  fetchImpl: typeof fetch = fetch,
): Promise<{ checked: boolean; breached: boolean }> {
  const { prefix, suffix } = pwnedParts(password);
  try {
    const res = await fetchImpl(`https://api.pwnedpasswords.com/range/${prefix}`, {
      headers: { "Add-Padding": "true", "user-agent": "Eduwit-Influencer-Portal" },
      signal: AbortSignal.timeout(4000),
      cache: "no-store",
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return { checked: true, breached: pwnedCount(await res.text(), suffix) > 0 };
  } catch {
    return { checked: false, breached: false };
  }
}
