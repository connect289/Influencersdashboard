import { getTranslations } from "next-intl/server";
import { DealList } from "@/components/deals/deal-list";
import { PageHeader } from "@/components/ui/page-header";
import { requireCreator } from "@/lib/auth/guards";
import { loadMyDeals } from "@/lib/deals/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.deals") };
}

export default async function CreatorDealsPage() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const deals = await loadMyDeals(supabase, me.creatorId);
  return (
    <>
      <PageHeader
        title={t("nav.creator.deals")}
        description={t("deals.my.subtitle")}
        help="/creator/help/creator#deals"
      />
      <DealList deals={deals} hrefBase="/creator/deals" />
    </>
  );
}
