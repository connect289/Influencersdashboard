import { getTranslations } from "next-intl/server";
import { HelpIndex } from "@/components/help/help-index";
import { PageHeader } from "@/components/ui/page-header";
import { requireStaff } from "@/lib/auth/guards";
import { guidesFor, staffGuideOrder } from "@/lib/guides";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.help") };
}

export default async function AdminHelpPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { me } = await requireStaff();
  const t = await getTranslations();
  const q = ((await searchParams).q ?? "").slice(0, 80);
  const { mine, others } = staffGuideOrder(guidesFor("admin", me.permissions), me.roles);
  return (
    <>
      <PageHeader title={t("help.title")} description={t("help.staffSubtitle")} />
      <HelpIndex base="/admin/help" mine={mine} others={others} q={q} />
    </>
  );
}
