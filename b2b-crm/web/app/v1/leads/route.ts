import { createClient } from "@supabase/supabase-js";
import { apiKeyFrom } from "@/lib/integrations";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * POST /v1/leads, the Intake API (contract in docs/intake-api.md). b2b.api_intake_lead checks the key (scope intake),
 * the Idempotency-Key and the body itself; a repeated key with the same body returns the stored answer.
 */
export const dynamic = "force-dynamic";
const MAX_BYTES = 64_000;

export async function POST(request: Request) {
  const key = apiKeyFrom(request.headers);
  if (!key) return Response.json({ ok: false, error: "send the API key as Authorization: Bearer <key>" }, { status: 401 });
  const idem = request.headers.get("idempotency-key")?.trim() ?? "";
  if (!idem) return Response.json({ ok: false, error: "send an Idempotency-Key header (1 to 200 characters)" }, { status: 400 });
  if (Number(request.headers.get("content-length") ?? 0) > MAX_BYTES) return Response.json({ ok: false, error: "body too large" }, { status: 413 });
  const text = await request.text();
  if (text.length > MAX_BYTES) return Response.json({ ok: false, error: "body too large" }, { status: 413 });
  let body: unknown;
  try { body = JSON.parse(text); } catch { return Response.json({ ok: false, error: "the body is not JSON" }, { status: 400 }); }

  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.schema("b2b").rpc("api_intake_lead", { p_key: key, p_idempotency_key: idem, p_body: body });
  if (error) return Response.json({ ok: false, error: "could not store the lead, try again with the same Idempotency-Key" }, { status: 503 });
  const r = data as { ok: boolean; status: number; result?: object; error?: string; replayed?: boolean };
  const headers = r.replayed ? { "Idempotent-Replayed": "true" } : undefined;
  return Response.json(r.ok ? { ok: true, ...r.result } : { ok: false, error: r.error }, { status: r.status ?? (r.ok ? 200 : 400), headers });
}

export function GET() {
  return Response.json({ ok: false, error: "POST leads here; see the intake API guide" }, { status: 405 });
}
