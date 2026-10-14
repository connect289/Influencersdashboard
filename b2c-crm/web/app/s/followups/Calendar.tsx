import Link from "next/link";
import { istDay, time } from "@/lib/format";
import { TASK_KIND_LABEL } from "@/lib/labels";
import type { LeadRow, Task } from "@/lib/types";

export type Item = { task: Task; lead: LeadRow };

const dayLabel = (d: Date) => new Intl.DateTimeFormat("en-IN", { timeZone: "Asia/Kolkata", weekday: "short", day: "numeric", month: "short" }).format(d);

function Entry({ i, late }: { i: Item; late?: boolean }) {
  return (
    <Link href={`/s/leads/${i.lead.lead_id}`} className={`cal-item${late ? " late" : ""}`}>
      <span className="mono">{time(i.task.due_at)}</span>
      <span className="ellipsis"><b>{i.lead.name ?? `Lead #${i.lead.lead_id}`}</b> · {TASK_KIND_LABEL[i.task.kind] ?? i.task.kind}: {i.task.title}</span>
    </Link>
  );
}

/** Follow-ups on a calendar (spec B8.3): today by hour, or the next seven days. Overdue ones stay on top in red. */
export function Calendar({ items, view, now = new Date() }: { items: Item[]; view: "day" | "week"; now?: Date }) {
  const today = istDay(now);
  const overdue = items.filter((i) => new Date(i.task.due_at) < now);
  const later = items.filter((i) => new Date(i.task.due_at) >= now);
  const days = Array.from({ length: view === "day" ? 1 : 7 }, (_, k) => new Date(now.getTime() + k * 86400000));
  return (
    <div className="stack">
      {overdue.length > 0 && (
        <section className="panel">
          <header><h3 className="error">Overdue ({overdue.length})</h3></header>
          <div className="body cal-day">{overdue.map((i) => <Entry key={i.task.id} i={i} late />)}</div>
        </section>
      )}
      {view === "day" ? (
        <section className="panel">
          <header><h3>Today</h3></header>
          <div className="body cal-hours">
            {Array.from({ length: 15 }, (_, h) => h + 8).map((h) => {
              const at = later.filter((i) => istDay(new Date(i.task.due_at)) === today && Number(time(i.task.due_at).slice(0, 2)) === h);
              return (
                <div key={h} className="cal-hour">
                  <span className="mono muted">{String(h).padStart(2, "0")}:00</span>
                  <div className="cal-day">{at.map((i) => <Entry key={i.task.id} i={i} />)}</div>
                </div>
              );
            })}
            {(() => {
              const off = later.filter((i) => istDay(new Date(i.task.due_at)) === today && !(Number(time(i.task.due_at).slice(0, 2)) >= 8 && Number(time(i.task.due_at).slice(0, 2)) < 23));
              return off.length ? <div className="cal-hour"><span className="mono muted">Other</span><div className="cal-day">{off.map((i) => <Entry key={i.task.id} i={i} />)}</div></div> : null;
            })()}
          </div>
        </section>
      ) : (
        <div className="cal-week">
          {days.map((d) => {
            const key = istDay(d);
            const at = later.filter((i) => istDay(new Date(i.task.due_at)) === key);
            return (
              <section key={key} className={`panel${key === today ? " today" : ""}`} aria-label={dayLabel(d)}>
                <header><h3>{key === today ? "Today" : dayLabel(d)}</h3><span className="muted num">{at.length}</span></header>
                <div className="body cal-day">{at.length === 0 ? <span className="note">Free</span> : at.map((i) => <Entry key={i.task.id} i={i} />)}</div>
              </section>
            );
          })}
        </div>
      )}
    </div>
  );
}
