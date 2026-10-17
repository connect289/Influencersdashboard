import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { NewContractForm } from "@/components/contracts/new-contract-form";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { Banner, EmptyState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadContractSource, templateOptions } from "@/lib/contracts/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("contracts.new.title") };
}

export default async function NewContractPage({
  searchParams,
}: {
  searchParams: Promise<{ deal?: string; parent?: string }>;
}) {
  const sp = await searchParams;
  if (!z.uuid().safeParse(sp.deal).success) notFound();
  const dealId = z.uuid().parse(sp.deal);
  const { supabase } = await requireStaff("contract.write");
  const t = await getTranslations();
  const [src, tpls] = await Promise.all([loadContractSource(supabase, dealId), templateOptions(supabase)]);
  if (!src) notFound();
  const active = src.contracts.find((c) => c.status === "active") ?? null;
  const openOne = src.contracts.find((c) =>
    ["draft", "sent", "in_negotiation", "ready_to_sign", "signed_by_creator"].includes(c.status),
  );
  const parent = sp.parent && active?.id === sp.parent ? { id: active.id, number: active.number } : null;
  const preferred =
    tpls.find((x) => x.id === src.campaign?.contract_template_id) ?? tpls.find((x) => x.is_default) ?? tpls[0];
  const back = (
    <Link
      href={`/admin/deals/${dealId}`}
      className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
    >
      <ArrowLeft className="size-4" /> {src.deal.title}
    </Link>
  );
  let blocker: string | null = null;
  if (!src.deal.comp_config) blocker = t("contracts.errors.noTerms");
  else if (openOne) blocker = t("contracts.new.openExists", { number: openOne.number });
  else if (active && !parent) blocker = t("contracts.new.activeExists", { number: active.number });
  else if (!preferred) blocker = t("contracts.new.noTemplate");
  return (
    <>
      {back}
      <PageHeader
        title={parent ? t("contracts.new.amendTitle") : t("contracts.new.title")}
        description={t("contracts.new.subtitle", {
          deal: `${src.deal.code} · ${src.creator.display_name}`,
        })}
        help="/admin/help/influencer-manager#contracts"
      />
      {blocker || !preferred ? (
        <Card>
          <EmptyState
            title={blocker ?? t("contracts.new.noTemplate")}
            action={
              openOne ? (
                <Link className="text-primary hover:underline" href={`/admin/contracts/${openOne.id}`}>
                  {t("contracts.new.openIt")}
                </Link>
              ) : active && !parent ? (
                <Link
                  className="text-primary hover:underline"
                  href={`/admin/contracts/new?deal=${dealId}&parent=${active.id}`}
                >
                  {t("contracts.actions.amend")}
                </Link>
              ) : undefined
            }
          />
        </Card>
      ) : (
        <div className="flex flex-col gap-4">
          {!src.creator.legal_name ? <Banner tone="warning">{t("contracts.new.noLegalName")}</Banner> : null}
          <NewContractForm
            dealId={dealId}
            templates={tpls.map((x) => ({ id: x.id, name: x.name }))}
            defaultTemplateId={preferred.id}
            agencies={src.agencies}
            parent={parent}
            startsOn={src.deal.starts_on}
            endsOn={src.deal.ends_on}
            renewal={src.deal.renewal_of !== null}
          />
        </div>
      )}
    </>
  );
}
