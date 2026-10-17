import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { TemplateEditor } from "@/components/contracts/template-editor";
import { PageHeader } from "@/components/ui/page-header";
import { requireStaff } from "@/lib/auth/guards";
import { loadLibrary } from "@/lib/contracts/data";
import { EMPTY_DOC } from "@/lib/contracts/doc";
import { libraryOptions } from "@/lib/contracts/library-options";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("contracts.templates.new") };
}

export default async function NewTemplatePage() {
  const { supabase } = await requireStaff("clause.write");
  const t = await getTranslations();
  const library = libraryOptions(await loadLibrary(supabase));
  return (
    <>
      <Link
        href="/admin/contracts/templates"
        className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" /> {t("contracts.area.templates")}
      </Link>
      <PageHeader
        title={t("contracts.templates.new")}
        description={t("contracts.templates.newHint")}
      />
      <TemplateEditor
        initial={{
          name: "",
          description: "",
          title: "Creator Agreement {{contract.number}}",
          header: EMPTY_DOC,
          footer: EMPTY_DOC,
          isDefault: false,
          clauses: library
            .filter((c) => c.required)
            .map((c) => ({ clauseId: c.id, condition: "" })),
        }}
        library={library}
        archived={false}
        canWrite
      />
    </>
  );
}
