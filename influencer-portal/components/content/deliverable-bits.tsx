// Small shared pieces for deliverables: status badge with overdue, the next due date, stage labels.
import { useTranslations } from "next-intl";
import { Badge, StatusBadge } from "@/components/ui/badge";
import type { DueStage, DeliverableStatus } from "@/lib/content/workflow";
import { DUE_STAGES } from "@/lib/content/workflow";
import { formatDate } from "@/lib/format";

export function DeliverableStatusBadge({
  status,
  overdueDays,
}: {
  status: DeliverableStatus;
  overdueDays?: number | null;
}) {
  const t = useTranslations();
  return (
    <span className="inline-flex flex-wrap items-center gap-1">
      <StatusBadge status={status} label={t(`content.statuses.${status}`)} />
      {overdueDays ? <Badge family="problem">{t("content.overdueDays", { count: overdueDays })}</Badge> : null}
    </span>
  );
}

/** Due dates as a compact line: "Concept 5 Nov · Draft 10 Nov · Live 15 Nov". */
export function DueLine({ due, highlight }: { due: Partial<Record<DueStage, string>>; highlight?: DueStage | null }) {
  const t = useTranslations();
  const parts = DUE_STAGES.filter((s) => due[s]);
  if (!parts.length) return null;
  return (
    <p className="text-xs text-muted">
      {parts.map((s, i) => (
        <span key={s} className={s === highlight ? "font-medium text-ink" : undefined}>
          {i > 0 ? " · " : ""}
          {t(`content.dueStages.${s}`)} {formatDate(due[s] ?? "")}
        </span>
      ))}
    </p>
  );
}

/** What the creator owes next, with its due date. */
export function NextStep({ stage, due }: { stage: DueStage | null; due: Partial<Record<DueStage, string>> }) {
  const t = useTranslations();
  if (!stage) return null;
  const at = due[stage];
  return (
    <span className="text-sm">
      {t(`content.next.${stage}`)}
      {at ? <span className="text-muted"> · {t("content.dueOn", { date: formatDate(at) })}</span> : null}
    </span>
  );
}
