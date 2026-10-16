import { NextResponse, type NextRequest } from "next/server";
import { assertUser } from "@/lib/auth";
import { friendly, rpc } from "@/lib/data";
import { invoicePdf, type InvoiceData } from "@/lib/pdf";

export const dynamic = "force-dynamic";

/** One invoice or credit note as a PDF (spec B11.1). Read as the signed-in person, so only those who may read money get it. */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    await assertUser(["admin", "marketing"]);
  } catch {
    return NextResponse.json({ error: "not allowed" }, { status: 403 });
  }
  const id = Number((await params).id);
  if (!Number.isInteger(id) || id <= 0) return NextResponse.json({ error: "bad id" }, { status: 400 });
  try {
    const i = await rpc<InvoiceData & { credit_of: number | null }>("invoice_get", { p_id: id });
    const credit = i.credit_of ? await rpc<{ number: string | null }>("invoice_get", { p_id: i.credit_of }).catch(() => null) : null;
    const bytes = await invoicePdf({ ...i, credit_of_number: credit?.number ?? null });
    const name = (i.number ?? `draft-${id}`).replace(/[^A-Za-z0-9-]+/g, "-");
    return new NextResponse(Buffer.from(bytes), { headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${name}.pdf"`, "cache-control": "private, no-store" } });
  } catch (e) {
    return NextResponse.json({ error: friendly(e) }, { status: 404 });
  }
}
