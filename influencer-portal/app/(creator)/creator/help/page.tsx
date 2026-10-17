import { getTranslations } from "next-intl/server";
import { HelpIndex } from "@/components/help/help-index";
import { PageHeader } from "@/components/ui/page-header";
import { requireCreator } from "@/lib/auth/guards";
import { guidesFor } from "@/lib/guides";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.help") };
}

export default async function CreatorHelpPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  await requireCreator();
  const t = await getTranslations();
  const q = ((await searchParams).q ?? "").slice(0, 80);
  return (
    <>
      <PageHeader title={t("help.title")} description={t("help.creatorSubtitle")} />
      <HelpIndex base="/creator/help" mine={guidesFor("creator")} others={[]} q={q} />
    </>
  );
}
