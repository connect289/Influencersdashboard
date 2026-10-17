import Link from "next/link";
import { CalendarClock, Users } from "lucide-react";
import { useTranslations } from "next-intl";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { formatDate } from "@/lib/format";
import type { CampaignPublic } from "./public";

/** Marketplace card: deliverables, compensation summary, deadline, slots left, and the creator's standing. */
export function CampaignCard({ c, href }: { c: CampaignPublic; href: string }) {
  const t = useTranslations();
  return (
    <Link
      href={href}
      className="flex flex-col gap-2 rounded-[var(--radius-card)] bg-surface p-4 shadow-[var(--shadow-card)] ring-1 ring-transparent hover:ring-primary"
    >
      <div className="flex items-start justify-between gap-2">
        <h3 className="font-semibold">{c.name}</h3>
        {c.application ? (
          <StatusBadge
            status={c.application.status}
            label={t(`campaigns.applicationStatuses.${c.application.status as "submitted"}`)}
          />
        ) : c.invite?.status === "sent" ? (
          <Badge family="attention">{t("campaigns.marketplace.invited")}</Badge>
        ) : null}
      </div>
      <p className="text-xs text-muted">{t(`campaigns.objectives.${c.objective as "leads"}`)}</p>
      {c.deliverables.length ? (
        <p className="text-sm">
          {c.deliverables
            .map((d) => `${String(d.count)} × ${t(`formats.${d.format}`)}`)
            .join(" · ")}
        </p>
      ) : null}
      {c.compensation_summary ? (
        <p className="line-clamp-2 text-sm text-muted">{c.compensation_summary}</p>
      ) : null}
      <div className="mt-1 flex flex-wrap gap-3 text-xs text-muted">
        {c.apply_by ? (
          <span className="flex items-center gap-1">
            <CalendarClock className="size-3.5" aria-hidden />{" "}
            {t("campaigns.marketplace.applyBy", { date: formatDate(c.apply_by) })}
          </span>
        ) : null}
        {c.slots_left !== null ? (
          <span className="flex items-center gap-1">
            <Users className="size-3.5" aria-hidden />{" "}
            {t("campaigns.marketplace.slotsLeft", { count: c.slots_left })}
          </span>
        ) : null}
      </div>
    </Link>
  );
}
