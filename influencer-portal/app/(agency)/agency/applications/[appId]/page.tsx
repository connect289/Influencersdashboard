import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { ApplicationView } from "@/components/campaigns/application-view";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireAgency } from "@/lib/auth/guards";
import { loadApplication } from "@/lib/campaigns/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("agencyPortal.campaigns") };
}

export default async function AgencyApplicationPage({
  params,
}: {
  params: Promise<{ appId: string }>;
}) {
  const { appId } = await params;
  if (!z.uuid().safeParse(appId).success) notFound();
  const { supabase } = await requireAgency();
  const t = await getTranslations();
  const { app, error } = await loadApplication(supabase, appId);
  if (!error && !app) notFound();
  return (
    <>
      {app ? (
        <Link
          href={`/agency/creators/${app.creator.id}`}
          className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
        >
          <ArrowLeft className="size-4" aria-hidden /> {app.creator.display_name}
        </Link>
      ) : null}
      {!app ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : (
        <>
          <PageHeader
            title={app.campaign.name}
            description={t("agencyPortal.onBehalf", { name: app.creator.display_name })}
          />
          <ApplicationView app={app} />
        </>
      )}
    </>
  );
}
