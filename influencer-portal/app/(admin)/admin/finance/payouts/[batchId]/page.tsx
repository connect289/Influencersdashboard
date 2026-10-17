import { Thread } from "@/components/messaging/thread";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, Download } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import {
  ApproveButton,
  CancelBatchButton,
  MarkPaidDialog,
  PayoutReasonButton,
  UtrFileButton,
} from "@/components/finance/batch-actions";
import { PayoutBreakdown } from "@/components/finance/payout-breakdown";
import { LeadDrawer } from "@/components/leads/lead-drawer";
import { StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { Banner, EmptyState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { loadBatch, loadPayout } from "@/lib/ledger/data";
import { formatDateTime, formatPaise, istToday } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("finance.area.payouts") };
}

export default async function PayoutBatchPage({
  params,
  searchParams,
}: {
  params: Promise<{ batchId: string }>;
  searchParams: Promise<{ payout?: string }>;
}) {
  const { batchId } = await params;
  if (!z.uuid().safeParse(batchId).success) notFound();
  const { supabase, me } = await requireStaff("payout.read");
  const t = await getTranslations();
  const b = await loadBatch(supabase, batchId);
  if (!b) notFound();
  const sp = await searchParams;
  const detail =
    sp.payout && z.uuid().safeParse(sp.payout).success ? await loadPayout(supabase, sp.payout).catch(() => null) : null;
  const canManage = me.permissions.has("payout.manage");
  const canApprove = me.permissions.has("payout.approve");
  const live = b.payouts.filter((p) => p.status === "pending" || p.status === "paid" || p.status === "failed");
  const total = (k: "gross_paise" | "tds_paise" | "gst_paise" | "net_paise") =>
    b.payouts.filter((p) => p.status === "pending" || p.status === "paid").reduce((s, p) => s + p[k], 0);
  const waitingInvoice = b.payouts.some(
    (p) => p.status === "pending" && p.needs_invoice && p.invoice_status !== "accepted",
  );
  const approvals = Number(b.approved_by !== null) + Number(b.second_approved_by !== null);
  const today = istToday();
  return (
    <>
      <Link
        href="/admin/finance/payouts"
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("finance.area.payouts")}
      </Link>
      <PageHeader
        title={b.ref}
        description={
          b.note ?? t("finance.payouts.createdBy", { name: b.created_by ?? "—", at: formatDateTime(b.created_at) })
        }
        help="/admin/help/finance#payouts"
        actions={<StatusBadge status={b.status} label={t(`finance.batchStatuses.${b.status}`)} />}
      />
      <div className="flex flex-col gap-4">
        {b.status === "draft" && waitingInvoice ? (
          <Banner tone="warning">{t("finance.payouts.waitingInvoice")}</Banner>
        ) : null}
        {b.status === "cancelled" && b.cancelled_reason ? (
          <Banner tone="info">{t("finance.payouts.cancelledReason", { reason: b.cancelled_reason })}</Banner>
        ) : null}
        <Card>
          <dl className="grid grid-cols-2 gap-3 text-center sm:grid-cols-4">
            {(["gross_paise", "tds_paise", "gst_paise", "net_paise"] as const).map((k) => (
              <div key={k}>
                <dt className="text-xs text-muted">{t(`finance.payouts.totals.${k}`)}</dt>
                <dd className="text-lg font-semibold tabular-nums">{formatPaise(total(k))}</dd>
              </div>
            ))}
          </dl>
          <p className="mt-3 text-sm text-muted">
            {b.two_person
              ? t("finance.payouts.approvalsTwo", { count: approvals })
              : t("finance.payouts.approvalsOne", { count: approvals })}
            {b.approved_by ? ` · ${b.approved_by}` : ""}
            {b.second_approved_by ? `, ${b.second_approved_by}` : ""}
            {b.exported_at
              ? ` · ${t("finance.payouts.exported", { at: formatDateTime(b.exported_at), count: b.export_count })}`
              : ""}
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            {b.status === "draft" && canApprove && !b.approved_by_me ? (
              <ApproveButton
                batchId={b.id}
                label={approvals === 0 ? t("finance.payouts.approve") : t("finance.payouts.secondApprove")}
              />
            ) : null}
            {(b.status === "approved" || b.status === "processing") && canManage ? (
              <Button asChild size="sm" variant="secondary">
                <a href={`/api/finance/batches/${b.id}/bank-file`}>
                  <Download /> {t("finance.payouts.bankFile")}
                </a>
              </Button>
            ) : null}
            {b.status === "processing" && canManage ? <UtrFileButton /> : null}
            {(b.status === "draft" || b.status === "approved") && canManage ? (
              <CancelBatchButton batchId={b.id} />
            ) : null}
          </div>
        </Card>
        <Card>
          <CardHeader title={t("finance.payouts.payoutsTitle")} />
          {b.payouts.length === 0 ? (
            <EmptyState title={t("finance.payouts.noPayouts")} />
          ) : (
            <Table>
              <thead>
                <tr>
                  <Th>{t("finance.payouts.columns.payout")}</Th>
                  <Th>{t("finance.ledger.columns.creator")}</Th>
                  <Th className="text-right">{t("finance.payouts.gross")}</Th>
                  <Th className="text-right">TDS</Th>
                  <Th className="text-right">GST</Th>
                  <Th className="text-right">{t("finance.payouts.net")}</Th>
                  <Th>{t("finance.payouts.columns.status")}</Th>
                  <Th>{t("finance.ledger.columns.actions")}</Th>
                </tr>
              </thead>
              <tbody>
                {b.payouts.map((p) => (
                  <tr
                    key={p.id}
                    className={p.status === "removed" || p.status === "cancelled" ? "opacity-60" : undefined}
                  >
                    <Td>
                      <Link
                        href={`/admin/finance/payouts/${b.id}?payout=${p.id}`}
                        className="font-mono text-primary hover:underline"
                      >
                        {p.ref}
                      </Link>
                      {p.needs_invoice ? (
                        <span className="block text-xs text-muted">
                          {t("finance.payouts.invoice", {
                            status: p.invoice_status
                              ? t(`finance.invoiceStatuses.${p.invoice_status}`)
                              : t("finance.payouts.invoiceNone"),
                          })}
                        </span>
                      ) : null}
                    </Td>
                    <Td>{p.creator_name}</Td>
                    <Td className="text-right tabular-nums">{formatPaise(p.gross_paise)}</Td>
                    <Td className="text-right tabular-nums">{formatPaise(p.tds_paise)}</Td>
                    <Td className="text-right tabular-nums">{formatPaise(p.gst_paise)}</Td>
                    <Td className="text-right font-medium tabular-nums">{formatPaise(p.net_paise)}</Td>
                    <Td>
                      <StatusBadge status={p.status} label={t(`finance.payoutStatuses.${p.status}`)} />
                      {p.utr ? <span className="block font-mono text-xs text-muted">{p.utr}</span> : null}
                    </Td>
                    <Td>
                      <span className="flex flex-wrap gap-1">
                        {canManage && p.status === "pending" && b.status === "draft" ? (
                          <PayoutReasonButton payoutId={p.id} kind="remove" />
                        ) : null}
                        {canManage && p.status === "pending" && b.status === "processing" ? (
                          <>
                            <MarkPaidDialog payoutRef={p.ref} today={today} />
                            <PayoutReasonButton payoutId={p.id} kind="fail" />
                          </>
                        ) : null}
                      </span>
                    </Td>
                  </tr>
                ))}
              </tbody>
            </Table>
          )}
          {live.length < b.payouts.length ? (
            <p className="mt-2 text-xs text-muted">{t("finance.payouts.removedNote")}</p>
          ) : null}
        </Card>
      </div>
      {detail ? (
        <LeadDrawer title={`${detail.ref} · ${detail.creator_name}`} param="payout">
          <div className="flex flex-col gap-4">
            <PayoutBreakdown p={detail} />
            <Thread db={supabase} thread={{ type: "payout", entityId: detail.id }} />
          </div>
        </LeadDrawer>
      ) : null}
    </>
  );
}
