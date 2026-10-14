import { NextResponse, type NextRequest } from "next/server";
import { assertUser } from "@/lib/auth";
import { toCsv } from "@/lib/csv";
import { friendly, rpc } from "@/lib/data";

export const dynamic = "force-dynamic";

type RunView = { period: string; status: string; is_test: boolean; counsellors: { counsellor_id: string; name: string; email: string; amount: number; tds: number; net: number; lines: unknown[] }[] };

/** The finance sheet for one run: one row per counsellor (spec B11.2). Admin only. */
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    await assertUser(["admin"]);
  } catch {
    return NextResponse.json({ error: "Only the Admin can download this." }, { status: 403 });
  }
  const id = Number((await params).id);
  if (!Number.isInteger(id) || id <= 0) return NextResponse.json({ error: "bad id" }, { status: 400 });
  try {
    const v = await rpc<RunView>("commission_run_view", { p_run: id });
    const rows = v.counsellors.map((c) => ({ period: v.period.slice(0, 7), run_status: v.status, test: v.is_test ? "yes" : "no", counsellor: c.name, email: c.email,
      lines: c.lines.length, amount: c.amount, tds: c.tds, net: c.net }));
    const csv = toCsv(["period", "run_status", "test", "counsellor", "email", "lines", "amount", "tds", "net"], rows);
    return new NextResponse(csv, { headers: { "content-type": "text/csv; charset=utf-8", "content-disposition": `attachment; filename="commission-run-${v.period.slice(0, 7)}${v.is_test ? "-test" : ""}.csv"`, "cache-control": "private, no-store" } });
  } catch (e) {
    return NextResponse.json({ error: friendly(e) }, { status: 404 });
  }
}
