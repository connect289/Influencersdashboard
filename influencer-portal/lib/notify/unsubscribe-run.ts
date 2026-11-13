import "server-only";
// Following an unsubscribe link (D-198): check the signature, then record the choice with the one database function
// that does it. Shared by the page's button and the one-click endpoint mail providers call.
import { env } from "@/lib/env";
import { errorMessage, log } from "@/lib/log";
import { rateLimit } from "@/lib/rate-limit";
import { rateIp } from "@/lib/security";
import { adminClient } from "@/lib/supabase/admin";
import { UNSUBSCRIBE_TOKEN_MAX, verifyUnsubscribe, type UnsubscribeClaims } from "./unsubscribe";

/**
 * "done": the choice is recorded, was recorded before, or the link is not one of ours (the same answer on purpose:
 * a link says nothing about whether an account exists). "limited": too many requests from this address just now.
 * "failed": the database could not record it; nothing changed and the person should try again.
 */
export type UnsubscribeOutcome = "done" | "limited" | "failed";

/** The claims of a link signed with this deployment's secret, or null (also when no secret is configured). */
export function readUnsubscribeToken(token: string): UnsubscribeClaims | null {
  const secret = env().UNSUBSCRIBE_SECRET;
  return secret ? verifyUnsubscribe(secret, token) : null;
}

/** The token as it may be put back into an address, or a fixed word for anything that is not shaped like one. */
export function tokenForPath(token: string): string {
  return token.length <= UNSUBSCRIBE_TOKEN_MAX && /^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+){2}$/.test(token) ? token : "link";
}

/**
 * Turns email off for the kind of notification the link names. The signature is checked first, so a made-up link
 * costs no database call; a genuine one is rate-limited per network address, then recorded by inf.unsubscribe_email
 * (which changes nothing when it was recorded before).
 */
export async function followUnsubscribe(token: string, headers: Headers): Promise<UnsubscribeOutcome> {
  try {
    const claims = readUnsubscribeToken(token);
    if (!claims) return "done";
    if (!(await rateLimit("unsubscribe", rateIp(headers))).ok) return "limited";
    const { data, error } = await adminClient().rpc("unsubscribe_email", {
      p_user: claims.userId,
      p_category: claims.category,
    });
    if (error) throw new Error(error.message);
    log.info("unsubscribe.recorded", { category: claims.category, changed: typeof data === "number" ? data : 0 });
    return "done";
  } catch (e) {
    log.error("unsubscribe.failed", { error: errorMessage(e) });
    return "failed";
  }
}
