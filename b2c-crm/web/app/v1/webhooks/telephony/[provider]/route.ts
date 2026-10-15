import { NextResponse, type NextRequest } from "next/server";
import { internalKeyOk } from "@/lib/internal";
import { adminClient } from "@/lib/supabase/admin";
import { exotelConfig, parseExotel } from "@/lib/telephony";

export const dynamic = "force-dynamic";

/**
 * Telephony provider → CRM (spec B8.4 onCallEvent). Exotel posts status callbacks of click-to-call (JSON or form) and
 * hits it from a Passthru applet for incoming calls (GET). Exotel does not sign webhooks, so the URL carries a secret
 * key (EXOTEL_WEBHOOK_KEY), compared in constant time. Each event goes to b2c.call_event(), which ignores repeats.
 */
async function handle(request: NextRequest, { params }: { params: Promise<{ provider: string }> }) {
  const provider = (await params).provider;
  if (provider !== "exotel") return NextResponse.json({ error: "unknown provider" }, { status: 404 });
  const cfg = exotelConfig();
  if (!cfg) return NextResponse.json({ error: "telephony is not configured" }, { status: 503 });
  if (!internalKeyOk(request.nextUrl.searchParams.get("key"), cfg.webhookKey)) return NextResponse.json({ error: "forbidden" }, { status: 403 });
  let q: Record<string, unknown> = Object.fromEntries(request.nextUrl.searchParams.entries());
  delete q.key;
  if (request.method === "POST") {
    const raw = await request.text();
    if (raw.length > 100_000) return NextResponse.json({ error: "too large" }, { status: 413 });
    if ((request.headers.get("content-type") ?? "").includes("json")) {
      try { q = { ...q, ...(JSON.parse(raw) as Record<string, unknown>) }; } catch { return NextResponse.json({ error: "invalid JSON" }, { status: 400 }); }
    } else {
      q = { ...q, ...Object.fromEntries(new URLSearchParams(raw).entries()) };
    }
  }
  const e = parseExotel(q);
  if (!e) return NextResponse.json({ ok: true, ignored: true });
  const { data, error } = await adminClient().rpc("call_event", { p: e });
  if (error) {
    console.error("call_event failed", error.message);
    return NextResponse.json({ error: "not recorded" }, { status: /unknown call/.test(error.message) ? 404 : 500 });
  }
  return NextResponse.json({ ok: true, ...(data as Record<string, unknown>) });
}

export const GET = handle;
export const POST = handle;
