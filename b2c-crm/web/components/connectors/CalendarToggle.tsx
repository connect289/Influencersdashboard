"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { calendarSet, unknownCallHandled } from "@/app/connector-actions";
import { when } from "@/lib/format";

export type CalendarMine = { on: boolean; error: string | null; synced_at: string | null; pending: number; events: number };

/** "Show my follow-ups in Google Calendar" (spec B17, personal). One way: the CRM writes, Calendar edits are not read back. */
export function CalendarToggle({ mine, ready }: { mine: CalendarMine | null; ready: boolean }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const on = !!mine?.on;
  const toggle = () => start(async () => {
    const r = await calendarSet(!on);
    if (!r.ok) return void toast.error(r.error);
    if (r.notice) toast.success(r.notice);
    router.refresh();
  });
  return (
    <div className="stack" style={{ gap: 6 }}>
      <label className="row small"><input type="checkbox" checked={on} disabled={busy} onChange={toggle} /> Show my follow-ups in my Google Calendar</label>
      {on && <span className="small muted">{mine?.events ?? 0} events · {mine?.pending ? `${mine.pending} waiting · ` : ""}last sync {when(mine?.synced_at)}</span>}
      {on && mine?.error && <span className="small" style={{ color: "var(--red)" }}>Last error: {mine.error}</span>}
      {!ready && <span className="note">Waiting for the Admin to connect Google Workspace; your events go out once it is.</span>}
      <span className="note">Each follow-up becomes an event with a 10-minute reminder and the lead&apos;s link. Changes you make in Calendar are not copied back: move follow-ups in the CRM.</span>
    </div>
  );
}

export function UnknownCallDone({ id }: { id: number }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  return (
    <button type="button" className="btn quiet sm" disabled={busy} onClick={() => start(async () => {
      const note = window.prompt("What happened? (optional)") ?? "";
      const r = await unknownCallHandled(id, note);
      if (!r.ok) return void toast.error(r.error);
      router.refresh();
    })}>Handled</button>
  );
}
