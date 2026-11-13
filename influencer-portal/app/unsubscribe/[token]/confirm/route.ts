import { followUnsubscribe, tokenForPath } from "@/lib/notify/unsubscribe-run";

export const dynamic = "force-dynamic";
export const maxDuration = 10;

/**
 * The button on the unsubscribe page: a plain form POST (works without JavaScript), then back to the page with the
 * result. No session and no same-site check: the signed link is the whole authority, and all it can do is turn one
 * kind of email off for one account.
 */
export async function POST(request: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const outcome = await followUnsubscribe(token, request.headers);
  return new Response(null, {
    status: 303,
    headers: {
      Location: `/unsubscribe/${tokenForPath(token)}?r=${outcome}`,
      "Cache-Control": "no-store",
      "X-Robots-Tag": "noindex, nofollow",
      "Referrer-Policy": "no-referrer",
    },
  });
}
