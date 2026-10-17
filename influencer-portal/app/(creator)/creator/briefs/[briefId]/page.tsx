import { getTranslations } from "next-intl/server";
import { ExternalBriefPage } from "@/components/content/external-brief-page";
import { requireCreator } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.briefs") };
}

export default async function CreatorBriefPage({
  params,
}: {
  params: Promise<{ briefId: string }>;
}) {
  const { briefId } = await params;
  const { supabase } = await requireCreator();
  const t = await getTranslations();
  return (
    <ExternalBriefPage
      supabase={supabase}
      briefId={briefId}
      back={() => ({ href: "/creator/briefs", label: t("nav.creator.briefs") })}
    />
  );
}
