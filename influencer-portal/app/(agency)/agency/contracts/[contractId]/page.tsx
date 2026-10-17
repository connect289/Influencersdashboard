import { getTranslations } from "next-intl/server";
import { ExternalContractPage } from "@/components/contracts/external-contract-page";
import { requireAgency } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.agency.home") };
}

/** A managed creator's contract (agencies with the "negotiate and sign" grant). */
export default async function AgencyContractPage({
  params,
  searchParams,
}: {
  params: Promise<{ contractId: string }>;
  searchParams: Promise<{ tab?: string; from?: string; to?: string }>;
}) {
  const [{ contractId }, search] = await Promise.all([params, searchParams]);
  const { supabase } = await requireAgency();
  return (
    <ExternalContractPage
      supabase={supabase}
      contractId={contractId}
      search={search}
      basePath="/agency/contracts"
      back={(c) => ({ href: `/agency/creators/${c.creatorId}`, label: c.creatorName })}
    />
  );
}
