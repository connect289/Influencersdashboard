import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { CampaignDetails } from "@/components/campaigns/campaign-details";
import { CampaignForm } from "@/components/campaigns/campaign-form";
import { CampaignStatusActions } from "@/components/campaigns/campaign-status";
import { CampaignTracking } from "@/components/campaigns/campaign-tracking";
import { InviteDialog } from "@/components/campaigns/invite-dialog";
import { WithdrawInviteButton } from "@/components/campaigns/withdraw-invite";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { Table, Td, Th } from "@/components/ui/table";
import { requireStaff } from "@/lib/auth/guards";
import type { CampaignStatus } from "@/lib/campaigns/schemas";
import { deliverablesOf, eligibilityOf, formValuesOf, loadProgrammes } from "@/lib/campaigns/data";
import { loadBriefTemplates } from "@/lib/content/data";
import { templateOptions } from "@/lib/contracts/data";
import { loadPickers } from "@/lib/creators/staff-data";
import { presetOptions } from "@/lib/deals/data";
import { SETTINGS } from "@/lib/settings/registry";
import { formatCompact, formatDateTime, formatPaise, formatRelative } from "@/lib/format";
import { cn } from "@/lib/utils";

const TABS = ["overview", "applications", "invites", "edit"] as const;

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.campaigns") };
}

