import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { TierEditor } from "@/components/scorecards/tier-editor";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadTiers } from "@/lib/scorecards/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("insight.tiers.title") };
}

export default async function TiersPage() {
  const { supabase } = await requireStaff("tier.manage");
  const t = await getTranslations();
  const tiers = await loadTiers(supabase).catch(() => null);
  return (
    <>
      <Link href="/admin/settings" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.admin.settings")}
      </Link>
      <PageHeader
        title={t("insight.tiers.title")}
        description={t("insight.tiers.subtitle")}
        help="/admin/help/super-admin#tiers"
      />
      {tiers ? (
        <TierEditor tiers={tiers} />
      ) : (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      )}
    </>
  );
}
