import { getTranslations } from "next-intl/server";
import { LeadsNav } from "@/components/leads/leads-nav";
import { StageRules } from "@/components/leads/stage-rules";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadStageRules } from "@/lib/leads/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("leads.area.stages") };
}

export default async function StageRulesPage() {
  const { supabase, me } = await requireStaff("lead.read");
  const t = await getTranslations();
  const rules = await loadStageRules(supabase).catch(() => null);
  return (
    <>
      <PageHeader
        title={t("nav.admin.leads")}
        description={t("leads.stages.subtitle")}
        help="/admin/help/super-admin#stage-rules"
      />
      <LeadsNav current="stages" permissions={me.permissions} />
      {rules === null ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : (
        <StageRules rules={rules} canEdit={me.permissions.has("settings.write")} />
      )}
    </>
  );
}
