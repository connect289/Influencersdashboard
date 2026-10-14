"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { targetSave } from "@/app/w/money-actions";

const FIELDS = [["enrollments", "Enrolments"], ["applications", "Applications"], ["counselled", "Counselled"], ["connected", "Connected calls"], ["calls", "Calls"], ["commission", "Commission ₹"]] as const;

/** Sets one person's targets for one month (spec B11.3). Admin for anyone; a sales head for counsellors. */
export function TargetEditor({ user, name, month, target }: { user: string; name: string; month: string; target: Record<string, unknown> | null }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, start] = useTransition();
  const [m, setM] = useState(month);
  const [f, setF] = useState<Record<string, string>>(Object.fromEntries(FIELDS.map(([k]) => [k, target?.[k] === undefined || target?.[k] === null ? "" : String(target[k])])));
  const save = () => start(async () => {
    const r = await targetSave(user, m, f);
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Saved.");
    setOpen(false);
    router.refresh();
  });
  return (
    <>
      <button type="button" className="btn quiet sm" onClick={() => setOpen(true)}>Target</button>
      {open && (
        <Sheet title={`Targets for ${name}`} onClose={() => setOpen(false)}>
          <div className="stack">
            <label className="field"><span>Month (first day)</span><input className="input" type="date" value={m} onChange={(e) => setM(e.target.value)} /></label>
            <div className="grid g2">
              {FIELDS.map(([k, l]) => <label key={k} className="field"><span>{l}</span><input className="input num" inputMode="numeric" value={f[k]} onChange={(e) => setF({ ...f, [k]: e.target.value })} placeholder="none" /></label>)}
            </div>
            <p className="note">Empty means no target for that number this month. {target?.source === "default" ? "Shown values are the person's standing monthly target." : ""}</p>
            <button type="button" className="btn primary block" disabled={busy} onClick={save}>Save targets</button>
          </div>
        </Sheet>
      )}
    </>
  );
}
