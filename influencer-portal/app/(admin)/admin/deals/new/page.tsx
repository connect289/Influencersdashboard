import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { NewDealForm } from "@/components/deals/new-deal-form";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { istToday } from "@/lib/format";
import { loadPresets } from "@/lib/deals/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("deals.new.button") };
}

export default async function NewDealPage({
  searchParams,
}: {
  searchParams: Promise<{ creator?: string; campaign?: string }>;
}) {
  const { supabase } = await requireStaff("deal.write");
  const t = await getTranslations();
  const sp = await searchParams;
  const creatorId = z.uuid().safeParse(sp.creator).success ? sp.creator : null;
  const [presets, campaigns, creator] = await Promise.all([
    loadPresets(supabase),
    supabase
      .from("campaigns")
      .select("id, name, starts_on, ends_on, default_preset_id")
      .in("status", ["draft", "open", "invite_only", "active", "paused"])
      .order("updated_at", { ascending: false })
      .limit(200),
    creatorId
      ? supabase.from("creators").select("id, display_name, handle").eq("id", creatorId).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);
  const today = istToday();
  return (
    <>
      <Link href="/admin/deals" className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" /> {t("nav.admin.deals")}
      </Link>
      <PageHeader
        title={t("deals.new.button")}
        description={t("deals.new.subtitle")}
        help="/admin/help/influencer-manager#deals"
      />
      {presets.length === 0 ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : (
        <NewDealForm
          presets={presets.map((p) => ({
            id: p.id,
            name: p.name,
            config: p.comp_config,
            default: p.key === "fixed_plus_commission",
          }))}
          campaigns={(campaigns.data ?? []).map((c) => ({
            id: c.id,
            name: c.name,
            startsOn: c.starts_on,
            endsOn: c.ends_on,
            presetId: c.default_preset_id,
          }))}
          initialCreator={
            creator.data
              ? {
                  id: creator.data.id,
                  name: creator.data.display_name,
                  handle: creator.data.handle,
                }
              : null
          }
          initialCampaignId={z.uuid().safeParse(sp.campaign).success ? (sp.campaign ?? "") : ""}
          today={today}
        />
      )}
    </>
  );
}
