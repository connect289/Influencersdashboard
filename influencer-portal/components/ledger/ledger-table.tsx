// Ledger entries as a table (desktop) or a list (phone). Amounts are signed: credits add to what the creator is owed,
// debits (penalties, clawbacks, TDS, payouts) reduce it.
import Link from "next/link";
import { useTranslations } from "next-intl";
import { StatusBadge } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import type { EntryStatus, LedgerType } from "@/lib/ledger/lifecycle";
import { formatDate, formatPaise } from "@/lib/format";
import { cn } from "@/lib/utils";

export interface LedgerLineView {
  id: number;
  type: LedgerType;
  direction: "credit" | "debit";
  amount_paise: number;
  confirmed_paise: number;
  paid_paise: number;
  status: EntryStatus;
  due_on: string;
  posted_at: string;
  note: string | null;
  deal_title?: string | null;
  creator_name?: string;
  creator_id?: string;
  held?: boolean;
}

export function Amount({ paise, direction }: { paise: number; direction: "credit" | "debit" }) {
  return (
    <span className={cn("tabular-nums", direction === "debit" && "text-danger")}>
      {direction === "debit" ? "−" : ""}
      {formatPaise(paise)}
    </span>
  );
}

export function LedgerTable({
  rows,
  showCreator = false,
  showDeal = true,
  emptyTitle,
  emptyHint,
  action,
  creatorHref,
}: {
  rows: readonly LedgerLineView[];
  /** Links each creator name (staff: to that creator's ledger). */
  creatorHref?: (row: LedgerLineView) => string;
  showCreator?: boolean;
  showDeal?: boolean;
  emptyTitle: string;
  emptyHint?: string;
  action?: (row: LedgerLineView) => React.ReactNode;
}) {
  const t = useTranslations();
  if (!rows.length) return <EmptyState title={emptyTitle} description={emptyHint} />;
  return (
    <>
      <ul className="flex flex-col divide-y divide-line md:hidden">
        {rows.map((r) => (
          <li key={r.id} className="flex items-start justify-between gap-3 py-3 text-sm">
            <div className="min-w-0">
              <p className="font-medium">{r.note ?? t(`finance.types.${r.type}`)}</p>
              <p className="text-xs text-muted">
                {[
                  t(`finance.types.${r.type}`),
                  showCreator ? r.creator_name : null,
                  showDeal ? r.deal_title : null,
                  formatDate(r.posted_at),
                ]
                  .filter(Boolean)
                  .join(" · ")}
              </p>
            </div>
            <div className="flex shrink-0 flex-col items-end gap-1">
              <Amount paise={r.amount_paise} direction={r.direction} />
              <StatusBadge status={r.status} label={t(`finance.statuses.${r.status}`)} />
              {action?.(r)}
            </div>
          </li>
        ))}
      </ul>
      <div className="hidden md:block">
        <Table>
          <thead>
            <tr>
              <Th>{t("finance.ledger.columns.date")}</Th>
              {showCreator ? <Th>{t("finance.ledger.columns.creator")}</Th> : null}
              <Th>{t("finance.ledger.columns.what")}</Th>
              {showDeal ? <Th>{t("finance.ledger.columns.deal")}</Th> : null}
              <Th className="text-right">{t("finance.ledger.columns.amount")}</Th>
              <Th className="text-right">{t("finance.ledger.columns.confirmed")}</Th>
              <Th>{t("finance.ledger.columns.status")}</Th>
              <Th>{t("finance.ledger.columns.due")}</Th>
              {action ? <Th>{t("finance.ledger.columns.actions")}</Th> : null}
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <Td className="whitespace-nowrap">{formatDate(r.posted_at)}</Td>
                {showCreator ? (
                  <Td>
                    {creatorHref ? (
                      <Link href={creatorHref(r)} className="text-primary hover:underline">
                        {r.creator_name}
                      </Link>
                    ) : (
                      r.creator_name
                    )}
                  </Td>
                ) : null}
                <Td>
                  <span className="block">{r.note ?? t(`finance.types.${r.type}`)}</span>
                  <span className="text-xs text-muted">{t(`finance.types.${r.type}`)}</span>
                </Td>
                {showDeal ? <Td>{r.deal_title ?? "—"}</Td> : null}
                <Td className="text-right">
                  <Amount paise={r.amount_paise} direction={r.direction} />
                </Td>
                <Td className="text-right text-muted tabular-nums">{formatPaise(r.confirmed_paise)}</Td>
                <Td>
                  <StatusBadge status={r.status} label={t(`finance.statuses.${r.status}`)} />
                </Td>
                <Td className="whitespace-nowrap">{formatDate(r.due_on)}</Td>
                {action ? <Td>{action(r)}</Td> : null}
              </tr>
            ))}
          </tbody>
        </Table>
      </div>
    </>
  );
}
