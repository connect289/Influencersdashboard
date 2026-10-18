import { getTranslations } from "next-intl/server";
import { LeadPipeline } from "@/components/leads/lead-pipeline";
import { PageHeader } from "@/components/ui/page-header";
import { requireCreator } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.leads") };
}

export default async function CreatorLeadsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  return (
    <>
      <PageHeader title={t("nav.creator.leads")} description={t("leads.subtitle")} help="/creator/help/creator#leads" />
      <LeadPipeline supabase={supabase} creatorId={me.creatorId} base="/creator/leads" search={await searchParams} />
    </>
  );
}
