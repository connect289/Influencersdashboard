import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { TermsEditor } from "@/components/deals/terms-editor";
import { TermsSummary } from "@/components/deals/terms-summary";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { requireStaff } from "@/lib/auth/guards";
import { istToday } from "@/lib/format";
import { SYSTEM_PRESETS } from "@/lib/compensation/presets";
import { loadCompContext, loadPresets, loadTdsSections } from "@/lib/deals/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("deals.presets.title") };
}

/** A preset: system presets are read-only (copy one to change it); custom presets open in the builder. */
export default async function PresetPage({
  params,
  searchParams,
}: {
  params: Promise<{ presetId: string }>;
  searchParams: Promise<{ from?: string }>;
}) {
  const { presetId } = await params;
  const isNew = presetId === "new";
  if (!isNew && !z.uuid().safeParse(presetId).success) notFound();
  const { supabase, me } = await requireStaff("deal.read");
  const t = await getTranslations();
  const canWrite = me.permissions.has("deal.write");
  const presets = await loadPresets(supabase, true);
  const from = (await searchParams).from;
  const preset = isNew ? null : presets.find((p) => p.id === presetId);
  if (!isNew && !preset) notFound();
  if (isNew && !canWrite) notFound();
  const source = isNew ? presets.find((p) => p.id === from) : null;
  const today = istToday();

  const header = (
    <Link href="/admin/deals/presets" className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
      <ArrowLeft className="size-4" /> {t("deals.presets.title")}
    </Link>
  );

  if (preset && (preset.is_system || !canWrite)) {
    return (
      <>
        {header}
        <PageHeader
          title={preset.name}
          description={preset.description ?? undefined}
          actions={
            canWrite ? (
              <Button asChild variant="secondary">
                <Link href={`/admin/deals/presets/new?from=${preset.id}`}>{t("deals.presets.copy")}</Link>
              </Button>
            ) : null
          }
        />
        <Card>
          <TermsSummary config={preset.comp_config} />
        </Card>
      </>
    );
  }

  const [ctx, tds] = await Promise.all([loadCompContext(supabase), loadTdsSections(supabase)]);
  const initial = preset?.comp_config ?? source?.comp_config ?? SYSTEM_PRESETS.fixed_plus_commission.config;
  return (
    <>
      {header}
      <PageHeader title={preset ? preset.name : t("deals.presets.new")} description={t("deals.presets.editorHint")} />
      <TermsEditor
        initial={initial}
        target={{
          kind: "preset",
          id: preset?.id ?? "",
          name: preset?.name ?? (source ? t("deals.presets.copyOf", { name: source.name }) : ""),
          description: preset?.description ?? "",
        }}
        simulator={{
          startsOn: today,
          context: ctx.engine,
          gstRateBps: ctx.gst_rate_bps,
          sections: tds.sections,
          estimatePaise: null,
          taxConfirmed: tds.confirmed,
        }}
      />
    </>
  );
}
