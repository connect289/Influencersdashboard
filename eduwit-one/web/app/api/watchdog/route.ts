import { SupabaseOneDb } from "@/lib/db.ts";

// Public and detail-free, for the free-plan uptime monitor (D-018): 200 {"ok":true} while the last minute tick is under
// five minutes old, 503 {"ok":false} otherwise or when the database cannot be read.
export const dynamic = "force-dynamic";

const MAX_TICK_AGE_S = 300;

export async function GET() {
  let ok = false;
  try {
    const ages = await SupabaseOneDb.fromEnv()?.watchdog();
    ok = ages?.tick_age_s != null && ages.tick_age_s < MAX_TICK_AGE_S;
  } catch {
    ok = false;
  }
  return Response.json({ ok }, { status: ok ? 200 : 503, headers: { "cache-control": "no-store" } });
}
