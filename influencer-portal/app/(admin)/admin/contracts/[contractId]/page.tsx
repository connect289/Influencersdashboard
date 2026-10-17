import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { ContractActions } from "@/components/contracts/contract-actions";
import {
  CONTRACT_TABS,
  ContractStatusLine,
  ContractView,
} from "@/components/contracts/contract-view";
import { PageHeader } from "@/components/ui/page-header";
import { requireStaff } from "@/lib/auth/guards";
import { loadContract, loadContractSource } from "@/lib/contracts/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.contracts") };
}

export default async function AdminContractPage({
  params,
  searchParams,
}: {
  params: Promise<{ contractId: string }>;
  searchParams: Promise<{ tab?: string; from?: string; to?: string }>;
}) {
  const { contractId } = await params;
  if (!z.uuid().safeParse(contractId).success) notFound();
  const { supabase, me } = await requireStaff("contract.read");
  const t = await getTranslations();
  const c = await loadContract(supabase, contractId);
  if (!c) notFound();
  const sp = await searchParams;
  const tab = CONTRACT_TABS.find((x) => x === sp.tab) ?? "document";
  // The deal's terms in force, for the counter-offer lines (staff with contract.write only).
  const src =
    me.permissions.has("contract.write") && tab === "requests"
      ? await loadContractSource(supabase, c.deal_id)
      : null;
  return (
    <>
      <Link
        href="/admin/contracts"
        className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" /> {t("nav.admin.contracts")}
      </Link>
      <PageHeader
        title={`${c.creator.display_name} · ${c.deal.title}`}
        description={
          <span className="flex flex-wrap items-center gap-2">
            <ContractStatusLine c={c} />
            <Link href={`/admin/deals/${c.deal.id}`} className="text-primary hover:underline">
              {c.deal.code}
            </Link>
          </span>
        }
        help="/admin/help/influencer-manager#contracts"
        actions={
          c.can_write ? (
            <ContractActions
              contractId={c.id}
              dealId={c.deal.id}
              status={c.status}
              hasVersion={c.current !== null}
              pendingRequests={c.requests.filter((r) => r.status === "pending").length}
            />
          ) : null
        }
      />
      <ContractView
        c={c}
        supabase={supabase}
        basePath="/admin/contracts"
        tab={tab}
        compare={{ from: sp.from, to: sp.to }}
        config={src?.deal.comp_config ?? null}
      />
    </>
  );
}
