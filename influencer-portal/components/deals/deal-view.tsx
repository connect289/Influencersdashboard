import { useTranslations } from "next-intl";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/states";
import { versionsOf, type DealDetail } from "@/lib/deals/data";
import { formatDate, formatDateTime } from "@/lib/format";
import { RespondPanel } from "./respond-panel";
import { CreatorSimulator } from "./simulator";
import { TermsSummary } from "./terms-summary";
import { VersionHistory } from "./version-history";

/** A deal as the creator (or their agency) sees it: terms to answer, the terms in force, a simulator, history. */
export function DealView({ deal }: { deal: DealDetail }) {
  const t = useTranslations();
  const { current, pending } = versionsOf(deal);
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <StatusBadge status={deal.status} label={t(`deals.statuses.${deal.status}`)} />
        <Badge>{t(`deals.models.${deal.deal_model}`)}</Badge>
        <span className="text-muted">
          {deal.code}
          {deal.campaign ? ` · ${deal.campaign.name}` : ""} · {formatDate(deal.starts_on)}
          {deal.ends_on ? ` – ${formatDate(deal.ends_on)}` : ""}
        </span>
      </div>
      {pending ? (
        <Card className="ring-2 ring-accent">
          <CardHeader
            title={
              current
                ? t("deals.my.amendmentToReview", { version: pending.version })
                : t("deals.my.termsToReview")
            }
            description={t("deals.effectiveFrom", { date: formatDateTime(pending.effective_from) })}
          />
          {pending.note ? <p className="mb-3 text-sm text-muted">{pending.note}</p> : null}
          <TermsSummary config={pending.comp_config} />
          {deal.can_respond ? (
            <div className="mt-4">
              <RespondPanel dealId={deal.id} versionId={pending.id} amendment={current !== null} />
            </div>
          ) : (
            <p className="mt-3 text-sm text-muted">{t("deals.my.cannotRespond")}</p>
          )}
        </Card>
      ) : null}
      {current ? (
        <Card>
          <CardHeader
            title={t("deals.currentTerms", { version: current.version })}
            description={t("deals.effectiveFrom", { date: formatDateTime(current.effective_from) })}
          />
          <TermsSummary config={current.comp_config} />
        </Card>
      ) : !pending ? (
        <EmptyState title={t("deals.my.noTermsYet")} description={t("deals.my.noTermsYetHint")} />
      ) : null}
      {(current ?? pending) ? (
        <CreatorSimulator
          dealId={deal.id}
          versionId={pending && !current ? pending.id : undefined}
        />
      ) : null}
      {deal.versions.length > 1 ? (
        <section className="flex flex-col gap-2">
          <h2 className="text-base font-semibold">{t("deals.tabs.versions")}</h2>
          <VersionHistory versions={deal.versions} currentId={deal.current_version_id} />
        </section>
      ) : null}
    </div>
  );
}
