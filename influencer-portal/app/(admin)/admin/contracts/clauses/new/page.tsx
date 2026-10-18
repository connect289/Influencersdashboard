import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { ClauseEditor, NEW_CLAUSE } from "@/components/contracts/clause-editor";
import { PageHeader } from "@/components/ui/page-header";
import { requireStaff } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("contracts.library.new") };
}

export default async function NewClausePage() {
  const { me } = await requireStaff("clause.write");
  const t = await getTranslations();
  return (
    <>
      <Link
        href="/admin/contracts/clauses"
        className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" /> {t("contracts.area.clauses")}
      </Link>
      <PageHeader title={t("contracts.library.new")} description={t("contracts.library.newHint")} />
      <ClauseEditor
        initial={NEW_CLAUSE}
        version={null}
        reviewed={false}
        archived={false}
        canWrite
        canReview={me.permissions.has("clause.legal_review")}
      />
    </>
  );
}
