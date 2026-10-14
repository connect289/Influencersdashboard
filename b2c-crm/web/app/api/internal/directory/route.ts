import { NextResponse, type NextRequest } from "next/server";
import { directoryConfig, listDirectory } from "@/lib/directory";
import { internalKeyOk } from "@/lib/internal";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/** Called daily by pg_cron (b2c-directory) with x-internal-key: Workspace names, photos and titles, and suspensions. */
export async function POST(request: NextRequest) {
  if (!internalKeyOk(request.headers.get("x-internal-key"), process.env.B2C_INTERNAL_KEY)) {
    return NextResponse.json({ ok: false, error: "unauthorised" }, { status: 401 });
  }
  const cfg = directoryConfig();
  if (!cfg) return NextResponse.json({ ok: true, skipped: "GOOGLE_SA_EMAIL, GOOGLE_SA_PRIVATE_KEY and GOOGLE_ADMIN_EMAIL are not set" });
  try {
    const users = await listDirectory(cfg.sa, cfg.admin, cfg.domain);
    const { data, error } = await adminClient().rpc("directory_sync", { p_users: users });
    if (error) throw new Error(error.message);
    return NextResponse.json({ ok: true, read: users.length, ...(data as object) });
  } catch (e) {
    console.error("directory sync failed", e);
    return NextResponse.json({ ok: false, error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
}
