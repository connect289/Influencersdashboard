import { getTranslations } from "next-intl/server";
import { HelpIndex } from "@/components/help/help-index";
import { PageHeader } from "@/components/ui/page-header";
import { requireAgency } from "@/lib/auth/guards";
import { guidesFor } from "@/lib/guides";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.agency.help") };
}

export default async function AgencyHelpPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  await requireAgency();
  const t = await getTranslations();
  const q = ((await searchParams).q ?? "").slice(0, 80);
  return (
    <>
      <PageHeader title={t("help.title")} description={t("help.agencySubtitle")} />
      <HelpIndex base="/agency/help" mine={guidesFor("agency")} others={[]} q={q} />
    </>
  );
}
