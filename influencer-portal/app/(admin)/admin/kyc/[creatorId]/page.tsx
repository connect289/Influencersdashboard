import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { KycReview } from "@/components/creator-profile/kyc-review";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadKyc } from "@/lib/creators/load";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.kyc") };
}

export default async function KycReviewPage({ params }: { params: Promise<{ creatorId: string }> }) {
  const { creatorId } = await params;
  if (!z.uuid().safeParse(creatorId).success) notFound();
  const { supabase, me } = await requireStaff("kyc.read_masked");
  const t = await getTranslations();
  const [creator, kyc] = await Promise.all([
    supabase.from("creators").select("display_name, handle").eq("id", creatorId).maybeSingle(),
    loadKyc(supabase, creatorId),
  ]);
  if (!creator.error && !creator.data) notFound();
  return (
    <>
      <Link href="/admin/kyc" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("kyc.queue.back")}
      </Link>
      <PageHeader
        title={creator.data ? creator.data.display_name : t("kyc.title")}
        description={creator.data ? `@${creator.data.handle}` : undefined}
      />
      {kyc && !creator.error ? (
        <KycReview
          creatorId={creatorId}
          kyc={kyc}
          canReveal={me.permissions.has("kyc.reveal")}
          canVerify={me.permissions.has("kyc.verify")}
        />
      ) : (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      )}
    </>
  );
}
