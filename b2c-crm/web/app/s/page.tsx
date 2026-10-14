import Link from "next/link";
import type { Metadata } from "next";
import { AlertTriangle, Check, Moon } from "lucide-react";
import { CallButton } from "@/components/lead/CallButton";
import { SlaChip, TempChip } from "@/components/lead/Chips";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { initials, inr, plural, when } from "@/lib/format";
import type { LeadRow } from "@/lib/types";
import { Leaderboard } from "@/components/team/Leaderboard";
import { FollowupCards } from "./followups/FollowupCards";
import { Notifications } from "./Notifications";

export const metadata: Metadata = { title: "Today" };

type Six = { calls: number; connected: number; counselled: number; applications: number; enrollments: number; commission: number };
type Progress = { month: string; target: Partial<Six> & { source?: string }; actual: Six; day_of_month: number; days_in_month: number };
type Board = { me_visible: boolean | null; rows: { name: string; me: boolean; actual: Six }[] };

type Today = {
  queue: { why: string; task_id?: number; task?: string; due_at?: string; lead: LeadRow }[];
  counts: { not_worked: number; overdue: number; today: number; upcoming: number };
  numbers: { calls: number; connected: number; counselled: number; applications: number; enrollments: number; target: Record<string, number> | null };
  me: { name: string | null; away_until: string | null; working_now: boolean };
};

