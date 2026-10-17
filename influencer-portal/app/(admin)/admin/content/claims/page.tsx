import { getTranslations } from "next-intl/server";
import { ClaimsEditor } from "@/components/content/claims-editor";
import { ContentNav } from "@/components/content/content-nav";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadBannedClaims } from "@/lib/content/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("content.area.claims") };
}

export default async function ClaimsPage() {
  const { supabase, me } = await requireStaff("deliverable.read");
  const t = await getTranslations();
  const rows = await loadBannedClaims(supabase).catch(() => null);
  return (
    <>
      <PageHeader
        title={t("nav.admin.content")}
        description={t("content.claims.subtitle")}
        help="/admin/help/content-reviewer#claims"
      />
      <ContentNav current="claims" />
      {rows === null ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : (
        <ClaimsEditor rows={rows} canEdit={me.permissions.has("compliance.manage")} />
      )}
    </>
  );
}
