import Link from "next/link";
import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { Eye } from "lucide-react";
import { LeadTable } from "@/components/lead/LeadTable";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { ROLE_LABEL } from "@/lib/labels";
import type { LeadList } from "@/lib/types";

export const metadata: Metadata = { title: "View as Sales" };

type ViewAs = { user: { user_id: string; name: string | null; role: string }; leads: LeadList; followups: { overdue: number; today: number } };

const QUICK: [string, string, Record<string, unknown>][] = [
  ["open", "Open leads", { all: [{ field: "status", op: "eq", value: "active" }] }],
  ["overdue", "Follow-up overdue", { all: [{ field: "status", op: "eq", value: "active" }, { field: "next_task_due_at", op: "lte_now" }] }],
  ["untouched", "Not contacted yet", { all: [{ field: "status", op: "eq", value: "active" }, { field: "first_contacted_at", op: "is_null" }] }],
  ["all", "Everything they hold", {}],
];

/** "View as Sales" (spec B3.1, B15): a counsellor's own lead list as they see it, read-only. Each opening is logged. */
export default async function ViewAsSales({ params, searchParams }: { params: Promise<{ user: string }>; searchParams: Promise<{ q?: string; f?: string }> }) {
  const me = await requireUser("workspace", "/w/teams");
  if (me.role !== "admin") redirect("/w");
  const { user } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(user)) notFound();
  const sp = await searchParams;
  const quick = QUICK.find(([k]) => k === sp.f) ?? QUICK[0]!;
  const q = (sp.q ?? "").slice(0, 100);
  let v: ViewAs;
  try {
    v = await rpc<ViewAs>("view_as_sales", { p_user: user, p: { filters: quick[2], search: q, sort: { field: "next_task_due_at", dir: "asc" }, limit: 200 } });
  } catch (e) {
    return <Page title="View as Sales"><SetupError error={e} /></Page>;
  }
  const name = v.user.name ?? "This counsellor";
  const href = (f: string) => `/w/view-as/${user}?f=${f}${q ? `&q=${encodeURIComponent(q)}` : ""}`;
  return (
    <Page title={`Viewing as ${name}`} sub={`${ROLE_LABEL[v.user.role] ?? v.user.role} · ${v.leads.total} leads in this list`}
      back={<Link className="btn quiet sm" href="/w/teams" aria-label="Back to Teams">←</Link>}>
      <div className="banner info" role="status"><Eye className="icon" aria-hidden />
        <div className="grow">You are seeing <b>{name}</b>&apos;s Sales list as they see it, read-only. This view is recorded in the audit log. Open a lead to work it as the Admin.</div>
      </div>
      <div className="grid g3">
        <div className="stat"><span>Follow-ups overdue</span><b>{v.followups.overdue}</b></div>
        <div className="stat"><span>Follow-ups due today</span><b>{v.followups.today}</b></div>
        <div className="stat"><span>In this list</span><b>{v.leads.total}</b></div>
      </div>
      <div className="row wrap" style={{ gap: 6 }}>
        <div className="hscroll">
          {QUICK.map(([k, l]) => <Link key={k} className="pill" href={href(k)} aria-pressed={quick[0] === k} style={{ color: "inherit", textDecoration: "none" }}>{l}</Link>)}
        </div>
        <form className="row grow" style={{ gap: 6 }} action={`/w/view-as/${user}`}>
          <input type="hidden" name="f" value={quick[0]} />
          <input className="input grow" name="q" defaultValue={q} placeholder="Search their leads" aria-label="Search their leads" />
          <button className="btn quiet sm" type="submit">Search</button>
        </form>
      </div>
      {v.leads.rows.length === 0 ? <p className="empty">Nothing here.</p> : <LeadTable rows={v.leads.rows} base="/w/leads" />}
      {v.leads.total > v.leads.rows.length && <p className="note">Showing the first {v.leads.rows.length} of {v.leads.total}.</p>}
    </Page>
  );
}
