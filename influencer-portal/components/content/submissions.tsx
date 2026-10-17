// Submissions for a deliverable, newest first: the latest open, earlier rounds folded away.
import { useTranslations } from "next-intl";
import { StatusBadge } from "@/components/ui/badge";
import type { DeliverableDetail, Submission } from "@/lib/content/data";
import { formatDateTime } from "@/lib/format";
import { MediaReview } from "./media-review";

export function SubmissionHeader({ s }: { s: Submission }) {
  const t = useTranslations();
  return (
    <span className="flex flex-wrap items-center gap-2 text-sm">
      <span className="font-medium">
        {t("content.review.round", { kind: t(`content.kinds.${s.kind}`), version: s.version })}
      </span>
      <StatusBadge status={s.status} label={t(`content.submissionStatus.${s.status}`)} />
      <span className="text-xs text-muted">{formatDateTime(s.created_at)}</span>
    </span>
  );
}

export function DecisionNote({ s }: { s: Submission }) {
  const t = useTranslations();
  if (!s.decision_note) return null;
  return (
    <p
      className={
        s.status === "changes_requested"
          ? "rounded-xl bg-accent-soft p-3 text-sm text-accent-ink"
          : "rounded-xl bg-success-soft p-3 text-sm text-success"
      }
    >
      <span className="font-medium">{t("content.review.eduwitSaid")} </span>
      {s.decision_note}
    </p>
  );
}

export function EarlierSubmissions({
  d,
  links,
  canComment,
  skip,
}: {
  d: DeliverableDetail;
  links: Record<string, string>;
  canComment: boolean;
  skip: string | null;
}) {
  const t = useTranslations();
  const rest = d.submissions.filter((s) => s.id !== skip);
  if (!rest.length) return null;
  return (
    <section className="flex flex-col gap-2" aria-label={t("content.review.earlier")}>
      <h2 className="text-sm font-semibold">{t("content.review.earlier")}</h2>
      {rest.map((s) => (
        <details key={s.id} className="rounded-[var(--radius-card)] bg-surface p-4 shadow-[var(--shadow-card)]">
          <summary className="cursor-pointer">
            <SubmissionHeader s={s} />
          </summary>
          <div className="mt-3 flex flex-col gap-3">
            <DecisionNote s={s} />
            <MediaReview
              deliverableId={d.id}
              submission={s}
              links={links}
              comments={d.comments.filter((c) => c.submission_id === s.id)}
              canComment={canComment}
            />
          </div>
        </details>
      ))}
    </section>
  );
}

/** Every file path a deliverable's page may need a link for. */
export function deliverablePaths(d: DeliverableDetail): string[] {
  return [...d.submissions.flatMap((s) => s.files.map((f) => f.path)), ...d.metrics.flatMap((m) => m.screenshot_paths)];
}
