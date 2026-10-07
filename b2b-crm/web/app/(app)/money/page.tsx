import type { Metadata } from "next";
import Link from "next/link";
import { FileSpreadsheet, FileText, GraduationCap, Wallet } from "lucide-react";
import { Badge, Card, CardHeader, EmptyState, PageHeader } from "@/components/ui/Card";
import { Notice } from "@/components/ui/Notice";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import { ENROLLMENT_STATUS, INVOICE_STATUS, TIER_BASIS, dayLabel, formatInr, monthLabel, tierWatch, type EnrollmentStatus } from "@/lib/money";
import { moneyEnrollments, moneyInvoices, moneyOverview, moneyReceipts, moneyStatements } from "@/lib/money-data";
import { listPartners } from "@/lib/partners-data";
import { AddEnrollment, AdjustmentButton, EnrollmentTable } from "./Enrollments";
import { BillingTable, SettingsForm } from "./Settings";
import { CloseMonth, ExportPanel } from "./Months";
import { ReceiptForm, ReceiptList } from "./Receipts";
import { StatementUpload } from "./StatementUpload";

export const metadata: Metadata = { title: "Commission & Finance" };

const TABS = [
  { id: "overview", label: "Overview" },
  { id: "enrollments", label: "Enrolments" },
  { id: "invoices", label: "Invoices" },
  { id: "receipts", label: "Receipts" },
  { id: "statements", label: "Statements" },
  { id: "settings", label: "Settings" },
] as const;
type Tab = (typeof TABS)[number]["id"];
type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };
const one = (v: string | string[] | undefined) => (typeof v === "string" ? v : undefined);

function Kpi({ label, value, hint, tone }: { label: string; value: string; hint?: string; tone?: string }) {
  return (
    <div className="bg-surface px-5 py-4">
      <dt className="text-[12px] text-muted">{label}</dt>
      <dd className={cn("tabular mt-0.5 text-xl font-semibold text-fg", tone)}>{value}</dd>
      {hint && <dd className="mt-0.5 text-[11.5px] text-subtle">{hint}</dd>}
    </div>
  );
}

