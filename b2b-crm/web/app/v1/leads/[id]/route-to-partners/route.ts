import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { apiKeyFrom } from "@/lib/integrations";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * POST /v1/leads/{id}/route-to-partners (contract in docs/b2c-contract.md): the B2C CRM hands a lead it holds back to
 * the routing engine, which picks a partner as usual. Needs the student's consent to partner sharing and a reason;
 * authorised by an API key with the 'events' scope. b2b.api_route_to_partners does every check.
 */
export const dynamic = "force-dynamic";
const Body = z.object({ reason: z.string().trim().min(3).max(300) });

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const key = apiKeyFrom(request.headers);
  if (!key) return Response.json({ ok: false, error: "send the API key as Authorization: Bearer <key>" }, { status: 401 });
  if (!/^\d{1,18}$/.test(id)) return Response.json({ ok: false, error: "unknown lead" }, { status: 404 });
  let json: unknown;
  try { json = await request.json(); } catch { return Response.json({ ok: false, error: "body is not JSON" }, { status: 400 }); }
  const b = Body.safeParse(json);
  if (!b.success) return Response.json({ ok: false, error: "a reason (3 to 300 characters) is required" }, { status: 422 });

  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.schema("b2b").rpc("api_route_to_partners", { p_key: key, p_lead_id: Number(id), p_reason: b.data.reason });
  if (error) return Response.json({ ok: false, error: "could not route the lead, try again" }, { status: 503 });
  const r = data as { ok: boolean; status: number; result?: unknown; error?: string };
  return Response.json(r.ok ? { ok: true, result: r.result } : { ok: false, error: r.error }, { status: r.status ?? (r.ok ? 200 : 400) });
}
