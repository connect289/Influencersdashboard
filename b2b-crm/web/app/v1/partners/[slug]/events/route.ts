import { createClient } from "@supabase/supabase-js";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * Partner events (spec B8.2; contract in docs/partner-api.md). The raw body goes to b2b.partner_event_ingest, which
 * checks the partner's HMAC signature and timestamp itself, stores the event raw and applies it. No session is used:
 * the database function is the only gate, so this route stays a thin pipe.
 */
export const dynamic = "force-dynamic";
const MAX_BYTES = 200_000;

export async function POST(request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (!/^[a-z0-9][a-z0-9-]{1,39}$/.test(slug)) return Response.json({ ok: false, error: "unknown partner" }, { status: 404 });
  const length = Number(request.headers.get("content-length") ?? 0);
  if (length > MAX_BYTES) return Response.json({ ok: false, error: "body too large" }, { status: 413 });
  const body = await request.text();
  if (body.length > MAX_BYTES) return Response.json({ ok: false, error: "body too large" }, { status: 413 });

  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.schema("b2b").rpc("partner_event_ingest", {
    p_slug: slug,
    p_body: body,
    p_timestamp: request.headers.get("x-eduwit-timestamp") ?? "",
    p_signature: request.headers.get("x-eduwit-signature") ?? "",
  });
  if (error) return Response.json({ ok: false, error: "could not process the event, try again" }, { status: 503 });
  const r = data as { ok: boolean; status: number; result?: string; error?: string };
  return Response.json(r.ok ? { ok: true, result: r.result } : { ok: false, error: r.error }, { status: r.status ?? (r.ok ? 200 : 400) });
}

export function GET() {
  return Response.json({ ok: false, error: "POST events here; see the partner integration guide" }, { status: 405 });
}
