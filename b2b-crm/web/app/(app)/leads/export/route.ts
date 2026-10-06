import { NextResponse, type NextRequest } from "next/server";
import { getMe } from "@/lib/auth";
import { EXPORT_COLUMNS, csvCell, csvLines, parseLeadQuery, toRpcParams } from "@/lib/leads";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export const maxDuration = 120;

const PAGE = 2000;

/**
 * GET /leads/export?<same filters as /leads>[&masked=1] → CSV, streamed page by page (up to 50,000 rows), so a large
 * download starts at once and runs in the browser's download bar while the Admin keeps working.
 * b2b.leads_export_start records the export (filters, masking, who); each b2b.leads_export_page reads its filters from
 * that record, not from this request, and the last page logs the row count. GET is safe here: SameSite=Lax cookies
 * are not sent on cross-site subresource requests, and the response is a download, never readable by another origin.
 */
export async function GET(req: NextRequest) {
  const result = await getMe();
  if ("setupError" in result || !result.me.is_admin) return new NextResponse("Not allowed", { status: 403 });

  const sp = Object.fromEntries(req.nextUrl.searchParams);
  const masked = sp.masked === "1";
  const supabase = await createClient();
  const { data: exportId, error } = await supabase.schema("b2b").rpc("leads_export_start", { p: toRpcParams(parseLeadQuery(sp), { masked }) });
  if (error || typeof exportId !== "number") return new NextResponse("Export failed", { status: 500 });

  // The first page is read before the response starts, so a failure still returns a proper error status.
  const first = await supabase.schema("b2b").rpc("leads_export_page", { p_export_id: exportId, p_after: null, p_limit: PAGE });
  if (first.error) return new NextResponse("Export failed", { status: 500 });

  type Page = { rows: Record<string, unknown>[]; next: { v: string; id: string } | null };
  const enc = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      controller.enqueue(enc.encode(`﻿${EXPORT_COLUMNS.map(csvCell).join(",")}\r\n`));
      let page = first.data as Page;
      for (;;) {
        controller.enqueue(enc.encode(csvLines(EXPORT_COLUMNS, page.rows)));
        if (!page.next) break;
        const res = await supabase.schema("b2b").rpc("leads_export_page", { p_export_id: exportId, p_after: page.next, p_limit: PAGE });
        if (res.error) {
          // Headers are already sent: end the file with a line that says it is incomplete rather than a silent cut.
          controller.enqueue(enc.encode(`${csvCell("EXPORT INCOMPLETE: a page failed to load. Download again.")}\r\n`));
          break;
        }
        page = res.data as Page;
      }
      controller.close();
    },
  });

  const stamp = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata" }).format(new Date());
  return new NextResponse(stream, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="eduwit-leads-${stamp}${masked ? "-masked" : ""}.csv"`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
