"use client";
import { Plus, Trash2 } from "lucide-react";
import type { Stage } from "@/lib/types";
import { needsValue, OPS, toFilter, type Condition, type FieldDef } from "@/lib/viewFields";

/** Conditions in the views' filter language (views, segments, journey triggers and branches). */
export function Conditions({ fields, stages, value, onChange, max = 12 }: { fields: FieldDef[]; stages: Stage[]; value: Condition[]; onChange: (c: Condition[]) => void; max?: number }) {
  const shown = fields.filter((f) => !f.noFilter);
  const defOf = (f: string) => shown.find((x) => x.field === f) ?? shown[0]!;
  const set = (i: number, c: Partial<Condition>) => onChange(value.map((x, k) => (k === i ? { ...x, ...c } : x)));
  const fresh = (field: string): Condition => {
    const d = defOf(field);
    return { field, op: OPS[d.type][0]![0], value: d.type === "choice" ? d.choices![0]![0] : d.type === "stage" ? [stages[0]?.id ?? 1] : undefined };
  };
  return (
    <div className="stack" style={{ gap: 6 }}>
      {value.map((c, i) => {
        const d = defOf(c.field);
        const pair = Array.isArray(c.value) ? (c.value as (string | number)[]) : [];
        const kind = d.type === "date" && ["between", "gte", "lte"].includes(c.op) ? "date" : d.type === "number" || c.op.endsWith("_days") ? "number" : "text";
        return (
          <div key={i} className="row wrap" style={{ gap: 6 }}>
            <select className="input" style={{ flex: "1 1 160px" }} value={c.field} onChange={(e) => set(i, fresh(e.target.value))} aria-label="Field">
              {shown.map((f) => <option key={f.field} value={f.field}>{f.label}</option>)}
            </select>
            <select className="input" style={{ flex: "1 1 130px" }} value={c.op} onChange={(e) => set(i, { op: e.target.value, value: e.target.value === "between" ? ["", ""] : c.op === "between" ? undefined : c.value })} aria-label="Condition">
              {OPS[d.type].map(([k, l]) => <option key={k} value={k}>{l}</option>)}
            </select>
            {needsValue(c.op) && d.field !== "owner_id" && (d.type === "choice" ? (
              <select className="input" style={{ flex: "1 1 120px" }} value={String(c.value ?? "")} onChange={(e) => set(i, { value: e.target.value })} aria-label="Value">
                {d.choices!.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </select>
            ) : d.type === "stage" ? (
              <select className="input" multiple style={{ flex: "1 1 160px", minHeight: 80 }} aria-label="Stages" value={(Array.isArray(c.value) ? c.value : []).map(String)}
                onChange={(e) => set(i, { value: [...e.target.selectedOptions].map((o) => Number(o.value)) })}>
                {stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            ) : c.op === "between" ? (
              <span className="row" style={{ gap: 4, flex: "1 1 200px" }}>
                <input className="input" type={kind} aria-label="From" value={String(pair[0] ?? "")} onChange={(e) => set(i, { value: [e.target.value, String(pair[1] ?? "")] })} />
                <span className="muted">and</span>
                <input className="input" type={kind} aria-label="To" value={String(pair[1] ?? "")} onChange={(e) => set(i, { value: [String(pair[0] ?? ""), e.target.value] })} />
              </span>
            ) : (
              <input className="input" style={{ flex: "1 1 120px" }} aria-label="Value" value={String(c.value ?? "")} min={kind === "number" ? 0 : undefined}
                type={kind} onChange={(e) => set(i, { value: e.target.value })} />
            ))}
            <button type="button" className="btn quiet sm" onClick={() => onChange(value.filter((_, k) => k !== i))} aria-label="Remove this condition"><Trash2 className="icon s" aria-hidden /></button>
          </div>
        );
      })}
      {value.length < max && (
        <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} onClick={() => onChange([...value, fresh(shown[0]!.field)])}>
          <Plus className="icon s" aria-hidden />Add a condition
        </button>
      )}
    </div>
  );
}

/** Conditions as the database wants them: numbers as numbers, valueless operators without a value, dates as IST days. */
export function toFilters(conds: Condition[], _fields?: FieldDef[]): { all: Condition[] } {
  return { all: conds.map(toFilter) };
}
