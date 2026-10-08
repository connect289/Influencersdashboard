import type { Metadata } from "next";
import Link from "next/link";
import { Download, FlaskConical, Inbox, Trash2, Users } from "lucide-react";
import { buttonClass } from "@/components/ui/Button";
import { Card, EmptyState, PageHeader } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { requireAdmin } from "@/lib/auth";
import {
  CLEAR_FILTERS, DESTINATION_HINT, DESTINATION_LABEL, FLAG_DESTINATIONS, PAID_FILTER_LABEL, hasFilters, leadsHref, leadsSearch, parseLeadId, parseLeadQuery,
} from "@/lib/leads";
import { leadDetail, leadEditHistory, leadFacets, listLeads } from "@/lib/leads-data";
import { leadRouting } from "@/lib/routing-data";
import { leadPartnerSync } from "@/lib/sync-data";
import { FilterBar } from "./FilterBar";
import { LeadDrawer } from "./LeadDrawer";
import { LeadsTable } from "./LeadsTable";
import { SearchBox } from "./SearchBox";

export const metadata: Metadata = { title: "Leads" };

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const DEFAULT_DESCRIPTION =
  "Every lead from every source: Witty, the website, imports and the API. Junk and programme-mismatch leads are in the Not passed view; the Flags filters show partner-barred, qualifying, consent-pending, re-enquired and lost-in-grace leads. Paid is a Meta / Google label and never changes routing.";

export default async function LeadsPage({ searchParams }: Props) {
  await requireAdmin();
  const sp = await searchParams;
  const query = parseLeadQuery(sp);
  const leadId = parseLeadId(sp);
  const [page, facets, detail, routing, history, sync] = await Promise.all([
    listLeads(query),
    leadFacets(query),
    leadId ? leadDetail(leadId) : Promise.resolve(null),
    // The drawer still opens if routing details fail to load; its Routing tab says so.
    leadId ? leadRouting(leadId).catch(() => null) : Promise.resolve(null),
    leadId ? leadEditHistory(leadId).catch(() => null) : Promise.resolve(null),
    leadId ? leadPartnerSync(leadId).catch(() => null) : Promise.resolve(null),
  ]);
  const search = leadsSearch(query);
  const filtered = hasFilters(query);
  // A named view: the Not passed list or one of the Addendum 3 flags (the four routing destinations stay plain filters).
  const view = !query.bin && query.dest && (query.dest === "not_passed" || (FLAG_DESTINATIONS as readonly string[]).includes(query.dest)) ? query.dest : null;
  const title = query.bin ? "Recycle bin" : view ? DESTINATION_LABEL[view] ?? "Leads" : "Leads";
  const description = query.bin
    ? "Deleted leads stay here and can be restored. If a deleted student messages Witty again, a new lead is created."
    : `${(view && DESTINATION_HINT[view]) || DEFAULT_DESCRIPTION}${query.paid ? ` Showing paid leads only (${PAID_FILTER_LABEL[query.paid]}).` : ""}`;

  return (
    <>
      <PageHeader
        title={title}
        description={description}
        actions={
          <>
            <Link href={leadsHref(query, { bin: !query.bin })} className={buttonClass("secondary", "sm")}>
              {query.bin ? <><Users className="size-3.5" /> Back to leads</> : <><Trash2 className="size-3.5" /> Recycle bin{facets.bin > 0 && <span className="tabular text-subtle">{facets.bin}</span>}</>}
            </Link>
            {!query.bin && (
              <details className="relative">
                <summary className={cn(buttonClass("secondary", "sm"), "cursor-pointer list-none [&::-webkit-details-marker]:hidden")}>
                  <Download className="size-3.5" /> Export
                </summary>
                <div className="absolute right-0 z-20 mt-1.5 w-64 overflow-hidden rounded-lg border border-border bg-surface p-1 shadow-lg animate-fade-in">
                  <a href={`/leads/export${search}`} className="block rounded-md px-3 py-2 text-[13px] text-fg hover:bg-surface-hover">
                    CSV with phone and email
                    <span className="block text-[12px] text-subtle">Current filters, up to 50,000 rows; large files keep downloading while you work</span>
                  </a>
                  <a href={`/leads/export${search ? `${search}&` : "?"}masked=1`} className="block rounded-md px-3 py-2 text-[13px] text-fg hover:bg-surface-hover">
                    Masked CSV
                    <span className="block text-[12px] text-subtle">Phone shows last 4 digits, email first letter</span>
                  </a>
                  <p className="border-t border-border px-3 py-2 text-[11.5px] text-subtle">Every export is logged.</p>
                </div>
              </details>
            )}
          </>
        }
      />

      <Card className="overflow-hidden">
        <div className="flex flex-wrap items-center gap-3 border-b border-border px-4 py-3">
          <SearchBox initial={query.q} search={search} />
          <Link
            href={leadsHref(query, { test: !query.test })}
            className={cn(
              "inline-flex h-9 items-center gap-1.5 rounded-lg border px-3 text-[13px] transition-colors",
              query.test ? "border-amber/40 bg-amber/10 text-navy dark:text-amber" : "border-border text-muted hover:bg-surface-hover hover:text-fg",
            )}
            aria-pressed={query.test}
          >
            <FlaskConical className="size-3.5" /> Test leads
            {facets.tests > 0 && <span className="tabular text-subtle">{facets.tests}</span>}
          </Link>
          <p className="ml-auto text-[12.5px] text-muted" aria-live="polite">
            <span className="tabular font-medium text-fg">{page.total ?? 0}</span> {page.total === 1 ? "lead" : "leads"}
            {filtered && " match"}
          </p>
        </div>

        <FilterBar query={query} facets={facets} />

        {page.rows.length === 0 ? (
          <EmptyState
            icon={query.bin ? Trash2 : Inbox}
            title={filtered ? "No leads match these filters" : query.bin ? "The recycle bin is empty" : "No leads yet"}
            action={filtered ? <Link href={leadsHref(query, CLEAR_FILTERS)} className={buttonClass("secondary", "sm")}>Clear filters</Link> : undefined}
          >
            {!filtered && !query.bin && (
              <p>New leads appear here as soon as a student sends Witty their first message after the access code, or arrive from the website, an import or the API.{facets.tests > 0 && " Test leads are hidden; use the Test leads switch to see them."}</p>
            )}
          </EmptyState>
        ) : (
          <LeadsTable key={search} search={search} query={query} initial={page} openId={leadId} />
        )}
      </Card>

      {leadId && <LeadDrawer key={leadId} id={leadId} detail={detail} routing={routing} history={history} sync={sync} closeHref={leadsHref(query)}
        initialTab={typeof sp.tab === "string" ? sp.tab : undefined} />}
    </>
  );
}
