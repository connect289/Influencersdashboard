import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { apiKeyFrom } from "@/lib/integrations";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * POST /v1/leads/{id}/route-to-partners (docs/b2c-contract.md §3.2): the B2C CRM hands a lead it holds back to the routing
 * engine, which picks a partner as usual (route_decide in the to_partners context). Authorised by an API key with the
 * 'events' scope. b2b.api_route_to_partners (m31f) does every check and answers {ok, status, result | error, error_code}:
 *   422 error_code partner_barred  the lead is partner-barred (duplicate cascade or partner lost): never to partners again
 *   422 error_code no_consent      no partner-sharing consent recorded under a text that names admission partners
 *   422 error_code not_held        B2C does not hold the lead (no sales hold or qualification nurture)
 *   422 error_code invalid         the reason is too short, or a test lead (the sandbox is for those)
 *   404 unknown lead · 401 bad key
 * The body passes the function's error and error_code through unchanged, with the HTTP status it gives.
 */
export const dynamic = "force-dynamic";
const Body = z.object({ reason: z.string().trim().min(3).max(300) });

type RouteAnswer = { ok: boolean; status?: number; result?: unknown; error?: string; error_code?: string | null };

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const key = apiKeyFrom(request.headers);
  if (!key) return Response.json({ ok: false, error: "send the API key as Authorization: Bearer <key>" }, { status: 401 });
  if (!/^\d{1,18}$/.test(id)) return Response.json({ ok: false, error: "unknown lead" }, { status: 404 });
  let json: unknown;
  try { json = await request.json(); } catch { return Response.json({ ok: false, error: "body is not JSON" }, { status: 400 }); }
  const b = Body.safeParse(json);
  if (!b.success) return Response.json({ ok: false, error: "a reason (3 to 300 characters) is required", error_code: "invalid" }, { status: 422 });

  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.schema("b2b").rpc("api_route_to_partners", { p_key: key, p_lead_id: Number(id), p_reason: b.data.reason });
  if (error) return Response.json({ ok: false, error: "could not route the lead, try again" }, { status: 503 });
  const r = data as RouteAnswer;
  if (r.ok) return Response.json({ ok: true, result: r.result }, { status: r.status ?? 200 });
  const body: { ok: false; error: string; error_code?: string } = { ok: false, error: r.error ?? "could not route the lead" };
  if (r.error_code) body.error_code = r.error_code;
  return Response.json(body, { status: r.status ?? 400 });
}
