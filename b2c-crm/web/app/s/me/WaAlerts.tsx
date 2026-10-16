"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { myWaAlertsSet } from "../workspace-actions";
import { WA_ALERT_LABEL } from "@/lib/workspace";

/** Which alerts also come on WhatsApp to my own number (spec B8.7, B17), through the approved staff template. */
export function WaAlerts({ kinds, chosen, phone }: { kinds: string[]; chosen: string[]; phone: string | null }) {
  const router = useRouter();
  const [on, setOn] = useState<string[]>(chosen);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const save = () => start(async () => {
    const r = await myWaAlertsSet(on);
    if (!r.ok) return setError(r.error);
    setError(null);
    toast.success(r.notice ?? "Saved.");
    router.refresh();
  });
  const changed = on.length !== chosen.length || on.some((k) => !chosen.includes(k));
  return (
    <div className="stack tight">
      <p className="note">{phone ? <>They go to <span className="mono">{phone}</span>, your mobile in Teams, as well as in the app.</> : "Add your mobile number in Teams (ask the Admin) to get alerts on WhatsApp."}</p>
      {kinds.map((k) => (
        <label key={k} className="checkbox">
          <input type="checkbox" checked={on.includes(k)} onChange={(e) => setOn((x) => (e.target.checked ? [...x, k] : x.filter((y) => y !== k)))} /> {WA_ALERT_LABEL[k] ?? k.replace(/_/g, " ")}
        </label>
      ))}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn ghost sm" style={{ justifySelf: "start" }} disabled={busy || !changed} onClick={save}>{busy ? "Saving…" : "Save"}</button>
    </div>
  );
}
