import { createClient } from "@supabase/supabase-js";
import { supabasePublishableKey, supabaseUrl } from "@/lib/env";

/**
 * GET /api/health (M33a): for uptime monitors. 200 {ok:true,…} when the database answers, the frequent jobs ran recently,
 * no job's last run failed and the B2C sync cursor is fresh; 503 otherwise. Counts only, nothing sensitive (b2b.health_check).
 */
export const dynamic = "force-dynamic";
// A health call never outlives its caller's patience: Eduwit One waits 5 s, and a function left waiting on a slow
// database runs (and is billed) up to Vercel's ceiling. The database gets 3 s, the call 10 s.
export const maxDuration = 10;
const READ_TIMEOUT_MS = 3_000;
// One reading serves every caller for 15 s, so a flood of calls cannot become a flood of database queries.
const CACHE_MS = 15_000;

type Reading = { status: number; body: unknown };
let cached: { at: number; reading: Reading } | null = null;

async function read(): Promise<Reading> {
  const supabase = createClient(supabaseUrl(), supabasePublishableKey(), { auth: { persistSession: false, autoRefreshToken: false } });
  // an aborted call comes back as { error } (it does not throw), so a database slower than 3 s reads as not answering
  const { data, error } = await supabase.schema("b2b").rpc("health_check").abortSignal(AbortSignal.timeout(READ_TIMEOUT_MS));
  if (error) return { status: 503, body: { ok: false, error: "database not answering" } };
  const r = data as { ok: boolean };
  return { status: r.ok ? 200 : 503, body: r };
}

export async function GET() {
  const now = Date.now();
  if (!cached || now - cached.at > CACHE_MS) cached = { at: now, reading: await read() };
  const { status, body } = cached.reading;
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}
