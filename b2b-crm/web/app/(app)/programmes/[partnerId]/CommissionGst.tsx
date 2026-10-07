"use client";
import { useState, useTransition } from "react";
import { LoaderCircle } from "lucide-react";
import { toast } from "sonner";
import { setCommissionGst } from "../actions";

/** "The commission % in this partner's sheet includes GST": on by default; the partner's programme rates follow at once. */
export function CommissionGst({ partnerId, includesGst, withCommission }: { partnerId: number; includesGst: boolean; withCommission: number }) {
  const [on, setOn] = useState(includesGst);
  const [busy, start] = useTransition();
  const change = (v: boolean) => start(async () => {
    const r = await setCommissionGst(partnerId, v);
    if ("error" in r) { toast.error(r.error); return; }
    setOn(v);
    toast.success(`Commission ${v ? "includes" : "excludes"} GST${r.created ? `; ${r.created} programme rates updated` : ""}`);
  });
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-5 py-3 text-[12.5px]">
      <p className="text-muted">
        <span className="font-medium text-fg">Commission from this sheet</span>: {withCommission} {withCommission === 1 ? "programme has" : "programmes have"} a commission %,
        used as programme-level rates (they win over university and partner-wide rates in Routing → Rates).
      </p>
      <label className="flex items-center gap-2 text-fg">
        {busy && <LoaderCircle className="size-3.5 animate-spin text-muted" />}
        <input type="checkbox" className="accent-[var(--primary)]" checked={on} disabled={busy} onChange={(e) => change(e.target.checked)} />
        The % includes 18% GST
      </label>
    </div>
  );
}
