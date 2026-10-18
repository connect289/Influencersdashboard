import { getTranslations } from "next-intl/server";
import { BackfillForm } from "@/components/leads/backfill-form";
import { LeadsNav } from "@/components/leads/leads-nav";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { Banner } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { leadSyncEnabled } from "@/lib/attribution/sync";
import { loadOverview } from "@/lib/leads/data";
import { formatDateTime, istToday } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("leads.area.tools") };
}

export default async function LeadToolsPage() {
  const { supabase, me } = await requireStaff("attribution.review");
  const t = await getTranslations();
  const overview = await loadOverview(supabase).catch(() => null);
  return (
    <>
      <PageHeader
        title={t("nav.admin.leads")}
        description={t("leads.tools.subtitle")}
        help="/admin/help/influencer-manager#leads"
      />
      <LeadsNav current="tools" permissions={me.permissions} />
      <div className="flex flex-col gap-4">
        {leadSyncEnabled() ? null : <Banner tone="warning">{t("leads.tools.disabled")}</Banner>}
        <Card>
          <CardHeader title={t("leads.tools.syncTitle")} description={t("leads.tools.syncHint")} />
          <p className="text-sm">
            {overview?.last_sync
              ? t("leads.lastSync", { at: formatDateTime(overview.last_sync.updated_at) })
              : t("leads.tools.neverSynced")}
          </p>
        </Card>
        <Card>
          <CardHeader title={t("leads.backfill.title")} description={t("leads.backfill.hint")} />
          <BackfillForm today={istToday()} />
        </Card>
      </div>
    </>
  );
}
