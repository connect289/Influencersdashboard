import { type NextRequest } from "next/server";
import { toCsv } from "@/lib/csv.ts";
import { assertUser } from "@/lib/session.ts";
import { ui, UiError } from "@/lib/ui/api.ts";
import { analyticsSchema } from "@/lib/ui/schemas.ts";

// The Analytics export (spec §12): the funnel as CSV. It holds counts only, so there are no contact fields to include
// (the spec's "include contact fields" box has nothing to switch on; D-062).
export async function GET(request: NextRequest) {
  try {
    await assertUser();
  } catch {
    return new Response("not allowed", { status: 403 });
  }
  const days = Number(request.nextUrl.searchParams.get("days") ?? 30);
  try {
    const data = await ui("ui_analytics", analyticsSchema, { p_days: Number.isFinite(days) ? days : 30 });
    const csv = toCsv(data.funnel, ["ord", "key", "label", "leads", "events", "median_min_from_previous"]);
    return new Response(csv, {
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="eduwit-one-funnel-${data.days}d.csv"`,
        "cache-control": "no-store",
      },
    });
  } catch (e) {
    return new Response(e instanceof UiError ? e.message : "export failed", { status: 500 });
  }
}
