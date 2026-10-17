import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { StatusBadge } from "@/components/ui/badge";
import type { ContractRow } from "@/lib/contracts/data";

/** Links from a deal to its contracts (creator and agency deal pages). */
export async function DealContracts({
  contracts,
  hrefBase,
}: {
  contracts: ContractRow[];
  hrefBase: string;
}) {
  const t = await getTranslations();
  if (contracts.length === 0) return null;
  return (
    <div className="mb-4 flex flex-wrap items-center gap-2 text-sm">
      <span className="text-muted">{t("contracts.onDeal")}</span>
      {contracts.map((c) => (
        <Link
          key={c.id}
          href={`${hrefBase}/${c.id}`}
          className="inline-flex items-center gap-1 text-primary hover:underline"
        >
          {c.number} <StatusBadge status={c.status} label={t(`contracts.statuses.${c.status}`)} />
        </Link>
      ))}
    </div>
  );
}
