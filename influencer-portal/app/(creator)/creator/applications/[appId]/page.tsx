import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { ApplicationView } from "@/components/campaigns/application-view";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { loadApplication } from "@/lib/campaigns/data";
import { loadMyDeals } from "@/lib/deals/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("campaigns.marketplace.tabs.applications") };
}

export default async function CreatorApplicationPage({ params }: { params: Promise<{ appId: string }> }) {
  const { appId } = await params;
  if (!z.uuid().safeParse(appId).success) notFound();
  const { supabase } = await requireCreator();
  const t = await getTranslations();
  const { app, error } = await loadApplication(supabase, appId);
  if (!error && !app) notFound();
  const deal =
    app?.status === "accepted"
      ? (await loadMyDeals(supabase, app.creator.id).catch(() => [])).find((d) => d.application_id === app.id)
      : undefined;
  return (
    <>
      <Link
        href="/creator/campaigns?tab=applications"
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("campaigns.marketplace.tabs.applications")}
      </Link>
      {!app ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : (
        <>
          <PageHeader
            title={app.campaign.name}
            actions={
              deal ? (
                <Button asChild>
                  <Link href={`/creator/deals/${deal.id}`}>{t("deals.my.viewDeal")}</Link>
                </Button>
              ) : null
            }
          />
          <ApplicationView app={app} />
        </>
      )}
    </>
  );
}
