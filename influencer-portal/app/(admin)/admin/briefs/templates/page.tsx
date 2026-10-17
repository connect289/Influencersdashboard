import Link from "next/link";
import { Plus } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { BriefsNav } from "@/components/content/briefs-nav";
import { TemplateArchiveButton } from "@/components/content/template-archive";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadBriefTemplates } from "@/lib/content/data";
import { STAGES } from "@/lib/content/workflow";
import { formatDate } from "@/lib/format";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("content.briefs.area.templates") };
}

export default async function BriefTemplatesPage({
  searchParams,
}: {
  searchParams: Promise<{ archived?: string }>;
}) {
  const { supabase, me } = await requireStaff("brief.read");
  const t = await getTranslations();
  const showArchived = (await searchParams).archived === "1";
  const canWrite = me.permissions.has("brief.write");
  const rows = await loadBriefTemplates(supabase, showArchived).catch(() => null);
  return (
    <>
      <PageHeader
        title={t("nav.admin.briefs")}
        description={t("content.templates.subtitle")}
        help="/admin/help/influencer-manager#briefs"
        actions={
          canWrite ? (
            <Button asChild>
              <Link href="/admin/briefs/templates/new">
                <Plus /> {t("content.templates.new")}
              </Link>
            </Button>
          ) : null
        }
      />
      <BriefsNav current="templates" />
      <p className="mb-3 text-sm">
        <Link
          href={showArchived ? "/admin/briefs/templates" : "/admin/briefs/templates?archived=1"}
          className="text-primary hover:underline"
        >
          {showArchived ? t("content.templates.hideArchived") : t("content.templates.showArchived")}
        </Link>
      </p>
      {rows === null ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : rows.length === 0 ? (
        <EmptyState
          title={t("content.templates.empty")}
          description={t("content.templates.emptyHint")}
        />
      ) : (
        <ul className="grid gap-3 md:grid-cols-2">
          {rows.map((r) => (
            <li key={r.id}>
              <Card className="flex h-full flex-col gap-2">
                <div className="flex items-start justify-between gap-2">
                  <Link
                    href={`/admin/briefs/templates/${r.id}`}
                    className="font-medium text-primary hover:underline"
                  >
                    {r.name}
                  </Link>
                  <span className="flex gap-1">
                    {r.is_default ? (
                      <Badge family="success">{t("content.templates.isDefault")}</Badge>
                    ) : null}
                    {r.archived_at ? (
                      <Badge family="closed">{t("content.templates.archived")}</Badge>
                    ) : null}
                  </span>
                </div>
                {r.description ? <p className="text-sm text-muted">{r.description}</p> : null}
                <p className="text-xs text-muted">
                  {STAGES.filter((s) => r.content.stages[s])
                    .map((s) => t(`content.stages.${s}`))
                    .join(" → ")}
                </p>
                <div className="mt-auto flex items-center justify-between gap-2 pt-2">
                  <span className="text-xs text-muted">
                    {t("content.templates.updated", { date: formatDate(r.updated_at) })}
                  </span>
                  {canWrite ? (
                    <TemplateArchiveButton id={r.id} archived={r.archived_at !== null} />
                  ) : null}
                </div>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