export default async function CampaignPage({
  params,
  searchParams,
}: {
  params: Promise<{ campaignId: string }>;
  searchParams: Promise<{ tab?: string }>;
}) {
  const { campaignId } = await params;
  if (!z.uuid().safeParse(campaignId).success) notFound();
  const { supabase, me } = await requireStaff("campaign.read");
  const t = await getTranslations();
  const canWrite = me.permissions.has("campaign.write");
  const visible = TABS.filter((x) => x !== "edit" || canWrite);
  const requested = (await searchParams).tab;
  const tab = visible.find((x) => x === requested) ?? "overview";
  const { data: c, error } = await supabase.from("campaigns").select("*").eq("id", campaignId).maybeSingle();
  if (!error && !c) notFound();
  if (!c) return <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />;
  const programmes = await loadProgrammes(supabase, campaignId);
  const status = c.status as CampaignStatus;
  const canInvite = canWrite && ["open", "invite_only", "active"].includes(status);

  let body: React.ReactNode;
  if (tab === "overview") {
    const { data: stats } = await supabase.rpc("campaign_stats", { p_campaign: campaignId });
    const s = (stats ?? {}) as Record<string, number>;
    body = (
      <div className="grid gap-4 lg:grid-cols-[1fr_300px]">
        <CampaignDetails
          description={c.description}
          deliverables={deliverablesOf(c.deliverables)}
          compensation={c.compensation_summary}
          eligibility={eligibilityOf(c.eligibility)}
          startsOn={c.starts_on}
          endsOn={c.ends_on}
          applyBy={c.apply_by}
          programmes={programmes}
        />
        <div className="flex flex-col gap-4">
          <Card>
            <CardHeader title={t("campaigns.details.numbers")} />
            <dl className="grid grid-cols-2 gap-3 text-center">
              {(["to_review", "accepted", "applications", "invites_open"] as const).map((k) => (
                <div key={k}>
                  <dt className="text-xs text-muted">{t(`campaigns.stats.${k}`)}</dt>
                  <dd className="text-2xl font-semibold tabular-nums">{s[k] ?? 0}</dd>
                </div>
              ))}
            </dl>
          </Card>
          <Card>
            <CardHeader title={t("campaigns.details.internal")} />
            <dl className="flex flex-col gap-1.5 text-sm">
              <div className="flex justify-between">
                <dt className="text-muted">{t("campaigns.fields.budget")}</dt>
                <dd className="tabular-nums">
                  {c.budget_paise !== null ? formatPaise(c.budget_paise, { whole: true }) : "—"}
                </dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-muted">{t("campaigns.fields.slots")}</dt>
                <dd>{c.slots ?? "—"}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-muted">{t("campaigns.fields.visibility")}</dt>
                <dd>{t(`campaigns.visibilities.${c.visibility as "open"}`)}</dd>
              </div>
            </dl>
            {c.internal_notes ? (
              <p className="mt-3 text-sm whitespace-pre-line text-muted">{c.internal_notes}</p>
            ) : null}
          </Card>
        </div>
      </div>
    );
  } else if (tab === "applications") {
    const { data: apps } = await supabase.rpc("applications_list", { p_campaign: campaignId });
    body = (
      <Card>
        {!apps?.length ? (
          <EmptyState title={t("campaigns.applicationsEmpty")} description={t("campaigns.applicationsEmptyHint")} />
        ) : (
          <Table>
            <thead>
              <tr>
                <Th>{t("campaigns.application.creator")}</Th>
                <Th>{t("campaigns.table.status")}</Th>
                <Th>{t("creators.table.followers")}</Th>
                <Th>{t("campaigns.application.source")}</Th>
                <Th>{t("campaigns.table.updated")}</Th>
              </tr>
            </thead>
            <tbody>
              {apps.map((a) => (
                <tr key={a.id}>
                  <Td>
                    <Link href={`/admin/applications/${a.id}`} className="font-medium text-primary hover:underline">
                      {a.display_name}
                    </Link>
                    <span className="block text-xs text-muted">@{a.handle}</span>
                  </Td>
                  <Td>
                    <span className="flex flex-col items-start gap-1">
                      <StatusBadge
                        status={a.status}
                        label={t(`campaigns.applicationStatuses.${a.status as "submitted"}`)}
                      />
                      {a.open_offer_from === "creator" ? (
                        <Badge family="attention">{t("campaigns.application.yourMove")}</Badge>
                      ) : null}
                    </span>
                  </Td>
                  <Td className="tabular-nums">{formatCompact(a.followers)}</Td>
                  <Td>{t(`campaigns.application.sources.${a.source as "marketplace"}`)}</Td>
                  <Td>{formatRelative(a.updated_at)}</Td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Card>
    );
  } else if (tab === "invites") {
    const { data: invites } = await supabase
      .from("campaign_invites")
      .select("id, status, sent_at, responded_at, application_id, creators(display_name, handle)")
      .eq("campaign_id", campaignId)
      .order("sent_at", { ascending: false });
    body = (
      <Card>
        <CardHeader
          title={t("campaigns.invites.title")}
          actions={canInvite ? <InviteDialog campaignId={campaignId} /> : null}
        />
        {!invites?.length ? (
          <EmptyState
            title={t("campaigns.invites.empty")}
            description={canInvite ? t("campaigns.invites.emptyHint") : t("campaigns.invites.openFirst")}
          />
        ) : (
          <ul className="flex flex-col divide-y divide-line">
            {invites.map((i) => (
              <li key={i.id} className="flex flex-wrap items-center gap-3 py-3">
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium">{i.creators.display_name}</p>
                  <p className="text-xs text-muted">
                    @{i.creators.handle} · {t("campaigns.invites.sentOn", { date: formatDateTime(i.sent_at) })}
                  </p>
                </div>
                <StatusBadge status={i.status} label={t(`campaigns.invites.statuses.${i.status as "sent"}`)} />
                {i.application_id ? (
                  <Link
                    href={`/admin/applications/${i.application_id}`}
                    className="text-sm text-primary hover:underline"
                  >
                    {t("campaigns.invites.openApplication")}
                  </Link>
                ) : null}
                {canWrite && i.status === "sent" ? <WithdrawInviteButton inviteId={i.id} /> : null}
              </li>
            ))}
          </ul>
        )}
      </Card>
    );
  } else {
    const [{ owners }, presets, templates, briefTemplates, links] = await Promise.all([
      loadPickers(supabase),
      presetOptions(supabase),
      templateOptions(supabase),
      loadBriefTemplates(supabase).then((r) => r.map((x) => ({ id: x.id, name: x.name }))),
      supabase.rpc("setting", { p_key: "attribution.links" }),
    ]);
    const linkSettings = SETTINGS["attribution.links"].schema
      .catch(SETTINGS["attribution.links"].default)
      .parse(links.data);
    body = (
      <div className="flex flex-col gap-4">
        <CampaignForm
          initial={formValuesOf(c, programmes)}
          owners={owners}
          presets={presets}
          templates={templates}
          briefTemplates={briefTemplates}
        />
        <CampaignTracking
          campaignId={campaignId}
          model={c.attribution_model}
          message={c.link_message}
          globalMessage={linkSettings.deep_link_template}
        />
      </div>
    );
  }

  return (
    <>
      <Link href="/admin/campaigns" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.admin.campaigns")}
      </Link>
      <PageHeader
        title={c.name}
        description={t(`campaigns.objectives.${c.objective as "leads"}`)}
        actions={
          <>
            <StatusBadge status={status} label={t(`campaigns.statuses.${status}`)} />
            {canWrite ? <CampaignStatusActions campaignId={campaignId} status={status} /> : null}
            {canInvite && tab !== "invites" ? <InviteDialog campaignId={campaignId} /> : null}
          </>
        }
      />
      <nav
        className="-mx-4 mb-4 flex gap-1 overflow-x-auto border-b border-line px-4 md:mx-0 md:px-0"
        aria-label={t("campaigns.tabs.label")}
      >
        {visible.map((x) => (
          <Link
            key={x}
            href={x === "overview" ? `/admin/campaigns/${campaignId}` : `/admin/campaigns/${campaignId}?tab=${x}`}
            aria-current={tab === x ? "page" : undefined}
            className={cn(
              "-mb-px border-b-2 px-3 py-2 text-sm whitespace-nowrap",
              tab === x ? "border-primary font-medium text-primary" : "border-transparent text-muted hover:text-ink",
            )}
          >
            {t(`campaigns.tabs.${x}`)}
          </Link>
        ))}
      </nav>
      {body}
    </>
  );
}
