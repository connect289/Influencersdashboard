// M34j: the student's unsubscribe link, /u/<lead>/<token>, and its one-click address (RFC 8058). The link is in every
// email the CRM sends a student (b2b.notify_request). Input checks are pure and unit-tested in unsubscribe.test.ts; the one
// database call is b2b.unsubscribe, which holds the rules (rate limits, the token, what an opt-out changes).
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";

/** The two path segments. The token is 40 lowercase hex characters, as b2b.unsubscribe_token writes it. */
export const UnsubscribeLinkSchema = z.object({
  lead: z.string().regex(/^[1-9]\d{0,17}$/),
  token: z.string().regex(/^[0-9a-f]{40}$/),
});
export type UnsubscribeLink = z.infer<typeof UnsubscribeLinkSchema>;

/** A link of the right shape, or null. Whether the token is that lead's is the database's question, never answered to the visitor. */
export function parseUnsubscribeLink(input: { lead?: unknown; token?: unknown }): UnsubscribeLink | null {
  const p = UnsubscribeLinkSchema.safeParse({ lead: input.lead, token: input.token });
  return p.success ? p.data : null;
}

/** RFC 8058: the mail provider posts exactly this field (form-encoded or multipart). */
export const OneClickBodySchema = z.object({ "List-Unsubscribe": z.literal("One-Click") });

export function isOneClickBody(form: { get(name: string): unknown }): boolean {
  return OneClickBodySchema.safeParse({ "List-Unsubscribe": form.get("List-Unsubscribe") }).success;
}

/**
 * What the visitor may learn. "done" covers a valid link, a link already used and a link whose token is not that lead's:
 * they are answered alike, so a link cannot be used to find out which lead ids exist.
 */
export type UnsubscribeOutcome = { kind: "done" } | { kind: "rate_limited"; retryAfter: number } | { kind: "unavailable" };

/** The opt-out is one indexed update; a call that takes longer than this is treated as not answered. */
const CALL_TIMEOUT_MS = 8_000;

/** SQLSTATE P0429 from b2b.unsubscribe carries the hint "retry after N seconds", as b2b.api_key_check does. */
export function retryAfterSeconds(hint: string | null | undefined): number {
  const n = Number(/retry after (\d{1,3})/.exec(hint ?? "")?.[1] ?? 60);
  return Number.isFinite(n) && n >= 1 && n <= 600 ? n : 60;
}

/** One line per failure, with no lead id, token or address: only a code when it looks like one. */
function logFailure(code: unknown): void {
  const c = typeof code === "string" && /^[A-Za-z0-9_.-]{1,40}$/.test(code) ? code : null;
  console.error(JSON.stringify({ event: "unsubscribe_failed", code: c }));
}

/**
 * Records the opt-out with the service-role client (the visitor is signed out; b2b.unsubscribe is granted to the service
 * role only). Never throws: a database that does not answer is "unavailable", so the page can ask the student to try again
 * and the one-click route can answer 503 for the mail provider to retry.
 */
export async function recordUnsubscribe(link: UnsubscribeLink, ip: string | null, source: "link" | "one_click"): Promise<UnsubscribeOutcome> {
  try {
    const { error } = await adminClient()
      .rpc("unsubscribe", { p_lead: link.lead, p_token: link.token, p_channel: "email", p_ip: ip, p_source: source })
      .abortSignal(AbortSignal.timeout(CALL_TIMEOUT_MS));
    if (!error) return { kind: "done" }; // true (this lead's token) and false (anything else) are not told apart
    if (error.code === "P0429") return { kind: "rate_limited", retryAfter: retryAfterSeconds(error.hint) };
    logFailure(error.code);
    return { kind: "unavailable" };
  } catch (e) {
    logFailure((e as { code?: unknown } | null)?.code);
    return { kind: "unavailable" };
  }
}
