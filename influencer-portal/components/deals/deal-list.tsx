import Link from "next/link";
import { useTranslations } from "next-intl";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { EmptyState } from "@/components/ui/states";
import type { DealRow } from "@/lib/deals/data";
import { formatDate } from "@/lib/format";

/** A creator's deals as cards (creator and agency portals; mobile-first). */
export function DealList({ deals, hrefBase }: { deals: DealRow[]; hrefBase: string }) {
  const t = useTranslations();
  if (!deals.length)
    return <EmptyState title={t("deals.my.empty")} description={t("deals.my.emptyHint")} />;
  return (
    <ul className="flex flex-col gap-2">
      {deals.map((d) => (
        <li key={d.id}>
          <Link
            href={`${hrefBase}/${d.id}`}
            className="flex flex-col gap-1 rounded-xl bg-surface p-3 shadow-[var(--shadow-card)] hover:opacity-90"
          >
            <span className="flex flex-wrap items-center gap-2">
              <span className="font-medium">{d.title}</span>
              <StatusBadge status={d.status} label={t(`deals.statuses.${d.status}`)} />
              {d.pending ? <Badge family="attention">{t("deals.my.needsAnswer")}</Badge> : null}
            </span>
            <span className="text-xs text-muted">
              {d.code}
              {d.campaign_name ? ` · ${d.campaign_name}` : ""} · {formatDate(d.starts_on)}
              {d.ends_on ? ` – ${formatDate(d.ends_on)}` : ""}
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}
