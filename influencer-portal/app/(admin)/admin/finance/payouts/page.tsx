import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { PrepareBatchForm } from "@/components/finance/batch-actions";
import { FinanceNav } from "@/components/finance/finance-nav";
import { StatusBadge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { loadBatches } from "@/lib/ledger/data";
import { loadTiers } from "@/lib/scorecards/data";
import { formatDate, formatPaise, istToday } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("finance.area.payouts") };
}

export default async function PayoutBatchesPage() {
  const { supabase, me } = await requireStaff("payout.read");
  const t = await getTranslations();
  const canManage = me.permissions.has("payout.manage");
  const [batches, campaigns, tiers] = await Promise.all([
    loadBatches(supabase).catch(() => null),
    canManage
      ? supabase
          .from("campaigns")
          .select("id, name")
          .order("created_at", { ascending: false })
          .limit(200)
          .then((r) => r.data ?? [])
      : Promise.resolve([]),
    canManage ? loadTiers(supabase).catch(() => []) : Promise.resolve([]),
  ]);
  const cycles = tiers.filter((x) => x.active && x.benefits.payout_cycle).sort((a, b) => b.rank - a.rank);
  return (
    <>
      <PageHeader
        title={t("nav.admin.finance")}
        description={t("finance.payouts.subtitle")}
        help="/admin/help/finance#payouts"
      />
      <FinanceNav current="payouts" permissions={me.permissions} />
      <div className="flex flex-col gap-4">
        {canManage ? (
          <Card>
            <CardHeader title={t("finance.payouts.prepareTitle")} description={t("finance.payouts.prepareHint")} />
            {cycles.length ? (
              <p className="mb-3 text-sm text-muted">
                {t("finance.payouts.tierCycles", {
                  list: cycles
                    .map((x) => `${x.name}: ${t(`insight.cycles.${x.benefits.payout_cycle ?? "monthly"}`)}`)
                    .join(" · "),
                })}
              </p>
            ) : null}
            <PrepareBatchForm campaigns={campaigns} today={istToday()} />
          </Card>
        ) : null}
        <Card>
          <CardHeader title={t("finance.payouts.batches")} />
          {batches === null ? (
            <ErrorState title={t("errors.loadFailed")} />
          ) : batches.length === 0 ? (
            <EmptyState title={t("finance.payouts.empty")} description={t("finance.payouts.emptyHint")} />
          ) : (
            <Table>
              <thead>
                <tr>
                  <Th>{t("finance.payouts.columns.batch")}</Th>
                  <Th>{t("finance.payouts.columns.created")}</Th>
                  <Th>{t("finance.payouts.columns.payouts")}</Th>
                  <Th className="text-right">{t("finance.payouts.columns.net")}</Th>
                  <Th>{t("finance.payouts.columns.status")}</Th>
                </tr>
              </thead>
              <tbody>
                {batches.map((b) => (
                  <tr key={b.id}>
                    <Td>
                      <Link
                        href={`/admin/finance/payouts/${b.id}`}
                        className="font-medium text-primary hover:underline"
                      >
                        {b.ref}
                      </Link>
                      {b.note ? <span className="block text-xs text-muted">{b.note}</span> : null}
                    </Td>
                    <Td>{formatDate(b.created_at)}</Td>
                    <Td>{t("finance.payouts.countPaid", { count: b.payouts, paid: b.paid })}</Td>
                    <Td className="text-right tabular-nums">{formatPaise(b.net_paise)}</Td>
                    <Td>
                      <StatusBadge status={b.status} label={t(`finance.batchStatuses.${b.status}`)} />
                    </Td>
                  </tr>
                ))}
              </tbody>
            </Table>
          )}
        </Card>
      </div>
    </>
  );
}
