import { NextResponse, type NextRequest } from "next/server";
import { assertUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { exportColumns, exportFile, type ExportFormat } from "@/lib/lead-export";
import type { LeadRow, SavedView } from "@/lib/types";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const PAGE = 500;

/**
 * The Admin's download of a Leads view, a search or the ticked rows (spec B10.5), as Excel or CSV, in the view's columns.
 * b2c.export_request decides: up to 10,000 rows come back at once; more are written in the background (lib/lead-jobs.ts)
 * and the person is sent back to the Leads page, where the file appears under Exports. Every export is logged.
 */
export async function GET(request: NextRequest) {
  try {
    await assertUser(["admin"]);
  } catch {
    return NextResponse.json({ error: "Only the Admin can export." }, { status: 403 });
  }
  const sp = request.nextUrl.searchParams;
  const q = sp.get("q") ?? "";
  const viewId = Number(sp.get("view") ?? sp.get("v"));
  const includeTest = sp.get("test") === "1";
  const format: ExportFormat = sp.get("format") === "xlsx" ? "xlsx" : "csv";
  const ids = (sp.get("ids") ?? "").split(",").map(Number).filter((n) => Number.isInteger(n) && n > 0).slice(0, 500);
  let view: SavedView | null = null;
  try {
    if (Number.isInteger(viewId) && viewId > 0) view = await rpc<SavedView>("view_get", { p_id: viewId });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : String(e) }, { status: 403 });
  }
  const filters = q ? {} : view?.filters ?? {};
  const sort = view?.sort ?? { field: "handed_off_at", dir: "desc" };
  const columns = exportColumns(view?.columns);
  const p = { filters, sort, search: q, include_test: includeTest, columns, ...(ids.length ? { ids } : {}) };
  const rows: LeadRow[] = [];
  let total = 0;
  try {
    const plan = await rpc<{ inline: boolean; rows: number; job_id?: number }>("export_request", { p: { ...p, format } });
    if (!plan.inline) {
      return NextResponse.redirect(new URL(`/w/leads?exports=1&queued=${plan.job_id ?? ""}&rows=${plan.rows}`, request.url), 303);
    }
    for (let offset = 0; offset < Math.max(plan.rows, 1); offset += PAGE) {
      const res = await rpc<{ total: number; rows: LeadRow[] }>("lead_list", { p: { ...p, limit: PAGE, offset } });
      total = res.total;
      rows.push(...res.rows);
      if (res.rows.length < PAGE) break;
    }
    await rpc("audit", { p_action: "export", p_lead: null, p_detail: { what: "leads", view: view ? { id: view.id, name: view.name } : null, search: q || null,
      filters, include_test: includeTest, ids: ids.length || null, columns, format, rows: rows.length, total } });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
  const stamp = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, "");
  const file = exportFile(format, columns, rows as unknown as Record<string, unknown>[]);
  return new NextResponse(typeof file.body === "string" ? file.body : Buffer.from(file.body), {
    headers: {
      "content-type": file.type,
      "content-disposition": `attachment; filename="b2c-leads-${stamp}.${file.ext}"`,
      "cache-control": "no-store",
      "x-rows": String(rows.length),
      "x-total": String(total),
    },
  });
}
