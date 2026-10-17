import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { TemplateEditor } from "@/components/contracts/template-editor";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/page-header";
import { requireStaff } from "@/lib/auth/guards";
import { loadLibrary, loadTemplate } from "@/lib/contracts/data";
import { libraryOptions } from "@/lib/contracts/library-options";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("contracts.area.templates") };
}

export default async function TemplatePage({ params }: { params: Promise<{ templateId: string }> }) {
  const { templateId } = await params;
  if (!z.uuid().safeParse(templateId).success) notFound();
  const { supabase, me } = await requireStaff("contract.read");
  const t = await getTranslations();
  const [tpl, library] = await Promise.all([loadTemplate(supabase, templateId), loadLibrary(supabase)]);
  if (!tpl) notFound();
  return (
    <>
      <Link
        href="/admin/contracts/templates"
        className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" /> {t("contracts.area.templates")}
      </Link>
      <PageHeader
        title={tpl.name}
        description={
          <span className="flex flex-wrap items-center gap-2">
            {tpl.description}
            {tpl.is_default ? <Badge family="success">{t("contracts.templates.defaultBadge")}</Badge> : null}
            {tpl.archived ? <Badge>{t("contracts.library.archivedBadge")}</Badge> : null}
          </span>
        }
        help="/admin/help/influencer-manager#contracts"
      />
      <TemplateEditor
        initial={{
          id: tpl.id,
          name: tpl.name,
          description: tpl.description ?? "",
          title: tpl.title,
          header: tpl.header,
          footer: tpl.footer,
          isDefault: tpl.is_default,
          clauses: tpl.clauses.map((c) => ({
            clauseId: c.clause_id,
            condition: c.condition ?? "",
          })),
        }}
        library={libraryOptions(library)}
        archived={tpl.archived}
        canWrite={me.permissions.has("clause.write")}
      />
    </>
  );
}
