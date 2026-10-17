import { getTranslations } from "next-intl/server";
import { MyDeliverables } from "@/components/content/my-deliverables";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { loadMyDeliverables } from "@/lib/content/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.deliverables") };
}

export default async function CreatorDeliverablesPage() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const rows = await loadMyDeliverables(supabase, me.creatorId).catch(() => null);
  return (
    <>
      <PageHeader
        title={t("nav.creator.deliverables")}
        description={t("content.my.subtitle")}
        help="/creator/help/creator#deliverables"
      />
      {rows === null ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : (
        <MyDeliverables rows={rows} hrefBase="/creator/deliverables" />
      )}
    </>
  );
}
