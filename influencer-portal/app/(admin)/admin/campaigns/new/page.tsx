import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { CampaignForm, EMPTY_CAMPAIGN } from "@/components/campaigns/campaign-form";
import { PageHeader } from "@/components/ui/page-header";
import { requireStaff } from "@/lib/auth/guards";
import { loadPickers } from "@/lib/creators/staff-data";
import { presetOptions } from "@/lib/deals/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("campaigns.new") };
}

export default async function NewCampaignPage() {
  const { supabase } = await requireStaff("campaign.write");
  const t = await getTranslations();
  const [{ owners }, presets] = await Promise.all([loadPickers(supabase), presetOptions(supabase)]);
  return (
    <>
      <Link href="/admin/campaigns" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.admin.campaigns")}
      </Link>
      <PageHeader title={t("campaigns.new")} description={t("campaigns.newHint")} />
      <CampaignForm initial={EMPTY_CAMPAIGN} owners={owners} presets={presets} />
    </>
  );
}
