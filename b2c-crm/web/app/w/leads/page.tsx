import Link from "next/link";
import type { Metadata } from "next";
import { Download, Eye, Pin, Search } from "lucide-react";
import { DensityToggle } from "@/components/lead/Density";
import { GroupSummary } from "@/components/lead/GroupSummary";
import { Kanban } from "@/components/lead/Kanban";
import { LeadTable } from "@/components/lead/LeadTable";
import { LiveRefresh } from "@/components/lead/LiveRefresh";
import { ViewBuilder } from "@/components/lead/ViewBuilder";
import { GroupBySelect, ViewTools } from "@/components/lead/ViewTools";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { plural } from "@/lib/format";
import { assignable, team, type TeamMember } from "@/lib/team";
import type { LeadList } from "@/lib/types";
import { stagesAndSubs } from "@/lib/stages";
import { createClient } from "@/lib/supabase/server";
import { fieldsFor, GROUPABLE } from "@/lib/viewFields";
import { pickView, viewsFor } from "@/lib/views";
import { BulkBar } from "./BulkBar";
import { ExportsPanel, JobsPanel, type BulkJob, type ExportRow } from "./Jobs";

export const metadata: Metadata = { title: "Leads" };
const PAGE = 100;

type SP = { view?: string; v?: string; q?: string; page?: string; bin?: string; test?: string; drill?: string; dl?: string; layout?: string; group?: string;
  exports?: string; deleted?: string; queued?: string; rows?: string };

/**
 * Every B2C lead (spec B10.1, B12.2): views with groups of conditions, chosen columns, group-by with totals, list or board,
 * search, bulk tools over ticked rows or the whole view, exports and background jobs, the Recycle bin. The Admin acts;
 * Marketing reads, tags and manages journey membership.
 */
