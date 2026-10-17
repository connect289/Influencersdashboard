import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { BriefFieldsPreview } from "@/components/content/template-preview";
import { TemplateForm } from "@/components/content/template-form";
import { PageHeader } from "@/components/ui/page-header";
import { Banner } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadBriefTemplates } from "@/lib/content/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("content.briefs.area.templates") };
}

export default async function BriefTemplatePage({
  params,
}: {
  params: Promise<{ templateId: string }>;
}) {
  const { templateId } = await params;
  if (!z.uuid().safeParse(templateId).success) notFound();
  const { supabase, me } = await requireStaff("brief.read");
  const t = await getTranslations();
  const tpl = (await loadBriefTemplates(supabase, true)).find((x) => x.id === templateId);
  if (!tpl) notFound();
  const editable = me.permissions.has("brief.write") && tpl.archived_at === null;
  return (
    <>
      <Link
        href="/admin/briefs/templates"
        className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("content.briefs.area.templates")}
      </Link>
      <PageHeader title={tpl.name} description={tpl.description ?? undefined} />
      {tpl.archived_at ? (
        <Banner tone="warning">{t("content.templates.archivedBanner")}</Banner>
      ) : null}
      {editable ? (
        <TemplateForm
          id={tpl.id}
          initial={{
            name: tpl.name,
            description: tpl.description ?? "",
            isDefault: tpl.is_default,
            content: tpl.content,
          }}
        />
      ) : (
        <BriefFieldsPreview content={tpl.content} />
      )}
    </>
  );
}
