import { getTranslations } from "next-intl/server";
import { ExternalBriefPage } from "@/components/content/external-brief-page";
import { requireAgency } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.agency.home") };
}

/** A managed creator's brief (agencies with the "act on deliverables" grant). */
export default async function AgencyBriefPage({ params }: { params: Promise<{ briefId: string }> }) {
  const { briefId } = await params;
  const { supabase } = await requireAgency();
  return (
    <ExternalBriefPage
      supabase={supabase}
      briefId={briefId}
      back={(c) => ({ href: `/agency/creators/${c.creatorId}`, label: c.creatorName })}
    />
  );
}
