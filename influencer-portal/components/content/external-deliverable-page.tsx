// A deliverable for the creator and their agency (with "act on deliverables"): what to do next, the work submitted,
// Eduwit's comments, the live post and metrics. Mobile-first.
import { Thread } from "@/components/messaging/thread";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, Clock } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { DeliverableStatusBadge, DueLine } from "@/components/content/deliverable-bits";
import { TrackingLink } from "@/components/links/tracking-link";
import { HistoryList } from "@/components/content/history-list";
import { GoLiveForm, PostsList, ScheduleForm } from "@/components/content/live-panel";
import { MediaReview } from "@/components/content/media-review";
import { MetricsForm, MetricsTable } from "@/components/content/metrics-panel";
import { SubmitForm } from "@/components/content/submit-form";
import { DecisionNote, deliverablePaths, EarlierSubmissions, SubmissionHeader } from "@/components/content/submissions";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { Banner } from "@/components/ui/states";
import { loadDeliverable } from "@/lib/content/data";
import { DELIVERABLES_BUCKET, signedLinks } from "@/lib/content/files";
import { availableActions } from "@/lib/content/workflow";
import { formatDate, formatDateTime } from "@/lib/format";
import { loadDeliverableLinks, noLinks } from "@/lib/leads/links";
import type { ServerSupabase } from "@/lib/supabase/server";

