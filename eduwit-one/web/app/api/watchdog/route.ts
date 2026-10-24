import { SupabaseOneDb } from "@/lib/db.ts";
import { WatchdogGate, watchdogOk } from "@/lib/watchdog.ts";

// Public and detail-free, for the free-plan uptime monitor (D-018): 200 {"ok":true} while the last finished minute tick
// is under five minutes old and no alert email has waited ten minutes, 503 {"ok":false} otherwise or when the database
// cannot be read (lib/watchdog.ts). The verdict is kept 10 s and more than 20 requests a minute on this instance get
// 429 {"ok":false} (security review m5).
export const dynamic = "force-dynamic";

const gate = new WatchdogGate();

export async function GET() {
  const now = Date.now();
  const headers = { "cache-control": "no-store" };
  const answer = gate.take(now);
  if (answer.kind === "limited") return Response.json({ ok: false }, { status: 429, headers });
  let ok = false;
  if (answer.kind === "cached") {
    ok = answer.ok;
  } else {
    try {
      ok = watchdogOk(await SupabaseOneDb.fromEnv()?.watchdog());
    } catch {
      ok = false;
    }
    gate.remember(ok, now);
  }
  return Response.json({ ok }, { status: ok ? 200 : 503, headers });
}
