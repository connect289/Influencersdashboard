import { getTranslations } from "next-intl/server";
import { ContractList } from "@/components/contracts/contract-list";
import { PageHeader } from "@/components/ui/page-header";
import { requireCreator } from "@/lib/auth/guards";
import { loadMyContracts } from "@/lib/contracts/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.contracts") };
}

export default async function CreatorContractsPage() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const contracts = await loadMyContracts(supabase, me.creatorId);
  return (
    <>
      <PageHeader
        title={t("nav.creator.contracts")}
        description={t("contracts.my.subtitle")}
        help="/creator/help/creator#contracts"
      />
      <ContractList contracts={contracts} hrefBase="/creator/contracts" />
    </>
  );
}