export async function ExternalDeliverablePage({
  supabase,
  deliverableId,
  basePath,
  back,
}: {
  supabase: ServerSupabase;
  deliverableId: string;
  /** /creator or /agency */
  basePath: string;
  back: (c: { creatorId: string; creatorName: string }) => { href: string; label: string };
}) {
  if (!z.uuid().safeParse(deliverableId).success) notFound();
  const t = await getTranslations();
  const d = await loadDeliverable(supabase, deliverableId);
  if (!d || d.side === "eduwit") notFound();
  const [links, trackingLinks] = await Promise.all([
    signedLinks(DELIVERABLES_BUCKET, deliverablePaths(d)).then((x) => Object.fromEntries(x)),
    loadDeliverableLinks(supabase, d.creator.id).catch(noLinks),
  ]);
  const trackingLink = trackingLinks[d.id] ?? null;
  const actions = availableActions(d.status, d.stages, "creator");
  const latest = d.submissions[0] ?? null;
  const bk = back({ creatorId: d.creator.id, creatorName: d.creator.display_name });
  const briefHref = d.brief?.published ? `${basePath}/briefs/${d.brief.id}` : null;
  const doneCheckpoints = d.metrics.map((m) => m.checkpoint);
  const live = d.posts.find((p) => p.verification_status !== "replaced");

  const pendingPost = d.posts.some((p) => p.verification_status === "pending");
  const correction = (
    <details className="mt-3">
      <summary className="cursor-pointer text-sm text-primary">{t("content.my.changeLink")}</summary>
      <div className="mt-3">
        <GoLiveForm deliverableId={d.id} correcting />
      </div>
    </details>
  );

  let next: React.ReactNode = null;
  if (actions.includes("submit_concept")) next = <SubmitForm deliverableId={d.id} kind="concept" />;
  else if (actions.includes("submit_draft")) next = <SubmitForm deliverableId={d.id} kind="draft" />;
  else if (d.status === "live") {
    // Live: metrics come next when verification is off; a rejected post needs a corrected link.
    if (actions.includes("submit_metrics"))
      next = (
        <>
          <MetricsForm deliverableId={d.id} checkpoints={d.metric_checkpoints} done={doneCheckpoints} />
          {correction}
        </>
      );
    else if (!pendingPost) next = <GoLiveForm deliverableId={d.id} correcting />;
  } else if (actions.includes("schedule") || actions.includes("go_live"))
    next = (
      <div className="flex flex-col gap-5">
        {actions.includes("schedule") ? <ScheduleForm deliverableId={d.id} current={d.scheduled_for} /> : null}
        {actions.includes("go_live") ? <GoLiveForm deliverableId={d.id} correcting={false} /> : null}
      </div>
    );
  else if (actions.includes("submit_metrics"))
    next = <MetricsForm deliverableId={d.id} checkpoints={d.metric_checkpoints} done={doneCheckpoints} />;

  const waiting =
    d.status === "not_started"
      ? t("content.my.waitBrief")
      : d.status === "concept_submitted" || d.status === "draft_submitted"
        ? t("content.my.waitReview")
        : d.status === "live" && pendingPost
          ? t("content.my.waitVerify")
          : d.status === "metrics_submitted"
            ? t("content.my.waitComplete")
            : d.status === "completed"
              ? t("content.my.done")
              : d.status === "cancelled"
                ? t("content.my.cancelled")
                : null;

  return (
    <>
      <Link href={bk.href} className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {bk.label}
      </Link>
      <PageHeader
        title={d.title}
        help={d.side === "creator" ? "/creator/help/creator#deliverables" : "/agency/help/agency#deliverables"}
        description={
          <span className="flex flex-col gap-1">
            <span className="flex flex-wrap items-center gap-2">
              <DeliverableStatusBadge status={d.status} overdueDays={d.overdue_days} />
              <span>
                {t(`platforms.${d.platform}`)} · {t(`formats.${d.format}`)}
              </span>
              <span>{d.deal.title}</span>
            </span>
            <DueLine due={d.due_dates} highlight={d.pending_stage} />
          </span>
        }
        actions={
          briefHref ? (
            <Button asChild variant="secondary" size="sm">
              <Link href={briefHref}>{t("content.my.openBrief")}</Link>
            </Button>
          ) : null
        }
      />
      <div className="flex flex-col gap-4">
        {d.brief?.published && !d.brief.acknowledged && briefHref ? (
          <Banner tone="warning">
            <Link href={briefHref} className="underline">
              {t("content.my.ackFirst")}
            </Link>
          </Banner>
        ) : null}
        {d.overdue_days ? <Banner tone="danger">{t("content.my.overdue", { count: d.overdue_days })}</Banner> : null}
        {d.disclosure_failed_at && d.status === "live" ? (
          <Banner tone="danger">{t("content.my.fixDisclosure")}</Banner>
        ) : null}
        {d.status_reason && d.status === "cancelled" ? (
          <Banner tone="warning">{t("content.statusReason", { reason: d.status_reason })}</Banner>
        ) : null}

        {next ? (
          <Card className="ring-2 ring-primary/30">
            <CardHeader
              title={t("content.my.nextTitle")}
              description={d.pending_stage ? t(`content.next.${d.pending_stage}`) : undefined}
            />
            {latest?.status === "changes_requested" &&
            (actions.includes("submit_concept") || actions.includes("submit_draft")) ? (
              <div className="mb-4">
                <DecisionNote s={latest} />
              </div>
            ) : null}
            {next}
          </Card>
        ) : waiting ? (
          <Card>
            <p className="flex items-center gap-2 text-sm">
              <Clock className="size-4 text-muted" aria-hidden /> {waiting}
            </p>
            {d.status === "live" ? correction : null}
          </Card>
        ) : null}

        {trackingLink && d.status !== "cancelled" ? (
          <Card>
            <CardHeader title={t("links.forThisPost")} description={t("links.forThisPostHint")} />
            <TrackingLink link={trackingLink} />
          </Card>
        ) : null}

        {latest ? (
          <Card>
            <CardHeader title={<SubmissionHeader s={latest} />} />
            <div className="flex flex-col gap-3">
              {latest.status !== "changes_requested" ? <DecisionNote s={latest} /> : null}
              <MediaReview
                deliverableId={d.id}
                submission={latest}
                links={links}
                comments={d.comments.filter((c) => c.submission_id === latest.id)}
                canComment={d.status !== "completed" && d.status !== "cancelled"}
              />
            </div>
          </Card>
        ) : null}

        {d.posts.length ? (
          <Card>
            <CardHeader
              title={t("content.live.title")}
              description={live ? t("content.live.postedLine", { date: formatDate(live.posted_on) }) : undefined}
            />
            {d.scheduled_for ? (
              <p className="mb-2 text-sm text-muted">
                {t("content.live.scheduledFor", { at: formatDateTime(d.scheduled_for) })}
              </p>
            ) : null}
            <PostsList deliverableId={d.id} posts={d.posts} canVerify={false} />
          </Card>
        ) : null}

        {d.metrics.length ? (
          <Card>
            <CardHeader title={t("content.metrics.title")} />
            <MetricsTable rows={d.metrics} links={links} />
          </Card>
        ) : null}

        <EarlierSubmissions d={d} links={links} canComment={false} skip={latest?.id ?? null} />

        <details className="rounded-[var(--radius-card)] bg-surface p-4 shadow-[var(--shadow-card)]">
          <summary className="cursor-pointer text-sm font-semibold">{t("content.history.title")}</summary>
          <div className="mt-3">
            <HistoryList transitions={d.transitions} />
          </div>
        </details>
        <Thread db={supabase} thread={{ type: "deliverable", entityId: d.id }} />
      </div>
    </>
  );
}
