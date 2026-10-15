import { NextResponse, type NextRequest } from "next/server";
import { verifyGet } from "@/lib/b2b-sign";
import { signingSecret } from "@/lib/env";
import { limit as rateLimit } from "@/lib/rate-limit";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

/**
 * The reconciliation feed for the B2B CRM (spec B17): every event Spark sent it, oldest first, after a sequence number.
 * `GET /v1/events?since=<seq>&limit=<1–1000>` (`after` works too). Signed like the webhooks, over "GET <path>?<query>"
 * instead of a body (lib/b2b-sign.ts). Answers { ok, events: [{ seq, event_id, type, lead_id, occurred_at, data,
 * delivery }], next_after }; pass next_after as the next `since`.
 */
export async function GET(request: NextRequest) {
  const limited = await rateLimit(request, "v1:events", "v1");
  if (limited) return limited;
  const secret = signingSecret();
  if (!secret) return NextResponse.json({ ok: false, error: "the B2C CRM is not set up yet" }, { status: 503 });
  const target = request.nextUrl.pathname + request.nextUrl.search;
  const check = verifyGet(target, request.headers.get("x-eduwit-timestamp"), request.headers.get("x-eduwit-signature"), secret);
  if (!check.ok) return NextResponse.json({ ok: false, error: `bad ${check.reason}` }, { status: 401 });

  const sp = request.nextUrl.searchParams;
  const since = sp.get("since") ?? sp.get("after") ?? "0";
  const limit = sp.get("limit") ?? "200";
  if (!/^\d{1,15}$/.test(since) || !/^\d{1,4}$/.test(limit)) return NextResponse.json({ ok: false, error: "since and limit are whole numbers" }, { status: 400 });

  const { data, error } = await adminClient().rpc("events_feed", { p_after: Number(since), p_limit: Math.min(Math.max(Number(limit), 1), 1000) });
  if (error) {
    console.error("events_feed failed", error.message);
    return NextResponse.json({ ok: false, error: "could not read the feed" }, { status: 500 });
  }
  return NextResponse.json({ ok: true, ...(data as object) }, { headers: { "cache-control": "no-store" } });
}
