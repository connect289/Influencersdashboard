import { clientIp } from "@/lib/security";
import { isOneClickBody, parseUnsubscribeLink, recordUnsubscribe } from "@/lib/unsubscribe";

/**
 * POST /u/{lead}/{token}/one-click (M34j): the address in the List-Unsubscribe header of every student email. A mail
 * provider posts `List-Unsubscribe=One-Click` here when the student presses its own Unsubscribe button (RFC 8058): no
 * cookies, no sign-in, no CSRF token, nothing to read back but the status.
 *   200 { ok: true }   recorded, already recorded, or a token that is not this lead's (answered alike)
 *   400                the body is not the one-click form
 *   404                the address is not an unsubscribe link (wrong shape)
 *   429 + Retry-After  too many requests (b2b.unsubscribe, SQLSTATE P0429)
 *   503                the database did not answer; the provider may retry
 * GET (a mail client that opens the address instead of posting to it) goes to the page with the confirm button; a GET
 * never unsubscribes, because mail scanners follow links.
 */
export const dynamic = "force-dynamic";
export const maxDuration = 10;

const MAX_BODY_BYTES = 2_048;
const NO_STORE = { "Cache-Control": "no-store" } as const;
const json = (status: number, body: Record<string, unknown>, headers?: Record<string, string>) =>
  Response.json(body, { status, headers: { ...NO_STORE, ...headers } });

type Context = { params: Promise<{ lead: string; token: string }> };

async function oneClickForm(request: Request): Promise<boolean> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (!Number.isFinite(length) || length > MAX_BODY_BYTES) return false;
  try {
    return isOneClickBody(await request.formData());
  } catch {
    return false; // not form-encoded or multipart
  }
}

export async function POST(request: Request, { params }: Context) {
  const link = parseUnsubscribeLink(await params);
  if (!link) return json(404, { ok: false, error: "not an unsubscribe link" });
  if (!(await oneClickForm(request))) return json(400, { ok: false, error: "send List-Unsubscribe=One-Click as a form field" });
  const outcome = await recordUnsubscribe(link, clientIp(request.headers), "one_click");
  if (outcome.kind === "rate_limited") {
    return json(429, { ok: false, error: "rate limited: too many requests", error_code: "rate_limited", retry_after: outcome.retryAfter },
      { "Retry-After": String(outcome.retryAfter) });
  }
  if (outcome.kind === "unavailable") return json(503, { ok: false, error: "the request could not be recorded, try again shortly" });
  return json(200, { ok: true });
}

export async function GET(_request: Request, { params }: Context) {
  const link = parseUnsubscribeLink(await params);
  if (!link) return json(404, { ok: false, error: "not an unsubscribe link" });
  // A relative Location: the host is never taken from the request (lib/env.ts siteUrl).
  return new Response(null, { status: 303, headers: { ...NO_STORE, Location: `/u/${link.lead}/${link.token}` } });
}