function greeting(now = new Date()) {
  const h = Number(new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Kolkata", hour: "numeric", hour12: false }).format(now));
  return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening";
}

/** Today (spec B8.1): one queue in working order, follow-up buckets, and today against target. */
export default async function TodayPage() {
  const me = await requireUser("sales", "/s");
  let t: Today;
  let progress: Progress | null, board: Board | null;
  try {
    [t, progress, board] = await Promise.all([rpc<Today>("today"), rpc<Progress>("my_progress").catch(() => null), rpc<Board>("leaderboard", { p_month: null }).catch(() => null)]);
  } catch (e) {
    return <Page title="Today"><SetupError error={e} /></Page>;
  }
  const breached = t.queue.filter((q) => q.lead.sla_breached_at && !q.lead.first_contacted_at);
  const target = t.numbers.target ?? {};
  const kpis: [string, number, number | undefined][] = [
    ["Calls logged", t.numbers.calls, target.calls], ["Connected", t.numbers.connected, target.connected], ["Counselled", t.numbers.counselled, target.counselled],
    ["Applications", t.numbers.applications, target.applications], ["Enrolments", t.numbers.enrollments, target.enrollments],
  ];
  const status = t.me.away_until && new Date(t.me.away_until) > new Date()
    ? <span className="chip risk"><Moon className="icon s" aria-hidden />Away till {when(t.me.away_until)}</span>
    : t.me.working_now ? <span className="chip ok"><Check className="icon s" aria-hidden />Working</span> : <span className="chip line">Outside your hours</span>;

  return (
    <Page title="Today" actions={status} sub={`${greeting()}, ${(me.full_name ?? "").split(" ")[0] || "there"}. ${plural(t.counts.not_worked, "new lead")}, ${plural(t.counts.overdue, "overdue follow-up")}.`}>
      <div className="grid g-lead">
        <div className="stack">
          {breached.length > 0 && (
            <div className="banner danger" role="alert">
              <AlertTriangle className="icon" aria-hidden />
              <div><b>{breached.length === 1 ? `${breached[0]!.lead.name ?? "A lead"} has` : `${breached.length} leads have`} not been called in time.</b> The first-contact SLA is breached; the Admin has been alerted. Call now.</div>
            </div>
          )}
          <div className="sec-title"><h2>Work next</h2><span className="note">In queue order</span></div>
          {t.queue.length === 0 ? (
            <div className="card pad empty">Nothing waiting. New leads and follow-ups appear here as they come due.</div>
          ) : (
            <div className="stack" style={{ gap: 8 }}>
              {t.queue.map((q, i) => {
                const l = q.lead;
                const breach = !!l.sla_breached_at && !l.first_contacted_at;
                return (
                  <div key={`${l.lead_id}-${q.task_id ?? i}`} className={`qcard${breach ? " breach" : ""}`}>
                    <span className="avatar">{initials(l.name)}</span>
                    <Link href={`/s/leads/${l.lead_id}`} className="plain grow" style={{ textDecoration: "none" }}>
                      <span className="name">{l.name ?? `Lead #${l.lead_id}`}</span> <TempChip t={l.temperature} />
                      <div className="small muted ellipsis">{q.why} · {l.course ?? "Programme not given"}</div>
                    </Link>
                    <CallButton leadId={l.lead_id} name={l.name ?? "the student"} small />
                    <div className="sub row wrap" style={{ gap: 6 }}>
                      <SlaChip lead={l} />
                      <span>{q.task ?? l.sub_stage ?? l.stage ?? ""}{q.due_at ? ` · ${when(q.due_at)}` : ""}</span>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
        <div className="stack">
          <div className="sec-title"><h2>Follow-ups</h2><Link className="btn quiet sm" href="/s/followups">Open</Link></div>
          <FollowupCards counts={t.counts} />
          <div className="sec-title"><h2>Today against target</h2></div>
          <div className="kpis">
            {kpis.slice(0, 3).map(([n, v, tg]) => <Kpi key={n} name={n} value={v} target={tg} />)}
          </div>
          <div className="sec-title"><h2>This month</h2>{progress && <span className="note">day {progress.day_of_month} of {progress.days_in_month}</span>}</div>
          {progress ? <MonthProgress p={progress} /> : (
            <div className="kpis" style={{ gridTemplateColumns: "repeat(2, 1fr)" }}>
              {kpis.slice(3).map(([n, v, tg]) => <Kpi key={n} name={n} value={v} target={tg} />)}
            </div>
          )}
          {board && board.rows.length > 1 && <>
            <div className="sec-title"><h2>Leaderboard</h2><Link className="btn quiet sm" href="/s/money">My money</Link></div>
            <Leaderboard rows={board.rows} visible={!!board.me_visible} />
          </>}
          <Notifications />
        </div>
      </div>
    </Page>
  );
}

function Kpi({ name, value, target }: { name: string; value: number; target?: number }) {
  const pct = target ? Math.min(100, Math.round((value / target) * 100)) : null;
  return (
    <div className="kpi">
      <span className="small muted">{name}</span>
      <b>{value}{target ? <span className="muted" style={{ fontSize: 13 }}>/{target}</span> : null}</b>
      {pct !== null && <div className="bar-track"><div className={`bar-fill${pct >= 50 ? "" : " amber"}`} style={{ width: `${pct}%` }} /></div>}
    </div>
  );
}

/** The month against target with a pace marker: where the bar should be by today if the month runs evenly. */
function MonthProgress({ p }: { p: Progress }) {
  const pace = p.day_of_month / p.days_in_month;
  const items: [keyof Six, string][] = [["enrollments", "Enrolments"], ["applications", "Applications"], ["counselled", "Counselled"], ["commission", "Commission"]];
  return (
    <div className="kpis" style={{ gridTemplateColumns: "repeat(2, 1fr)" }}>
      {items.map(([k, label]) => {
        const v = Number(p.actual[k] ?? 0), t = p.target[k] ? Number(p.target[k]) : null;
        const share = t ? v / t : null;
        return (
          <div key={k} className="kpi">
            <span className="small muted">{label}</span>
            <b>{k === "commission" ? inr(v) : v}{t ? <span className="muted" style={{ fontSize: 13 }}>/{k === "commission" ? inr(t) : t}</span> : null}</b>
            {share !== null && <div className="bar-track pace" style={{ ["--pace" as string]: `${pace * 100}%` }} title={share < pace ? "Behind pace" : "On pace"}>
              <div className={`bar-fill${share < pace ? " amber" : ""}`} style={{ width: `${Math.min(100, share * 100)}%` }} /></div>}
          </div>
        );
      })}
    </div>
  );
}
