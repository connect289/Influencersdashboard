import { createClient } from "@supabase/supabase-js";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * Meta Lead Ads webhook (spec B4). GET answers Meta's subscription check with the verify token set on the Intake
 * screen; POST passes the raw body and X-Hub-Signature-256 to b2b.meta_webhook_ingest, which checks the signature with
 * the app secret and queues each leadgen id. The lead itself is fetched from the Graph API by b2b.intake_tick.
 */
export const dynamic = "force-dynamic";
const MAX_BYTES = 200_000;

const client = () => createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });

export async function GET(request: Request) {
  const q = new URL(request.url).searchParams;
  const { data, error } = await client().schema("b2b").rpc("meta_webhook_verify", {
    p_mode: q.get("hub.mode") ?? "", p_token: q.get("hub.verify_token") ?? "", p_challenge: q.get("hub.challenge") ?? "",
  });
  if (error) return new Response("try again", { status: 503 });
  if (typeof data !== "string") return new Response("forbidden", { status: 403 });
  return new Response(data, { status: 200, headers: { "content-type": "text/plain" } });
}

export async function POST(request: Request) {
  if (Number(request.headers.get("content-length") ?? 0) > MAX_BYTES) return Response.json({ ok: false, error: "body too large" }, { status: 413 });
  const body = await request.text();
  if (body.length > MAX_BYTES) return Response.json({ ok: false, error: "body too large" }, { status: 413 });
  const { data, error } = await client().schema("b2b").rpc("meta_webhook_ingest", {
    p_body: body, p_signature: request.headers.get("x-hub-signature-256") ?? "",
  });
  if (error) return Response.json({ ok: false, error: "try again" }, { status: 503 });
  const r = data as { ok: boolean; status: number; result?: unknown; error?: string };
  return Response.json(r.ok ? { ok: true } : { ok: false, error: r.error }, { status: r.status ?? (r.ok ? 200 : 400) });
}
