import { NextResponse, type NextRequest } from "next/server";
import { assertUser } from "@/lib/auth";
import { toCsv } from "@/lib/csv";
import { rpc } from "@/lib/data";
import { createClient } from "@/lib/supabase/server";
import type { LeadRow } from "@/lib/types";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

const COLUMNS = ["lead_id", "name", "phone", "email", "city", "state", "language", "course", "specialization", "university", "programme_level", "study_mode",
  "qualification", "source", "campaign", "lane", "status", "stage", "sub_stage", "temperature", "score", "owner_name", "handoff_reason", "partner_consent_state",
  "marketing_consent", "opted_out", "handed_off_at", "assigned_at", "first_contacted_at", "last_contacted_at", "contact_attempts", "next_task_due_at", "tags", "is_test"];
const MAX = 10_000;
const PAGE = 500;

/** The Admin's CSV of the current Leads view or search (spec B10.5). Up to 10,000 rows; every export is logged. */
export async function GET(request: NextRequest) {
  try {
    await assertUser(["admin"]);
  } catch {
    return NextResponse.json({ error: "Only the Admin can export." }, { status: 403 });
  }
  const sp = request.nextUrl.searchParams;
  const q = sp.get("q") ?? "";
  const viewId = Number(sp.get("v"));
  const includeTest = sp.get("test") === "1";
  let view: { id: number; name: string; filters: unknown; sort: unknown } | null = null;
  if (Number.isInteger(viewId) && viewId > 0) {
    const supabase = await createClient();
    const { data } = await supabase.from("saved_views").select("id, name, filters, sort").eq("id", viewId).maybeSingle();
    view = data;
  }
  const filters = q ? {} : view?.filters ?? {};
  const sort = view?.sort ?? { field: "handed_off_at", dir: "desc" };
  const rows: LeadRow[] = [];
  let total = 0;
  try {
    for (let offset = 0; offset < MAX; offset += PAGE) {
      const res = await rpc<{ total: number; rows: LeadRow[] }>("lead_list", { p: { filters, sort, search: q, limit: PAGE, offset, include_test: includeTest } });
      total = res.total;
      rows.push(...res.rows);
      if (res.rows.length < PAGE) break;
    }
    await rpc("audit", { p_action: "export", p_lead: null, p_detail: { what: "leads", view: view ? { id: view.id, name: view.name } : null, search: q || null,
      filters, include_test: includeTest, columns: COLUMNS, rows: rows.length, total } });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : String(e) }, { status: 500 });
  }
  const stamp = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, "");
  return new NextResponse(toCsv(COLUMNS, rows as unknown as Record<string, unknown>[]), {
    headers: {
      "content-type": "text/csv; charset=utf-8",
      "content-disposition": `attachment; filename="b2c-leads-${stamp}.csv"`,
      "cache-control": "no-store",
      "x-rows": String(rows.length),
      "x-total": String(total),
    },
  });
}
