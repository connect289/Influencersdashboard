import Link from "next/link";
import type { Metadata } from "next";
import { Pin, Search } from "lucide-react";
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
import type { LeadList } from "@/lib/types";
import { stagesAndSubs } from "@/lib/stages";
import { fieldsFor, GROUPABLE } from "@/lib/viewFields";
import { pickView, viewsFor } from "@/lib/views";
import { NewLeadButton } from "./NewLead";
import { SalesBulkBar } from "./SalesBulkBar";
import { Hotkeys } from "@/components/shell/Hotkeys";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Leads" };

const PAGE = 50;

/** My leads (spec B8.2): saved, pinned and shared views as pills, chosen columns, group-by, list or board; search by name, any phone, email or application ID. */
export default async function LeadsPage({ searchParams }: { searchParams: Promise<{ view?: string; v?: string; q?: string; page?: string; drill?: string; dl?: string; layout?: string; group?: string }> }) {
  const me = await requireUser("sales", "/s/leads");
  const sp = await searchParams;
  const supabase = await createClient();
  const money = me.role === "admin";
  let list: Awaited<ReturnType<typeof viewsFor>>;
  let stagesSubs: Awaited<ReturnType<typeof stagesAndSubs>>;
  let tpls: unknown[] | null;
  try {
    [list, stagesSubs, { data: tpls }] = await Promise.all([viewsFor("sales"), stagesAndSubs(),
      supabase.from("wa_templates").select("id, name, language, purpose, status").eq("usable_by_sales", true).eq("audience", "sales").in("status", ["approved", "draft"]).order("purpose")]);
  } catch (e) {
    return <Page title="Leads"><SetupError error={e} /></Page>;
  }
  const { stages, subs } = stagesSubs;
  const { view, refused } = await pickView(list, sp.view ?? sp.v, (vs) => vs.find((v) => v.name === "Due now"));
  const views = list.views;
  const kanban = (sp.layout ?? view?.layout) === "kanban";
  const groupBy = sp.group === "none" ? "" : sp.group ?? view?.group_by ?? "";
  const page = Math.max(0, Number(sp.page ?? 0) || 0);
  const drill = sp.drill && /^[0-9a-f-]{36}$/i.test(sp.drill) ? sp.drill : undefined;
  let res: LeadList;
  try {
    res = await rpc("lead_list", { p: { filters: sp.q || drill ? {} : view?.filters ?? {}, sort: view?.sort, search: sp.q ?? "", limit: kanban ? 500 : PAGE, offset: kanban ? 0 : page * PAGE, drill, group_by: groupBy || undefined } });
  } catch (e) {
    return <Page title="Leads"><SetupError error={e} /></Page>;
  }
  const link = (o: Record<string, string | number | undefined>) => {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries({ view: view && !drill ? String(view.id) : undefined, q: sp.q, drill, dl: drill ? sp.dl : undefined, layout: sp.layout, group: sp.group, ...o })) if (v !== undefined && v !== "") q.set(k, String(v));
    return `/s/leads?${q}`;
  };
  const allowed = fieldsFor("sales", money).map((f) => f.field);
  const groupHrefs = Object.fromEntries([["", link({ group: "none", page: undefined })], ...GROUPABLE.map((g) => [g, link({ group: g, page: undefined })])]);
  return (
    <Page title="Leads" sub={`${res.total} ${sp.q ? "found" : drill ? `behind “${(sp.dl ?? "a number").slice(0, 80)}”` : view?.name ?? ""}`} actions={<span data-hotkey="n" className="contents"><NewLeadButton /></span>}>
      {drill && <div className="banner info"><div className="grow">These are the {res.total} leads behind the number you opened in Analytics.</div><Link className="btn ghost sm" href="/s/leads">All my leads</Link></div>}
      {refused && <div className="banner danger" role="alert">{refused}</div>}
      <form className="search" action="/s/leads" role="search">
        <Search className="icon s" aria-hidden />
        <input name="q" defaultValue={sp.q ?? ""} placeholder="Name, any phone, email, application ID" aria-label="Search leads" />
      </form>
      <div className="hscroll" role="tablist" aria-label="Views">
        {views.map((v) => (
          <Link key={v.id} className="pill" href={`/s/leads?view=${v.id}`} aria-pressed={!sp.q && !drill && view?.id === v.id} style={{ textDecoration: "none", color: "inherit" }}>
            {list.defaultId === v.id && <Pin className="icon s" aria-label="Your default" />}{v.name}{v.shared_with_role && !v.mine ? ` · ${v.owner ?? "shared"}` : ""}
          </Link>
        ))}
        {view && !views.some((v) => v.id === view.id) && <span className="pill" aria-pressed="true">{view.name}</span>}
      </div>
      <div className="row wrap" style={{ gap: 6 }}>
        <ViewBuilder role="sales" base="/s/leads" stages={stages} admin={me.role === "admin"} myRole={me.role} />
        {view && (view.mine || (view.is_standard && me.role === "admin")) && !sp.q && <ViewBuilder key={view.id} role="sales" base="/s/leads" stages={stages} view={view} admin={me.role === "admin"} myRole={me.role} />}
        {view && !drill && <ViewTools role="sales" base="/s/leads" viewId={view.id} pinned={list.defaultId === view.id} shareable={view.is_standard || !!view.shared_with_role} />}
        <span className="pills" role="group" aria-label="Show as">
          <Link className="pill" href={link({ layout: "list", page: undefined })} aria-pressed={!kanban} style={{ color: "inherit", textDecoration: "none" }}>List</Link>
          <Link className="pill" href={link({ layout: "kanban", page: undefined })} aria-pressed={kanban} style={{ color: "inherit", textDecoration: "none" }}>Board</Link>
        </span>
        <GroupBySelect value={groupBy} href={groupHrefs} allowed={allowed} />
        <DensityToggle />
        <LiveRefresh />
      </div>
      {res.groups && res.group_by && res.total > 0 && <GroupSummary groups={res.groups} by={res.group_by} total={res.total} />}
      {res.rows.length === 0 ? (
        <Empty>{sp.q ? <>Nobody matches “{sp.q}”. Try part of the name, or the phone's last digits.</> : <>No leads in “{view?.name ?? "this view"}”. {views.find((v) => v.name === "All mine") && <Link href={`/s/leads?view=${views.find((v) => v.name === "All mine")!.id}`}>See all my leads</Link>}</>}</Empty>
      ) : kanban ? (
        <Kanban rows={res.rows} stages={stages} subs={subs} base="/s/leads" canWork canMoveBack={me.role === "admin" || me.role === "sales_head"} showOwner={me.role !== "counsellor"} />
      ) : <LeadTable rows={res.rows} base="/s/leads" select columns={view?.columns} money={money} showOwner={me.role !== "counsellor"} />}
      {!kanban && res.rows.length > 0 && <SalesBulkBar templates={(tpls ?? []) as { id: number; name: string; language: string; purpose: string | null; status: string }[]} />}
      <Hotkeys keys={[{ key: "n", label: "New lead" }]} />
      {!kanban && res.total > PAGE && (
        <div className="pager">
          {page > 0 && <Link className="btn ghost sm" href={link({ page: page - 1 })}>Previous</Link>}
          <span className="muted">{page * PAGE + 1}–{Math.min(res.total, (page + 1) * PAGE)} of {res.total}</span>
          {(page + 1) * PAGE < res.total && <Link className="btn ghost sm" href={link({ page: page + 1 })}>Next</Link>}
        </div>
      )}
    </Page>
  );
}
