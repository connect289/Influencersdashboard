import "server-only";
import { env, isProduction } from "./env";
import { kvShared } from "./kv";
import { log } from "./log";
import { LIMITS, rateLimit } from "./rate-limit";

export interface TurnstileResult {
  ok: boolean;
  mocked: boolean;
  /** Cloudflare did not answer (network error or 5xx) and the attempt was refused: say "try again", not "robot". */
  unreachable?: boolean;
}

/**
 * Cloudflare Turnstile verification (spec 7.2 abuse protection, S-13). Without a secret (or with Cloudflare's test
 * secrets) outside production the check is mocked; in production a missing or test secret fails closed.
 */
export async function verifyTurnstile(token: string | undefined, ip: string): Promise<TurnstileResult> {
  const secret = env().TURNSTILE_SECRET_KEY;
  // Cloudflare's documented test secrets (1x…/2x…/3x…): deterministic outside production, refused in production.
  if (secret && /^[123]x0{30,}A{2}$/.test(secret)) {
    if (isProduction()) {
      log("error", "turnstile.test_secret_in_production");
      return { ok: false, mocked: false };
    }
    return { ok: secret.startsWith("1x"), mocked: true };
  }
  if (!secret) {
    if (isProduction()) {
      log("error", "turnstile.secret_missing");
      return { ok: false, mocked: false };
    }
    return { ok: true, mocked: true };
  }
  if (!token) return { ok: false, mocked: false };
  let res: Response;
  try {
    const body = new URLSearchParams({ secret, response: token, remoteip: ip });
    res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      body,
      signal: AbortSignal.timeout(5000),
    });
  } catch (err) {
    return unreachable(ip, err instanceof Error ? err.name : "error");
  }
  if (res.status >= 500) return unreachable(ip, `http_${res.status}`);
  let j: { success?: boolean; "error-codes"?: string[] };
  try {
    j = (await res.json()) as typeof j;
  } catch {
    log("warn", "turnstile.bad_response", { status: res.status });
    return { ok: false, mocked: false };
  }
  if (!j.success) log("info", "turnstile.failed", { codes: j["error-codes"] });
  return { ok: !!j.success, mocked: false };
}

/**
 * Cloudflare unreachable (D-095). The attempt goes through (rate limits, screening and the code step still apply) only
 * when the limits are shared across server instances (Upstash) and this IP has not used up its few such passes;
 * otherwise it is refused and the visitor is asked to try again.
 */
async function unreachable(ip: string, reason: string): Promise<TurnstileResult> {
  const shared = kvShared();
  if (shared && (await rateLimit(LIMITS.turnstileUnreachablePerIp, ip)).ok) {
    log("warn", "turnstile.unreachable", { reason, outcome: "allowed" });
    return { ok: true, mocked: false };
  }
  log("error", "turnstile.unreachable", { reason, outcome: "refused", shared_store: shared });
  return { ok: false, mocked: false, unreachable: true };
}
