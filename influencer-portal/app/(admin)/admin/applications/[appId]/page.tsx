import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { ApplicationView } from "@/components/campaigns/application-view";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadApplication } from "@/lib/campaigns/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.applications") };
}

export default async function AdminApplicationPage({ params }: { params: Promise<{ appId: string }> }) {
  const { appId } = await params;
  if (!z.uuid().safeParse(appId).success) notFound();
  const { supabase, me } = await requireStaff("campaign.read");
  const t = await getTranslations();
  const [{ app, error }, templates] = await Promise.all([
    loadApplication(supabase, appId),
    me.permissions.has("application.review")
      ? supabase
          .from("reason_templates")
          .select("label, body")
          .eq("kind", "application_rejection")
          .eq("active", true)
          .order("position")
      : Promise.resolve({ data: [] as { label: string; body: string }[] }),
  ]);
  if (!error && !app) notFound();
  const { data: deal } =
    app?.status === "accepted" && me.permissions.has("deal.read")
      ? await supabase.from("deals").select("id, code").eq("application_id", appId).maybeSingle()
      : { data: null };
  return (
    <>
      <Link
        href="/admin/applications"
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.admin.applications")}
      </Link>
      {!app ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : (
        <>
          <PageHeader
            title={app.creator.display_name}
            description={
              <Link href={`/admin/campaigns/${app.campaign.id}`} className="hover:underline">
                {app.campaign.name}
              </Link>
            }
            actions={
              deal ? (
                <Button asChild>
                  <Link href={`/admin/deals/${deal.id}`}>{t("deals.openDeal", { code: deal.code })}</Link>
                </Button>
              ) : null
            }
          />
          <ApplicationView app={app} templates={templates.data ?? []} />
        </>
      )}
    </>
  );
}
