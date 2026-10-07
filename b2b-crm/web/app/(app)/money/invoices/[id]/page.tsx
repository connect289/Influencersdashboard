import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ChevronLeft } from "lucide-react";
import { Badge, Card } from "@/components/ui/Card";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { GST_STATES, INVOICE_STATUS, amountInWords, dayLabel, formatInr, monthLabel, type Party } from "@/lib/money";
import { invoiceDetail } from "@/lib/money-data";
import { InvoiceActions } from "./InvoiceActions";

export const metadata: Metadata = { title: "Invoice" };
type Props = { params: Promise<{ id: string }> };

function PartyBlock({ title, p }: { title: string; p: Party }) {
  return (
    <div className="min-w-0 space-y-0.5 text-[12.5px]">
      <p className="text-[11px] font-semibold uppercase tracking-wider text-subtle">{title}</p>
      <p className="font-semibold text-fg">{p.legal_name ?? <span className="text-danger">Legal name missing</span>}</p>
      {p.address ? <p className="whitespace-pre-line text-muted">{p.address}</p> : <p className="text-danger">Address missing</p>}
      <p className="text-muted">GSTIN <span className="font-mono text-fg">{p.gstin ?? "—"}</span>
        {p.state_code && <> · State {p.state_code}{GST_STATES[p.state_code] ? ` (${GST_STATES[p.state_code]})` : ""}</>}</p>
      {p.email && <p className="text-muted">{p.email}</p>}
    </div>
  );
}

