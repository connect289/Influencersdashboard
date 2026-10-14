import { NextResponse, type NextRequest } from "next/server";
import { verify } from "@/lib/b2b-sign";
import { signingSecret } from "@/lib/env";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

const MAX_BODY = 1024 * 1024;

/**
 * Webhooks from the B2B CRM (contract §1): every b2c.* and b2b.* envelope. The signature is checked over the exact raw
 * bytes before anything else; the envelope is stored and applied in one call (b2c.handoff_receive), once per id, and the
 * answer goes back well inside B2B's 10-second budget. A failure answers 500 so B2B retries the same envelope.
 */
export async function POST(request: NextRequest) {
  const secret = signingSecret();
  if (!secret) return NextResponse.json({ ok: false, error: "the B2C CRM is not set up yet" }, { status: 503 });
  const raw = await request.text();
  if (raw.length > MAX_BODY) return NextResponse.json({ ok: false, error: "too large" }, { status: 413 });
  const check = verify(raw, request.headers.get("x-eduwit-timestamp"), request.headers.get("x-eduwit-signature"), secret);
  if (!check.ok) return NextResponse.json({ ok: false, error: `bad ${check.reason}` }, { status: 401 });

  let env: Record<string, unknown>;
  try {
    env = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ ok: false, error: "not JSON" }, { status: 400 });
  }
  if (typeof env.id !== "string" && typeof env.id !== "number") return NextResponse.json({ ok: false, error: "no envelope id" }, { status: 400 });
  if (typeof env.type !== "string") return NextResponse.json({ ok: false, error: "no type" }, { status: 400 });
  env.id = String(env.id);

  const { data, error } = await adminClient().rpc("handoff_receive", { p_env: env, p_via: env.type === "ping" ? "test" : "webhook" });
  if (error) {
    console.error("handoff_receive failed", env.type, error.message);
    return NextResponse.json({ ok: false, error: "could not store the event" }, { status: 500 });
  }
  return NextResponse.json({ ok: true, result: data });
}
