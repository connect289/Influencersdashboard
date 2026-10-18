import { getTranslations } from "next-intl/server";
import { FinanceNav } from "@/components/finance/finance-nav";
import { ReceiptDialog } from "@/components/finance/receipt-form";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { loadRecon } from "@/lib/ledger/data";
import { reconcile } from "@/lib/ledger/reconcile";
import { formatDate, formatPaise } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("finance.area.receipts") };
}

export default async function ReceiptsPage() {
  const { supabase, me } = await requireStaff("ledger.read");
  const t = await getTranslations();
  const src = await loadRecon(supabase).catch(() => null);
  const canRecord = me.permissions.has("commission_receipt.write");
  const rows = src ? reconcile(src.entries, src.receipts, src.flag_after_days, new Date().toISOString()) : [];
  const creatorOf = new Map(
    (src?.entries ?? []).map((e) => [
      e.subject.slice(6),
      `${e.creator_name}${e.deal_title ? ` · ${e.deal_title}` : ""}`,
    ]),
  );
  const receiptOf = new Map((src?.receipts ?? []).map((r) => [r.enrollment_ref, r]));
  const unmatched = (src?.receipts ?? []).filter((r) => !rows.some((x) => x.enrollment_ref === r.enrollment_ref));
  return (
    <>
      <PageHeader
        title={t("nav.admin.finance")}
        description={t("finance.receipts.subtitle")}
        help="/admin/help/finance#receipts"
        actions={canRecord ? <ReceiptDialog /> : undefined}
      />
      <FinanceNav current="receipts" permissions={me.permissions} />
      {src === null ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : (
        <div className="flex flex-col gap-4">
          <Card>
            <CardHeader
              title={t("finance.receipts.reconTitle")}
              description={t("finance.receipts.reconHint", { days: src.flag_after_days })}
            />
            {rows.length === 0 ? (
              <EmptyState title={t("finance.receipts.empty")} description={t("finance.receipts.emptyHint")} />
            ) : (
              <Table>
                <thead>
                  <tr>
                    <Th>{t("finance.receipts.enrolment")}</Th>
                    <Th>{t("finance.ledger.columns.creator")}</Th>
                    <Th className="text-right">{t("finance.receipts.expected")}</Th>
                    <Th className="text-right">{t("finance.receipts.received")}</Th>
                    <Th className="text-right">{t("finance.receipts.commission")}</Th>
                    <Th>{t("finance.receipts.flag")}</Th>
                    {canRecord ? <Th>{t("finance.ledger.columns.actions")}</Th> : null}
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.enrollment_ref}>
                      <Td className="font-mono">
                        {r.enrollment_ref}
                        <span className="block font-sans text-xs text-muted">{formatDate(r.oldest_at)}</span>
                      </Td>
                      <Td>{creatorOf.get(r.enrollment_ref) ?? "—"}</Td>
                      <Td className="text-right tabular-nums">
                        {r.expected_paise === null ? "—" : formatPaise(r.expected_paise)}
                      </Td>
                      <Td className="text-right tabular-nums">
                        {formatPaise(r.received_paise)}
                        <span className="block">
                          <StatusBadge
                            status={r.receipt_status}
                            label={t(`finance.receiptStatuses.${r.receipt_status}`)}
                          />
                        </span>
                        {receiptOf.get(r.enrollment_ref)?.source === "manual" ? (
                          <Badge>{t("finance.receipts.manual")}</Badge>
                        ) : null}
                      </Td>
                      <Td className="text-right tabular-nums">
                        {formatPaise(r.confirmed_paise)} / {formatPaise(r.accrued_paise)}
                      </Td>
                      <Td>
                        {r.flag ? (
                          <Badge family={r.flag === "overdue" ? "problem" : "attention"}>
                            {t(`finance.receipts.flags.${r.flag}`)}
                          </Badge>
                        ) : null}
                      </Td>
                      {canRecord ? (
                        <Td>
                          <ReceiptDialog enrollmentRef={r.enrollment_ref} label={t("finance.receipts.update")} />
                        </Td>
                      ) : null}
                    </tr>
                  ))}
                </tbody>
              </Table>
            )}
          </Card>
          {unmatched.length ? (
            <Card>
              <CardHeader title={t("finance.receipts.unmatched")} description={t("finance.receipts.unmatchedHint")} />
              <ul className="flex flex-col divide-y divide-line text-sm">
                {unmatched.map((r) => (
                  <li key={r.enrollment_ref} className="flex justify-between gap-3 py-2">
                    <span className="font-mono">{r.enrollment_ref}</span>
                    <span className="tabular-nums">{formatPaise(r.received_paise)}</span>
                  </li>
                ))}
              </ul>
            </Card>
          ) : null}
        </div>
      )}
    </>
  );
}
