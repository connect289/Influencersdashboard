import Link from "next/link";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { AnalyticsNav } from "@/components/analytics/analytics-nav";
import { BarList } from "@/components/analytics/charts";
import { KpiCard } from "@/components/analytics/kpi-card";
import { RangeControl } from "@/components/analytics/range-control";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { loadFinanceAnalytics } from "@/lib/analytics/data";
import { formatMetric } from "@/lib/analytics/format";
import { parseRange, rangeParams } from "@/lib/analytics/ranges";
import { loadRecon } from "@/lib/ledger/data";
import { reconcile } from "@/lib/ledger/reconcile";
import { istToday } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("analytics.areas.finance") };
}

const shortMonth = new Intl.DateTimeFormat("en-IN", {
  day: "2-digit",
  month: "short",
  year: "numeric",
  timeZone: "UTC",
});

/** Finance dashboard (spec 12): what is owed, payouts by period, TDS by quarter and reconciliation status. */
export default async function FinanceDashboard({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase, me } = await requireStaff("analytics.read");
  if (!me.permissions.has("ledger.read")) notFound();
  const t = await getTranslations();
  const today = istToday();
  const range = parseRange(await searchParams, today);
  const keep = new URLSearchParams(rangeParams(range)).toString();
  const [fin, recon] = await Promise.all([
    loadFinanceAnalytics(supabase, range).catch(() => null),
    loadRecon(supabase).catch(() => null),
  ]);
  const rows = recon ? reconcile(recon.entries, recon.receipts, recon.flag_after_days, new Date().toISOString()) : [];
  const waiting = rows.reduce((s, r) => s + Math.max(r.accrued_paise - r.confirmed_paise, 0), 0);
  const flagged = rows.filter((r) => r.flag === "overdue").length;
  const statusCounts = Object.entries(
    rows.reduce<Record<string, number>>((a, r) => ((a[r.receipt_status] = (a[r.receipt_status] ?? 0) + 1), a), {}),
  );
  const tdsInRange = (fin?.payouts ?? []).reduce((s, p) => s + p.tds_paise, 0);

  return (
    <>
      <PageHeader
        title={t("nav.admin.analytics")}
        description={t("analytics.finance.subtitle")}
        help="/admin/help/analytics#finance"
      />
      <AnalyticsNav current="finance" permissions={me.permissions} search={keep} />
      <div className="mb-4">
        <RangeControl preset={range.preset} from={range.from} to={range.to} compare={false} today={today} />
      </div>
      {!fin ? (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      ) : (
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-2 lg:grid-cols-5">
            <KpiCard id="liabilities" value={fin.liabilities_paise} href="/admin/finance" />
            <KpiCard id="payouts_due" value={fin.payable_paise} href="/admin/finance/payouts" />
            <KpiCard id="tds_deducted" value={tdsInRange} href="/admin/finance/tds" />
            <KpiCard id="receipts_waiting" value={recon ? waiting : null} href="/admin/finance/receipts" />
            <KpiCard id="receipts_flagged" value={recon ? flagged : null} href="/admin/finance/receipts" />
          </div>
          <div className="grid gap-4 lg:grid-cols-2">
            <Card>
              <CardHeader title={t("analytics.finance.payouts")} description={t("analytics.finance.payoutsHint")} />
              {fin.payouts.length === 0 ? (
                <EmptyState title={t("analytics.finance.noPayouts")} />
              ) : (
                <Table className="min-w-[480px]">
                  <thead>
                    <tr>
                      <Th>{t("analytics.date")}</Th>
                      <Th className="text-right">{t("analytics.finance.count")}</Th>
                      <Th className="text-right">{t("finance.payouts.gross")}</Th>
                      <Th className="text-right">TDS</Th>
                      <Th className="text-right">GST</Th>
                      <Th className="text-right">{t("finance.payouts.net")}</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {fin.payouts.map((p) => (
                      <tr key={p.at}>
                        <Td>{shortMonth.format(new Date(`${p.at}T00:00:00Z`))}</Td>
                        <Td className="text-right tabular-nums">{formatMetric("count", p.count)}</Td>
                        <Td className="text-right tabular-nums">{formatMetric("money", p.gross_paise)}</Td>
                        <Td className="text-right tabular-nums">{formatMetric("money", p.tds_paise)}</Td>
                        <Td className="text-right tabular-nums">{formatMetric("money", p.gst_paise)}</Td>
                        <Td className="text-right tabular-nums">{formatMetric("money", p.net_paise)}</Td>
                      </tr>
                    ))}
                  </tbody>
                </Table>
              )}
            </Card>
            <Card>
              <CardHeader title={t("analytics.finance.tds")} description={t("analytics.finance.tdsHint")} />
              {fin.tds.length === 0 ? (
                <EmptyState title={t("analytics.finance.noTds")} />
              ) : (
                <Table className="min-w-[420px]">
                  <thead>
                    <tr>
                      <Th>{t("analytics.finance.quarter")}</Th>
                      <Th>{t("analytics.finance.section")}</Th>
                      <Th className="text-right">{t("analytics.finance.amount")}</Th>
                      <Th className="text-right">{t("analytics.finance.creators")}</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {fin.tds.map((r) => (
                      <tr key={`${r.fy}-${r.quarter}-${r.section}`}>
                        <Td>
                          {r.fy} {r.quarter}
                        </Td>
                        <Td>{r.section}</Td>
                        <Td className="text-right tabular-nums">{formatMetric("money", r.amount_paise)}</Td>
                        <Td className="text-right tabular-nums">{formatMetric("count", r.creators)}</Td>
                      </tr>
                    ))}
                  </tbody>
                </Table>
              )}
            </Card>
          </div>
          <Card>
            <CardHeader title={t("analytics.finance.recon")} description={t("analytics.finance.reconHint")} />
            {!recon ? (
              <ErrorState title={t("errors.loadFailed")} />
            ) : (
              <>
                <BarList
                  empty={t("analytics.finance.noRecon")}
                  rows={statusCounts.map(([k, v]) => ({
                    key: k,
                    label: k === "none" ? t("analytics.finance.noReceipt") : t(`finance.receiptStatuses.${k}`),
                    value: v,
                  }))}
                />
                <p className="mt-3 text-sm">
                  <Link href="/admin/finance/receipts" className="text-primary hover:underline">
                    {t("analytics.finance.openRecon")}
                  </Link>
                </p>
              </>
            )}
          </Card>
        </div>
      )}
    </>
  );
}
