import { getTranslations } from "next-intl/server";
import { EarningsView } from "@/components/earnings/earnings-view";
import { PayoutThreadDrawer } from "@/components/messaging/payout-thread";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { loadEarnings } from "@/lib/ledger/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.earnings") };
}

export default async function CreatorEarningsPage({ searchParams }: { searchParams: Promise<{ payout?: string }> }) {
  const { supabase, me } = await requireCreator();
  const sp = await searchParams;
  const t = await getTranslations();
  const data = await loadEarnings(supabase, me.creatorId).catch(() => null);
  return (
    <>
      <PageHeader
        title={t("nav.creator.earnings")}
        description={t("earnings.subtitle")}
        help="/creator/help/creator#earnings"
      />
      {data ? (
        <EarningsView data={data} creatorId={me.creatorId} canUpload leadsHref="/creator/leads" />
      ) : (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      )}
      <PayoutThreadDrawer db={supabase} payoutId={sp.payout} />
    </>
  );
}
