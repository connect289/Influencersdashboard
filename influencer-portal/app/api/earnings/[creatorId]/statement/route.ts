import { NextResponse, type NextRequest } from "next/server";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { monthStatement } from "@/lib/ledger/earnings";
import { loadEarnings } from "@/lib/ledger/data";
import { renderStatementPdf } from "@/lib/ledger/pdf";
import { financePdfLabels } from "@/lib/ledger/pdf-labels";
import { errorMessage, log } from "@/lib/log";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

const MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/;

/**
 * A creator's monthly statement PDF (opening balance, every ledger line posted that IST month, closing balance), for
 * the creator, an agency with the earnings grant and Finance. Access is decided by inf.creator_earnings().
 */
export async function GET(request: NextRequest, { params }: { params: Promise<{ creatorId: string }> }) {
  const { creatorId } = await params;
  const month = request.nextUrl.searchParams.get("month") ?? "";
  if (!z.uuid().safeParse(creatorId).success || !MONTH_RE.test(month))
    return new NextResponse("Not found", { status: 404 });
  const supabase = await createClient();
  const { data: claims } = await supabase.auth.getClaims();
  if (!claims?.claims.sub) return new NextResponse("Sign in required", { status: 401 });
  try {
    const e = await loadEarnings(supabase, creatorId);
    if (!e) return new NextResponse("Not found", { status: 404 });
    const t = await getTranslations();
    const st = monthStatement(
      e.entries.map((x) => ({
        ...x,
        label: [x.note ?? t(`finance.types.${x.type}`), x.deal_title, x.lead_ref].filter(Boolean).join(" · "),
      })),
      month,
    );
    const monthLabel = new Intl.DateTimeFormat("en-IN", { month: "long", year: "numeric", timeZone: "UTC" }).format(
      new Date(`${month}-15T00:00:00Z`),
    );
    const pdf = await renderStatementPdf(st, e.creator, e.organisation, monthLabel, await financePdfLabels());
    return new NextResponse(new Uint8Array(pdf), {
      headers: {
        "content-type": "application/pdf",
        "content-disposition": `attachment; filename="eduwit-statement-${e.creator.handle}-${month}.pdf"`,
        "cache-control": "private, no-store",
      },
    });
  } catch (err) {
    log.error("earnings.statement_failed", { creator_id: creatorId, error: errorMessage(err) });
    return new NextResponse("Error", { status: 500 });
  }
}
