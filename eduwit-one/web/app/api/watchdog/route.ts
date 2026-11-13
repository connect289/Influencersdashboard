import { SupabaseOneDb } from "@/lib/db.ts";
import { WatchdogGate, watchdogOk } from "@/lib/watchdog.ts";

// Public and detail-free, for the free-plan uptime monitor (D-018): 200 {"ok":true} while the last finished minute tick
// is under five minutes old and no alert email has waited ten minutes, 503 {"ok":false} otherwise or when the database
// cannot be read (lib/watchdog.ts). The verdict is kept 10 s and the database is read at most 20 times a minute on this
// instance; past that a request gets the last verdict with its real status, never a 429 (security review m5, D-137).
export const dynamic = "force-dynamic";

const gate = new WatchdogGate();

export async function GET() {
  const headers = { "cache-control": "no-store" };
  const ok = await gate.verdictFor(Date.now(), async () => watchdogOk(await SupabaseOneDb.fromEnv()?.watchdog()));
  return Response.json({ ok }, { status: ok ? 200 : 503, headers });
}
