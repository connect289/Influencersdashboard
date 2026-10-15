import { createClient } from "@supabase/supabase-js";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * GET /api/health (M33a): for uptime monitors. 200 {ok:true,…} when the database answers, the frequent jobs ran recently,
 * no job's last run failed and the B2C sync cursor is fresh; 503 otherwise. Counts only, nothing sensitive (b2b.health_check).
 */
export const dynamic = "force-dynamic";

export async function GET() {
  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.schema("b2b").rpc("health_check");
  if (error) return Response.json({ ok: false, error: "database not answering" }, { status: 503, headers: { "Cache-Control": "no-store" } });
  const r = data as { ok: boolean };
  return Response.json(r, { status: r.ok ? 200 : 503, headers: { "Cache-Control": "no-store" } });
}
