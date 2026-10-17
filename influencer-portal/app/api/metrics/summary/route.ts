import { NextResponse, type NextRequest } from "next/server";
import { hasInternalKey } from "@/lib/internal-auth";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

/** Counts for the oversight system. Requires the internal key. No personal data. */
export async function GET(request: NextRequest) {
  if (!hasInternalKey(request.headers))
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const db = adminClient();
  const [status, creators] = await Promise.all([
    db.rpc("system_status"),
    db.from("creators").select("status"),
  ]);
  if (status.error || creators.error)
    return NextResponse.json({ error: "unavailable" }, { status: 503 });
  const byStatus: Record<string, number> = {};
  for (const c of creators.data) byStatus[c.status] = (byStatus[c.status] ?? 0) + 1;
  return NextResponse.json(
    { time: new Date().toISOString(), creators: byStatus, system: status.data },
    { headers: { "cache-control": "no-store" } },
  );
}