export default async function WorkspaceLeads({ searchParams }: { searchParams: Promise<SP> }) {
  const me = await requireUser("workspace", "/w/leads");
  const sp = await searchParams;
  const admin = me.role === "admin";
  const money = admin || me.role === "marketing";
  const bin = sp.bin === "1" && admin;
  const drill = sp.drill && /^[0-9a-f-]{36}$/i.test(sp.drill) ? sp.drill : undefined;
  let list: Awaited<ReturnType<typeof viewsFor>>;
  let stagesSubs: Awaited<ReturnType<typeof stagesAndSubs>>;
  try {
    [list, stagesSubs] = await Promise.all([viewsFor("workspace"), stagesAndSubs()]);
  } catch (e) {
    return <Page title="Leads"><SetupError error={e} /></Page>;
  }
  const { stages, subs } = stagesSubs;
  const { view, refused } = bin ? { view: undefined, refused: null } : await pickView(list, sp.view ?? sp.v);
  const kanban = !bin && (sp.layout ?? view?.layout) === "kanban";
  const groupBy = bin || sp.group === "none" ? "" : sp.group ?? view?.group_by ?? "";
  const page = Math.max(0, Number(sp.page ?? 0) || 0);
  const query = { filters: sp.q || drill ? {} : view?.filters ?? {}, search: sp.q ?? "", include_test: drill ? undefined : sp.test === "1", drill, deleted: bin };
  const supabase = await createClient();
  let res: LeadList;
  let members: TeamMember[] = [];
  let jobs: BulkJob[] = [];
  let exports: ExportRow[] = [];
  let journeys: { id: number; name: string }[] = [];
  try {
    [res, members, jobs, exports, journeys] = await Promise.all([
      rpc<LeadList>("lead_list", { p: { ...query, sort: view?.sort ?? { field: "updated_at", dir: "desc" }, limit: kanban ? 500 : PAGE, offset: kanban ? 0 : page * PAGE, group_by: groupBy || undefined } }),
      admin ? team() : Promise.resolve([]),
      admin ? rpc<BulkJob[]>("bulk_jobs_list").catch(() => []) : Promise.resolve([]),
      admin ? rpc<ExportRow[]>("exports_mine").catch(() => []) : Promise.resolve([]),
      supabase.from("journeys").select("id, name").gt("current_version", 0).neq("status", "archived").order("name").then((r) => (r.data ?? []) as { id: number; name: string }[]),
    ]);
  } catch (e) {
    return <Page title="Leads"><SetupError error={e} /></Page>;
  }
  const people = assignable(members);
  const params = (o: Record<string, string | number | undefined>) => {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries({ view: view && !drill && !bin ? String(view.id) : undefined, q: sp.q, bin: bin ? "1" : undefined, test: sp.test, drill, dl: drill ? sp.dl : undefined,
      layout: sp.layout, group: sp.group, ...o })) if (v !== undefined && v !== "") q.set(k, String(v));
    return q;
  };
  const qs = (o: Record<string, string | number | undefined>) => `/w/leads?${params(o)}`;
  const allowed = fieldsFor("workspace", money).map((f) => f.field);
  const groupHrefs = Object.fromEntries([["", qs({ group: "none", page: undefined })], ...GROUPABLE.map((g) => [g, qs({ group: g, page: undefined })])]);
  const exportQuery = params({ layout: undefined, group: undefined, bin: undefined, dl: undefined }).toString();
  const mine = !!view && (view.mine || (view.is_standard && admin));
  const runningJobs = jobs.filter((j) => j.status === "queued" || j.status === "running").length;

  return (
    <Page title={bin ? "Recycle bin" : "Leads"} sub={`${res.total} ${bin ? "deleted in the last 30 days can be restored" : drill ? `behind “${(sp.dl ?? "a number").slice(0, 80)}”` : view?.name ?? ""}`}
      actions={!admin ? <span className="readonly-flag"><Eye className="icon s" aria-hidden />Marketing: tags and journeys</span> : undefined}>
      {drill && <div className="banner info"><div className="grow">These are the {res.total} leads behind the number you opened in Analytics.</div><Link className="btn ghost sm" href="/w/leads">All leads</Link></div>}
      {refused && <div className="banner danger" role="alert">{refused}</div>}
      {sp.queued && <div className="banner info" role="status"><div className="grow">Your export of {sp.rows ? plural(Number(sp.rows), "row") : "this view"} is being written in the background. It appears under <b>Exports</b> below and you get an alert when it is ready; the link then works for 7 days.</div></div>}
      <form className="row wrap" action="/w/leads" role="search">
        <label className="search grow"><Search className="icon s" aria-hidden /><input name="q" defaultValue={sp.q ?? ""} placeholder="Name, any phone, email, application ID" aria-label="Search all leads" /></label>
        {admin && <label className="checkbox"><input type="checkbox" name="test" value="1" defaultChecked={sp.test === "1"} /> Include test leads</label>}
        <button className="btn ghost sm" type="submit">Search</button>
      </form>
      <div className="hscroll">
        {list.views.map((v) => (
          <Link key={v.id} className="pill" href={`/w/leads?view=${v.id}`} aria-pressed={!bin && !sp.q && !drill && view?.id === v.id} style={{ color: "inherit", textDecoration: "none" }}>
            {list.defaultId === v.id && <Pin className="icon s" aria-label="Your default" />}{v.name}{v.shared_with_role && !v.mine ? ` · ${v.owner ?? "shared"}` : ""}
          </Link>
        ))}
        {view && !list.views.some((v) => v.id === view.id) && <span className="pill" aria-pressed="true">{view.name}</span>}
        {admin && <Link className="pill" href="/w/leads?bin=1" aria-pressed={bin} style={{ color: "inherit", textDecoration: "none" }}>Recycle bin</Link>}
      </div>
      {!bin && (
        <div className="row wrap" style={{ gap: 6 }}>
          <ViewBuilder role="workspace" base="/w/leads" stages={stages} admin={admin} money={money} myRole={me.role} />
          {view && !sp.q && mine && <ViewBuilder key={view.id} role="workspace" base="/w/leads" stages={stages} view={view} admin={admin} money={money} myRole={me.role} />}
          {view && !drill && <ViewTools role="workspace" base="/w/leads" viewId={view.id} pinned={list.defaultId === view.id} shareable={view.is_standard || !!view.shared_with_role} />}
          <span className="pills" role="group" aria-label="Show as">
            <Link className="pill" href={qs({ layout: "list", page: undefined })} aria-pressed={!kanban} style={{ color: "inherit", textDecoration: "none" }}>List</Link>
            <Link className="pill" href={qs({ layout: "kanban", page: undefined })} aria-pressed={kanban} style={{ color: "inherit", textDecoration: "none" }}>Board</Link>
          </span>
          <GroupBySelect value={groupBy} href={groupHrefs} allowed={allowed} />
          <DensityToggle />
          <LiveRefresh />
          <Link className="btn ghost sm" href="/w/leads/duplicates">Duplicate suspects</Link>
          {admin && <Link className="btn ghost sm" href="/w/leads/flagged">Flagged</Link>}
          {admin && <Link className="btn ghost sm" href="/w/qualify">To qualify</Link>}
          {admin && !drill && <a className="btn ghost sm" href={`/w/leads/export?${exportQuery}&format=xlsx`}><Download className="icon s" aria-hidden />Excel</a>}
          {admin && !drill && <a className="btn ghost sm" href={`/w/leads/export?${exportQuery}&format=csv`}><Download className="icon s" aria-hidden />CSV</a>}
        </div>
      )}
      {res.groups && res.group_by && res.total > 0 && <GroupSummary groups={res.groups} by={res.group_by} total={res.total} />}
      {res.rows.length === 0 ? <Empty>No leads match this view. Test leads are shown only with “Include test leads”.</Empty>
        : kanban ? (
          <>
            <Kanban rows={res.rows} stages={stages} subs={subs} base="/w/leads" canWork={admin} canMoveBack={admin} showOwner />
            {res.total > res.rows.length && <p className="note">The board shows the first {res.rows.length} of {res.total}; leads in the pool or closed are not on it. Narrow the view, or use the list.</p>}
          </>
        ) : <LeadTable rows={res.rows} base="/w/leads" showOwner select columns={view?.columns} money={money} />}
      {!kanban && res.total > PAGE && (
        <div className="pager">
          {page > 0 && <Link className="btn ghost sm" href={qs({ page: page - 1 })}>Previous</Link>}
          <span className="muted">{page * PAGE + 1}–{Math.min(res.total, (page + 1) * PAGE)} of {res.total}</span>
          {(page + 1) * PAGE < res.total && <Link className="btn ghost sm" href={qs({ page: page + 1 })}>Next</Link>}
        </div>
      )}
      {!kanban && res.rows.length > 0 && (
        <BulkBar people={people} admin={admin} recycle={bin} total={res.total} query={query} journeys={journeys} stages={stages} subs={subs} exportQuery={drill ? null : exportQuery} />
      )}
      {admin && (
        <>
          <JobsPanel jobs={jobs} open={sp.deleted === "1" || runningJobs > 0} />
          <ExportsPanel rows={exports} open={sp.exports === "1" || !!sp.queued} />
          <p className="note">Deletes are soft, with a 30-day Recycle bin; a bulk delete runs in the background and can be undone for 30 days. A lead with an enrolment cannot be deleted, only closed. Erasure on a student&apos;s request is on the lead&apos;s Admin tools.</p>
        </>
      )}
    </Page>
  );
}
