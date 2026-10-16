import { getTranslations } from "next-intl/server";
import { KycForm } from "@/components/creator-profile/kyc-form";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { loadKyc } from "@/lib/creators/load";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.kyc") };
}

export default async function CreatorKycPage() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const kyc = await loadKyc(supabase, me.creatorId);
  return (
    <>
      <PageHeader title={t("kyc.pageTitle")} description={t("kyc.pageSubtitle")} />
      {kyc ? (
        <KycForm creatorId={me.creatorId} kyc={kyc} canEdit />
      ) : (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      )}
    </>
  );
}
