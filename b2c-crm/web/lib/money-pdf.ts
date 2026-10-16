import "server-only";
import { invoicePdf, statementPdf, type InvoiceData, type StatementData } from "@/lib/pdf";
import { adminClient } from "@/lib/supabase/admin";

/**
 * The PDFs the send job attaches to system email (spec B11.1, B11.2; b2c.invoice_send, b2c.run_statements_send). The
 * screens render the same PDFs through invoice_get and commission_statement as the signed-in person; those functions
 * need a person, so the job reads the same rows with the service role and shapes them the same way, then uses the
 * same generators (lib/pdf.ts). `test` marks an invoice or statement of test leads: the sender never sends it live.
 */
export type Attachment = { kind: "invoice_pdf"; invoice_id: number } | { kind: "statement_pdf"; run_id: number; user_id: string };
export type RenderedFile = { filename: string; content: Buffer; contentType: string; test: boolean };

type Db = ReturnType<typeof adminClient>;

export function parseAttachments(v: unknown): Attachment[] {
  if (!Array.isArray(v)) return [];
  return v.flatMap((a): Attachment[] => {
    const x = a as Record<string, unknown>;
    if (x?.kind === "invoice_pdf" && Number.isInteger(Number(x.invoice_id))) return [{ kind: "invoice_pdf", invoice_id: Number(x.invoice_id) }];
    if (x?.kind === "statement_pdf" && Number.isInteger(Number(x.run_id)) && typeof x.user_id === "string") return [{ kind: "statement_pdf", run_id: Number(x.run_id), user_id: x.user_id }];
    throw new Error(`unknown attachment ${JSON.stringify(a).slice(0, 80)}`);
  });
}

export async function renderAttachment(a: Attachment, db: Db = adminClient()): Promise<RenderedFile> {
  return a.kind === "invoice_pdf" ? invoiceFile(db, a.invoice_id) : statementFile(db, a.run_id, a.user_id);
}

const num = (v: unknown) => Number(v ?? 0);

async function invoiceFile(db: Db, id: number): Promise<RenderedFile> {
  const { data: i, error } = await db.from("invoices").select("*").eq("id", id).maybeSingle();
  if (error || !i) throw new Error(`invoice ${id}: ${error?.message ?? "not found"}`);
  const [{ data: lines, error: le }, credit] = await Promise.all([
    db.from("invoice_lines").select("description, net, gst, gross").eq("invoice_id", id).order("id"),
    i.credit_of ? db.from("invoices").select("number").eq("id", i.credit_of).maybeSingle() : Promise.resolve({ data: null }),
  ]);
  if (le) throw new Error(`invoice ${id} lines: ${le.message}`);
  const data: InvoiceData = {
    kind: i.kind, number: i.number, issue_date: i.issue_date, due_on: i.due_on, status: i.status, sac: i.sac, gst_pct: num(i.gst_pct), supply: i.supply,
    net: num(i.net), gst: num(i.gst), gross: num(i.gross), is_test: !!i.is_test, credit_of_number: (credit.data as { number?: string | null } | null)?.number ?? null,
    billing: { eduwit: i.billing?.eduwit ?? {}, university: i.billing?.university ?? {} },
    lines: ((lines ?? []) as { description: string; net: unknown; gst: unknown; gross: unknown }[]).map((l) => ({ description: l.description, net: num(l.net), gst: num(l.gst), gross: num(l.gross) })),
  };
  const name = (i.number ?? `draft-${id}`).replace(/[^A-Za-z0-9-]+/g, "-");
  return { filename: `${name}.pdf`, content: Buffer.from(await invoicePdf(data)), contentType: "application/pdf", test: !!i.is_test };
}

type LineRow = { id: number; kind: string; amount: unknown; tds: unknown; rate_source: string | null; reason: string | null; snapshot: Record<string, unknown> | null; enrollment_id: number; lead_id: number; is_test: boolean };

async function statementFile(db: Db, runId: number, userId: string): Promise<RenderedFile> {
  const [{ data: run, error: re }, { data: user }, { data: lineRows, error: le }, { data: openRows }] = await Promise.all([
    db.from("commission_runs").select("id, period, status, approved_at, is_test").eq("id", runId).maybeSingle(),
    db.from("users").select("full_name, email").eq("user_id", userId).maybeSingle(),
    db.from("commission_lines").select("id, kind, amount, tds, rate_source, reason, snapshot, enrollment_id, lead_id, is_test").eq("run_id", runId).eq("counsellor_id", userId).order("id"),
    db.from("commission_lines").select("amount").eq("counsellor_id", userId).in("status", ["provisional", "confirmed", "due"]).eq("is_test", false),
  ]);
  if (re || !run) throw new Error(`run ${runId}: ${re?.message ?? "not found"}`);
  if (le) throw new Error(`run ${runId} lines: ${le.message}`);
  const lines = (lineRows ?? []) as LineRow[];
  const enrolIds = [...new Set(lines.map((l) => l.enrollment_id))];
  const leadIds = [...new Set(lines.map((l) => l.lead_id))];
  const [{ data: enrols }, { data: records }] = await Promise.all([
    enrolIds.length ? db.from("enrollments").select("id, university, programme, enrolled_on").in("id", enrolIds) : Promise.resolve({ data: [] }),
    leadIds.length ? db.from("lead_records").select("lead_id, record").in("lead_id", leadIds) : Promise.resolve({ data: [] }),
  ]);
  const enrol = new Map(((enrols ?? []) as { id: number; university: string; programme: string; enrolled_on: string }[]).map((e) => [e.id, e]));
  const student = new Map(((records ?? []) as { lead_id: number; record: { student?: { name?: string } } | null }[]).map((r) => [r.lead_id, r.record?.student?.name ?? null]));
  const data: StatementData = {
    counsellor: { name: user?.full_name ?? null, email: user?.email ?? null }, period: String(run.period), approved_at: run.approved_at, status: run.status,
    amount: lines.reduce((a, l) => a + num(l.amount), 0), tds: lines.reduce((a, l) => a + num(l.tds), 0),
    open: ((openRows ?? []) as { amount: unknown }[]).reduce((a, l) => a + num(l.amount), 0),
    lines: lines.map((l) => {
      const e = enrol.get(l.enrollment_id);
      const snap = l.snapshot ?? {};
      const rate = (l.rate_source === "override" ? snap.computed : (snap.used as Record<string, unknown> | undefined)?.computed) as StatementData["lines"][number]["rate"];
      return {
        kind: l.kind, student: student.get(l.lead_id) ?? null, university: e?.university ?? null, programme: e?.programme ?? null, enrolled_on: e?.enrolled_on ?? null,
        amount: l.amount === null ? null : num(l.amount), tds: num(l.tds), rate: rate ?? null, partners: (snap.partners as StatementData["lines"][number]["partners"]) ?? [],
        reason: l.reason, rate_source: l.rate_source,
      };
    }),
  };
  const test = !!run.is_test || (lines.length > 0 && lines.every((l) => l.is_test));
  return { filename: `commission-statement-${String(run.period).slice(0, 7)}.pdf`, content: Buffer.from(await statementPdf(data)), contentType: "application/pdf", test };
}
