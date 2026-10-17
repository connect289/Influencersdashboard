import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { GuideView } from "@/components/help/guide-view";
import { PageHeader } from "@/components/ui/page-header";
import { requireCreator } from "@/lib/auth/guards";
import { findGuide } from "@/lib/guides";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.help") };
}

export default async function CreatorGuidePage({ params }: { params: Promise<{ slug: string }> }) {
  await requireCreator();
  const t = await getTranslations();
  const guide = findGuide("creator", (await params).slug);
  if (!guide) notFound();
  return (
    <>
      <Link
        href="/creator/help"
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("help.title")}
      </Link>
      <PageHeader title={guide.title} description={guide.summary} />
      <GuideView guide={guide} />
    </>
  );
}
