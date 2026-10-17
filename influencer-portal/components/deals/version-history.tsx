import { useTranslations } from "next-intl";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/states";
import type { DealVersionView } from "@/lib/deals/data";
import { formatDateTime } from "@/lib/format";
import { TermsSummary } from "./terms-summary";

/** Every version of a deal, newest first, each expandable to its full terms (the newest and the one in force open). */
export function VersionHistory({
  versions,
  currentId,
}: {
  versions: DealVersionView[];
  currentId: string | null;
}) {
  const t = useTranslations();
  if (!versions.length)
    return (
      <EmptyState title={t("deals.versions.empty")} description={t("deals.versions.emptyHint")} />
    );
  return (
    <div className="flex flex-col gap-3">
      {[...versions].reverse().map((v, i) => (
        <Card key={v.id}>
          <details open={i === 0 || v.id === currentId || v.state === "proposed"}>
            <summary className="flex cursor-pointer flex-wrap items-center gap-2">
              <span className="font-semibold">
                {t("deals.versions.version", { version: v.version })}
              </span>
              <StatusBadge status={v.state} label={t(`deals.versionStates.${v.state}`)} />
              {v.id === currentId ? (
                <Badge family="success">{t("deals.versions.inForce")}</Badge>
              ) : null}
              <span className="text-xs text-muted">
                {t(`deals.origins.${v.origin}`)} ·{" "}
                {t("deals.effectiveFrom", { date: formatDateTime(v.effective_from) })}
              </span>
            </summary>
            <div className="mt-3 flex flex-col gap-3">
              {v.note ? <p className="text-sm text-muted">{v.note}</p> : null}
              {v.decision_reason ? (
                <p className="rounded-xl bg-surface-2 px-3 py-2 text-sm">
                  {t("deals.versions.reason", { reason: v.decision_reason })}
                </p>
              ) : null}
              <TermsSummary config={v.comp_config} />
              <p className="text-xs text-muted">
                {t("deals.versions.proposedAt", { date: formatDateTime(v.proposed_at) })}
                {v.decided_at
                  ? ` · ${t("deals.versions.decidedAt", { date: formatDateTime(v.decided_at) })}`
                  : ""}
              </p>
            </div>
          </details>
        </Card>
      ))}
    </div>
  );
}
