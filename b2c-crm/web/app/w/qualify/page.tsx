import Link from "next/link";
import type { Metadata } from "next";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { when } from "@/lib/format";
import { QUESTIONS, isQuestion } from "@/lib/qualify";
import { team } from "@/lib/team";
import { QualifyActions } from "./QualifyActions";

export const metadata: Metadata = { title: "To qualify" };

type Row = { id: number; lead_id: number; name: string | null; course: string | null; phone: string | null; trigger: string | null; questions: string[]; status: "waiting" | "escalated";
  created_at: string; due_at: string; task_id: number | null; task_owner: string | null; task_owner_name: string | null; link: string };

/**
 * To qualify (spec B6.3, b39): not-qualified leads that re-engaged while still missing details. They got the 3-question
 * form; after 48 hours without answers they wait here. The Admin gives one to a counsellor to collect the details only,
 * or sends the form again.
 */
export default async function QualifyQueue({ searchParams }: { searchParams: Promise<{ test?: string }> }) {
  const me = await requireUser("workspace", "/w/qualify");
  if (me.role !== "admin") return <Page title="To qualify"><Empty>The To qualify queue is the Admin&apos;s.</Empty></Page>;
  const test = (await searchParams).test === "1";
  let rows: Row[];
  let people: { user_id: string; name: string }[];
  try {
    const [r, t] = await Promise.all([rpc<Row[]>("qualify_queue", { p: { test } }), team()]);
    rows = r;
    people = t.filter((m) => m.user.is_active && ["counsellor", "sales_head"].includes(m.user.role)).map((m) => ({ user_id: m.user.user_id, name: m.user.full_name ?? m.user.email }));
  } catch (e) {
    return <Page title="To qualify"><SetupError error={e} /></Page>;
  }
  const waiting = rows.filter((r) => r.status === "escalated").length;
  return (
    <Page title="To qualify" sub={`${rows.length} re-engaged leads still missing details · ${waiting} past 48 hours`}>
      <div className="row wrap between">
        <p className="note">These leads are not sold to: once the details are in, the B2B CRM routes them again. Give one to a counsellor to call and collect the details only.</p>
        <Link className="btn quiet sm" href={test ? "/w/qualify" : "/w/qualify?test=1"}>{test ? "Hide test leads" : "Include test leads"}</Link>
      </div>
      {rows.length === 0 ? <Empty>Nobody is waiting to be qualified.</Empty> : (
        <div className="table-wrap"><table>
          <thead><tr><th>Lead</th><th>Missing</th><th>Since</th><th>Status</th><th>Counsellor</th><th /></tr></thead>
          <tbody>{rows.map((r) => (
            <tr key={r.id}>
              <td><Link href={`/w/leads/${r.lead_id}`}><b>{r.name ?? `Lead #${r.lead_id}`}</b></Link><div className="small muted">{r.course ?? "Programme not given"} · {r.trigger ?? "—"}</div></td>
              <td className="small">{r.questions.map((q) => (isQuestion(q) ? QUESTIONS[q].staffLabel : q)).join(", ")}</td>
              <td className="small nowrap">{when(r.created_at)}<div className="muted">form until {when(r.due_at)}</div></td>
              <td><span className={`chip ${r.status === "escalated" ? "risk" : "line"}`}>{r.status === "escalated" ? "Past 48 hours" : "Form sent"}</span></td>
              <td colSpan={2}><QualifyActions id={r.id} owner={r.task_owner} people={people} link={r.link} /></td>
            </tr>
          ))}</tbody>
        </table></div>
      )}
    </Page>
  );
}
