// A creator's lead pipeline (creator and agency views): filters, board or table, the drawer, Realtime and export.
import { Download } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Button } from "@/components/ui/button";
import { EmptyState, ErrorState, NoResults } from "@/components/ui/states";
import { loadFeed, loadLead, loadViews, parseFilters, type FeedRow } from "@/lib/leads/data";
import type { ServerSupabase } from "@/lib/supabase/server";
import { LeadDetailView } from "./lead-detail";
import { LeadDrawer } from "./lead-drawer";
import { LeadFilters } from "./lead-filters";
import { LeadBoard, LeadTable } from "./lead-views";
import { RealtimeRefresh } from "./realtime-refresh";

const pairs = (
  rows: FeedRow[],
  id: (r: FeedRow) => string | null,
  label: (r: FeedRow) => string | null,
): [string, string][] => {
  const m = new Map<string, string>();
  for (const r of rows) {
    const k = id(r);
    if (k && !m.has(k)) m.set(k, label(r) ?? k);
  }
  return [...m.entries()];
};

export async function LeadPipeline({
  supabase,
  creatorId,
  base,
  search,
}: {
  supabase: ServerSupabase;
  creatorId: string;
  base: string;
  search: Record<string, string | undefined>;
}) {
  const t = await getTranslations();
  const filters = parseFilters(search);
  const [rows, all, views, lead] = await Promise.all([
    loadFeed(supabase, creatorId, filters).catch(() => null),
    loadFeed(supabase, creatorId, parseFilters({}), 1000).catch(() => []),
    loadViews(supabase),
    search.lead && /^[0-9a-f-]{36}$/.test(search.lead)
      ? loadLead(supabase, search.lead).catch(() => null)
      : Promise.resolve(null),
  ]);
  const query = new URLSearchParams(
    Object.entries(search).filter((e): e is [string, string] => typeof e[1] === "string" && e[0] !== "lead"),
  ).toString();
  const filtered = Object.values(filters).some((v) => v !== null);
  const options = {
    campaigns: pairs(
      all,
      (r) => r.campaign_id,
      (r) => r.campaign_name,
    ),
    deals: pairs(
      all,
      (r) => r.deal_id,
      (r) => r.deal_title,
    ),
    deliverables: pairs(
      all,
      (r) => r.deliverable_id,
      (r) => r.deliverable_title,
    ),
    programmes: pairs(
      all,
      (r) => (r.programme_id === null ? null : String(r.programme_id)),
      (r) => r.programme_name,
    ),
    links: pairs(
      all,
      (r) => r.link_id,
      (r) => (r.link_label ? `${r.code} · ${r.link_label}` : r.code),
    ),
  };
  return (
    <>
      <RealtimeRefresh creatorId={creatorId} />
      <div className="mb-2 flex justify-end">
        <Button asChild size="sm" variant="ghost">
          <a href={`/api/leads/export?creator=${creatorId}${query ? `&${query}` : ""}`}>
            <Download /> {t("leads.export")}
          </a>
        </Button>
      </div>
      <LeadFilters options={options} views={views} canShare={false} />
      {rows === null ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : rows.length === 0 ? (
        filtered ? (
          <NoResults title={t("leads.noResults")} />
        ) : (
          <EmptyState title={t("leads.empty")} description={t("leads.emptyHint")} />
        )
      ) : search.layout === "table" ? (
        <div className="rounded-[var(--radius-card)] bg-surface p-2 shadow-[var(--shadow-card)]">
          <LeadTable rows={rows} base={base} query={query} />
        </div>
      ) : (
        <LeadBoard rows={rows} base={base} query={query} />
      )}
      {lead ? (
        <LeadDrawer title={lead.removed ? t("leads.removed") : (lead.display_name ?? lead.lead_ref)}>
          <LeadDetailView d={lead} />
        </LeadDrawer>
      ) : null}
    </>
  );
}
