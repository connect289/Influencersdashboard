import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { DealContent } from "@/components/content/deal-content";
import { DealLedger } from "@/components/ledger/deal-ledger";
import { DealActions } from "@/components/deals/deal-actions";
import { DealDetailsForm } from "@/components/deals/deal-details-form";
import { DryRunPanel } from "@/components/deals/dry-run-panel";
import { StaffSimulator } from "@/components/deals/simulator";
import { TermsEditor, type SimulatorProps } from "@/components/deals/terms-editor";
import { TermsSummary } from "@/components/deals/terms-summary";
import { VersionHistory } from "@/components/deals/version-history";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { Banner } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { compConfig } from "@/lib/compensation/schema";
import { contractRowSchema, OPEN_CONTRACT_STATUSES } from "@/lib/contracts/data";
import { loadPickers } from "@/lib/creators/staff-data";
import { commissionEstimate, loadCompContext, loadDeal, loadTdsSections, versionsOf } from "@/lib/deals/data";
import { formatDate, formatDateTime } from "@/lib/format";
import { cn } from "@/lib/utils";

const TABS = ["terms", "versions", "content", "ledger", "dryRun", "details"] as const;
const EMPTY = compConfig.parse({ schema_version: 1 });

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.deals") };
}

export default async function DealPage({
  params,
  searchParams,
}: {
  params: Promise<{ dealId: string }>;
  searchParams: Promise<{ tab?: string }>;
}) {
  const { dealId } = await params;
  if (!z.uuid().safeParse(dealId).success) notFound();
  const { supabase, me } = await requireStaff("deal.read");
  const t = await getTranslations();
  const deal = await loadDeal(supabase, dealId);
  if (!deal) notFound();
  const canWrite = me.permissions.has("deal.write");
  const { current, pending } = versionsOf(deal);
  const contracts = me.permissions.has("contract.read")
    ? await supabase
        .rpc("contracts_list", { p: { deal_id: deal.id, status: [], page_size: 20 } })
        .then((r) => z.object({ rows: z.array(contractRowSchema) }).safeParse(r.data))
        .then((r) => (r.success ? r.data.rows : []))
    : [];
  const activeContract = contracts.find((c) => c.status === "active");
  const canContract =
    me.permissions.has("contract.write") &&
    current !== null &&
    ["agreed", "active"].includes(deal.status) &&
    !contracts.some((c) => (OPEN_CONTRACT_STATUSES as readonly string[]).includes(c.status));
  const draft = deal.draft_config ?? null;
  const amendmentDraft = draft !== null && current !== null;
  const canContent = me.permissions.has("brief.read") || me.permissions.has("deliverable.read");
  const visible = TABS.filter((x) =>
    x === "dryRun"
      ? amendmentDraft && canWrite
      : x === "content"
        ? canContent
        : x === "ledger"
          ? me.permissions.has("ledger.read")
          : x !== "details" || canWrite,
  );
  const requested = (await searchParams).tab;
  const tab = visible.find((x) => x === requested) ?? "terms";

  const simulatorProps = async (): Promise<SimulatorProps> => {
    const [ctx, tds, estimate] = await Promise.all([
      loadCompContext(supabase),
      loadTdsSections(supabase),
      commissionEstimate(deal.campaign_id),
    ]);
    return {
      startsOn: deal.starts_on,
      context: ctx.engine,
      gstRateBps: ctx.gst_rate_bps,
      sections: tds.sections,
      estimatePaise: estimate,
      taxConfirmed: tds.confirmed,
    };
  };

  let body: React.ReactNode;
  if (tab === "terms") {
    const sim = await simulatorProps();
    if (draft && canWrite && !pending) {
      body = (
        <div className="flex flex-col gap-4">
          {amendmentDraft ? <Banner tone="info">{t("deals.amendmentDraft")}</Banner> : null}
          <TermsEditor initial={draft} target={{ kind: "deal", dealId: deal.id }} simulator={sim} />
        </div>
      );
    } else {
      const shown = pending ?? current;
      body = shown ? (
        <div className="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_380px]">
          <Card>
            <CardHeader
              title={
                pending
                  ? t("deals.pendingTerms", { version: pending.version })
                  : t("deals.currentTerms", { version: shown.version })
              }
              description={t("deals.effectiveFrom", { date: formatDateTime(shown.effective_from) })}
            />
            <TermsSummary config={shown.comp_config} />
          </Card>
          <StaffSimulator config={shown.comp_config} {...sim} />
        </div>
      ) : (
        <Card>
          <TermsSummary config={draft ?? EMPTY} />
        </Card>
      );
    }
  } else if (tab === "versions") {
    body = <VersionHistory versions={deal.versions} currentId={deal.current_version_id} />;
  } else if (tab === "content") {
    body = <DealContent supabase={supabase} deal={deal} permissions={me.permissions} />;
  } else if (tab === "ledger") {
    const released = await supabase
      .from("deal_manual_events")
      .select("ref")
      .eq("deal_id", deal.id)
      .eq("kind", "manual_release")
      .then((r) => (r.data ?? []).map((x) => x.ref ?? ""));
    body = (
      <DealLedger
        supabase={supabase}
        dealId={deal.id}
        config={current?.comp_config ?? null}
        released={released}
        permissions={me.permissions}
      />
    );
  } else if (tab === "dryRun" && draft) {
    body = (
      <div className="flex flex-col gap-4">
        <DryRunPanel dealId={deal.id} draft={draft} />
        {deal.runs?.length ? (
          <Card>
            <CardHeader title={t("deals.dryRun.history")} />
            <ul className="flex flex-col gap-1 text-sm">
              {deal.runs.map((r) => (
                <li key={r.id} className="flex justify-between gap-3">
                  <span>{formatDateTime(r.created_at)}</span>
                  <span className="text-muted">
                    {t("deals.dryRun.historyRow", {
                      changes: Number(r.summary.changes ?? 0),
                      delta:
                        typeof r.summary.delta_paise === "number"
                          ? (r.summary.delta_paise / 100).toLocaleString("en-IN")
                          : "0",
                    })}
                  </span>
                </li>
              ))}
            </ul>
          </Card>
        ) : null}
      </div>
    );
  } else {
    const { owners } = await loadPickers(supabase);
    body = (
      <DealDetailsForm
        dealId={deal.id}
        owners={owners}
        datesEditable={deal.status === "draft" || deal.status === "negotiating"}
        initial={{
          title: deal.title,
          startsOn: deal.starts_on,
          endsOn: deal.ends_on ?? "",
          ownerId: deal.owner_id ?? "",
          notes: deal.internal_notes ?? "",
        }}
      />
    );
  }

  return (
    <>
      <Link href="/admin/deals" className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" /> {t("nav.admin.deals")}
      </Link>
      <PageHeader
        title={deal.title}
        description={
          <span className="flex flex-wrap items-center gap-2">
            <span>{deal.code}</span>
            <StatusBadge status={deal.status} label={t(`deals.statuses.${deal.status}`)} />
            <Badge>{t(`deals.models.${deal.deal_model}`)}</Badge>
            <Link href={`/admin/creators/${deal.creator.id}`} className="text-primary hover:underline">
              {deal.creator.display_name}
            </Link>
            {deal.campaign ? (
              <Link href={`/admin/campaigns/${deal.campaign.id}`} className="text-primary hover:underline">
                {deal.campaign.name}
              </Link>
            ) : null}
            <span className="text-muted">
              {formatDate(deal.starts_on)}
              {deal.ends_on ? ` – ${formatDate(deal.ends_on)}` : ""}
            </span>
          </span>
        }
        actions={
          canWrite ? (
            <DealActions
              dealId={deal.id}
              status={deal.status}
              hasDraft={draft !== null}
              pendingVersionId={pending?.id ?? null}
              currentConfig={current?.comp_config ?? null}
              hasVersions={deal.versions.length > 0}
            />
          ) : null
        }
      />
      {contracts.length || canContract ? (
        <div className="mb-3 flex flex-wrap items-center gap-2 text-sm">
          <span className="text-muted">{t("contracts.onDeal")}</span>
          {contracts.map((c) => (
            <Link
              key={c.id}
              href={`/admin/contracts/${c.id}`}
              className="inline-flex items-center gap-1 hover:underline"
            >
              {c.number} <StatusBadge status={c.status} label={t(`contracts.statuses.${c.status}`)} />
            </Link>
          ))}
          {canContract ? (
            <Button asChild size="sm" variant="secondary">
              <Link
                href={`/admin/contracts/new?deal=${deal.id}${activeContract ? `&parent=${activeContract.id}` : ""}`}
              >
                {activeContract ? t("contracts.actions.amend") : t("contracts.generate")}
              </Link>
            </Button>
          ) : null}
        </div>
      ) : null}
      {pending ? <Banner tone="warning">{t("deals.awaitingResponse", { version: pending.version })}</Banner> : null}
      {deal.status_reason && ["terminated", "active"].includes(deal.status) ? (
        <p className="mt-2 text-sm text-muted">{t("deals.statusReason", { reason: deal.status_reason })}</p>
      ) : null}
      <nav className="-mx-4 my-4 flex gap-1 overflow-x-auto px-4 md:mx-0 md:px-0" aria-label={t("deals.sectionsNav")}>
        {visible.map((x) => (
          <Link
            key={x}
            href={`/admin/deals/${deal.id}?tab=${x}`}
            aria-current={tab === x ? "page" : undefined}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap",
              tab === x ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
            )}
          >
            {t(`deals.tabs.${x}`)}
          </Link>
        ))}
      </nav>
      {body}
    </>
  );
}
