import { NextResponse, type NextRequest } from "next/server";
import { getMe } from "@/lib/auth";
import { decodeDef } from "@/lib/reports";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** GET /reports/export?id=<saved report> or ?def=<base64url definition> → CSV (all rows, up to 5,000; logged). */
export async function GET(req: NextRequest) {
  const me = await getMe();
  if ("setupError" in me || !me.me.is_admin) return new NextResponse("Not allowed", { status: 403 });
  const id = req.nextUrl.searchParams.get("id");
  const def = req.nextUrl.searchParams.get("def");
  let p: Record<string, unknown> | null = null;
  if (id && /^\d{1,15}$/.test(id)) p = { id: Number(id), override: { limit: 5000 } };
  else if (def) { const d = decodeDef(def); if (d) p = d.kind === "tabular" ? { ...d, definition: { ...d.definition, limit: d.definition.limit ?? 5000 } } : d; }
  if (!p) return new NextResponse("Unknown report", { status: 400 });
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("report_csv_admin", { p });
  if (error || typeof data !== "string") return new NextResponse(error?.code === "22023" ? error.message : "Export failed", { status: error?.code === "22023" ? 400 : 500 });
  const name = (req.nextUrl.searchParams.get("name") ?? "report").replace(/[^a-z0-9-]+/gi, "-").slice(0, 60) || "report";
  return new NextResponse(`﻿${data.replace(/\n/g, "\r\n")}\r\n`, {
    headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="${name}.csv"`, "Cache-Control": "no-store" },
  });
}
