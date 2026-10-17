import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { DealView } from "@/components/deals/deal-view";
import { PageHeader } from "@/components/ui/page-header";
import { requireCreator } from "@/lib/auth/guards";
import { loadDeal } from "@/lib/deals/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.deals") };
}

export default async function CreatorDealPage({ params }: { params: Promise<{ dealId: string }> }) {
  const { dealId } = await params;
  if (!z.uuid().safeParse(dealId).success) notFound();
  const { supabase } = await requireCreator();
  const t = await getTranslations();
  const deal = await loadDeal(supabase, dealId);
  if (!deal || deal.status === "draft") notFound();
  return (
    <>
      <Link href="/creator/deals" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.creator.deals")}
      </Link>
      <PageHeader title={deal.title} />
      <DealView deal={deal} />
    </>
  );
}
