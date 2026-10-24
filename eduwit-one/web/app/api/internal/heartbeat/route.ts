import { internalAuthorized } from "@/lib/auth.ts";
import { SupabaseOneDb } from "@/lib/db.ts";

// The two ages the external watchdog reads (spec §3): the last one-tick and the app's last answer to it.
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  if (!(await internalAuthorized(request))) return Response.json({ error: "unauthorized" }, { status: 401 });
  const db = SupabaseOneDb.fromEnv();
  if (!db) return Response.json({ error: "not_configured" }, { status: 503 });
  try {
    return Response.json(await db.watchdog(), { headers: { "cache-control": "no-store" } });
  } catch {
    return Response.json({ error: "database" }, { status: 503 });
  }
}
