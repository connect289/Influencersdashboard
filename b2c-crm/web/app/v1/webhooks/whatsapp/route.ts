import { timingSafeEqual } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { adminClient } from "@/lib/supabase/admin";
import { parseWebhook, verifyMetaSignature } from "@/lib/whatsapp";

export const dynamic = "force-dynamic";

/** Meta's one-time check when the webhook is registered: echo hub.challenge when the verify token matches. */
export function GET(request: NextRequest) {
  const p = request.nextUrl.searchParams;
  const expected = process.env.WHATSAPP_VERIFY_TOKEN ?? "";
  const given = p.get("hub.verify_token") ?? "";
  const same = expected.length >= 16 && given.length === expected.length && timingSafeEqual(Buffer.from(given), Buffer.from(expected));
  if (p.get("hub.mode") === "subscribe" && same) return new NextResponse(p.get("hub.challenge") ?? "", { status: 200 });
  return new NextResponse("forbidden", { status: 403 });
}

/**
 * Messages and delivery statuses on the Eduwit B2C number (spec B10). Signed by Meta with the app secret. Each inbound
 * message goes to b2c.wa_inbound (opt-out words, consent YES/NO, routing to the counsellor, or a new student through
 * intake); each status to b2c.wa_status. Always 200 once stored, so Meta does not retry what was handled.
 */
export async function POST(request: NextRequest) {
  const secret = process.env.WHATSAPP_APP_SECRET;
  if (!secret) return NextResponse.json({ ok: false }, { status: 503 });
  const raw = await request.text();
  if (!verifyMetaSignature(raw, request.headers.get("x-hub-signature-256"), secret)) return NextResponse.json({ ok: false }, { status: 401 });
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return NextResponse.json({ ok: false }, { status: 400 });
  }
  const { messages, statuses } = parseWebhook(body);
  const db = adminClient();
  let failed = 0;
  for (const m of messages) {
    const { error } = await db.rpc("wa_inbound", { p: m });
    if (error) { failed++; console.error("wa_inbound failed", error.message); }
  }
  for (const s of statuses) {
    const { error } = await db.rpc("wa_status", { p_wamid: s.wamid, p_status: s.status, p_at: s.at, p_error: s.error });
    if (error) { failed++; console.error("wa_status failed", error.message); }
  }
  // A database failure answers 500 so Meta retries; wa_inbound ignores a message id it has already stored.
  return NextResponse.json({ ok: failed === 0 }, { status: failed ? 500 : 200 });
}
