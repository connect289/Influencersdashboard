import { Thread } from "@/components/messaging/thread";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { DeliverableStatusBadge, DueLine, NextStep } from "@/components/content/deliverable-bits";
import { DeliverableSettings } from "@/components/content/deliverable-settings";
import { HistoryList } from "@/components/content/history-list";
import { LiveCard, PostsList } from "@/components/content/live-panel";
import { MediaReview } from "@/components/content/media-review";
import { MetricsTable } from "@/components/content/metrics-panel";
import { ChecksList, ReviewPanel } from "@/components/content/review-panel";
import { DecisionNote, deliverablePaths, EarlierSubmissions, SubmissionHeader } from "@/components/content/submissions";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { Banner, EmptyState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadDeliverable } from "@/lib/content/data";
import { DELIVERABLES_BUCKET, signedLinks } from "@/lib/content/files";
import { formatDateTime } from "@/lib/format";
import { cn } from "@/lib/utils";

const TABS = ["review", "live", "metrics", "history", "messages", "settings"] as const;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.content") };
}

export default async function DeliverablePage({
  params,
  searchParams,
}: {
  params: Promise<{ deliverableId: string }>;
  searchParams: Promise<{ tab?: string }>;
}) {
  const { deliverableId } = await params;
  if (!z.uuid().safeParse(deliverableId).success) notFound();
  const { supabase, me } = await requireStaff("deliverable.read");
  const t = await getTranslations();
  const d = await loadDeliverable(supabase, deliverableId);
  if (!d || d.side !== "eduwit") notFound();
  const visible = TABS.filter((x) =>
    x === "settings" ? d.can_edit : x !== "messages" || me.permissions.has("message.read"),
  );
  const requested = (await searchParams).tab;
  const pendingPost = d.posts.some((p) => p.verification_status === "pending");
  const tab = visible.find((x) => x === requested) ?? (pendingPost ? "live" : "review");
  const links = Object.fromEntries(await signedLinks(DELIVERABLES_BUCKET, deliverablePaths(d)));
  const latest = d.submissions[0] ?? null;
  const reviewable =
    latest !== null && latest.status === "submitted" && d.status === `${latest.kind}_submitted` && d.can_review;
  const left = d.revision_limit + d.extra_revisions - d.revisions_used;

  let body: React.ReactNode;
  if (tab === "review") {
    body = latest ? (
      <div className="flex flex-col gap-4">
        <div className={cn("grid gap-4", reviewable && "lg:grid-cols-[minmax(0,1fr)_24rem]")}>
          <Card className="min-w-0">
            <CardHeader title={<SubmissionHeader s={latest} />} />
            <div className="flex flex-col gap-3">
              <DecisionNote s={latest} />
              <MediaReview
                deliverableId={d.id}
                submission={latest}
                links={links}
                comments={d.comments.filter((c) => c.submission_id === latest.id)}
                canComment={d.can_review}
              />
            </div>
          </Card>
          {reviewable ? (
            <div>
              <ReviewPanel
                deliverableId={d.id}
                submission={latest}
                checks={d.checks}
                needsChecklist={latest.kind === "draft" || !d.stages.draft}
                revisionsLeft={left}
                canOverride={d.can_override}
                canExtend={d.can_extend}
                extensions={d.extensions ?? []}
              />
            </div>
          ) : (
            <Card>
              <CardHeader title={t("content.checks.title")} />
              <ChecksList
                deliverableId={d.id}
                checks={d.checks}
                canOverride={false}
                canRescan={false}
                submissionId={latest.id}
              />
            </Card>
          )}
        </div>
        <EarlierSubmissions d={d} links={links} canComment={d.can_review} skip={latest.id} />
      </div>
    ) : (
      <EmptyState title={t("content.review.nothingYet")} description={t("content.review.nothingYetHint")} />
    );
  } else if (tab === "live") {
    body = (
      <LiveCard>
        {d.scheduled_for ? (
          <p className="mb-3 text-sm text-muted">
            {t("content.live.scheduledFor", { at: formatDateTime(d.scheduled_for) })}
          </p>
        ) : null}
        <PostsList deliverableId={d.id} posts={d.posts} canVerify={d.can_verify} />
      </LiveCard>
    );
  } else if (tab === "metrics") {
    body = (
      <Card>
        <CardHeader title={t("content.metrics.title")} description={t("content.metrics.staffHint")} />
        <MetricsTable rows={d.metrics} links={links} />
      </Card>
    );
  } else if (tab === "history") {
    body = (
      <Card>
        <CardHeader title={t("content.history.title")} />
        <HistoryList transitions={d.transitions} />
      </Card>
    );
  } else if (tab === "messages") {
    body = <Thread db={supabase} thread={{ type: "deliverable", entityId: d.id }} />;
  } else {
    body = <DeliverableSettings d={d} />;
  }

  return (
    <>
      <Link href="/admin/content" className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.admin.content")}
      </Link>
      <PageHeader
        title={d.title}
        help="/admin/help/content-reviewer#review"
        description={
          <span className="flex flex-col gap-1">
            <span className="flex flex-wrap items-center gap-2">
              <span>{d.code}</span>
              <DeliverableStatusBadge status={d.status} overdueDays={d.overdue_days} />
              <span>
                {t(`platforms.${d.platform}`)} · {t(`formats.${d.format}`)}
              </span>
              <Link href={`/admin/creators/${d.creator.id}`} className="text-primary hover:underline">
                {d.creator.display_name}
              </Link>
              <Link href={`/admin/deals/${d.deal.id}?tab=content`} className="text-primary hover:underline">
                {d.deal.title}
              </Link>
              {d.brief ? (
                <Link href={`/admin/briefs/${d.brief.id}`} className="text-primary hover:underline">
                  {t("content.brief.title")}
                </Link>
              ) : null}
            </span>
            <NextStep stage={d.pending_stage} due={d.due_dates} />
            <DueLine due={d.due_dates} highlight={d.pending_stage} />
          </span>
        }
      />
      {d.status_reason && (d.status === "cancelled" || d.status === "completed") ? (
        <div className="mb-3">
          <Banner tone={d.status === "cancelled" ? "warning" : "success"}>
            {t("content.statusReason", { reason: d.status_reason })}
          </Banner>
        </div>
      ) : null}
      {d.disclosure_failed_at ? (
        <div className="mb-3">
          <Banner tone="danger">{t("content.disclosureFailed", { at: formatDateTime(d.disclosure_failed_at) })}</Banner>
        </div>
      ) : null}
      <nav className="-mx-4 mb-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0" aria-label={t("content.sections")}>
        {visible.map((x) => (
          <Link
            key={x}
            href={`/admin/content/${d.id}?tab=${x}`}
            aria-current={tab === x ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
              tab === x ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {t(`content.tabs.${x}`)}
          </Link>
        ))}
      </nav>
      {body}
    </>
  );
}
