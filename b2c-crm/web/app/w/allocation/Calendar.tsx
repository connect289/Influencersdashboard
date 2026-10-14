"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { date } from "@/lib/format";
import { calendarSave, holidaySave, leaveAdd } from "../actions";

type Member = {
  user: { user_id: string; full_name: string | null; email: string; away_until: string | null };
  working_now: boolean;
  patterns: { isodow: number; start: string; end: string }[];
  leave: { id: number; from_day: string; to_day: string; mode: string; reassign_after_hours: number | null; reason: string | null }[];
};
const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** Working hours, leave and holidays (spec B7.1). Without a pattern a person works the company default hours. */
export function Calendar({ people, holidays, admin }: { people: Member[]; holidays: { day: string; name: string; kind: string }[]; admin: boolean }) {
  const [hours, setHours] = useState<Member | null>(null);
  const [leave, setLeave] = useState<Member | null>(null);
  const [holiday, setHoliday] = useState(false);
  return (
    <div className="stack">
      <div style={{ overflowX: "auto" }}>
        <div className="calendar" style={{ minWidth: 820 }}>
          <div className="h">Person</div>
          {DAYS.map((d) => <div key={d} className="h">{d}</div>)}
          {people.map((p) => (
            <Row key={p.user.user_id} p={p} admin={admin} onHours={() => setHours(p)} onLeave={() => setLeave(p)} />
          ))}
        </div>
      </div>
      <section className="panel">
        <header><h3>Holidays</h3>{admin && <button type="button" className="btn quiet sm" onClick={() => setHoliday(true)}>Add</button>}</header>
        <div className="body small">
          {holidays.length === 0 && <p className="note">No upcoming holidays.</p>}
          {holidays.map((h) => <div key={h.day} className="row between"><span>{h.name}</span><span className="muted">{date(h.day)} · {h.kind}</span></div>)}
          <p className="note">On a holiday nobody is working: hot leads wait for the next working hour and the Admin is alerted.</p>
        </div>
      </section>
      {hours && <HoursSheet p={hours} onClose={() => setHours(null)} />}
      {leave && <LeaveSheet p={leave} onClose={() => setLeave(null)} />}
      {holiday && <HolidaySheet onClose={() => setHoliday(false)} />}
    </div>
  );
}

function Row({ p, admin, onHours, onLeave }: { p: Member; admin: boolean; onHours: () => void; onLeave: () => void }) {
  return (
    <>
      <div>
        <b>{p.user.full_name ?? p.user.email}</b>
        {admin && <div className="row" style={{ gap: 2 }}><button type="button" className="btn quiet sm" onClick={onHours}>Hours</button><button type="button" className="btn quiet sm" onClick={onLeave}>Leave</button></div>}
        {p.leave.map((l) => <div key={l.id} className="small"><span className="shift leave">Leave {date(l.from_day)}–{date(l.to_day)}{l.mode === "reassign" ? ` · reassign after ${l.reassign_after_hours ?? 0} h` : ""}</span></div>)}
      </div>
      {DAYS.map((_, i) => {
        const pat = p.patterns.find((x) => x.isodow === i + 1);
        return (
          <div key={i}>
            {p.patterns.length === 0 ? <span className="shift off">Default</span> : pat ? <span className="shift">{pat.start.slice(0, 5)}–{pat.end.slice(0, 5)}</span> : <span className="shift off">Off</span>}
          </div>
        );
      })}
    </>
  );
}

function useRun(onClose: () => void) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const run = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>) => start(async () => {
    const r = await fn();
    if (!r.ok) return setError(r.error ?? "That did not work.");
    toast.success(r.notice ?? "Saved.");
    onClose();
    router.refresh();
  });
  return { busy, error, run };
}

function HoursSheet({ p, onClose }: { p: Member; onClose: () => void }) {
  const [rows, setRows] = useState(() => DAYS.map((_, i) => {
    const pat = p.patterns.find((x) => x.isodow === i + 1);
    return { on: p.patterns.length === 0 ? i < 6 : !!pat, start: pat?.start.slice(0, 5) ?? "10:00", end: pat?.end.slice(0, 5) ?? "19:00" };
  }));
  const { busy, error, run } = useRun(onClose);
  return (
    <Sheet title={`Working hours: ${p.user.full_name ?? p.user.email}`} onClose={onClose}>
      {rows.map((r, i) => (
        <div key={i} className="row">
          <label className="checkbox" style={{ width: 70 }}><input type="checkbox" checked={r.on} onChange={(e) => setRows(rows.map((x, j) => (j === i ? { ...x, on: e.target.checked } : x)))} />{DAYS[i]}</label>
          <input className="input" type="time" value={r.start} disabled={!r.on} onChange={(e) => setRows(rows.map((x, j) => (j === i ? { ...x, start: e.target.value } : x)))} aria-label={`${DAYS[i]} start`} />
          <input className="input" type="time" value={r.end} disabled={!r.on} onChange={(e) => setRows(rows.map((x, j) => (j === i ? { ...x, end: e.target.value } : x)))} aria-label={`${DAYS[i]} end`} />
        </div>
      ))}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" disabled={busy || rows.some((r) => r.on && r.end <= r.start)}
        onClick={() => run(() => calendarSave(p.user.user_id, rows.map((r, i) => ({ isodow: i + 1, start: r.start, end: r.end, on: r.on })).filter((r) => r.on).map(({ isodow, start, end }) => ({ isodow, start, end }))))}>
        {busy ? "Saving…" : "Save hours"}
      </button>
    </Sheet>
  );
}

function LeaveSheet({ p, onClose }: { p: Member; onClose: () => void }) {
  const [mode, setMode] = useState<"hold" | "reassign">("hold");
  const { busy, error, run } = useRun(onClose);
  return (
    <Sheet title={`Leave: ${p.user.full_name ?? p.user.email}`} onClose={onClose}>
      <form className="stack" action={(f) => run(() => leaveAdd(p.user.user_id, String(f.get("from")), String(f.get("to")), mode, mode === "reassign" ? Number(f.get("after") ?? 0) : null, String(f.get("reason") ?? "")))}>
        <div className="grid g2" style={{ gap: 10 }}>
          <label className="field"><span>From</span><input className="input" type="date" name="from" required /></label>
          <label className="field"><span>To</span><input className="input" type="date" name="to" required /></label>
        </div>
        <div className="field"><span>Their open leads</span><div className="pills">
          <button type="button" className="pill" aria-pressed={mode === "hold"} onClick={() => setMode("hold")}>Wait for them</button>
          <button type="button" className="pill" aria-pressed={mode === "reassign"} onClick={() => setMode("reassign")}>Reassign</button>
        </div></div>
        {mode === "reassign" && <label className="field"><span>Reassign after (hours into the leave)</span><input className="input" type="number" name="after" min={0} max={72} defaultValue={4} /></label>}
        <label className="field"><span>Reason</span><input className="input" name="reason" maxLength={200} /></label>
        <p className="note">New leads skip them while on leave either way.</p>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : "Add leave"}</button>
      </form>
    </Sheet>
  );
}

function HolidaySheet({ onClose }: { onClose: () => void }) {
  const { busy, error, run } = useRun(onClose);
  return (
    <Sheet title="Add a company holiday" onClose={onClose}>
      <form className="stack" action={(f) => run(() => holidaySave(String(f.get("day")), String(f.get("name"))))}>
        <label className="field"><span>Day</span><input className="input" type="date" name="day" required /></label>
        <label className="field"><span>Name</span><input className="input" name="name" required maxLength={80} /></label>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : "Add holiday"}</button>
      </form>
    </Sheet>
  );
}
