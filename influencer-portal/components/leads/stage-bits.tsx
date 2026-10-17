import { useTranslations } from "next-intl";
import { Badge, StatusBadge } from "@/components/ui/badge";
import type { CreatorStage } from "@/lib/attribution/stages";
import type { StatusFamily } from "@/lib/design/status";

const FAMILY: Record<CreatorStage, StatusFamily> = {
  new: "neutral",
  qualifying: "progress",
  qualified: "progress",
  allocated: "progress",
  counselling: "progress",
  applied: "attention",
  enrolled: "success",
  lost: "closed",
  duplicate: "closed",
  junk: "problem",
  not_attributed: "closed",
};

export function StageBadge({ stage, flags = [] }: { stage: CreatorStage; flags?: readonly string[] }) {
  const t = useTranslations();
  return (
    <span className="inline-flex flex-wrap items-center gap-1">
      <Badge family={FAMILY[stage]}>{t(`leads.stages.names.${stage}`)}</Badge>
      {flags.includes("cancelled") ? <Badge family="problem">{t("leads.flags.cancelled")}</Badge> : null}
      {flags.includes("under_review") ? <Badge family="attention">{t("leads.flags.under_review")}</Badge> : null}
    </span>
  );
}

export function TemperatureBadge({ value }: { value: string | null }) {
  if (!value) return null;
  return <StatusBadge status={value === "HOT" ? "overdue" : value === "WARM" ? "pending" : "draft"} label={value} />;
}
