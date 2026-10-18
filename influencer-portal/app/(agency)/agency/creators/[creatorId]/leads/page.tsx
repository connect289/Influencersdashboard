import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { LeadPipeline } from "@/components/leads/lead-pipeline";
import { PageHeader } from "@/components/ui/page-header";
import { requireAgency } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.leads") };
}

/** A managed creator's leads (agencies with the view grant), masked exactly as the creator sees them. */
export default async function AgencyLeadsPage({
  params,
  searchParams,
}: {
  params: Promise<{ creatorId: string }>;
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { creatorId } = await params;
  if (!z.uuid().safeParse(creatorId).success) notFound();
  const { supabase } = await requireAgency();
  const t = await getTranslations();
  const links = await supabase.rpc("agency_creators");
  const link = (links.data ?? []).find((l) => l.creator_id === creatorId && l.link_status === "active" && l.can_view);
  if (!link) notFound();
  return (
    <>
      <Link
        href={`/agency/creators/${creatorId}`}
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {link.display_name}
      </Link>
      <PageHeader
        title={t("nav.creator.leads")}
        description={t("leads.agencySubtitle", { name: link.display_name })}
        help="/agency/help/agency#leads"
      />
      <LeadPipeline
        supabase={supabase}
        creatorId={creatorId}
        base={`/agency/creators/${creatorId}/leads`}
        search={await searchParams}
      />
    </>
  );
}
