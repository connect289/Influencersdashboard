"use client";
import { useState, useTransition } from "react";
import { FlaskConical, LoaderCircle } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { simulationText, type Simulation } from "@/lib/ai/labels";
import { simulateChange } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30";
const LEVERS = [
  { v: "exploration_share", label: "Exploration share for a segment (%)", seg: true, unit: "pct" },
  { v: "segment_pin", label: "Pin a segment's mode", seg: true, unit: "mode" },
  { v: "share_cap", label: "Share cap for a segment (%)", seg: true, unit: "pct" },
  { v: "partner_weight", label: "Temporary partner weight (%)", partner: true, unit: "pct" },
  { v: "prior_weight", label: "Prior strength (leads)", unit: "num" },
  { v: "speed_factor", label: "Speed factor", unit: "bool" },
  { v: "reliability_factor", label: "Reliability factor", unit: "bool" },
] as const;

/** "What if": a change replayed on past decisions (inverse propensity), before anyone applies it. */
export function ChangeSimulator({ partners }: { partners: { id: number; name: string }[] }) {
  const [lever, setLever] = useState<(typeof LEVERS)[number]["v"]>("exploration_share");
  const [res, setRes] = useState<Simulation | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const L = LEVERS.find((x) => x.v === lever)!;
  return (
    <form className="space-y-3" onSubmit={(e) => {
      e.preventDefault();
      const f = new FormData(e.currentTarget);
      const raw = String(f.get("value") ?? "");
      const value = L.unit === "pct" ? (raw === "" && lever === "share_cap" ? null : Number(raw) / 100) : L.unit === "num" ? Number(raw) : L.unit === "bool" ? raw === "on" : raw;
      const change: Record<string, unknown> = { lever, value };
      if ("seg" in L) change.segment = String(f.get("segment") ?? "").trim();
      if ("partner" in L) change.partner_id = Number(f.get("partner"));
      start(async () => {
        const r = await simulateChange(change, Number(f.get("days")) || 90);
        if (!r.ok) { setErr(r.error); setRes(null); } else { setErr(null); setRes(r.result as Simulation); }
      });
    }}>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <label className="block space-y-1 lg:col-span-2"><span className="text-[12px] text-muted">Change</span>
          <select value={lever} onChange={(e) => { setLever(e.target.value as typeof lever); setRes(null); }} className={field}>{LEVERS.map((x) => <option key={x.v} value={x.v}>{x.label}</option>)}</select></label>
        {"seg" in L && <label className="block space-y-1"><span className="text-[12px] text-muted">Segment (course|level|mode)</span><input name="segment" placeholder="mba|PG|Online" className={field} /></label>}
        {"partner" in L && <label className="block space-y-1"><span className="text-[12px] text-muted">Partner</span>
          <select name="partner" className={field}>{partners.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>}
        <label className="block space-y-1"><span className="text-[12px] text-muted">{L.unit === "bool" ? "On" : "Value"}</span>
          {L.unit === "mode" ? <select name="value" className={field}><option value="performance">Performance</option><option value="commission_first">Commission first</option></select>
            : L.unit === "bool" ? <input type="checkbox" name="value" className="mt-2 size-4 accent-[var(--primary)]" />
            : <input name="value" inputMode="decimal" className={field} placeholder={L.unit === "pct" ? "e.g. 30" : "e.g. 10"} />}</label>
        <label className="block space-y-1"><span className="text-[12px] text-muted">Past days</span><input name="days" type="number" min={7} max={365} defaultValue={90} className={field} /></label>
      </div>
      <div className="flex items-center gap-3">
        <Button type="submit" size="sm" disabled={busy}>{busy ? <LoaderCircle className="size-3.5 animate-spin" /> : <FlaskConical className="size-3.5" />} Replay on past decisions</Button>
        {err && <span role="alert" className="text-[13px] text-danger">{err}</span>}
      </div>
      {res && <p className="rounded-lg border border-info/25 bg-info-bg px-3 py-2 text-[13px] text-info">{simulationText(res)}{res.ess !== undefined && res.simulated && res.decisions ? ` · effective sample ${res.ess}` : ""}</p>}
      <p className="text-[12px] text-subtle">Only leads older than the maturity window count, so early on there is little to replay. Nothing is changed by a simulation.</p>
    </form>
  );
}
