import Link from "next/link";
import { AlertTriangle } from "lucide-react";
import { date, istDay, time } from "@/lib/format";
import { weekOf } from "@/lib/holidays";
import { BreaksEditor, HolidayImport, type Break } from "./WeekTools";

export type CalendarWeek = {
  from: string;
  days: { day: string; holiday: string | null; nobody_on_duty: boolean;
    people: { user_id: string; name: string | null; on_call: boolean; start: string | null; end: string | null; leave: boolean; override: boolean }[] }[];
  breaks: Break[];
};
const DOW = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** The week (spec B7.4): each person's hours per day, leave, holidays, overrides, on-call, and days with nobody on duty. */
export function Week({ w, admin, people }: { w: CalendarWeek; admin: boolean; people: { user_id: string; name: string }[] }) {
  const { prev, next } = weekOf(w.from);
  const today = istDay(new Date());
  const thisWeek = weekOf(today).from;
  const persons = new Map<string, { name: string; on_call: boolean }>();
  for (const d of w.days) for (const p of d.people) if (!persons.has(p.user_id)) persons.set(p.user_id, { name: p.name ?? "—", on_call: p.on_call });
  const empty = w.days.filter((d) => d.nobody_on_duty && !d.holiday);
  return (
    <section className="stack">
      <div className="row wrap between">
        <h2 className="grow">Week of {date(w.from)}</h2>
        <span className="row" style={{ gap: 4 }}>
          <Link className="btn quiet sm" href={`/w/allocation?tab=calendar&week=${prev}`}>← Previous</Link>
          {w.from !== thisWeek && <Link className="btn quiet sm" href="/w/allocation?tab=calendar">This week</Link>}
          <Link className="btn quiet sm" href={`/w/allocation?tab=calendar&week=${next}`}>Next →</Link>
        </span>
      </div>
      {empty.length > 0 && (
        <div className="banner danger" role="alert"><AlertTriangle className="icon" aria-hidden />
          <div className="grow"><b>Nobody on duty</b> on {empty.map((d) => `${DOW[(new Date(`${d.day}T00:00:00Z`).getUTCDay() + 6) % 7]} ${date(d.day)}`).join(", ")}: hot leads wait (or go to the on-call counsellor) and the Admin is alerted.</div>
        </div>
      )}
      <div className="table-wrap"><table>
        <thead><tr><th>Person</th>{w.days.map((d, i) => (
          <th key={d.day} style={d.day === today ? { color: "var(--ink)" } : undefined}>{DOW[i]} {Number(d.day.slice(8))}
            {d.holiday && <div className="small"><span className="chip warm">{d.holiday}</span></div>}
            {d.nobody_on_duty && !d.holiday && <div className="small"><span className="chip breach">Nobody on duty</span></div>}
          </th>))}</tr></thead>
        <tbody>
          {persons.size === 0 && <tr><td colSpan={8} className="muted">Nobody takes leads yet. Add counsellors under Teams.</td></tr>}
          {[...persons.entries()].map(([uid, p]) => (
            <tr key={uid}>
              <td><b>{p.name}</b>{p.on_call && <span className="chip soft" style={{ marginLeft: 4 }}>On call</span>}</td>
              {w.days.map((d) => {
                const x = d.people.find((y) => y.user_id === uid);
                const cell = !x ? "—" : d.holiday ? <span className="shift off">Holiday</span> : x.leave ? <span className="shift leave">Leave</span>
                  : x.start ? <span className="shift">{time(x.start)}–{time(x.end)}{x.override ? " *" : ""}</span> : <span className="shift off">Off{x.override ? " *" : ""}</span>;
                return <td key={d.day} className="nowrap small">{cell}</td>;
              })}
            </tr>
          ))}
        </tbody>
      </table></div>
      <p className="note">* a one-day change to the usual hours. Times are IST.</p>
      <BreaksEditor breaks={w.breaks} people={people} admin={admin} />
      {admin && <HolidayImport />}
    </section>
  );
}
