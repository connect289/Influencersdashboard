import { getTranslations } from "next-intl/server";
import { ExternalDeliverablePage } from "@/components/content/external-deliverable-page";
import { requireAgency } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.agency.home") };
}

/** A managed creator's deliverable (agencies with the "act on deliverables" grant). */
export default async function AgencyDeliverablePage({ params }: { params: Promise<{ deliverableId: string }> }) {
  const { deliverableId } = await params;
  const { supabase } = await requireAgency();
  return (
    <ExternalDeliverablePage
      supabase={supabase}
      deliverableId={deliverableId}
      basePath="/agency"
      back={(c) => ({ href: `/agency/creators/${c.creatorId}`, label: c.creatorName })}
    />
  );
}
