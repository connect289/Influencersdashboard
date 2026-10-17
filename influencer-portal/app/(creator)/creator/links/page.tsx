import { getTranslations } from "next-intl/server";
import { LinksPanel } from "@/components/links/links-panel";
import { PageHeader } from "@/components/ui/page-header";
import { requireCreator } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.links") };
}

export default async function CreatorLinksPage() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  return (
    <>
      <PageHeader
        title={t("nav.creator.links")}
        description={t("links.subtitle")}
        help="/creator/help/creator#links"
      />
      <LinksPanel supabase={supabase} creatorId={me.creatorId} canCreate staff={false} />
    </>
  );
}