export default async function MoneyPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const tab: Tab = TABS.find((t) => t.id === sp.tab)?.id ?? "overview";
  const partnerId = Number(one(sp.partner)) || null;
  const o = await moneyOverview();
  const partners = o.partners.map((p) => ({ id: p.id, name: p.name }));
  const qs = (extra: Record<string, string | null>) => {
    const u = new URLSearchParams({ tab });
    if (partnerId) u.set("partner", String(partnerId));
    for (const [k, v] of Object.entries(extra)) if (v === null) u.delete(k); else u.set(k, v);
    return `/money?${u}`;
  };

  return (
    <>
      <PageHeader title="Commission & Finance"
        description="What partners owe Eduwit: enrolments verified against proof, commission booked from the rate in force, monthly GST invoices, receipts with TDS, and the partner's own statement reconciled line by line." />
      <nav className="mb-6 flex gap-5 overflow-x-auto border-b border-border" aria-label="Commission sections">
        {TABS.map((t) => (
          <Link key={t.id} href={`/money?tab=${t.id}`} aria-current={tab === t.id ? "page" : undefined}
            className={cn("-mb-px shrink-0 whitespace-nowrap border-b-2 pb-2.5 text-[13px] font-medium transition-colors", tab === t.id ? "border-amber text-fg" : "border-transparent text-muted hover:text-fg")}>
            {t.label}
            {t.id === "enrollments" && o.enrollments.to_verify > 0 && <Badge tone="warning" className="ml-1.5">{o.enrollments.to_verify}</Badge>}
            {t.id === "invoices" && o.invoices.drafts > 0 && <Badge tone="brand" className="ml-1.5">{o.invoices.drafts}</Badge>}
            {t.id === "settings" && o.setup_missing.length > 0 && <Badge tone="danger" className="ml-1.5">!</Badge>}
          </Link>
        ))}
      </nav>

      {tab === "overview" && (
        <div className="space-y-6">
          {o.setup_missing.length > 0 && (
            <Notice tone="warning">Money settings still to complete: {o.setup_missing.join(", ")}. <Link href="/money?tab=settings" className="font-medium underline">Settings</Link></Notice>
          )}
          <Card className="min-w-0 overflow-hidden">
            <dl className="grid grid-cols-2 gap-px bg-border md:grid-cols-3 xl:grid-cols-6">
              <Kpi label="Expected (not yet verified)" value={formatInr(o.totals.expected_net)} hint={`${o.enrollments.to_verify} enrolments to verify`} />
              <Kpi label="Realised, not invoiced" value={formatInr(o.totals.realised_uninvoiced_net)} hint="net of GST; invoiced at month close" />
              <Kpi label="Draft invoices" value={formatInr(o.invoices.draft_total)} hint={`${o.invoices.drafts} waiting for approval`} />
              <Kpi label="Outstanding" value={formatInr(o.invoices.outstanding)} hint="approved and sent, incl. GST" />
              <Kpi label="Overdue" value={formatInr(o.invoices.overdue)} tone={o.invoices.overdue > 0 ? "text-danger" : undefined} hint="past the payment terms" />
              <Kpi label="Received this financial year" value={formatInr(o.received_fy.amount)} hint={`+ ${formatInr(o.received_fy.tds)} TDS`} />
            </dl>
          </Card>

          <div className="grid gap-6 xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
            <Card className="min-w-0 xl:self-start">
              <CardHeader title="Partners" description={`${monthLabel(o.month)} so far. Tiered rates are provisional until the month is closed; conversion is enrolments ÷ leads accepted.`} />
              {o.partners.length === 0 ? (
                <EmptyState icon={Wallet} title="No partners yet">Partners appear here once they are added.</EmptyState>
              ) : (
                <div className="relative overflow-x-auto">
                  <table className="w-full min-w-[760px] text-left text-[12.5px]">
                    <thead className="text-[11px] uppercase tracking-wider text-subtle">
                      <tr className="border-b border-border">
                        <th scope="col" className="px-5 py-2 font-medium">Partner</th>
                        <th scope="col" className="px-3 py-2 text-right font-medium">Expected</th>
                        <th scope="col" className="px-3 py-2 text-right font-medium">Not invoiced</th>
                        <th scope="col" className="px-3 py-2 text-right font-medium">Outstanding</th>
                        <th scope="col" className="px-3 py-2 font-medium">This month</th>
                        <th scope="col" className="min-w-[190px] px-5 py-2 font-medium">Tier watch</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border">
                      {o.partners.map((p) => {
                        const w = p.tier ? tierWatch(p.tier.tiers, p.conversion.accepted, p.conversion.enrollments) : null;
                        return (
                          <tr key={p.id}>
                            <td className="px-5 py-2.5">
                              <span className="font-medium text-fg">{p.name}</span>
                              {!p.billing_ready && <Link href="/money?tab=settings" className="ml-2 text-[11.5px] text-warning hover:underline">billing details missing</Link>}
                              {p.to_verify > 0 && <Link href={`/money?tab=enrollments&partner=${p.id}`} className="block text-[11.5px] text-muted hover:text-fg">{p.to_verify} to verify</Link>}
                            </td>
                            <td className="tabular px-3 py-2.5 text-right text-muted">{formatInr(p.expected_net)}</td>
                            <td className="tabular px-3 py-2.5 text-right text-fg">{formatInr(p.realised_uninvoiced_net)}</td>
                            <td className="tabular px-3 py-2.5 text-right text-fg">{formatInr(p.outstanding)}</td>
                            <td className="px-3 py-2.5 text-muted">
                              <span className="tabular">{p.conversion.enrollments}</span> of <span className="tabular">{p.conversion.accepted}</span> accepted
                              {p.conversion.conversion_pct !== null && <span className="tabular"> · {p.conversion.conversion_pct}%</span>}
                            </td>
                            <td className="px-5 py-2.5">
                              {p.tier && w ? (
                                <>
                                  <span className="tabular font-medium text-fg">{p.tier.now.pct ?? w.current.pct}%</span>
                                  <span className="block text-[11.5px] text-muted">now, {TIER_BASIS[p.tier.now.basis]}</span>
                                  {w.next && <span className="block text-[11.5px] text-subtle">
                                    next {w.next.pct}% at {w.next.from_pct}%{w.enrollments_to_next !== null ? ` · ${w.enrollments_to_next} more` : ""}</span>}
                                </>
                              ) : <span className="text-subtle">Fixed or percentage rate</span>}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </Card>

            <div className="min-w-0 space-y-6">
              <Card className="min-w-0">
                <CardHeader title="Ageing" description="Outstanding by days since the invoice date." />
                <ul className="space-y-2 px-5 py-4">
                  {([["0_30", "0–30 days"], ["31_60", "31–60 days"], ["61_90", "61–90 days"], ["90_plus", "Over 90 days"]] as const).map(([k, l]) => {
                    const v = o.invoices.ageing[k];
                    const pct = o.invoices.outstanding > 0 ? Math.round((v / o.invoices.outstanding) * 100) : 0;
                    return (
                      <li key={k} className="flex items-center gap-3 text-[12.5px]">
                        <span className="w-24 shrink-0 text-muted">{l}</span>
                        <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface-2" aria-hidden>
                          <span className={cn("block h-full rounded-full", k === "0_30" ? "bg-success" : k === "31_60" ? "bg-amber" : "bg-danger")} style={{ width: `${pct}%` }} />
                        </span>
                        <span className="tabular w-24 text-right text-fg">{formatInr(v)}</span>
                      </li>
                    );
                  })}
                </ul>
              </Card>
              <Card className="min-w-0">
                <CardHeader title="Month close" description={`Settles tiers and drafts invoices. Runs by itself on the ${o.settings.close_day}${o.settings.close_day === 1 ? "st" : o.settings.close_day === 2 ? "nd" : o.settings.close_day === 3 ? "rd" : "th"} of the next month${o.settings.auto_close ? "" : " (automatic close is off)"}.`} />
                <CloseMonth months={o.months} />
              </Card>
              <Card className="min-w-0">
                <CardHeader title="Export for accounts" description="CSV for Tally or Zoho Books." />
                <ExportPanel />
              </Card>
            </div>
          </div>
        </div>
      )}

      {tab === "enrollments" && <EnrollmentsTab sp={sp} partnerId={partnerId} partners={partners} qs={qs} refundDays={o.settings.refund_window_days} />}
      {tab === "invoices" && <InvoicesTab status={one(sp.status) ?? null} partnerId={partnerId} qs={qs} />}
      {tab === "receipts" && <ReceiptsTab partnerId={partnerId} partners={partners} />}
      {tab === "statements" && <StatementsTab partners={partners} />}
      {tab === "settings" && <SettingsTab o={o} />}
    </>
  );
}

async function SettingsTab({ o }: { o: Awaited<ReturnType<typeof moneyOverview>> }) {
  const all = await listPartners();
  return (
        <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
          <Card className="min-w-0">
            <CardHeader title="Money settings" description="Confirm these with Eduwit's CA before the first invoice. Every change is versioned with a reason." />
            <SettingsForm s={o.settings} />
          </Card>
          <Card className="min-w-0 xl:self-start">
            <CardHeader title="Partner billing details" description="The invoice recipient: legal name, GSTIN and address. The state decides IGST or CGST + SGST." />
            <BillingTable partners={all.filter((p) => p.status !== "closed")} />
          </Card>
        </div>
  );
}

const ENR_FILTERS: (EnrollmentStatus | "all")[] = ["reported", "verified", "refunded", "cancelled", "all"];

async function EnrollmentsTab({ sp, partnerId, partners, qs, refundDays }: {
  sp: Record<string, string | string[] | undefined>; partnerId: number | null; partners: { id: number; name: string }[];
  qs: (x: Record<string, string | null>) => string; refundDays: number;
}) {
  const status = ENR_FILTERS.find((s) => s === sp.status) ?? "reported";
  const q = one(sp.q)?.trim().slice(0, 80) || null;
  const offset = Math.max(0, Number(one(sp.offset)) || 0);
  const list = await moneyEnrollments({ status, partner_id: partnerId, q, offset });
  return (
    <Card className="min-w-0">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-3">
        <div className="flex flex-wrap gap-1.5">
          {ENR_FILTERS.map((s) => (
            <Link key={s} href={qs({ status: s, offset: null })} aria-current={status === s ? "page" : undefined}
              className={cn("rounded-md border px-2.5 py-1 text-[12.5px]", status === s ? "border-border-strong bg-surface-2 font-medium text-fg" : "border-transparent text-muted hover:text-fg")}>
              {s === "all" ? "All" : ENROLLMENT_STATUS[s].label}
            </Link>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <form action="/money" className="flex gap-2">
            <input type="hidden" name="tab" value="enrollments" /><input type="hidden" name="status" value={status} />
            <select name="partner" defaultValue={partnerId ?? ""} aria-label="Partner"
              className="h-8 rounded-lg border border-border bg-surface px-2 text-[12.5px] text-fg">
              <option value="">All partners</option>
              {partners.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
            <input name="q" defaultValue={q ?? ""} placeholder="Name, reference or phone" aria-label="Search"
              className="h-8 w-48 rounded-lg border border-border bg-surface px-2.5 text-[12.5px] text-fg placeholder:text-subtle" />
            <button type="submit" className="h-8 rounded-lg border border-border px-3 text-[12.5px] text-fg hover:bg-surface-hover">Filter</button>
          </form>
          <AddEnrollment />
          <AdjustmentButton partners={partners} />
        </div>
      </div>
      {list.rows.length === 0 ? (
        <EmptyState icon={GraduationCap} title={status === "reported" ? "Nothing to verify" : "No enrolments here"}>
          A partner moving a lead to “enrolled” (by webhook, polling or a statement) adds it here as “to verify”. You can also record one by its Eduwit reference.
        </EmptyState>
      ) : (
        <>
          <EnrollmentTable rows={list.rows} refundDays={refundDays} />
          {list.total > 50 && (
            <div className="flex items-center justify-between border-t border-border px-5 py-2.5 text-[12.5px] text-muted">
              <span className="tabular">{offset + 1}–{Math.min(offset + 50, list.total)} of {list.total}</span>
              <span className="flex gap-3">
                {offset > 0 && <Link href={qs({ status, offset: String(Math.max(0, offset - 50)) })} className="hover:text-fg">Previous</Link>}
                {offset + 50 < list.total && <Link href={qs({ status, offset: String(offset + 50) })} className="hover:text-fg">Next</Link>}
              </span>
            </div>
          )}
        </>
      )}
    </Card>
  );
}

const INV_FILTERS = [["", "All"], ["draft", "Drafts"], ["open", "Open"], ["paid", "Paid"], ["cancelled", "Cancelled"]] as const;

async function InvoicesTab({ status, partnerId, qs }: { status: string | null; partnerId: number | null; qs: (x: Record<string, string | null>) => string }) {
  const rows = await moneyInvoices(status || null, partnerId);
  return (
    <Card className="min-w-0">
      <div className="flex flex-wrap gap-1.5 border-b border-border px-5 py-3">
        {INV_FILTERS.map(([s, l]) => (
          <Link key={s} href={qs({ status: s || null })} aria-current={(status ?? "") === s ? "page" : undefined}
            className={cn("rounded-md border px-2.5 py-1 text-[12.5px]", (status ?? "") === s ? "border-border-strong bg-surface-2 font-medium text-fg" : "border-transparent text-muted hover:text-fg")}>{l}</Link>
        ))}
      </div>
      {rows.length === 0 ? (
        <EmptyState icon={FileText} title="No invoices yet">Closing a month drafts one invoice per partner from its verified, uninvoiced commission. You approve each before it gets a number.</EmptyState>
      ) : (
        <div className="relative overflow-x-auto">
          <table className="w-full min-w-[820px] text-left text-[12.5px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-b border-border">
                <th scope="col" className="px-5 py-2 font-medium">Invoice</th>
                <th scope="col" className="px-3 py-2 font-medium">Partner</th>
                <th scope="col" className="px-3 py-2 font-medium">Status</th>
                <th scope="col" className="px-3 py-2 font-medium">Date</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Taxable</th>
                <th scope="col" className="px-3 py-2 text-right font-medium">Total</th>
                <th scope="col" className="px-5 py-2 text-right font-medium">Outstanding</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {rows.map((i) => (
                <tr key={i.id} className="hover:bg-surface-hover/50">
                  <td className="px-5 py-2.5"><Link href={`/money/invoices/${i.id}`} className="font-mono font-medium text-fg hover:underline">{i.number ?? `Draft #${i.id}`}</Link>
                    <span className="block text-[11.5px] text-subtle">{i.lines} lines · through {monthLabel(i.through_period)}</span></td>
                  <td className="px-3 py-2.5 text-fg">{i.partner_name}</td>
                  <td className="px-3 py-2.5"><Badge tone={INVOICE_STATUS[i.status].tone}>{INVOICE_STATUS[i.status].label}</Badge>
                    {i.days_overdue !== null && <span className="ml-1.5 text-[11.5px] text-danger">{i.days_overdue} days overdue</span>}</td>
                  <td className="whitespace-nowrap px-3 py-2.5 text-muted">{i.issue_date ? dayLabel(i.issue_date) : "—"}</td>
                  <td className="tabular px-3 py-2.5 text-right text-muted">{formatInr(i.taxable_inr, true)}</td>
                  <td className="tabular px-3 py-2.5 text-right text-fg">{formatInr(i.total_inr, true)}</td>
                  <td className={cn("tabular px-5 py-2.5 text-right", i.outstanding_inr > 0 ? "text-fg" : "text-subtle")}>{formatInr(i.outstanding_inr, true)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}

async function ReceiptsTab({ partnerId, partners }: { partnerId: number | null; partners: { id: number; name: string }[] }) {
  const d = await moneyReceipts(partnerId);
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,2fr)]">
      <Card className="min-w-0 xl:self-start">
        <CardHeader title="Record a receipt" description="The bank amount plus the TDS the partner deducted. It is matched to the invoice with exactly that outstanding, else to the oldest open ones." />
        <ReceiptForm partners={partners} invoices={d.open_invoices} />
      </Card>
      <Card className="min-w-0">
        <CardHeader title="Receipts" description="Void a receipt entered by mistake; its invoices reopen." />
        <ReceiptList receipts={d.receipts} invoices={d.open_invoices} />
      </Card>
    </div>
  );
}

async function StatementsTab({ partners }: { partners: { id: number; name: string }[] }) {
  const rows = await moneyStatements();
  return (
    <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <Card className="min-w-0 xl:self-start">
        <CardHeader title="Reconcile a partner statement" description="Upload the partner's Excel or CSV. Rows match by Eduwit reference, then the partner's record ID, phone, or name and programme." />
        <StatementUpload partners={partners} />
      </Card>
      <Card className="min-w-0">
        <CardHeader title="Statements" />
        {rows.length === 0 ? (
          <EmptyState icon={FileSpreadsheet} title="No statements yet">Each upload is kept with its four piles: matched, amount mismatch, partner only and Eduwit only.</EmptyState>
        ) : (
          <ul className="divide-y divide-border">
            {rows.map((s) => (
              <li key={s.id}>
                <Link href={`/money/statements/${s.id}`} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-5 py-3 text-[12.5px] hover:bg-surface-hover/50">
                  <span className="font-medium text-fg">{s.partner_name}</span>
                  <span className="text-muted">{dayLabel(s.period_from)} – {dayLabel(s.period_to)}</span>
                  <span className="min-w-0 truncate text-subtle">{s.file_name}</span>
                  <span className="ml-auto flex gap-1.5">
                    <Badge tone="success">{s.matched} matched</Badge>
                    {s.amount_mismatch > 0 && <Badge tone="warning">{s.amount_mismatch} mismatch</Badge>}
                    {s.partner_only > 0 && <Badge tone="danger">{s.partner_only} partner only</Badge>}
                    {s.open > 0 && <Badge>{s.open} open</Badge>}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
