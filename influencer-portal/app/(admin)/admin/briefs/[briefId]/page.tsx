import { Thread } from "@/components/messaging/thread";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { BriefEditor } from "@/components/content/brief-editor";
import { BriefQa } from "@/components/content/brief-qa";
import { BriefView, VersionLine } from "@/components/content/brief-view";
import { DeliverableStatusBadge } from "@/components/content/deliverable-bits";
import { Badge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadBrief, threads } from "@/lib/content/data";
import { BRIEFS_BUCKET, signedLinks } from "@/lib/content/files";
import { loadDeliverableLinks, noLinks } from "@/lib/leads/links";
import { formatDate } from "@/lib/format";
import { cn } from "@/lib/utils";

const TABS = ["edit", "preview", "versions"] as const;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.briefs") };
}

export default async function BriefPage({
  params,
  searchParams,
}: {
  params: Promise<{ briefId: string }>;
  searchParams: Promise<{ tab?: string }>;
}) {
  const { briefId } = await params;
  if (!z.uuid().safeParse(briefId).success) notFound();
  const { supabase } = await requireStaff("brief.read");
  const t = await getTranslations();
  const b = await loadBrief(supabase, briefId);
  if (!b || b.side !== "eduwit" || !b.draft_content) notFound();
  const visible = TABS.filter((x) => x !== "edit" || b.can_write);
  const requested = (await searchParams).tab;
  const tab = visible.find((x) => x === requested) ?? visible[0] ?? "preview";
  const draft = b.draft_content;
  const unpublished = b.current === null || JSON.stringify(b.current.content) !== JSON.stringify(draft);
  const links =
    tab === "preview"
      ? Object.fromEntries(
          await signedLinks(
            BRIEFS_BUCKET,
            draft.assets.map((a) => a.path),
          ),
        )
      : {};
  const trackingLinks = tab === "preview" ? await loadDeliverableLinks(supabase, b.creator.id).catch(noLinks) : {};

  return (
    <>
      <Link href="/admin/briefs" className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.admin.briefs")}
      </Link>
      <PageHeader
        title={b.deal.title}
        help="/admin/help/influencer-manager#briefs"
        description={
          <span className="flex flex-wrap items-center gap-2">
            <Link href={`/admin/deals/${b.deal.id}?tab=content`} className="text-primary hover:underline">
              {b.deal.code ?? t("content.briefs.deal")}
            </Link>
            <Link href={`/admin/creators/${b.creator.id}`} className="text-primary hover:underline">
              {b.creator.display_name}
            </Link>
            {b.current ? (
              <>
                <VersionLine version={b.current.version} publishedAt={b.current.published_at} />
                <Badge family={b.acknowledged_current ? "success" : "attention"}>
                  {b.acknowledged_current
                    ? t("content.briefs.states.acknowledged")
                    : t("content.briefs.states.unacknowledged")}
                </Badge>
              </>
            ) : (
              <Badge>{t("content.briefs.states.draft")}</Badge>
            )}
          </span>
        }
      />
      <nav
        className="-mx-4 mb-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0"
        aria-label={t("content.briefs.sections")}
      >
        {visible.map((x) => (
          <Link
            key={x}
            href={`/admin/briefs/${b.id}?tab=${x}`}
            aria-current={tab === x ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
              tab === x ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {t(`content.briefs.tabs.${x}`)}
          </Link>
        ))}
      </nav>
      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <div className="min-w-0">
          {tab === "edit" ? (
            <BriefEditor
              briefId={b.id}
              initial={draft}
              published={b.current !== null}
              unpublishedChanges={unpublished && b.current !== null}
            />
          ) : tab === "preview" ? (
            <BriefView
              content={draft}
              deliverables={b.deliverables}
              assetLinks={links}
              programmes={b.programmes}
              trackingLinks={trackingLinks}
            />
          ) : (
            <Card>
              <CardHeader title={t("content.briefs.versionsTitle")} />
              {b.versions.length === 0 ? (
                <EmptyState title={t("content.briefs.noVersions")} description={t("content.briefs.noVersionsHint")} />
              ) : (
                <ul className="flex flex-col divide-y divide-line text-sm">
                  {[...b.versions].reverse().map((v) => (
                    <li key={v.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                      <span>
                        <span className="font-medium">{t("content.briefs.versionN", { version: v.version })}</span>
                        <span className="text-muted"> · {formatDate(v.published_at)}</span>
                        {v.note ? <span className="block text-muted">{v.note}</span> : null}
                      </span>
                      {v.acknowledged_at ? (
                        <Badge family="success">
                          {t("content.briefs.ackOn", { date: formatDate(v.acknowledged_at) })}
                        </Badge>
                      ) : (
                        <Badge family="attention">{t("content.briefs.states.unacknowledged")}</Badge>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          )}
        </div>
        <aside className="flex flex-col gap-4">
          <Card>
            <CardHeader title={t("content.brief.deliverables")} />
            {b.deliverables.length === 0 ? (
              <p className="text-sm text-muted">{t("content.briefs.noDeliverables")}</p>
            ) : (
              <ul className="flex flex-col gap-2 text-sm">
                {b.deliverables.map((d) => (
                  <li key={d.id} className="flex flex-wrap items-center justify-between gap-2">
                    <Link href={`/admin/content/${d.id}`} className="text-primary hover:underline">
                      {d.title}
                    </Link>
                    <DeliverableStatusBadge status={d.status} />
                  </li>
                ))}
              </ul>
            )}
          </Card>
          <BriefQa briefId={b.id} threads={threads(b.questions)} canAsk={false} canAnswer={b.can_write} />
          <Thread db={supabase} thread={{ type: "brief", entityId: b.id }} />
        </aside>
      </div>
    </>
  );
}
