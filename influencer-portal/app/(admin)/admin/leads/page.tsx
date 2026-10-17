import Link from "next/link";
import { Search } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { LeadDetailView } from "@/components/leads/lead-detail";
import { LeadDrawer } from "@/components/leads/lead-drawer";
import { LeadsNav } from "@/components/leads/leads-nav";
import { LeadBoard, LeadTable } from "@/components/leads/lead-views";
import { OverrideForm } from "@/components/leads/override-form";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { PageHeader } from "@/components/ui/page-header";
import { Banner, EmptyState, ErrorState, NoResults } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { ATTRIBUTION_STATUSES, type AttributionStatus } from "@/lib/attribution/rules";
import { CREATOR_STAGES } from "@/lib/attribution/stages";
import { listLeads, loadLead, loadOverview } from "@/lib/leads/data";
import { formatDateTime, formatNumber } from "@/lib/format";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.leads") };
}

export default async function AdminLeadsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase, me } = await requireStaff("lead.read");
  const t = await getTranslations();
  const sp = await searchParams;
  const status = (ATTRIBUTION_STATUSES as readonly string[]).includes(sp.status ?? "")
    ? (sp.status as AttributionStatus)
    : null;
  const stage = (CREATOR_STAGES as readonly string[]).includes(sp.stage ?? "") ? sp.stage : null;
  const q = (sp.q ?? "").slice(0, 60);
  const page = Math.max(Number.parseInt(sp.page ?? "1", 10) || 1, 1);
  const includeTest = sp.test === "1";
  const board = sp.layout === "board";
  const [list, overview, lead] = await Promise.all([
    listLeads(supabase, { status: status ? [status] : [], stage, q, page, includeTest }).catch(() => null),
    loadOverview(supabase).catch(() => null),
    sp.lead && /^[0-9a-f-]{36}$/.test(sp.lead) ? loadLead(supabase, sp.lead).catch(() => null) : Promise.resolve(null),
  ]);
  const query = new URLSearchParams(
    Object.entries(sp).filter((e): e is [string, string] => typeof e[1] === "string" && e[0] !== "lead"),
  ).toString();
  const href = (patch: Record<string, string | null>) => {
    const u = new URLSearchParams(query);
    for (const [k, v] of Object.entries(patch)) {
      if (v) u.set(k, v);
      else u.delete(k);
    }
    if (!("page" in patch)) u.delete("page");
    const s = u.toString();
    return s ? `/admin/leads?${s}` : "/admin/leads";
  };
  const canReview = me.permissions.has("attribution.review");
  const pages = list ? Math.max(Math.ceil(list.total / 50), 1) : 1;
  return (
    <>
      <PageHeader
        title={t("nav.admin.leads")}
        description={t("leads.staffSubtitle")}
        help="/admin/help/influencer-manager#leads"
      />
      <LeadsNav current="all" permissions={me.permissions} />
      {overview ? (
        <div className="mb-3 flex flex-wrap gap-2 text-sm">
          {ATTRIBUTION_STATUSES.map((s) => (
            <Link
              key={s}
              href={href({ status: status === s ? null : s })}
              aria-current={status === s ? "page" : undefined}
              className={cn(
                "rounded-lg px-3 py-1.5",
                status === s ? "bg-primary-soft font-medium text-primary" : "bg-surface text-muted hover:bg-surface-2",
              )}
            >
              {t(`leads.status.${s}`)} · {formatNumber(overview.by_status[s] ?? 0)}
            </Link>
          ))}
          {overview.open_flags ? (
            <Link href="/admin/leads/fraud" className="rounded-lg bg-accent-soft px-3 py-1.5 text-accent-ink">
              {t("leads.openFlags", { count: overview.open_flags })}
            </Link>
          ) : null}
        </div>
      ) : null}
      {overview?.unmapped ? (
        <div className="mb-3">
          <Banner tone="warning">{t("leads.unmappedBanner", { count: overview.unmapped })}</Banner>
        </div>
      ) : null}
      <form method="get" action="/admin/leads" className="mb-3 flex flex-wrap gap-2" role="search">
        {status ? <input type="hidden" name="status" value={status} /> : null}
        <label htmlFor="ld-q" className="sr-only">
          {t("leads.filters.search")}
        </label>
        <Input
          id="ld-q"
          name="q"
          defaultValue={q}
          placeholder={t("leads.staffSearch")}
          maxLength={60}
          className="min-w-48 flex-1"
        />
        <select
          name="stage"
          defaultValue={stage ?? ""}
          aria-label={t("leads.filters.stage")}
          className="rounded-xl bg-surface px-3 text-sm ring-1 ring-line-strong"
        >
          <option value="">{t("leads.filters.allStages")}</option>
          {CREATOR_STAGES.map((s) => (
            <option key={s} value={s}>
              {t(`leads.stages.names.${s}`)}
            </option>
          ))}
        </select>
        <label className="inline-flex items-center gap-2 text-sm">
          <input type="checkbox" name="test" value="1" defaultChecked={includeTest} /> {t("leads.includeTest")}
        </label>
        {board ? <input type="hidden" name="layout" value="board" /> : null}
        <Button type="submit" variant="secondary" aria-label={t("leads.filters.search")}>
          <Search />
        </Button>
        <span className="ml-auto flex gap-1">
          {(["table", "board"] as const).map((l) => (
            <Link
              key={l}
              href={href({ layout: l === "board" ? "board" : null })}
              aria-current={(l === "board") === board ? "page" : undefined}
              className={cn(
                "rounded-lg px-3 py-2 text-sm",
                (l === "board") === board
                  ? "bg-primary-soft font-medium text-primary"
                  : "text-muted hover:bg-surface-2",
              )}
            >
              {t(`leads.layout.${l}`)}
            </Link>
          ))}
        </span>
      </form>
      <Card className={board ? "bg-transparent p-0 shadow-none" : undefined}>
        {list === null ? (
          <ErrorState title={t("errors.loadFailed")} />
        ) : list.rows.length === 0 ? (
          q || status || stage ? (
            <NoResults title={t("leads.noResults")} />
          ) : (
            <EmptyState title={t("leads.staffEmpty")} description={t("leads.staffEmptyHint")} />
          )
        ) : board ? (
          <LeadBoard rows={list.rows} base="/admin/leads" query={query} />
        ) : (
          <LeadTable rows={list.rows} base="/admin/leads" query={query} staff />
        )}
      </Card>
      {pages > 1 ? (
        <nav className="mt-3 flex items-center justify-between text-sm" aria-label={t("common.pagination")}>
          {page > 1 ? <Link href={href({ page: String(page - 1) })}>{t("common.previous")}</Link> : <span />}
          <span className="text-muted">{t("contracts.pageOf", { page, pages })}</span>
          {page < pages ? <Link href={href({ page: String(page + 1) })}>{t("common.next")}</Link> : <span />}
        </nav>
      ) : null}
      {overview?.last_sync ? (
        <p className="mt-3 text-xs text-muted">
          {t("leads.lastSync", { at: formatDateTime(overview.last_sync.updated_at) })}
        </p>
      ) : null}
      {lead ? (
        <LeadDrawer title={lead.contact?.name ?? lead.display_name ?? lead.lead_ref}>
          <div className="flex flex-col gap-4">
            {lead.flags_open?.length ? (
              <div className="flex flex-wrap gap-1">
                {lead.flags_open.map((f) => (
                  <Badge key={f.id} family="attention">
                    {t(`leads.signals.${f.signal as "velocity"}`)}
                  </Badge>
                ))}
              </div>
            ) : null}
            <LeadDetailView d={lead} />
            {canReview && lead.student_lead_id !== null ? (
              <OverrideForm
                studentLeadId={lead.student_lead_id}
                creatorId={lead.creator_id}
                canCredit={lead.attribution_status !== "manually_credited"}
                canReject={lead.attribution_status !== "manually_rejected"}
              />
            ) : null}
          </div>
        </LeadDrawer>
      ) : null}
    </>
  );
}
