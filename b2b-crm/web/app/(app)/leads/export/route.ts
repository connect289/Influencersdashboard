import { NextResponse, type NextRequest } from "next/server";
import { getMe } from "@/lib/auth";
import { EXPORT_COLUMNS, parseLeadQuery, toCsv, toRpcParams } from "@/lib/leads";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/**
 * GET /leads/export?<same filters as /leads>[&masked=1] → CSV (up to 10,000 rows). b2b.leads_export re-checks the
 * Admin and writes the export to b2b.lead_exports and the event log. GET is safe here: SameSite=Lax cookies are not
 * sent on cross-site subresource requests, and the response is a download, never readable by another origin.
 */
export async function GET(req: NextRequest) {
  const result = await getMe();
  if ("setupError" in result || !result.me.is_admin) return new NextResponse("Not allowed", { status: 403 });

  const sp = Object.fromEntries(req.nextUrl.searchParams);
  const masked = sp.masked === "1";
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("leads_export", { p: toRpcParams(parseLeadQuery(sp), { masked }) });
  if (error) return new NextResponse("Export failed", { status: 500 });

  const stamp = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata" }).format(new Date());
  return new NextResponse(toCsv([...EXPORT_COLUMNS], (data ?? []) as Record<string, unknown>[]), {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="eduwit-leads-${stamp}${masked ? "-masked" : ""}.csv"`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
