import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { GrantBadges } from "@/components/agency/grant-badges";
import { PlatformsCard } from "@/components/creator-profile/platforms-card";
import { PortfolioCard, RateCardCard } from "@/components/creator-profile/profile-lists";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireAgency } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.agency.home") };
}

/** A managed creator, read-only: what the agency needs to pitch and plan. No contact details or KYC. */
export default async function AgencyCreatorPage({ params }: { params: Promise<{ creatorId: string }> }) {
  const { creatorId } = await params;
  if (!z.uuid().safeParse(creatorId).success) notFound();
  const { supabase } = await requireAgency();
  const t = await getTranslations();
  const [links, platforms, rates, portfolio] = await Promise.all([
    supabase.rpc("agency_creators"),
    supabase.from("creator_platforms").select("*").eq("creator_id", creatorId).order("created_at"),
    supabase.from("creator_rate_cards").select("*").eq("creator_id", creatorId).order("platform"),
    supabase.from("creator_portfolio").select("*").eq("creator_id", creatorId).order("position"),
  ]);
  const link = (links.data ?? []).find((l) => l.creator_id === creatorId && l.link_status === "active");
  if (!links.error && !link) notFound();
  const failed = links.error ?? platforms.error ?? rates.error ?? portfolio.error;
  return (
    <>
      <Link href="/agency" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("agencyPortal.creators")}
      </Link>
      <PageHeader title={link?.display_name ?? ""} description={link ? `@${link.handle}` : undefined} />
      {failed || !link ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : (
        <div className="flex flex-col gap-4">
          <div className="flex items-center gap-2 text-sm text-muted">
            {t("agencyPortal.granted")} <GrantBadges grants={link} />
          </div>
          <PlatformsCard creatorId={creatorId} platforms={platforms.data ?? []} canEdit={false} />
          <RateCardCard creatorId={creatorId} rates={rates.data ?? []} canEdit={false} />
          <PortfolioCard creatorId={creatorId} items={portfolio.data ?? []} canEdit={false} />
        </div>
      )}
    </>
  );
}
