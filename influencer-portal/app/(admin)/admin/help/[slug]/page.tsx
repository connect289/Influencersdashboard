import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { GuideView } from "@/components/help/guide-view";
import { PageHeader } from "@/components/ui/page-header";
import { requireStaff } from "@/lib/auth/guards";
import { findGuide } from "@/lib/guides";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.help") };
}

export default async function AdminGuidePage({ params }: { params: Promise<{ slug: string }> }) {
  const { me } = await requireStaff();
  const t = await getTranslations();
  const guide = findGuide("admin", (await params).slug, me.permissions);
  if (!guide) notFound();
  return (
    <>
      <Link href="/admin/help" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("help.title")}
      </Link>
      <PageHeader title={guide.title} description={guide.summary} />
      <GuideView guide={guide} />
    </>
  );
}
