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
import { requireAgency } from "@/lib/auth/guards";
import { loadProgrammes } from "@/lib/campaigns/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("agencyPortal.campaigns") };
}

/** An agency answers an invitation (or applies) for a creator who granted it "negotiate and sign". */
export default async function AgencyCampaignPage({
  params,
}: {
  params: Promise<{ creatorId: string; campaignId: string }>;
}) {
  const { creatorId, campaignId } = await params;
  if (!z.uuid().safeParse(creatorId).success || !z.uuid().safeParse(campaignId).success) notFound();
  const { supabase } = await requireAgency();
  const t = await getTranslations();
  const { data, error } = await supabase.rpc("campaign_for_creator", {
    p_campaign: campaignId,
    p_creator: creatorId,
  });
  if (error?.code === "42501" || (!error && !data)) notFound();
  const parsed = campaignPublic.safeParse(data);
  if (!parsed.success)
    return <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />;
  const c = parsed.data;
  const programmes = await loadProgrammes(supabase, campaignId);
  return (
    <>
      <Link
        href={`/agency/creators/${creatorId}`}
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("agencyPortal.creators")}
      </Link>
      <PageHeader
        title={c.name}
        description={t(`campaigns.objectives.${c.objective as "leads"}`)}
      />
      <div className="flex flex-col gap-4">
        <ApplyPanel c={c} creatorId={creatorId} appBase="/agency/applications/" />
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
