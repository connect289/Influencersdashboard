"use client";
import { useState, useTransition } from "react";
import { FlaskConical, LoaderCircle } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { parseLeverValue, simulationText, type Simulation } from "@/lib/ai/labels";
import { formatDateTime } from "@/lib/format";
import { EFFORT_METRIC_LABEL, EFFORT_METRICS, EFFORT_RANGE, pct, performanceDefaults, SLA_RANGE, WEIGHT_RANGE, type EffortWeights, type SlaWeights } from "@/lib/segments";
import { simulateChange } from "./actions";

const field = "h-9 w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";

/** The Admin's "what if" levers (C16, C113): the five Addendum 3 levers, validated by b2b.simulate_change against the Admin
 *  ranges (m31l engine_settings_save), wider than the AI's. Pins, caps, partner weights, exploration and the speed and
 *  reliability factors were retired. */
const LEVERS = [
  { v: "effort_weights", label: "Sales-effort weights (six metrics)" },
  { v: "effort_bounds", label: "Sales-effort factor bounds" },
  { v: "sla_floor", label: "SLA-adherence factor floor (%)" },
  { v: "half_life_days", label: "Recency half-life of P(enrol) (days)" },
  { v: "prior_weight", label: "Prior strength of P(enrol) (leads)" },
] as const;
type Lever = (typeof LEVERS)[number]["v"];

/** The Admin ranges, as m31l engine_settings_save validates them (CONTRACT 1.4; C113). */
const ADMIN_RANGE = {
  half_life_days: [7, 120], prior_weight: [1, 100], effort_lo: [EFFORT_RANGE[0], 1], effort_hi: [1, EFFORT_RANGE[1]], sla_floor_pct: [SLA_RANGE[0] * 100, SLA_RANGE[1] * 100], weight: [WEIGHT_RANGE[0], WEIGHT_RANGE[1]],
} as const;

/** What b2b.simulate_change returns (m31m 12): ai_simulate's doubly robust estimate plus the projected 'recent' block. */
type SimResult = Simulation & {
  support?: number; min_support?: number; affected?: number; window?: { from: string; to: string } | null; days?: number;
  recent?: { simulated: boolean; projected?: boolean; label?: string; days?: number; decisions?: number; affected?: number; projected_ncpl_now?: number | null; projected_ncpl_new?: number | null; projected_difference?: number | null } | null;
};

type Current = {
  effort_factor?: { enabled?: boolean; bounds?: number[] | { lo?: number; hi?: number }; weights?: Partial<EffortWeights>; min_sample?: number } | null;
  sla_factor?: { enabled?: boolean; floor?: number; ceiling?: number; step?: number; weights?: Partial<SlaWeights> } | null;
  half_life_days?: number; prior_weight?: number;
};

const rupees = (n: number | null | undefined) => (n == null || !Number.isFinite(n) ? "—" : `₹${Math.round(n).toLocaleString("en-IN")}`);

/** "What if": a change replayed on matured decisions (doubly robust against the current policy), before anyone applies it.
 *  `current` (the engine setting) pre-fills the inputs; `partners` is accepted for the old mount and no longer used. */
