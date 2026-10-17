import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { GuideView } from "@/components/help/guide-view";
import { PageHeader } from "@/components/ui/page-header";
import { requireAgency } from "@/lib/auth/guards";
import { findGuide } from "@/lib/guides";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.agency.help") };
}

export default async function AgencyGuidePage({ params }: { params: Promise<{ slug: string }> }) {
  await requireAgency();
  const t = await getTranslations();
  const guide = findGuide("agency", (await params).slug);
  if (!guide) notFound();
  return (
    <>
      <Link href="/agency/help" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("help.title")}
      </Link>
      <PageHeader title={guide.title} description={guide.summary} />
      <GuideView guide={guide} />
    </>
  );
}
