import "server-only";
import { env, isProduction } from "./env";
import { log } from "./log";

/**
 * Cloudflare Turnstile verification (spec 7.2 abuse protection, S-13). Without a secret (or with Cloudflare's test
 * secrets) outside production the check is mocked; in production a missing or test secret fails closed.
 */
export async function verifyTurnstile(token: string | undefined, ip: string): Promise<{ ok: boolean; mocked: boolean }> {
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
  try {
    const body = new URLSearchParams({ secret, response: token, remoteip: ip });
    const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      body,
      signal: AbortSignal.timeout(5000),
    });
    const j = (await res.json()) as { success?: boolean; "error-codes"?: string[] };
    if (!j.success) log("info", "turnstile.failed", { codes: j["error-codes"] });
    return { ok: !!j.success, mocked: false };
  } catch (err) {
    // Cloudflare unreachable: let the attempt through (rate limits, screening and the code step still apply), but log it.
    log("warn", "turnstile.unreachable", { message: err instanceof Error ? err.message : String(err) });
    return { ok: true, mocked: false };
  }
}
