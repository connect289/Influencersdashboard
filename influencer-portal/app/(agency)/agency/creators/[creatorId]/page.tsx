import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, Download } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { GrantBadges } from "@/components/agency/grant-badges";
import { MyDeliverables } from "@/components/content/my-deliverables";
import { LinksPanel } from "@/components/links/links-panel";
import { ContractList } from "@/components/contracts/contract-list";
import { DealList } from "@/components/deals/deal-list";
import { PlatformsCard } from "@/components/creator-profile/platforms-card";
import { PortfolioCard, RateCardCard } from "@/components/creator-profile/profile-lists";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireAgency } from "@/lib/auth/guards";
import { loadMyBriefs, loadMyDeliverables } from "@/lib/content/data";
import { loadMyContracts } from "@/lib/contracts/data";
import type { Database } from "@/lib/database.types";
import { loadMyDeals } from "@/lib/deals/data";

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
  const negotiates = link?.can_negotiate_sign === true;
  const seesDeals = negotiates || link?.can_view_earnings === true;
  const acts = link?.can_act_deliverables === true;
  const [deals, contracts, deliverables, briefs] = await Promise.all([
    seesDeals ? loadMyDeals(supabase, creatorId).catch(() => null) : [],
    negotiates ? loadMyContracts(supabase, creatorId).catch(() => null) : [],
    acts ? loadMyDeliverables(supabase, creatorId).catch(() => null) : [],
    acts ? loadMyBriefs(supabase, creatorId).catch(() => null) : [],
  ]);
  let inviteRows: Database["inf"]["Functions"]["my_invites"]["Returns"] = [];
  let appRows: Database["inf"]["Functions"]["my_applications"]["Returns"] = [];
  if (negotiates) {
    const [i, a] = await Promise.all([
      supabase.rpc("my_invites", { p_creator: creatorId }),
      supabase.rpc("my_applications", { p_creator: creatorId }),
    ]);
    inviteRows = (i.data ?? []).filter((x) => x.status === "sent");
    appRows = a.data ?? [];
  }
  return (
    <>
      <Link href="/agency" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("agencyPortal.creators")}
      </Link>
      <PageHeader
        title={link?.display_name ?? ""}
        description={link ? `@${link.handle}` : undefined}
        actions={
          link ? (
            <Button asChild variant="secondary" size="sm">
              <a href={`/api/media-kit/${creatorId}`}>
                <Download /> {t("mediaKit.pdf")}
              </a>
            </Button>
          ) : null
        }
      />
      {failed || !link ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : (
        <div className="flex flex-col gap-4">
          <div className="flex items-center gap-2 text-sm text-muted">
            {t("agencyPortal.granted")} <GrantBadges grants={link} />
          </div>
          {negotiates ? (
            <Card>
              <CardHeader title={t("agencyPortal.campaigns")} description={t("agencyPortal.campaignsHint")} />
              {inviteRows.length === 0 && appRows.length === 0 ? (
                <EmptyState title={t("agencyPortal.noCampaigns")} />
              ) : (
                <ul className="flex flex-col divide-y divide-line">
                  {inviteRows.map((i) => (
                    <li key={i.id} className="flex items-center gap-3 py-2.5">
                      <Link
                        href={`/agency/creators/${creatorId}/campaigns/${i.campaign_id}`}
                        className="min-w-0 flex-1 text-sm font-medium text-primary hover:underline"
                      >
                        {i.campaign_name}
                      </Link>
                      <Badge family="attention">{t("campaigns.marketplace.invited")}</Badge>
                    </li>
                  ))}
                  {appRows.map((a) => (
                    <li key={a.id} className="flex items-center gap-3 py-2.5">
                      <Link
                        href={`/agency/applications/${a.id}`}
                        className="min-w-0 flex-1 text-sm font-medium text-primary hover:underline"
                      >
                        {a.campaign_name}
                      </Link>
                      <StatusBadge
                        status={a.status}
                        label={t(`campaigns.applicationStatuses.${a.status as "submitted"}`)}
                      />
                    </li>
                  ))}
                </ul>
              )}
            </Card>
          ) : null}
          {seesDeals ? (
            <Card>
              <CardHeader title={t("nav.creator.deals")} description={t("agencyPortal.dealsHint")} />
              {deals === null ? (
                <ErrorState title={t("errors.loadFailed")} />
              ) : (
                <DealList deals={deals} hrefBase="/agency/deals" />
              )}
            </Card>
          ) : null}
          {acts ? (
            <Card>
              <CardHeader title={t("nav.creator.deliverables")} description={t("agencyPortal.deliverablesHint")} />
              {deliverables === null || briefs === null ? (
                <ErrorState title={t("errors.loadFailed")} />
              ) : (
                <div className="flex flex-col gap-4">
                  {briefs.length ? (
                    <ul className="flex flex-col gap-1 text-sm">
                      {briefs.map((b) => (
                        <li key={b.id} className="flex flex-wrap items-center gap-2">
                          <Link href={`/agency/briefs/${b.id}`} className="font-medium text-primary hover:underline">
                            {t("agencyPortal.briefFor", { deal: b.deal_title })}
                          </Link>
                          {b.acknowledged ? null : (
                            <Badge family="attention">{t("content.my.readAndAcknowledge")}</Badge>
                          )}
                        </li>
                      ))}
                    </ul>
                  ) : null}
                  <MyDeliverables rows={deliverables} hrefBase="/agency/deliverables" />
                </div>
              )}
            </Card>
          ) : null}
          <Card>
            <CardHeader
              title={t("nav.creator.leads")}
              description={t("agencyPortal.leadsHint")}
              actions={
                <Button asChild size="sm" variant="secondary">
                  <Link href={`/agency/creators/${creatorId}/leads`}>{t("agencyPortal.openLeads")}</Link>
                </Button>
              }
            />
          </Card>
          <Card>
            <CardHeader title={t("nav.creator.links")} description={t("agencyPortal.linksHint")} />
            <LinksPanel supabase={supabase} creatorId={creatorId} canCreate={negotiates} staff={false} />
          </Card>
          {negotiates ? (
            <Card>
              <CardHeader title={t("nav.creator.contracts")} description={t("agencyPortal.contractsHint")} />
              {contracts === null ? (
                <ErrorState title={t("errors.loadFailed")} />
              ) : (
                <ContractList contracts={contracts} hrefBase="/agency/contracts" />
              )}
            </Card>
          ) : null}
          <PlatformsCard creatorId={creatorId} platforms={platforms.data ?? []} canEdit={false} />
          <RateCardCard creatorId={creatorId} rates={rates.data ?? []} canEdit={false} />
          <PortfolioCard creatorId={creatorId} items={portfolio.data ?? []} canEdit={false} />
        </div>
      )}
    </>
  );
}
