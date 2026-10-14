import Link from "next/link";
import type { Metadata } from "next";
import { Eye, Search } from "lucide-react";
import { LeadTable } from "@/components/lead/LeadTable";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { assignable, team, type TeamMember } from "@/lib/team";
import type { LeadRow } from "@/lib/types";
import { viewsFor } from "@/lib/views";
import { BulkBar } from "./BulkBar";

export const metadata: Metadata = { title: "Leads" };
const PAGE = 100;

/** Every B2C lead (spec B12.2): standard views, search, bulk tools, the Recycle bin. Marketing reads; the Admin acts. */
export default async function WorkspaceLeads({ searchParams }: { searchParams: Promise<{ v?: string; q?: string; page?: string; bin?: string; test?: string }> }) {
  const me = await requireUser("workspace", "/w/leads");
  const sp = await searchParams;
  const admin = me.role === "admin";
  const bin = sp.bin === "1" && admin;
  const views = await viewsFor("workspace");
  const view = bin ? undefined : views.find((v) => String(v.id) === sp.v) ?? views[0];
  const page = Math.max(0, Number(sp.page ?? 0) || 0);
  let res: { total: number; rows: LeadRow[] };
  let members: TeamMember[] = [];
  try {
    [res, members] = await Promise.all([
      rpc<{ total: number; rows: LeadRow[] }>("lead_list", {
        p: { filters: sp.q ? {} : view?.filters ?? {}, sort: view?.sort ?? { field: "updated_at", dir: "desc" }, search: sp.q ?? "", limit: PAGE, offset: page * PAGE,
             deleted: bin, include_test: sp.test === "1" },
      }),
      admin ? team() : Promise.resolve([]),
    ]);
  } catch (e) {
    return <Page title="Leads"><SetupError error={e} /></Page>;
  }
  const people = assignable(members);
  const qs = (o: Record<string, string | number | undefined>) => {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries({ v: view ? String(view.id) : undefined, q: sp.q, bin: bin ? "1" : undefined, test: sp.test, ...o })) if (v !== undefined && v !== "") q.set(k, String(v));
    return `/w/leads?${q}`;
  };
  return (
    <Page title={bin ? "Recycle bin" : "Leads"} sub={`${res.total} ${bin ? "deleted in the last 30 days can be restored" : view?.name ?? ""}`}
      actions={!admin ? <span className="readonly-flag"><Eye className="icon s" aria-hidden />Read-only for Marketing</span> : undefined}>
      <form className="row wrap" action="/w/leads" role="search">
        <label className="search grow"><Search className="icon s" aria-hidden /><input name="q" defaultValue={sp.q ?? ""} placeholder="Name, any phone, email, application ID" aria-label="Search all leads" /></label>
        {admin && <label className="checkbox"><input type="checkbox" name="test" value="1" defaultChecked={sp.test === "1"} /> Include test leads</label>}
        <button className="btn ghost sm" type="submit">Search</button>
      </form>
      <div className="hscroll">
        {views.map((v) => (
          <Link key={v.id} className="pill" href={`/w/leads?v=${v.id}`} aria-pressed={!bin && !sp.q && view?.id === v.id} style={{ color: "inherit", textDecoration: "none" }}>{v.name}</Link>
        ))}
        {admin && <Link className="pill" href="/w/leads?bin=1" aria-pressed={bin} style={{ color: "inherit", textDecoration: "none" }}>Recycle bin</Link>}
      </div>
      {res.rows.length === 0 ? <Empty>No leads here.</Empty> : <LeadTable rows={res.rows} base="/w/leads" showOwner select />}
      {res.total > PAGE && (
        <div className="pager">
          {page > 0 && <Link className="btn ghost sm" href={qs({ page: page - 1 })}>Previous</Link>}
          <span className="muted">{page * PAGE + 1}–{Math.min(res.total, (page + 1) * PAGE)} of {res.total}</span>
          {(page + 1) * PAGE < res.total && <Link className="btn ghost sm" href={qs({ page: page + 1 })}>Next</Link>}
        </div>
      )}
      {res.rows.length > 0 && <BulkBar people={people} admin={admin} recycle={bin} />}
      {admin && <p className="note">Deletes are soft, with a 30-day Recycle bin. A lead with an enrolment cannot be deleted, only closed.</p>}
    </Page>
  );
}
