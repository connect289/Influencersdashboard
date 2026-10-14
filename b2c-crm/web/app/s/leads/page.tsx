import Link from "next/link";
import type { Metadata } from "next";
import { Search } from "lucide-react";
import { LeadTable } from "@/components/lead/LeadTable";
import { ViewBuilder } from "@/components/lead/ViewBuilder";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import type { LeadRow } from "@/lib/types";
import { stagesAndSubs } from "@/lib/stages";
import { viewsFor } from "@/lib/views";
import { NewLeadButton } from "./NewLead";

export const metadata: Metadata = { title: "Leads" };

const PAGE = 50;

/** My leads (spec B8.4): saved views as pills, search by name, any phone, email or application ID. */
export default async function LeadsPage({ searchParams }: { searchParams: Promise<{ v?: string; q?: string; page?: string }> }) {
  const me = await requireUser("sales", "/s/leads");
  const sp = await searchParams;
  const [views, { stages }] = await Promise.all([viewsFor("sales"), stagesAndSubs()]);
  const view = views.find((v) => String(v.id) === sp.v) ?? views.find((v) => v.name === "Due now") ?? views[0];
  const page = Math.max(0, Number(sp.page ?? 0) || 0);
  let res: { total: number; rows: LeadRow[] };
  try {
    res = await rpc("lead_list", { p: { filters: sp.q ? {} : view?.filters ?? {}, sort: view?.sort, search: sp.q ?? "", limit: PAGE, offset: page * PAGE } });
  } catch (e) {
    return <Page title="Leads"><SetupError error={e} /></Page>;
  }
  const link = (o: Record<string, string | number | undefined>) => {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries({ v: view ? String(view.id) : undefined, q: sp.q, ...o })) if (v !== undefined && v !== "") q.set(k, String(v));
    return `/s/leads?${q}`;
  };
  return (
    <Page title="Leads" sub={`${res.total} ${sp.q ? "found" : view?.name ?? ""}`} actions={<NewLeadButton />}>
      <form className="search" action="/s/leads" role="search">
        <Search className="icon s" aria-hidden />
        <input name="q" defaultValue={sp.q ?? ""} placeholder="Name, any phone, email, application ID" aria-label="Search leads" />
      </form>
      <div className="hscroll" role="tablist" aria-label="Views">
        {views.map((v) => (
          <Link key={v.id} className="pill" href={`/s/leads?v=${v.id}`} aria-pressed={!sp.q && view?.id === v.id} style={{ textDecoration: "none", color: "inherit" }}>
            {v.name}
          </Link>
        ))}
      </div>
      <div className="row" style={{ gap: 6 }}>
        <ViewBuilder role="sales" base="/s/leads" stages={stages} />
        {view && !view.is_standard && view.owner_id === me.user_id && !sp.q && <ViewBuilder key={view.id} role="sales" base="/s/leads" stages={stages} view={view} />}
      </div>
      {res.rows.length === 0 ? <Empty>No leads here.</Empty> : <LeadTable rows={res.rows} base="/s/leads" />}
      {res.total > PAGE && (
        <div className="pager">
          {page > 0 && <Link className="btn ghost sm" href={link({ page: page - 1 })}>Previous</Link>}
          <span className="muted">{page * PAGE + 1}–{Math.min(res.total, (page + 1) * PAGE)} of {res.total}</span>
          {(page + 1) * PAGE < res.total && <Link className="btn ghost sm" href={link({ page: page + 1 })}>Next</Link>}
        </div>
      )}
    </Page>
  );
}
