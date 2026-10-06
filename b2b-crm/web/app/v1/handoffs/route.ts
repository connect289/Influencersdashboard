import { createClient } from "@supabase/supabase-js";
import { apiKeyFrom, parseHandoffsQuery } from "@/lib/integrations";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * GET /v1/handoffs (contract in docs/b2c-contract.md): the reconciliation feed for the B2C CRM, the same envelopes the
 * webhooks carry, in order. Authorised by an API key with the 'events' scope, which b2b.api_b2c_handoffs checks itself.
 */
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const key = apiKeyFrom(request.headers);
  if (!key) return Response.json({ ok: false, error: "send the API key as Authorization: Bearer <key>" }, { status: 401 });
  const p = parseHandoffsQuery(new URL(request.url).searchParams);
  if (!p.ok) return Response.json({ ok: false, error: p.error }, { status: 400 });

  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.schema("b2b").rpc("api_b2c_handoffs", {
    p_key: key, p_since: p.q.since, p_after: p.q.after, p_limit: p.q.limit,
  });
  if (error) return Response.json({ ok: false, error: "could not read the feed, try again" }, { status: 503 });
  const r = data as { ok: boolean; status: number; result?: unknown; error?: string };
  return Response.json(r.ok ? { ok: true, ...(r.result as object) } : { ok: false, error: r.error }, { status: r.status ?? (r.ok ? 200 : 400) });
}
