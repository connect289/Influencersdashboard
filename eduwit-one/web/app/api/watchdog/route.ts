import { SupabaseOneDb } from "@/lib/db.ts";
import { watchdogOk } from "@/lib/watchdog.ts";

// Public and detail-free, for the free-plan uptime monitor (D-018): 200 {"ok":true} while the last finished minute tick
// is under five minutes old and no alert email has waited ten minutes, 503 {"ok":false} otherwise or when the database
// cannot be read (lib/watchdog.ts).
export const dynamic = "force-dynamic";

export async function GET() {
  let ok = false;
  try {
    ok = watchdogOk(await SupabaseOneDb.fromEnv()?.watchdog());
  } catch {
    ok = false;
  }
  return Response.json({ ok }, { status: ok ? 200 : 503, headers: { "cache-control": "no-store" } });
}
