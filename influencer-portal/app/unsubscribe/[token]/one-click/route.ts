import { isOneClickBody } from "@/lib/notify/unsubscribe";
import { followUnsubscribe, tokenForPath } from "@/lib/notify/unsubscribe-run";

export const dynamic = "force-dynamic";
// Mail providers expect a quick answer; a stalled database must not hold the call open.
export const maxDuration = 10;

const HEADERS = { "Cache-Control": "no-store", "X-Robots-Tag": "noindex, nofollow", "Referrer-Policy": "no-referrer" };
const answer = (status: number, text: string, extra: Record<string, string> = {}) =>
  new Response(text, { status, headers: { ...HEADERS, "Content-Type": "text/plain; charset=utf-8", ...extra } });

/** Whether the body is the one RFC 8058 defines (form-encoded or multipart `List-Unsubscribe=One-Click`). */
async function isOneClick(request: Request): Promise<boolean> {
  try {
    if (/^multipart\/form-data/i.test(request.headers.get("content-type") ?? ""))
      return (await request.formData()).get("List-Unsubscribe") === "One-Click";
    return isOneClickBody((await request.text()).slice(0, 1000));
  } catch {
    return false;
  }
}

/**
 * One-click unsubscribe (RFC 8058): the address in an email's List-Unsubscribe header. Mail providers POST
 * `List-Unsubscribe=One-Click` here when the person presses "Unsubscribe" in their mail app. No cookies, no session:
 * the signed link is the whole authority, and all it can do is turn one kind of email off for one account. A link
 * that is not ours gets the same 200 as one that worked.
 */
export async function POST(request: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!(await isOneClick(request))) return answer(400, "Expected List-Unsubscribe=One-Click");
  const outcome = await followUnsubscribe(token, request.headers);
  if (outcome === "limited") return answer(429, "Too many requests", { "Retry-After": "60" });
  if (outcome === "failed") return answer(503, "Try again later", { "Retry-After": "60" });
  return answer(200, "OK");
}

/** People land on the page, not here: a GET changes nothing (mail scanners follow links). */
export async function GET(_request: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return new Response(null, { status: 303, headers: { ...HEADERS, Location: `/unsubscribe/${tokenForPath(token)}` } });
}
