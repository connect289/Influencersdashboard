import { NextResponse, type NextRequest } from "next/server";
import { assertUser } from "@/lib/auth";
import { friendly, rpc } from "@/lib/data";
import { statementPdf, type StatementData } from "@/lib/pdf";

export const dynamic = "force-dynamic";

/** A counsellor's own statement for one approved run, as a PDF (spec B11.2). The database returns only the caller's lines. */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ run: string }> }) {
  try {
    await assertUser();
  } catch {
    return NextResponse.json({ error: "not allowed" }, { status: 403 });
  }
  const run = Number((await params).run);
  if (!Number.isInteger(run) || run <= 0) return NextResponse.json({ error: "bad run" }, { status: 400 });
  try {
    const s = await rpc<StatementData>("commission_statement", { p_run: run, p_user: null });
    const bytes = await statementPdf(s);
    return new NextResponse(Buffer.from(bytes), { headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="commission-statement-${s.period.slice(0, 7)}.pdf"`, "cache-control": "private, no-store" } });
  } catch (e) {
    return NextResponse.json({ error: friendly(e) }, { status: 404 });
  }
}
