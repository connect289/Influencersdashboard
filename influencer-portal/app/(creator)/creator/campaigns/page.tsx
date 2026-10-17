import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { CampaignCard } from "@/components/campaigns/campaign-card";
import { campaignPublic } from "@/components/campaigns/public";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/ui/page-header";
import { Banner, EmptyState, ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { onboardingState } from "@/lib/creators/onboarding";
import { formatDate, formatRelative } from "@/lib/format";
import { cn } from "@/lib/utils";

const TABS = ["open", "invited", "applications"] as const;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.campaigns") };
}

/** Campaigns: Open (marketplace), Invited, My applications (spec 17 creator nav). */
export default async function CreatorCampaignsPage({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const { supabase } = await requireCreator();
  const t = await getTranslations();
  const requested = (await searchParams).tab;
  const tab = TABS.find((x) => x === requested) ?? "open";
  const onboarding = onboardingState.safeParse((await supabase.rpc("onboarding_state")).data);
  const approved = onboarding.success && onboarding.data.approved;

  let body: React.ReactNode;
  if (tab === "open") {
    const { data, error } = await supabase.rpc("marketplace");
    const list = z.array(campaignPublic).safeParse(data);
    body =
      error || !list.success ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : list.data.length === 0 ? (
        <EmptyState title={t("campaigns.marketplace.empty")} description={t("campaigns.marketplace.emptyHint")} />
      ) : (
        <div className="grid gap-3 md:grid-cols-2">
          {list.data.map((c) => (
            <CampaignCard key={c.id} c={c} href={`/creator/campaigns/${c.id}`} />
          ))}
        </div>
      );
  } else if (tab === "invited") {
    const { data, error } = await supabase.rpc("my_invites");
    body = error ? (
      <ErrorState title={t("errors.loadFailed")} />
    ) : data.length === 0 ? (
      <EmptyState title={t("campaigns.marketplace.noInvites")} />
    ) : (
      <ul className="flex flex-col gap-2">
        {data.map((i) => (
          <li key={i.id}>
            <Link
              href={`/creator/campaigns/${i.campaign_id}`}
              className="flex items-center gap-3 rounded-xl bg-surface p-3 shadow-[var(--shadow-card)] hover:opacity-90"
            >
              <span className="min-w-0 flex-1">
                <span className="block font-medium">{i.campaign_name}</span>
                <span className="block text-xs text-muted">
                  {i.apply_by
                    ? t("campaigns.marketplace.applyBy", { date: formatDate(i.apply_by) })
                    : formatRelative(i.sent_at)}
                </span>
              </span>
              <StatusBadge status={i.status} label={t(`campaigns.invites.statuses.${i.status as "sent"}`)} />
            </Link>
          </li>
        ))}
      </ul>
    );
  } else {
    const { data, error } = await supabase.rpc("my_applications");
    body = error ? (
      <ErrorState title={t("errors.loadFailed")} />
    ) : data.length === 0 ? (
      <EmptyState title={t("campaigns.marketplace.noApplications")} />
    ) : (
      <ul className="flex flex-col gap-2">
        {data.map((a) => (
          <li key={a.id}>
            <Link
              href={`/creator/applications/${a.id}`}
              className="flex items-center gap-3 rounded-xl bg-surface p-3 shadow-[var(--shadow-card)] hover:opacity-90"
            >
              <span className="min-w-0 flex-1">
                <span className="block font-medium">{a.campaign_name}</span>
                <span className="block text-xs text-muted">{formatRelative(a.updated_at)}</span>
              </span>
              {a.open_offer_from === "eduwit" ? (
                <Badge family="attention">{t("campaigns.application.newOffer")}</Badge>
              ) : null}
              <StatusBadge status={a.status} label={t(`campaigns.applicationStatuses.${a.status as "submitted"}`)} />
            </Link>
          </li>
        ))}
      </ul>
    );
  }

  return (
    <>
      <PageHeader title={t("nav.creator.campaigns")} description={t("campaigns.marketplace.subtitle")} />
      {!approved ? (
        <div className="mb-4 flex flex-col gap-2">
          <Banner tone="warning">{t("campaigns.marketplace.finishOnboarding")}</Banner>
          <div>
            <Button asChild size="sm">
              <Link href="/creator/onboarding">{t("home.actions.onboarding")}</Link>
            </Button>
          </div>
        </div>
      ) : null}
      <nav className="mb-4 flex gap-1" aria-label={t("nav.creator.campaigns")}>
        {TABS.map((x) => (
          <Link
            key={x}
            href={x === "open" ? "/creator/campaigns" : `/creator/campaigns?tab=${x}`}
            aria-current={tab === x ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm",
              tab === x ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {t(`campaigns.marketplace.tabs.${x}`)}
          </Link>
        ))}
      </nav>
      {body}
    </>
  );
}
