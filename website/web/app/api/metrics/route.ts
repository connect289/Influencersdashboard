import { connection } from "next/server";
import { dbConfigured, rpc } from "@/lib/server/db";
import { isInternal } from "@/lib/server/internal-auth";

/** Metrics summary for the oversight system (spec 9.4). Internal key required. Extended as features land. */
export async function GET(req: Request) {
  await connection();
  if (!isInternal(req)) return new Response("unauthorised", { status: 401 });
  if (!dbConfigured()) return Response.json({ ok: false, error: "db not configured" }, { status: 503 });
  const health = await rpc<Record<string, unknown>>("web_health");
  return Response.json(
    { ok: true, at: new Date().toISOString(), health },
    { headers: { "cache-control": "no-store" } },
  );
}
