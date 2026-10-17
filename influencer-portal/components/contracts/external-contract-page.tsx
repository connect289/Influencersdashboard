// The contract page for the creator and their negotiating agency (same view, different back link and base path).
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import {
  CONTRACT_TABS,
  ContractStatusLine,
  ContractView,
} from "@/components/contracts/contract-view";
import { PageHeader } from "@/components/ui/page-header";
import { Banner } from "@/components/ui/states";
import { loadContract } from "@/lib/contracts/data";
import { loadDeal, versionsOf } from "@/lib/deals/data";
import type { ServerSupabase } from "@/lib/supabase/server";

export async function ExternalContractPage({
  supabase,
  contractId,
  search,
  basePath,
  back,
}: {
  supabase: ServerSupabase;
  contractId: string;
  search: { tab?: string; from?: string; to?: string };
  basePath: string;
  back: (c: { creatorId: string; creatorName: string }) => { href: string; label: string };
}) {
  if (!z.uuid().safeParse(contractId).success) notFound();
  const t = await getTranslations();
  const c = await loadContract(supabase, contractId);
  if (!c || c.side === "eduwit") notFound();
  const tab = CONTRACT_TABS.find((x) => x === search.tab) ?? "document";
  const deal = tab === "requests" ? await loadDeal(supabase, c.deal_id) : null;
  const config = deal ? (versionsOf(deal).current?.comp_config ?? null) : null;
  const b = back({ creatorId: c.creator.id, creatorName: c.creator.display_name });
  const hint =
    c.status === "sent" || c.status === "in_negotiation"
      ? t("contracts.my.reviewHint")
      : c.status === "ready_to_sign"
        ? t("contracts.my.readyHint")
        : c.status === "signed_by_creator"
          ? t("contracts.my.countersignHint")
          : null;
  return (
    <>
      <Link
        href={b.href}
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {b.label}
      </Link>
      <PageHeader title={c.deal.title} description={<ContractStatusLine c={c} />} />
      {hint ? <Banner tone="info">{hint}</Banner> : null}
      <ContractView
        c={c}
        supabase={supabase}
        basePath={basePath}
        tab={tab}
        compare={{ from: search.from, to: search.to }}
        config={config}
      />
    </>
  );
}
