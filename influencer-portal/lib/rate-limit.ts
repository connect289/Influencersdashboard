import "server-only";
import { adminClient } from "@/lib/supabase/admin";
import { log, errorMessage } from "@/lib/log";
import { RATE_LIMITS, rateKey, retryAfter, type RateScope } from "@/lib/security";

/**
 * Fixed-window rate limit in the database (inf.rate_check). Sign-in, OTP and code scopes fail CLOSED when the database
 * can't be reached (better a short lockout than unlimited guessing); other scopes fail open.
 */
export async function rateLimit(
  scope: RateScope,
  subject: string,
): Promise<{ ok: true } | { ok: false; retryAfter: number }> {
  const [limit, seconds] = RATE_LIMITS[scope];
  const failClosed = /sign_in|signup|otp|code|password/.test(scope);
  try {
    const { data, error } = await adminClient().rpc("rate_check", {
      p_key: rateKey(scope, subject),
      p_limit: limit,
      p_seconds: seconds,
    });
    if (error) throw new Error(error.message);
    return data ? { ok: true } : { ok: false, retryAfter: retryAfter(seconds) };
  } catch (e) {
    log.warn("rate_limit.unavailable", { scope, error: errorMessage(e) });
    return failClosed ? { ok: false, retryAfter: 60 } : { ok: true };
  }
}
