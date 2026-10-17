import "server-only";
import { createHash } from "node:crypto";
import { kv, kvShared } from "./kv";
import { isDeployed } from "./env";
import { log } from "./log";
import { rpc } from "./db";

export interface Limit {
  /** Logical name, e.g. "email_code_send". */
  name: string;
  limit: number;
  windowSeconds: number;
  /** Refuse when no limiter is reachable (limits that cost money or write to the shared CRM). Others fail open. */
  failClosed?: boolean;
}

/** Hash identifiers (IP, email, device) so limiter keys never hold raw personal data. */
export function hashId(value: string): string {
  return createHash("sha256").update(value.trim().toLowerCase()).digest("base64url").slice(0, 22);
}

/**
 * Fixed-window counter. Uses the shared key-value store (Upstash) when configured. On a deployed environment without
 * it, or if it fails, the Postgres limiter (web_rate_hit) is used instead, so limits are never per server instance
 * (spec 15 graceful degradation). If neither is reachable, cost-bearing limits refuse and the rest allow.
 */
export async function rateLimit(l: Limit, id: string): Promise<{ ok: boolean; remaining: number }> {
  const window = Math.floor(Date.now() / 1000 / l.windowSeconds);
  const key = `rl:${l.name}:${hashId(id)}:${window}`;
  if (kvShared() || !isDeployed()) {
    try {
      const n = await kv().incr(key, l.windowSeconds);
      return { ok: n <= l.limit, remaining: Math.max(0, l.limit - n) };
    } catch (err) {
      log("warn", "ratelimit.kv_failed", { name: l.name, message: err instanceof Error ? err.message : String(err) });
    }
  }
  try {
    const ok = await rpc<boolean>("web_rate_hit", {
      p_bucket: `${l.name}:${hashId(id)}`,
      p_window_seconds: l.windowSeconds,
      p_limit: l.limit,
    });
    return { ok, remaining: ok ? 1 : 0 };
  } catch (err) {
    log("error", "ratelimit.unavailable", { name: l.name, fail_closed: !!l.failClosed, message: err instanceof Error ? err.message : String(err) });
    return { ok: !l.failClosed, remaining: 0 };
  }
}

/** Limits used across the site (per spec 7.2: per IP, device and email). */
export const LIMITS = {
  emailCodeSendPerEmail: { name: "code_email", limit: 5, windowSeconds: 3600, failClosed: true },
  emailCodeSendPerIp: { name: "code_ip", limit: 20, windowSeconds: 3600, failClosed: true },
  emailCodeSendPerDevice: { name: "code_device", limit: 10, windowSeconds: 3600, failClosed: true },
  emailCodeVerifyPerEmail: { name: "verify_email", limit: 10, windowSeconds: 600, failClosed: true },
  emailCodeVerifyPerIp: { name: "verify_ip", limit: 40, windowSeconds: 600, failClosed: true },
  formSubmitPerIp: { name: "form_ip", limit: 30, windowSeconds: 3600, failClosed: true },
  chatTurnPerSession: { name: "chat_session", limit: 30, windowSeconds: 600, failClosed: true },
  chatTurnPerIp: { name: "chat_ip", limit: 120, windowSeconds: 3600, failClosed: true },
  callbackPerStudent: { name: "callback_student", limit: 3, windowSeconds: 86400, failClosed: true },
  savePerStudent: { name: "save_student", limit: 60, windowSeconds: 3600 },
  searchPerIp: { name: "search_ip", limit: 600, windowSeconds: 600 },
  beaconPerIp: { name: "beacon_ip", limit: 300, windowSeconds: 600 },
} satisfies Record<string, Limit>;
