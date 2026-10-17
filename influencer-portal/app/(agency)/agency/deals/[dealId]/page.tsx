import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { DealContracts } from "@/components/contracts/deal-contracts";
import { DealView } from "@/components/deals/deal-view";
import { PageHeader } from "@/components/ui/page-header";
import { requireAgency } from "@/lib/auth/guards";
import { loadMyContracts } from "@/lib/contracts/data";
import { loadDeal } from "@/lib/deals/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.agency.home") };
}

/** A managed creator's deal (agencies with the "negotiate" or "view earnings" grant). */
export default async function AgencyDealPage({ params }: { params: Promise<{ dealId: string }> }) {
  const { dealId } = await params;
  if (!z.uuid().safeParse(dealId).success) notFound();
  const { supabase } = await requireAgency();
  const deal = await loadDeal(supabase, dealId);
  if (!deal || deal.status === "draft") notFound();
  const contracts = (await loadMyContracts(supabase, deal.creator_id).catch(() => [])).filter(
    (c) => c.deal_id === deal.id,
  );
  return (
    <>
      <Link
        href={`/agency/creators/${deal.creator_id}`}
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {deal.creator.display_name}
      </Link>
      <PageHeader title={deal.title} description={`@${deal.creator.handle}`} />
      <DealContracts contracts={contracts} hrefBase="/agency/contracts" />
      <DealView deal={deal} />
    </>
  );
}
