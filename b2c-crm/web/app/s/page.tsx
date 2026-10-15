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
import { Swipeable } from "@/components/ui/Swipeable";
import { Hotkeys } from "@/components/shell/Hotkeys";

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

/** Today (spec B8.1): the queue in working order; beside it the follow-up counts, the month in one card, and alerts. */
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
          <div className="sec-title"><h2>Work next</h2><span className="note">In queue order · swipe right to call</span></div>
          <Hotkeys keys={[]} />
          {t.queue.length === 0 ? (
            <div className="card empty">Nothing waiting. New leads and follow-ups appear here as they come due.</div>
          ) : (
            <div className="stack tight">
              {t.queue.map((q, i) => {
                const l = q.lead;
                const breach = !!l.sla_breached_at && !l.first_contacted_at;
                return (
                  <Swipeable key={`${l.lead_id}-${q.task_id ?? i}`} right={{ label: "Call", selector: ".btn.call" }} left={{ label: "Open", selector: "a.plain", tone: "primary" }}>
                  <div className={`qcard${breach ? " breach" : ""}`} data-row>
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
                  </Swipeable>
                );
              })}
            </div>
          )}
        </div>
        <div className="stack">
          <div className="sec-title"><h2>Follow-ups</h2><Link className="btn quiet sm" href="/s/followups">Open</Link></div>
          <FollowupCards counts={t.counts} />
          <div className="sec-title"><h2>This month</h2>{progress && <span className="note">day {progress.day_of_month} of {progress.days_in_month}</span>}</div>
          <MonthCard today={t.numbers} progress={progress} />
          <Notifications limit={6} />
          {board && board.rows.length > 1 && (
            <details className="panel">
              <summary>Leaderboard</summary>
              <div className="stack tight">
                <Leaderboard rows={board.rows} visible={!!board.me_visible} />
                <Link className="small" href="/s/money">My money</Link>
              </div>
            </details>
          )}
        </div>
      </div>
    </Page>
  );
}

/** One card for the month: the four targets with a pace marker (where the bar should be today), and today's calls in a line. */
function MonthCard({ today, progress: p }: { today: Today["numbers"]; progress: Progress | null }) {
  const target = today.target ?? {};
  const line = [["calls", "calls"], ["connected", "connected"], ["counselled", "counselled"]] as const;
  const items: [keyof Six, string][] = [["enrollments", "Enrolments"], ["applications", "Applications"], ["counselled", "Counselled"], ["commission", "Commission"]];
  const pace = p ? p.day_of_month / p.days_in_month : null;
  return (
    <section className="panel">
      <div className="body">
        <div className="kpis" style={{ gridTemplateColumns: "repeat(2, 1fr)" }}>
          {items.map(([k, label]) => {
            const v = p ? Number(p.actual[k] ?? 0) : Number((today as unknown as Record<string, number>)[k] ?? 0);
            const tg = p ? (p.target[k] ? Number(p.target[k]) : null) : (target[k] ? Number(target[k]) : null);
            const share = tg ? v / tg : null;
            const behind = share !== null && pace !== null && share < pace;
            return (
              <div key={k} className="kpi" style={{ boxShadow: "none", background: "var(--bg)" }}>
                <span>{label}</span>
                <b>{k === "commission" ? inr(v) : v}{tg ? <span className="muted" style={{ fontSize: 13, fontWeight: 500 }}> / {k === "commission" ? inr(tg) : tg}</span> : null}</b>
                {share !== null && (
                  <div className={`bar-track${pace !== null ? " pace" : ""}`} style={pace !== null ? { ["--pace" as string]: `${pace * 100}%` } : undefined} title={behind ? "Behind pace" : "On pace"}>
                    <div className={`bar-fill${behind ? " amber" : ""}`} style={{ width: `${Math.min(100, share * 100)}%` }} />
                  </div>
                )}
              </div>
            );
          })}
        </div>
        <p className="note">Today: {line.map(([k, w]) => `${today[k]}${target[k] ? `/${target[k]}` : ""} ${w}`).join(" · ")}.</p>
      </div>
    </section>
  );
}
