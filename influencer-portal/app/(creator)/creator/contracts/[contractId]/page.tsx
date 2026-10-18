import { getTranslations } from "next-intl/server";
import { ExternalContractPage } from "@/components/contracts/external-contract-page";
import { requireCreator } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.contracts") };
}

export default async function CreatorContractPage({
  params,
  searchParams,
}: {
  params: Promise<{ contractId: string }>;
  searchParams: Promise<{ tab?: string; from?: string; to?: string }>;
}) {
  const [{ contractId }, search] = await Promise.all([params, searchParams]);
  const { supabase } = await requireCreator();
  const t = await getTranslations();
  return (
    <ExternalContractPage
      supabase={supabase}
      contractId={contractId}
      search={search}
      basePath="/creator/contracts"
      back={() => ({ href: "/creator/contracts", label: t("nav.creator.contracts") })}
    />
  );
}
