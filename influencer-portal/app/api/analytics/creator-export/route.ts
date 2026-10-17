import { NextResponse, type NextRequest } from "next/server";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { loadCreatorDashboard } from "@/lib/analytics/data";
import { fillSeries, parseRange } from "@/lib/analytics/ranges";
import { toCsv } from "@/lib/csv";
import { errorMessage, log } from "@/lib/log";
import { istToday } from "@/lib/format";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** Byte order mark so Excel opens the UTF-8 file correctly. */
const BOM = String.fromCharCode(0xfeff);

/**
 * A creator's home dashboard as CSV (the creator, their agency with the view grant, or staff; inf.creator_dashboard
 * checks). Counts only: no student names, phone numbers or emails, and never Eduwit's revenue.
 */
export async function GET(request: NextRequest) {
  const search = Object.fromEntries(request.nextUrl.searchParams.entries());
  const creatorId = z.uuid().safeParse(search.creator);
  if (!creatorId.success) return new NextResponse("Not found", { status: 404 });
  const range = parseRange(search, istToday());
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims.sub) return new NextResponse("Sign in required", { status: 401 });
  try {
    const t = await getTranslations();
    const d = await loadCreatorDashboard(supabase, creatorId.data, range);
    const byDay = new Map(d.series.map((s) => [s.at, s]));
    const series = fillSeries(
      d.series.map((s) => ({ at: s.at, value: s.leads })),
      range.from,
      range.to,
      range.bucket,
    );
    const rows: unknown[][] = [
      ...series.map((p) => [t("analytics.date"), p.at, p.value, byDay.get(p.at)?.enrolled ?? 0]),
      ...d.content.map((c) => [t("home.topContent"), c.title ?? t("home.unknownContent"), c.leads, c.enrolled]),
      ...d.programmes.map((p) => [t("home.programmes"), p.label ?? t("home.noProgramme"), p.leads, p.enrolled]),
      ...d.platforms.map((p) => [
        t("home.platforms"),
        p.key ? t(`platforms.${p.key}`) : t("home.noPlatform"),
        p.leads,
        p.enrolled,
      ]),
    ];
    const csv = toCsv(
      [
        t("analytics.section"),
        t("analytics.name"),
        t("analytics.metrics.leads.label"),
        t("analytics.metrics.enrollments.label"),
      ],
      rows,
    );
    return new NextResponse(`${BOM}${csv}`, {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="eduwit-my-leads-${range.from}-to-${range.to}.csv"`,
        "cache-control": "private, no-store",
      },
    });
  } catch (e) {
    const msg = errorMessage(e);
    if (/not allowed/.test(msg)) return new NextResponse("Not found", { status: 404 });
    log.error("analytics.creator_export_failed", { error: msg });
    return new NextResponse("Error", { status: 500 });
  }
}
