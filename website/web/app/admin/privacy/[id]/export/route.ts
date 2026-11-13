import { NextResponse } from "next/server";
import { exportFileName, privacyError, requestId } from "@/lib/admin/privacy";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";
import { errorFields, log } from "@/lib/server/log";

/**
 * GET /admin/privacy/:id/export — the copy of data for one "send me my data" request, as a JSON file for the super
 * admin to send to the requester (web17, D-096). The database checks the role again, verifies the requester is the
 * account that filed the request, returns only that account's rows and writes the audit row. Never cached; nothing of
 * the document is logged.
 */
const NO_STORE = { "Cache-Control": "no-store", "X-Robots-Tag": "noindex" };

export async function GET(_req: Request, ctx: RouteContext<"/admin/privacy/[id]/export">) {
  const s = await requireAdmin("super_admin");
  const id = requestId.safeParse((await ctx.params).id);
  if (!id.success) return NextResponse.json({ error: "Unknown request." }, { status: 404, headers: NO_STORE });
  let r: { ok: boolean; error?: string; export?: unknown };
  try {
    r = await rpc("web_admin_privacy_export", {
      p_id: id.data,
      p_actor: s.userId,
      p_actor_email: s.email,
      p_role: s.role,
    });
  } catch (err) {
    log("error", "admin.privacy_export_failed", { id: id.data, ...errorFields(err) });
    return NextResponse.json(
      { error: "The copy could not be prepared. Try again." },
      { status: 503, headers: NO_STORE },
    );
  }
  if (!r.ok || r.export === undefined) {
    const status = r.error === "forbidden" ? 403 : r.error === "not_found" ? 404 : 409;
    return NextResponse.json({ error: privacyError(r.error) }, { status, headers: NO_STORE });
  }
  log("info", "admin.privacy_export_downloaded", { id: id.data, actor: s.email });
  return new NextResponse(JSON.stringify(r.export, null, 2), {
    headers: {
      ...NO_STORE,
      "Content-Type": "application/json; charset=utf-8",
      "Content-Disposition": `attachment; filename="${exportFileName(id.data)}"`,
    },
  });
}
