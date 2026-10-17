import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { TemplateForm } from "@/components/content/template-form";
import { PageHeader } from "@/components/ui/page-header";
import { requireStaff } from "@/lib/auth/guards";
import { briefTemplateContent } from "@/lib/content/brief";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("content.templates.new") };
}

export default async function NewBriefTemplatePage() {
  await requireStaff("brief.write");
  const t = await getTranslations();
  return (
    <>
      <Link
        href="/admin/briefs/templates"
        className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("content.briefs.area.templates")}
      </Link>
      <PageHeader title={t("content.templates.new")} description={t("content.templates.newHint")} />
      <TemplateForm
        id={null}
        initial={{
          name: "",
          description: "",
          isDefault: false,
          content: briefTemplateContent.parse({}),
        }}
      />
    </>
  );
}
