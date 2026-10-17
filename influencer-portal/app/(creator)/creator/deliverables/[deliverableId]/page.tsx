import { getTranslations } from "next-intl/server";
import { ExternalDeliverablePage } from "@/components/content/external-deliverable-page";
import { requireCreator } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.deliverables") };
}

export default async function CreatorDeliverablePage({ params }: { params: Promise<{ deliverableId: string }> }) {
  const { deliverableId } = await params;
  const { supabase } = await requireCreator();
  const t = await getTranslations();
  return (
    <ExternalDeliverablePage
      supabase={supabase}
      deliverableId={deliverableId}
      basePath="/creator"
      back={() => ({ href: "/creator/deliverables", label: t("nav.creator.deliverables") })}
    />
  );
}
