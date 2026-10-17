import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { FinanceNav } from "@/components/finance/finance-nav";
import { InvoiceReview } from "@/components/finance/invoice-review";
import { StatusBadge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { loadInvoices } from "@/lib/ledger/data";
import { fileHref } from "@/lib/ledger/files";
import { INVOICE_TOLERANCE_PAISE } from "@/lib/ledger/invoice";
import { formatDate, formatPaise } from "@/lib/format";
import { cn } from "@/lib/utils";

const FILTERS = ["submitted", "accepted", "rejected", ""] as const;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("finance.area.invoices") };
}

export default async function InvoicesPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { supabase, me } = await requireStaff("tax.manage");
  const t = await getTranslations();
  const requested = (await searchParams).status ?? "submitted";
  const status = FILTERS.find((x) => x === requested) ?? "submitted";
  const rows = await loadInvoices(supabase, status).catch(() => null);
  const off = (a: number, b: number) => Math.abs(a - b) > INVOICE_TOLERANCE_PAISE;
  return (
    <>
      <PageHeader
        title={t("nav.admin.finance")}
        description={t("finance.invoices.subtitle")}
        help="/admin/help/finance#invoices"
      />
      <FinanceNav current="invoices" permissions={me.permissions} />
      <nav className="mb-3 flex gap-1" aria-label={t("finance.invoices.filter")}>
        {FILTERS.map((f) => (
          <Link
            key={f || "all"}
            href={`/admin/finance/invoices?status=${f}`}
            aria-current={status === f ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm",
              status === f ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {f ? t(`finance.invoiceStatuses.${f}`) : t("finance.invoices.all")}
          </Link>
        ))}
      </nav>
      <Card>
        {rows === null ? (
          <ErrorState title={t("errors.loadFailed")} />
        ) : rows.length === 0 ? (
          <EmptyState title={t("finance.invoices.empty")} description={t("finance.invoices.emptyHint")} />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("finance.invoices.columns.invoice")}</Th>
                <Th>{t("finance.ledger.columns.creator")}</Th>
                <Th>{t("finance.payouts.columns.payout")}</Th>
                <Th className="text-right">{t("finance.invoices.columns.taxable")}</Th>
                <Th className="text-right">GST</Th>
                <Th>{t("finance.payouts.columns.status")}</Th>
                <Th>{t("finance.ledger.columns.actions")}</Th>
              </tr>
            </thead>
            <tbody>
              {rows.map((i) => (
                <tr key={i.id}>
                  <Td>
                    <span className="font-medium">{i.number}</span>
                    <span className="block text-xs text-muted">
                      {formatDate(i.issued_on)} · <span className="font-mono">{i.gstin}</span>
                    </span>
                    {i.file_path ? (
                      <a
                        href={fileHref(i.file_path)}
                        target="_blank"
                        rel="noreferrer"
                        className="text-xs text-primary hover:underline"
                      >
                        {t("finance.open")}
                      </a>
                    ) : null}
                  </Td>
                  <Td>{i.creator_name}</Td>
                  <Td className="font-mono">{i.payout_ref}</Td>
                  <Td
                    className={cn(
                      "text-right tabular-nums",
                      off(i.taxable_paise, i.payout_gst_base_paise) && "text-danger",
                    )}
                  >
                    {formatPaise(i.taxable_paise)}
                    <span className="block text-xs text-muted">
                      {t("finance.invoices.expected", { amount: formatPaise(i.payout_gst_base_paise) })}
                    </span>
                  </Td>
                  <Td className={cn("text-right tabular-nums", off(i.gst_paise, i.payout_gst_paise) && "text-danger")}>
                    {formatPaise(i.gst_paise)}
                    <span className="block text-xs text-muted">
                      {t("finance.invoices.expected", { amount: formatPaise(i.payout_gst_paise) })}
                    </span>
                  </Td>
                  <Td>
                    <StatusBadge status={i.status} label={t(`finance.invoiceStatuses.${i.status}`)} />
                    {i.review_note ? <span className="block text-xs text-muted">{i.review_note}</span> : null}
                  </Td>
                  <Td>{i.status === "submitted" ? <InvoiceReview invoiceId={i.id} /> : null}</Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </>
  );
}
