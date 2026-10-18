import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { EarningsView } from "@/components/earnings/earnings-view";
import { PayoutThreadDrawer } from "@/components/messaging/payout-thread";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireAgency } from "@/lib/auth/guards";
import { loadEarnings } from "@/lib/ledger/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.earnings") };
}

/** A managed creator's earnings (agencies with the earnings grant). Read only: invoices are the creator's to raise. */
export default async function AgencyEarningsPage({
  params,
  searchParams,
}: {
  params: Promise<{ creatorId: string }>;
  searchParams: Promise<{ payout?: string }>;
}) {
  const [{ creatorId }, sp] = await Promise.all([params, searchParams]);
  if (!z.uuid().safeParse(creatorId).success) notFound();
  const { supabase } = await requireAgency();
  const t = await getTranslations();
  const links = await supabase.rpc("agency_creators");
  const link = (links.data ?? []).find(
    (l) => l.creator_id === creatorId && l.link_status === "active" && l.can_view_earnings,
  );
  if (!link) notFound();
  const data = await loadEarnings(supabase, creatorId).catch(() => null);
  return (
    <>
      <Link
        href={`/agency/creators/${creatorId}`}
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {link.display_name}
      </Link>
      <PageHeader
        title={t("nav.creator.earnings")}
        description={t("earnings.agencySubtitle", { name: link.display_name })}
        help="/agency/help/agency#earnings"
      />
      {data ? (
        <EarningsView
          data={data}
          creatorId={creatorId}
          canUpload={false}
          leadsHref={link.can_view ? `/agency/creators/${creatorId}/leads` : `/agency/creators/${creatorId}`}
        />
      ) : (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      )}
      <PayoutThreadDrawer db={supabase} payoutId={sp.payout} />
    </>
  );
}
