// The brief for the creator and their agency (with "act on deliverables"): read, acknowledge, ask questions.
import { Thread } from "@/components/messaging/thread";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { AcknowledgeCard } from "@/components/content/acknowledge-card";
import { BriefQa } from "@/components/content/brief-qa";
import { BriefView, VersionLine } from "@/components/content/brief-view";
import { PageHeader } from "@/components/ui/page-header";
import { Banner } from "@/components/ui/states";
import { loadBrief, threads } from "@/lib/content/data";
import { BRIEFS_BUCKET, signedLinks } from "@/lib/content/files";
import { loadDeliverableLinks, noLinks } from "@/lib/leads/links";
import type { ServerSupabase } from "@/lib/supabase/server";

export async function ExternalBriefPage({
  supabase,
  briefId,
  back,
}: {
  supabase: ServerSupabase;
  briefId: string;
  back: (c: { creatorId: string; creatorName: string }) => { href: string; label: string };
}) {
  if (!z.uuid().safeParse(briefId).success) notFound();
  const t = await getTranslations();
  const b = await loadBrief(supabase, briefId);
  if (!b || b.side === "eduwit" || !b.current) notFound();
  const [links, trackingLinks] = await Promise.all([
    signedLinks(
      BRIEFS_BUCKET,
      b.current.content.assets.map((a) => a.path),
    ).then((x) => Object.fromEntries(x)),
    loadDeliverableLinks(supabase, b.creator.id).catch(noLinks),
  ]);
  const bk = back({ creatorId: b.creator.id, creatorName: b.creator.display_name });
  return (
    <>
      <Link href={bk.href} className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {bk.label}
      </Link>
      <PageHeader
        title={b.deal.title}
        description={<VersionLine version={b.current.version} publishedAt={b.current.published_at} />}
        help={b.side === "creator" ? "/creator/help/creator#briefs" : "/agency/help/agency#deliverables"}
      />
      {b.current.note && b.current.version > 1 ? (
        <div className="mb-3">
          <Banner tone="info">{t("content.brief.whatChanged", { note: b.current.note })}</Banner>
        </div>
      ) : null}
      <AcknowledgeCard briefId={b.id} versionId={b.current.id} acknowledged={b.acknowledged_current} />
      <div className="flex flex-col gap-4">
        <BriefView
          content={b.current.content}
          deliverables={b.deliverables}
          assetLinks={links}
          programmes={b.programmes}
          trackingLinks={trackingLinks}
        />
        <BriefQa briefId={b.id} threads={threads(b.questions)} canAsk canAnswer={false} />
        <Thread db={supabase} thread={{ type: "brief", entityId: b.id }} />
      </div>
    </>
  );
}
