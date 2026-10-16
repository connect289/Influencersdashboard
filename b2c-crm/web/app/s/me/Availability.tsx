"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { setAway } from "../actions";

/** Away (spec B7.4): new leads go to others while away; it ends by itself. */
export function Availability({ awayUntil, label }: { awayUntil: string | null; label: string }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const set = (min: number) => start(async () => {
    const r = await setAway(min);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Saved.");
    router.refresh();
  });
  return (
    <section className="panel">
      <header><h3>Availability</h3><span className="small muted">{label}</span></header>
      <div className="body">
        <div className="pills">
          <button type="button" className="pill" aria-pressed={!awayUntil} disabled={busy} onClick={() => set(0)}>Working</button>
          <button type="button" className="pill" disabled={busy} onClick={() => set(30)}>Away 30 min</button>
          <button type="button" className="pill" disabled={busy} onClick={() => set(60)}>Away 1 hour</button>
          <button type="button" className="pill" disabled={busy} onClick={() => set(1440)}>Away for the rest of today</button>
        </div>
        <p className="note">Your working hours and leave are set by the Admin. Hot leads never wait for you while you are away.</p>
      </div>
    </section>
  );
}
