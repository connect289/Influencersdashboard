import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { ApplyPanel } from "@/components/campaigns/apply-panel";
import { CampaignDetails } from "@/components/campaigns/campaign-details";
import { campaignPublic } from "@/components/campaigns/public";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { loadProgrammes } from "@/lib/campaigns/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.campaigns") };
}

export default async function CreatorCampaignPage({
  params,
}: {
  params: Promise<{ campaignId: string }>;
}) {
  const { campaignId } = await params;
  if (!z.uuid().safeParse(campaignId).success) notFound();
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const { data, error } = await supabase.rpc("campaign_for_creator", { p_campaign: campaignId });
  if (!error && !data) notFound();
  const parsed = campaignPublic.safeParse(data);
  if (!parsed.success)
    return <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />;
  const c = parsed.data;
  const programmes = await loadProgrammes(supabase, campaignId);
  return (
    <>
      <Link
        href="/creator/campaigns"
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.creator.campaigns")}
      </Link>
      <PageHeader
        title={c.name}
        description={t(`campaigns.objectives.${c.objective as "leads"}`)}
      />
      <div className="flex flex-col gap-4">
        <ApplyPanel c={c} creatorId={me.creatorId} appBase="/creator/applications/" />
        <CampaignDetails
          description={c.description}
          deliverables={c.deliverables}
          compensation={c.compensation_summary}
          eligibility={c.eligibility}
          startsOn={c.starts_on}
          endsOn={c.ends_on}
          applyBy={c.apply_by}
          programmes={programmes}
        />
      </div>
    </>
  );
}
