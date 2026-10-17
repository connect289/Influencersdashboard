// A creator's earnings (spec 11), shared by the creator portal and agencies with the earnings grant: totals by stage
// and period, the next expected payout, payouts with their invoices and payment advice, earnings per deal, monthly
// statements, TDS deducted with Form 16A certificates, and every ledger line. Only the creator uploads invoices.
import Link from "next/link";
import { Download, FileText } from "lucide-react";
import { useTranslations } from "next-intl";
import { Amount, LedgerTable } from "@/components/ledger/ledger-table";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { Banner, EmptyState } from "@/components/ui/states";
import type { Earnings } from "@/lib/ledger/data";
import { dealEarnings, earningTotals, nextPayoutDate, statementMonths } from "@/lib/ledger/earnings";
import { fileHref } from "@/lib/ledger/files";
import { formatDate, formatPaise, istToday } from "@/lib/format";
import { InvoiceUpload } from "./invoice-upload";

const ENTRY_LIMIT = 100;

function Tile({ label, paise, hint, strong }: { label: string; paise: number; hint?: string; strong?: boolean }) {
  return (
    <div className="rounded-xl border border-line bg-surface p-3">
      <p className="text-xs text-muted">{label}</p>
      <p className={strong ? "text-xl font-semibold tabular-nums" : "text-lg font-medium tabular-nums"}>
        {formatPaise(paise)}
      </p>
      {hint ? <p className="mt-0.5 text-xs text-muted">{hint}</p> : null}
    </div>
  );
}

