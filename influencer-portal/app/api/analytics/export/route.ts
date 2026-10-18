import { NextResponse, type NextRequest } from "next/server";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { breakdownCsv, sortBreakdown, toBreakdown } from "@/lib/analytics/breakdown";
import { DIMENSIONS, loadTotals } from "@/lib/analytics/data";
import { dimensionLabel } from "@/lib/analytics/labels";
import { parseRange } from "@/lib/analytics/ranges";
import { errorMessage, log } from "@/lib/log";
import { istToday } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** Byte order mark so Excel opens the UTF-8 file (₹, names) correctly. */
const BOM = String.fromCharCode(0xfeff);

const params = z.object({
  dim: z.enum(DIMENSIONS).catch("creator"),
  campaign: z.uuid().optional().catch(undefined),
  creator: z.uuid().optional().catch(undefined),
  test: z.literal("1").optional().catch(undefined),
});

/**
 * A dashboard breakdown as CSV (staff with analytics.read; inf.analytics_totals checks). Aggregates only: no student
 * names or contact details are ever in it.
 */
export async function GET(request: NextRequest) {
  const search = Object.fromEntries(request.nextUrl.searchParams.entries());
  const p = params.parse(search);
  const range = parseRange(search, istToday());
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims.sub) return new NextResponse("Sign in required", { status: 401 });
  try {
    const t = await getTranslations();
    const rows = await loadTotals(supabase, range, {
      dim: p.dim,
      campaignId: p.campaign ?? null,
      creatorId: p.creator ?? null,
      includeTest: p.test === "1",
    });
    const csv = breakdownCsv(
      sortBreakdown(toBreakdown(rows, (r) => dimensionLabel(p.dim, r.key, r.label, t))),
      t(`analytics.dimensions.${p.dim}`),
    );
    return new NextResponse(`${BOM}${csv}`, {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="eduwit-analytics-${p.dim}-${range.from}-to-${range.to}.csv"`,
        "cache-control": "private, no-store",
      },
    });
  } catch (e) {
    const msg = errorMessage(e);
    if (/not allowed/.test(msg)) return new NextResponse("Not found", { status: 404 });
    log.error("analytics.export_failed", { error: msg });
    return new NextResponse("Error", { status: 500 });
  }
}
