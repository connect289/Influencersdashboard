import { createClient } from "@supabase/supabase-js";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * POST /v1/events/b2ccrm (contract in docs/b2c-contract.md): events from the B2C CRM — counsellor assigned, stage
 * changed, enrolled, opted out, erasure requested. Signed with the B2C endpoint's secret (HMAC-SHA256 of
 * "<timestamp>.<raw body>"); b2b.b2ccrm_event_ingest checks the signature and timestamp, de-duplicates by event_id and
 * applies the event. The raw body is passed through untouched so the signature still matches.
 */
export const dynamic = "force-dynamic";
const MAX_BYTES = 100_000;

export async function POST(request: Request) {
  const length = Number(request.headers.get("content-length") ?? 0);
  if (length > MAX_BYTES) return Response.json({ ok: false, error: "body too large" }, { status: 413 });
  const body = await request.text();
  if (body.length > MAX_BYTES) return Response.json({ ok: false, error: "body too large" }, { status: 413 });

  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.schema("b2b").rpc("b2ccrm_event_ingest", {
    p_body: body,
    p_timestamp: request.headers.get("x-eduwit-timestamp") ?? "",
    p_signature: request.headers.get("x-eduwit-signature") ?? "",
  });
  if (error) return Response.json({ ok: false, error: "could not process the event, try again" }, { status: 503 });
  const r = data as { ok: boolean; status: number; result?: string; error?: string };
  return Response.json(r.ok ? { ok: true, result: r.result } : { ok: false, error: r.error }, { status: r.status ?? (r.ok ? 200 : 400) });
}

export function GET() {
  return Response.json({ ok: false, error: "POST B2C CRM events here; see the B2C integration contract" }, { status: 405 });
}
