import { createClient } from "@supabase/supabase-js";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * Google Ads lead form webhook (spec B4). Google posts each lead with the key set on the Intake screen as google_key;
 * b2b.google_leadform_ingest checks it and stores the lead (a lead that fails is kept for review and still answered 200,
 * so Google does not resend it forever).
 */
export const dynamic = "force-dynamic";
const MAX_BYTES = 100_000;

export async function POST(request: Request) {
  if (Number(request.headers.get("content-length") ?? 0) > MAX_BYTES) return Response.json({ ok: false, error: "body too large" }, { status: 413 });
  const body = await request.text();
  if (body.length > MAX_BYTES) return Response.json({ ok: false, error: "body too large" }, { status: 413 });
  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.schema("b2b").rpc("google_leadform_ingest", { p_body: body });
  if (error) return Response.json({ ok: false, error: "try again" }, { status: 503 });
  const r = data as { ok: boolean; status: number; result?: unknown; error?: string };
  return Response.json(r.ok ? {} : { ok: false, error: r.error }, { status: r.status ?? (r.ok ? 200 : 400) });
}