export function ChangeSimulator({ current }: { partners?: { id: number; name: string }[]; current?: Current | null }) {
  const [lever, setLever] = useState<Lever>("effort_weights");
  const [res, setRes] = useState<SimResult | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [fieldErr, setFieldErr] = useState<Record<string, string>>({});
  const [busy, start] = useTransition();
  const dflt = performanceDefaults(current ?? {});
  const L = LEVERS.find((x) => x.v === lever)!;

  const submit = (f: FormData) => {
    const errors: Record<string, string> = {};
    const num = (name: string, unit: "num" | "pct") => {
      const v = parseLeverValue(String(f.get(name) ?? ""), unit);
      if (typeof v === "string") { errors[name] = v; return null; }
      return v;
    };
    let value: unknown;
    if (lever === "effort_weights") {
      const w: Partial<Record<string, number>> = {};
      for (const k of EFFORT_METRICS) { const v = num(`w_${k}`, "num"); if (v !== null) w[k] = v; }
      value = w;
    } else if (lever === "effort_bounds") {
      value = [num("lo", "num"), num("hi", "num")];
    } else if (lever === "sla_floor") {
      value = num("value", "pct");
    } else {
      value = num("value", "num");
    }
    const days = num("days", "num");
    if (days !== null && (!Number.isInteger(days) || days < 7 || days > 365)) errors.days = "7 to 365 days.";
    setFieldErr(errors);
    if (Object.keys(errors).length) { setErr("Check the highlighted fields."); return; }
    start(async () => {
      const r = await simulateChange({ lever, value }, days ?? 90);
      if (!r.ok) { setErr(r.error); setRes(null); } else { setErr(null); setRes(r.result as SimResult); }
    });
  };

  const invalid = (name: string) => ({ "aria-invalid": Boolean(fieldErr[name]) || undefined, title: fieldErr[name] });

  return (
    <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); submit(new FormData(e.currentTarget)); }}>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <label className="block space-y-1 lg:col-span-2"><span className="text-[12px] text-muted">Change</span>
          <select value={lever} onChange={(e) => { setLever(e.target.value as Lever); setRes(null); setErr(null); setFieldErr({}); }} className={field}>
            {LEVERS.map((x) => <option key={x.v} value={x.v}>{x.label}</option>)}
          </select></label>
        {lever === "half_life_days" && (
          <label className="block space-y-1"><span className="text-[12px] text-muted">Days ({ADMIN_RANGE.half_life_days[0]}–{ADMIN_RANGE.half_life_days[1]})</span>
            <input name="value" inputMode="numeric" min={ADMIN_RANGE.half_life_days[0]} max={ADMIN_RANGE.half_life_days[1]} defaultValue={current?.half_life_days ?? ""} placeholder="e.g. 30" className={field} {...invalid("value")} /></label>
        )}
        {lever === "prior_weight" && (
          <label className="block space-y-1"><span className="text-[12px] text-muted">Leads ({ADMIN_RANGE.prior_weight[0]}–{ADMIN_RANGE.prior_weight[1]})</span>
            <input name="value" inputMode="decimal" min={ADMIN_RANGE.prior_weight[0]} max={ADMIN_RANGE.prior_weight[1]} defaultValue={current?.prior_weight ?? ""} placeholder="e.g. 20" className={field} {...invalid("value")} /></label>
        )}
        {lever === "sla_floor" && (
          <label className="block space-y-1"><span className="text-[12px] text-muted">Floor % ({ADMIN_RANGE.sla_floor_pct[0]}–{ADMIN_RANGE.sla_floor_pct[1]})</span>
            <input name="value" inputMode="decimal" min={ADMIN_RANGE.sla_floor_pct[0]} max={ADMIN_RANGE.sla_floor_pct[1]} defaultValue={String(Math.round(Number(dflt.sla_floor) * 100))} placeholder="e.g. 85" className={field} {...invalid("value")} /></label>
        )}
        {lever === "effort_bounds" && (
          <>
            <label className="block space-y-1"><span className="text-[12px] text-muted">Low ({ADMIN_RANGE.effort_lo[0]}–{ADMIN_RANGE.effort_lo[1]})</span>
              <input name="lo" inputMode="decimal" min={ADMIN_RANGE.effort_lo[0]} max={ADMIN_RANGE.effort_lo[1]} step={0.01} defaultValue={dflt.effort_lo} className={field} {...invalid("lo")} /></label>
            <label className="block space-y-1"><span className="text-[12px] text-muted">High ({ADMIN_RANGE.effort_hi[0]}–{ADMIN_RANGE.effort_hi[1]})</span>
              <input name="hi" inputMode="decimal" min={ADMIN_RANGE.effort_hi[0]} max={ADMIN_RANGE.effort_hi[1]} step={0.01} defaultValue={dflt.effort_hi} className={field} {...invalid("hi")} /></label>
          </>
        )}
        <label className="block space-y-1"><span className="text-[12px] text-muted">Matured days to replay</span>
          <input name="days" type="number" min={7} max={365} defaultValue={90} className={field} {...invalid("days")} /></label>
      </div>
      {lever === "effort_weights" && (
        <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
          {EFFORT_METRICS.map((k) => (
            <label key={k} className="block space-y-1"><span className="text-[12px] text-muted">{EFFORT_METRIC_LABEL[k]}</span>
              <input name={`w_${k}`} inputMode="decimal" min={ADMIN_RANGE.weight[0]} max={ADMIN_RANGE.weight[1]} step={0.5} defaultValue={dflt[`effort_w_${k}`]} className={field} {...invalid(`w_${k}`)} /></label>
          ))}
          <p className="text-[11.5px] text-subtle sm:col-span-3 lg:col-span-6">Each weight 0 to 5, not all 0. The factor stays inside the bounds (now {dflt.effort_lo}–{dflt.effort_hi}).</p>
        </div>
      )}
      <div className="flex flex-wrap items-center gap-3">
        <Button type="submit" size="sm" disabled={busy}>{busy ? <LoaderCircle className="size-3.5 animate-spin" /> : <FlaskConical className="size-3.5" />} Replay on past decisions</Button>
        {err && <span role="alert" className="text-[13px] text-danger">{err}</span>}
      </div>
      {res && (
        <div className="space-y-2 rounded-lg border border-info/25 bg-info-bg px-3 py-2 text-[13px] text-info">
          <p>{simulationText(res)}</p>
          {res.simulated && res.decisions ? (
            <p className="text-[12px]">
              {res.ci95 && <>95% interval {rupees(res.ci95[0])} to {rupees(res.ci95[1])} per lead (doubly robust against the current policy)</>}
              {res.support != null && <> · support {pct(res.support, 0)}{res.min_support != null ? ` (Autopilot needs ${pct(res.min_support, 0)})` : ""}</>}
              {res.ess != null && <> · effective sample {Math.round(res.ess)}</>}
              {res.affected != null && <> · {res.affected} of {res.decisions} decisions would change</>}
              {res.window && <> · window {formatDateTime(res.window.from)} – {formatDateTime(res.window.to)}</>}
              {res.enough === false && <> · too few decisions or too little support to rely on</>}
            </p>
          ) : !res.simulated ? (
            <p className="text-[12px]">Measured by the holdout instead: compare AI-steered and holdout leads on the AI page once this change has run for a few weeks.</p>
          ) : null}
          {res.recent?.simulated && res.recent.decisions ? (
            <p className="text-[12px]">{res.recent.label ?? "Projected: outcomes not known yet"}: {res.recent.decisions} decisions of the last {res.recent.days ?? 60} days, projected NCPL {rupees(res.recent.projected_ncpl_now)} → {rupees(res.recent.projected_ncpl_new)}.</p>
          ) : null}
        </div>
      )}
      <p className="text-[12px] text-subtle">Counts decisions routed more than 60 days ago (their outcomes are known), going back this many days. Nothing is changed by a simulation. The AI's own levers move inside these ranges; yours are validated against the Admin ranges.</p>
    </form>
  );
}