/** A GST tax invoice as the partner receives it (print or save as PDF), with approve, sent and cancel for the Admin. */
export default async function InvoicePage({ params }: Props) {
  await requireAdmin();
  const id = Number((await params).id);
  if (!Number.isInteger(id) || id <= 0) notFound();
  const i = await invoiceDetail(id);
  if (!i) notFound();
  const lines = i.lines.filter((l) => !l.released);
  const st = INVOICE_STATUS[i.status];
  const outstanding = ["approved", "sent", "partly_paid"].includes(i.status) ? i.total_inr - i.received_inr - i.tds_inr : 0;
  const draft = i.status === "draft";
  // the CA's confirmation is advised, not required; the details printed on the invoice are required
  const blocking = i.setup_missing.filter((m) => !m.startsWith("confirmation"));
  if (draft && !i.recipient.legal_name) blocking.push("partner legal name");
  if (draft && !i.recipient.address) blocking.push("partner billing address");
  if (draft && !i.recipient.state_code) blocking.push("partner state (GSTIN or state code)");

  return (
    <>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3 print:hidden">
        <Link href="/money?tab=invoices" className="inline-flex items-center gap-1 text-[13px] text-muted hover:text-fg"><ChevronLeft className="size-4" /> Invoices</Link>
        <InvoiceActions id={i.id} status={i.status} number={i.number} blocked={blocking.length > 0} total={i.total_inr} lines={lines} />
      </div>
      {draft && blocking.length > 0 && (
        <Notice tone="warning" className="mb-4 print:hidden">Approval needs: {blocking.join(", ")}. Set them in <Link href="/money?tab=settings" className="font-medium underline">Settings</Link>.</Notice>
      )}
      {draft && blocking.length === 0 && i.setup_missing.length > 0 && (
        <Notice tone="info" className="mb-4 print:hidden">Not yet confirmed by Eduwit&apos;s CA: check the GST rate and SAC code before approving.</Notice>
      )}
      {i.status === "cancelled" && <Notice tone="error" className="mb-4">Cancelled{i.cancel_reason ? `: ${i.cancel_reason}` : ""}. Its lines went back to the next invoice.</Notice>}

      <Card className="mx-auto max-w-4xl min-w-0 print:border-0 print:shadow-none">
        <header className="flex flex-wrap items-start justify-between gap-4 border-b border-border px-6 py-5">
          <div>
            <h1 className="text-lg font-semibold tracking-tight text-fg">{draft ? "Draft tax invoice" : "Tax invoice"}</h1>
            <p className="mt-0.5 font-mono text-[13px] text-fg">{i.number ?? `Draft #${i.id} (numbered on approval)`}</p>
          </div>
          <div className="text-right text-[12.5px]">
            <Badge tone={st.tone} className="print:hidden">{st.label}</Badge>
            <p className="mt-1 text-muted">Date <span className="text-fg">{i.issue_date ? dayLabel(i.issue_date) : "on approval"}</span></p>
            <p className="text-muted">Due <span className="text-fg">{i.due_date ? dayLabel(i.due_date) : "—"}</span></p>
            <p className="text-muted">For commission through {monthLabel(i.through_period)}</p>
          </div>
        </header>
        <div className="grid gap-6 border-b border-border px-6 py-5 sm:grid-cols-2">
          <PartyBlock title="From" p={i.supplier} />
          <PartyBlock title="Bill to" p={i.recipient} />
        </div>
        <div className="flex flex-wrap gap-x-6 gap-y-1 border-b border-border px-6 py-3 text-[12px] text-muted">
          <span>SAC <span className="font-mono text-fg">{i.sac_code ?? "—"}</span></span>
          <span>Place of supply <span className="text-fg">{i.place_of_supply ? `${i.place_of_supply}${GST_STATES[i.place_of_supply] ? ` · ${GST_STATES[i.place_of_supply]}` : ""}` : "—"}</span></span>
          <span>Tax <span className="text-fg">{i.tax_type === "cgst_sgst" ? "CGST + SGST" : "IGST"} at {Math.round(i.gst_rate * 10000) / 100}%</span></span>
          <span>Service: commission for student enrolments referred by Eduwit</span>
        </div>
        <div className="relative overflow-x-auto">
          <table className="w-full min-w-[640px] text-left text-[12.5px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-b border-border">
                <th scope="col" className="w-10 px-6 py-2 font-medium">#</th>
                <th scope="col" className="px-3 py-2 font-medium">Description</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Taxable value</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">GST</th>
                <th scope="col" className="px-6 py-2 text-right font-medium">Amount</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {lines.map((l, n) => (
                <tr key={l.id}>
                  <td className="tabular px-6 py-2 text-subtle">{n + 1}</td>
                  <td className="px-3 py-2 text-fg">{l.description}</td>
                  <td className={cn("tabular whitespace-nowrap px-3 py-2 text-right", l.taxable_inr < 0 ? "text-danger" : "text-fg")}>{formatInr(l.taxable_inr, true)}</td>
                  <td className="tabular whitespace-nowrap px-3 py-2 text-right text-muted">{formatInr(l.gst_inr, true)}</td>
                  <td className="tabular whitespace-nowrap px-6 py-2 text-right text-fg">{formatInr(l.total_inr, true)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="grid gap-6 border-t border-border px-6 py-5 sm:grid-cols-[1fr_auto]">
          <div className="space-y-2 text-[12.5px]">
            <p className="text-muted">Amount in words: <span className="text-fg">{amountInWords(i.total_inr)}</span></p>
            {i.supplier.bank && <div><p className="text-[11px] font-semibold uppercase tracking-wider text-subtle">Pay to</p><p className="whitespace-pre-line text-muted">{i.supplier.bank}</p></div>}
            <p className="text-subtle">Please quote the invoice number with the payment. TDS deducted, if any, should be reported against Eduwit&apos;s PAN.</p>
          </div>
          <dl className="grid min-w-64 grid-cols-[1fr_auto] gap-x-6 gap-y-1 text-[12.5px]">
            <dt className="text-muted">Taxable value</dt><dd className="tabular text-right text-fg">{formatInr(i.taxable_inr, true)}</dd>
            {i.tax_type === "cgst_sgst" ? (<>
              <dt className="text-muted">CGST</dt><dd className="tabular text-right text-fg">{formatInr(i.cgst_inr, true)}</dd>
              <dt className="text-muted">SGST</dt><dd className="tabular text-right text-fg">{formatInr(i.sgst_inr, true)}</dd>
            </>) : (<><dt className="text-muted">IGST</dt><dd className="tabular text-right text-fg">{formatInr(i.igst_inr, true)}</dd></>)}
            <dt className="border-t border-border pt-1 font-semibold text-fg">Total</dt><dd className="tabular border-t border-border pt-1 text-right font-semibold text-fg">{formatInr(i.total_inr, true)}</dd>
            {(i.received_inr > 0 || i.tds_inr > 0) && (<>
              <dt className="text-muted print:hidden">Received</dt><dd className="tabular text-right text-muted print:hidden">{formatInr(i.received_inr, true)}</dd>
              <dt className="text-muted print:hidden">TDS</dt><dd className="tabular text-right text-muted print:hidden">{formatInr(i.tds_inr, true)}</dd>
              <dt className="font-medium text-fg print:hidden">Outstanding</dt><dd className="tabular text-right font-medium text-fg print:hidden">{formatInr(outstanding, true)}</dd>
            </>)}
          </dl>
        </div>
      </Card>

      {i.payments.length > 0 && (
        <Card className="mx-auto mt-6 max-w-4xl min-w-0 print:hidden">
          <h2 className="border-b border-border px-6 py-3 text-sm font-semibold text-fg">Payments</h2>
          <ul className="divide-y divide-border text-[12.5px]">
            {i.payments.map((p, n) => (
              <li key={n} className={cn("flex flex-wrap gap-x-4 px-6 py-2", p.reversed && "text-subtle line-through")}>
                <span>{dayLabel(p.received_on)}</span><span className="tabular">{formatInr(p.amount_inr, true)}</span>
                {p.tds_inr > 0 && <span className="tabular">+ {formatInr(p.tds_inr, true)} TDS</span>}
                {p.bank_ref && <span className="font-mono">{p.bank_ref}</span>}{p.reversed && <span className="no-underline">(receipt voided)</span>}
              </li>
            ))}
          </ul>
        </Card>
      )}
    </>
  );
}
