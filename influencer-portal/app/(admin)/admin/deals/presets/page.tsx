import Link from "next/link";
import { ArrowLeft, Plus } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { PresetArchiveButton } from "@/components/deals/preset-archive";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import { loadPresets } from "@/lib/deals/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("deals.presets.title") };
}

export default async function PresetsPage() {
  const { supabase, me } = await requireStaff("deal.read");
  const t = await getTranslations();
  const canWrite = me.permissions.has("deal.write");
  const presets = await loadPresets(supabase, true);
  return (
    <>
      <Link href="/admin/deals" className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" /> {t("nav.admin.deals")}
      </Link>
      <PageHeader
        title={t("deals.presets.title")}
        description={t("deals.presets.subtitle")}
        actions={
          canWrite ? (
            <Button asChild>
              <Link href="/admin/deals/presets/new">
                <Plus /> {t("deals.presets.new")}
              </Link>
            </Button>
          ) : null
        }
      />
      <Card>
        {presets.length === 0 ? (
          <EmptyState title={t("deals.presets.empty")} description={t("deals.presets.emptyHint")} />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("deals.presets.name")}</Th>
                <Th>{t("deals.model")}</Th>
                <Th>{t("deals.presets.kind")}</Th>
                {canWrite ? <Th className="sr-only">{t("common.actions")}</Th> : null}
              </tr>
            </thead>
            <tbody>
              {presets.map((p) => (
                <tr key={p.id} className={p.archived ? "opacity-60" : undefined}>
                  <Td>
                    <Link href={`/admin/deals/presets/${p.id}`} className="font-medium text-primary hover:underline">
                      {p.name}
                    </Link>
                    {p.description ? <span className="block text-xs text-muted">{p.description}</span> : null}
                  </Td>
                  <Td>{t(`deals.models.${p.deal_model}`)}</Td>
                  <Td>
                    {p.is_system ? (
                      <Badge family="progress">{t("deals.presets.system")}</Badge>
                    ) : (
                      <Badge>{t("deals.presets.custom")}</Badge>
                    )}
                    {p.archived ? <Badge className="ml-1">{t("deals.presets.archivedBadge")}</Badge> : null}
                  </Td>
                  {canWrite ? (
                    <Td className="text-right">
                      {p.is_system ? null : <PresetArchiveButton id={p.id} archived={p.archived} />}
                    </Td>
                  ) : null}
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    </>
  );
}
