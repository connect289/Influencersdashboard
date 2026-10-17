import "server-only";
import { createHash } from "node:crypto";
import { kv } from "./kv";
import { log } from "./log";
import { rpc } from "./db";

export interface Limit {
  /** Logical name, e.g. "email_code_send". */
  name: string;
  limit: number;
  windowSeconds: number;
}

/** Hash identifiers (IP, email, device) so limiter keys never hold raw personal data. */
export function hashId(value: string): string {
  return createHash("sha256").update(value.trim().toLowerCase()).digest("base64url").slice(0, 22);
}

/**
 * Fixed-window counter in the key-value store; if the store fails, falls back to the Postgres limiter so protection
 * never silently disappears (spec 15 graceful degradation). Returns whether the call is allowed.
 */
export async function rateLimit(l: Limit, id: string): Promise<{ ok: boolean; remaining: number }> {
  const window = Math.floor(Date.now() / 1000 / l.windowSeconds);
  const key = `rl:${l.name}:${hashId(id)}:${window}`;
  try {
    const n = await kv().incr(key, l.windowSeconds);
    return { ok: n <= l.limit, remaining: Math.max(0, l.limit - n) };
  } catch (err) {
    log("warn", "ratelimit.kv_failed", { name: l.name, message: err instanceof Error ? err.message : String(err) });
    try {
      const ok = await rpc<boolean>("web_rate_hit", {
        p_bucket: `${l.name}:${hashId(id)}`,
        p_window_seconds: l.windowSeconds,
        p_limit: l.limit,
      });
      return { ok, remaining: ok ? 1 : 0 };
    } catch {
      return { ok: true, remaining: 0 };
    }
  }
}

/** Limits used across the site (per spec 7.2: per IP, device and email). */
export const LIMITS = {
  emailCodeSendPerEmail: { name: "code_email", limit: 5, windowSeconds: 3600 },
  emailCodeSendPerIp: { name: "code_ip", limit: 20, windowSeconds: 3600 },
  emailCodeSendPerDevice: { name: "code_device", limit: 10, windowSeconds: 3600 },
  emailCodeVerifyPerEmail: { name: "verify_email", limit: 10, windowSeconds: 600 },
  emailCodeVerifyPerIp: { name: "verify_ip", limit: 40, windowSeconds: 600 },
  formSubmitPerIp: { name: "form_ip", limit: 30, windowSeconds: 3600 },
  chatTurnPerSession: { name: "chat_session", limit: 30, windowSeconds: 600 },
  chatTurnPerIp: { name: "chat_ip", limit: 120, windowSeconds: 3600 },
  searchPerIp: { name: "search_ip", limit: 600, windowSeconds: 600 },
} satisfies Record<string, Limit>;