export function EarningsView({
  data,
  creatorId,
  canUpload,
  leadsHref,
}: {
  data: Earnings;
  creatorId: string;
  canUpload: boolean;
  leadsHref: string;
}) {
  const t = useTranslations();
  const today = istToday();
  const totals = earningTotals(data.entries, today);
  const next = nextPayoutDate(data.settings.cycle, data.settings.payout_day_of_month, today);
  const deals = dealEarnings(data.entries);
  const months = statementMonths(data.entries).slice(0, 12);
  const gstin = data.gst?.charges_gst ? (data.gst.gstin ?? "") : "";
  const waiting = data.payouts.filter(
    (p) => p.status === "pending" && p.needs_invoice && (!p.invoice || p.invoice.status === "rejected"),
  );
  const tdsGroups = [...new Set(data.tds.map((x) => `${x.fy} ${x.quarter}`))].sort().reverse();
  const monthLabel = (m: string) =>
    new Intl.DateTimeFormat("en-IN", { month: "long", year: "numeric", timeZone: "UTC" }).format(
      new Date(`${m}-15T00:00:00Z`),
    );

  return (
    <div className="flex flex-col gap-4">
      {waiting.length ? (
        <Banner tone="warning">
          <p className="font-medium">{t("earnings.invoiceNeeded", { count: waiting.length })}</p>
          <p>{t(canUpload ? "earnings.invoiceNeededHint" : "earnings.invoiceNeededAgency")}</p>
        </Banner>
      ) : null}

      <section aria-labelledby="earn-totals">
        <h2 id="earn-totals" className="sr-only">
          {t("earnings.totals.title")}
        </h2>
        <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
          <Tile
            label={t("earnings.totals.payable")}
            paise={totals.payable_paise}
            strong
            hint={t("earnings.totals.payableHint")}
          />
          <Tile
            label={t("earnings.totals.confirmed")}
            paise={totals.confirmed_paise}
            hint={t("earnings.totals.confirmedHint")}
          />
          <Tile
            label={t("earnings.totals.pending")}
            paise={totals.pending_paise}
            hint={t("earnings.totals.pendingHint")}
          />
          <Tile label={t("earnings.totals.paid")} paise={totals.paid_paise} hint={t("earnings.totals.paidHint")} />
          <Tile label={t("earnings.totals.month")} paise={totals.month_paise} />
          <Tile label={t("earnings.totals.fy")} paise={totals.fy_paise} />
          <Tile label={t("earnings.totals.lifetime")} paise={totals.lifetime_paise} />
          <div className="rounded-xl border border-line bg-primary-soft p-3">
            <p className="text-xs text-muted">{t("earnings.totals.nextPayout")}</p>
            <p className="text-lg font-medium">{formatDate(next)}</p>
            <p className="mt-0.5 text-xs text-muted">{t(`earnings.cycle.${data.settings.cycle}`)}</p>
          </div>
        </div>
      </section>

      <Card>
        <CardHeader title={t("earnings.payouts.title")} description={t("earnings.payouts.hint")} />
        {data.payouts.length === 0 ? (
          <EmptyState title={t("earnings.payouts.empty")} description={t("earnings.payouts.emptyHint")} />
        ) : (
          <ul className="flex flex-col divide-y divide-line">
            {data.payouts.map((p) => (
              <li key={p.id} className="flex flex-col gap-2 py-3 text-sm sm:flex-row sm:items-start sm:justify-between">
                <div className="min-w-0">
                  <p className="flex flex-wrap items-center gap-2 font-medium">
                    <span className="font-mono">{p.ref}</span>
                    <StatusBadge status={p.status} label={t(`finance.payoutStatuses.${p.status}`)} />
                  </p>
                  <p className="text-xs text-muted">
                    {[
                      t("earnings.payouts.gross", { amount: formatPaise(p.gross_paise) }),
                      p.tds_paise ? t("earnings.payouts.tds", { amount: formatPaise(p.tds_paise) }) : null,
                      p.gst_paise ? t("earnings.payouts.gst", { amount: formatPaise(p.gst_paise) }) : null,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                  {p.paid_on ? (
                    <p className="text-xs text-muted">
                      {t("earnings.payouts.paid", { date: formatDate(p.paid_on), utr: p.utr ?? "" })}
                    </p>
                  ) : null}
                  {p.invoice ? (
                    <p className="mt-1 text-xs">
                      {t(`earnings.payouts.invoice.${p.invoice.kind}`, { number: p.invoice.number })}{" "}
                      <Badge>{t(`finance.invoiceStatuses.${p.invoice.status}`)}</Badge>
                      {p.invoice.status === "rejected" && p.invoice.review_note ? (
                        <span className="block text-danger">{p.invoice.review_note}</span>
                      ) : null}
                    </p>
                  ) : null}
                </div>
                <div className="flex shrink-0 flex-wrap items-center gap-2 sm:flex-col sm:items-end">
                  <span className="text-base font-semibold tabular-nums">{formatPaise(p.net_paise)}</span>
                  {p.advice_path ? (
                    <a
                      href={fileHref(p.advice_path)}
                      className="inline-flex items-center gap-1 text-primary hover:underline"
                    >
                      <Download className="size-4" aria-hidden /> {t("earnings.payouts.advice")}
                    </a>
                  ) : null}
                  {canUpload && waiting.some((w) => w.id === p.id) && gstin ? (
                    <InvoiceUpload payout={p} gstin={gstin} again={p.invoice?.status === "rejected"} />
                  ) : null}
                </div>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card>
        <CardHeader
          title={t("earnings.deals.title")}
          description={t("earnings.deals.hint")}
          actions={
            <Link href={leadsHref} className="text-sm text-primary hover:underline">
              {t("earnings.deals.leads")}
            </Link>
          }
        />
        {deals.length === 0 ? (
          <EmptyState title={t("earnings.deals.empty")} description={t("earnings.deals.emptyHint")} />
        ) : (
          <ul className="flex flex-col divide-y divide-line">
            {deals.map((d) => (
              <li key={d.deal_id ?? "none"} className="flex items-start justify-between gap-3 py-3 text-sm">
                <div className="min-w-0">
                  <p className="font-medium">{d.title ?? t("earnings.deals.other")}</p>
                  <p className="text-xs text-muted">
                    {[
                      d.leads ? t("earnings.deals.leadCount", { count: d.leads }) : null,
                      t("earnings.deals.pending", { amount: formatPaise(d.pending_paise) }),
                      t("earnings.deals.owed", { amount: formatPaise(d.owed_paise) }),
                      t("earnings.deals.paid", { amount: formatPaise(d.paid_paise) }),
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                </div>
                <Amount paise={Math.abs(d.earned_paise)} direction={d.earned_paise < 0 ? "debit" : "credit"} />
              </li>
            ))}
          </ul>
        )}
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader title={t("earnings.statements.title")} description={t("earnings.statements.hint")} />
          {months.length === 0 ? (
            <EmptyState title={t("earnings.statements.empty")} />
          ) : (
            <ul className="flex flex-col divide-y divide-line">
              {months.map((m) => (
                <li key={m} className="flex items-center justify-between gap-3 py-2 text-sm">
                  <span>{monthLabel(m)}</span>
                  <a
                    href={`/api/earnings/${creatorId}/statement?month=${m}`}
                    className="inline-flex items-center gap-1 text-primary hover:underline"
                    aria-label={t("earnings.statements.download", { month: monthLabel(m) })}
                  >
                    <FileText className="size-4" aria-hidden /> PDF
                  </a>
                </li>
              ))}
            </ul>
          )}
        </Card>
        <Card>
          <CardHeader title={t("earnings.tds.title")} description={t("earnings.tds.hint")} />
          {tdsGroups.length === 0 && data.certificates.length === 0 ? (
            <EmptyState title={t("earnings.tds.empty")} />
          ) : (
            <ul className="flex flex-col divide-y divide-line">
              {[...new Set([...tdsGroups, ...data.certificates.map((c) => `${c.fy} ${c.quarter}`)])]
                .sort()
                .reverse()
                .map((g) => {
                  const [fy, quarter] = g.split(" ");
                  const rows = data.tds.filter((x) => x.fy === fy && x.quarter === quarter);
                  const cert = data.certificates.find((c) => c.fy === fy && c.quarter === quarter);
                  return (
                    <li key={g} className="flex items-start justify-between gap-3 py-2 text-sm">
                      <div>
                        <p className="font-medium">
                          {t("earnings.tds.quarter", { fy: fy ?? "", quarter: quarter ?? "" })}
                        </p>
                        <p className="text-xs text-muted">
                          {rows.map((r) => `${r.section}: ${formatPaise(r.amount_paise)}`).join(" · ") || "—"}
                        </p>
                      </div>
                      {cert ? (
                        <a
                          href={fileHref(cert.path)}
                          className="inline-flex shrink-0 items-center gap-1 text-primary hover:underline"
                        >
                          <Download className="size-4" aria-hidden /> {t("earnings.tds.certificate")}
                        </a>
                      ) : (
                        <span className="shrink-0 text-xs text-muted">{t("earnings.tds.certificatePending")}</span>
                      )}
                    </li>
                  );
                })}
            </ul>
          )}
        </Card>
      </div>

      <Card>
        <CardHeader
          title={t("earnings.entries.title")}
          description={
            data.entries.length > ENTRY_LIMIT
              ? t("earnings.entries.limited", { count: ENTRY_LIMIT })
              : t("earnings.entries.hint")
          }
        />
        <LedgerTable
          rows={data.entries.slice(0, ENTRY_LIMIT)}
          emptyTitle={t("earnings.entries.empty")}
          emptyHint={t("earnings.entries.emptyHint")}
        />
      </Card>
    </div>
  );
}
