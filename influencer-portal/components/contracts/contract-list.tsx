import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/states";
import type { ContractRow } from "@/lib/contracts/data";
import { formatDate } from "@/lib/format";

/** A creator's (or managed creator's) contracts as cards, mobile-first. */
export async function ContractList({
  contracts,
  hrefBase,
}: {
  contracts: ContractRow[];
  hrefBase: string;
}) {
  const t = await getTranslations();
  if (contracts.length === 0)
    return <EmptyState title={t("contracts.my.empty")} description={t("contracts.my.emptyHint")} />;
  return (
    <ul className="flex flex-col gap-2">
      {contracts.map((c) => (
        <li key={c.id}>
          <Link
            href={`${hrefBase}/${c.id}`}
            className="flex items-center gap-3 rounded-[var(--radius-card)] bg-surface p-4 shadow-[var(--shadow-card)] hover:bg-surface-2"
          >
            <div className="min-w-0 flex-1">
              <p className="font-medium">{c.deal_title}</p>
              <p className="mt-1 flex flex-wrap items-center gap-2 text-sm text-muted">
                <span>{c.number}</span>
                <StatusBadge status={c.status} label={t(`contracts.statuses.${c.status}`)} />
                {c.needs_action ? (
                  <Badge family="attention">{t("contracts.my.needsAction")}</Badge>
                ) : null}
                <span>{t("contracts.my.updated", { date: formatDate(c.updated_at) })}</span>
              </p>
            </div>
            <ChevronRight className="size-5 shrink-0 text-muted" aria-hidden />
          </Link>
        </li>
      ))}
    </ul>
  );
}
