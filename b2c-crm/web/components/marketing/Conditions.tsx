"use client";
import { Plus, Trash2 } from "lucide-react";
import type { Stage } from "@/lib/types";
import { needsValue, OPS, type Condition, type FieldDef } from "@/lib/viewFields";

/** "All of these hold" conditions in the views' filter language (views, segments, journey branches). */
export function Conditions({ fields, stages, value, onChange }: { fields: FieldDef[]; stages: Stage[]; value: Condition[]; onChange: (c: Condition[]) => void }) {
  const defOf = (f: string) => fields.find((x) => x.field === f) ?? fields[0]!;
  const set = (i: number, c: Partial<Condition>) => onChange(value.map((x, k) => (k === i ? { ...x, ...c } : x)));
  const changeField = (i: number, field: string) => {
    const d = defOf(field);
    set(i, { field, op: OPS[d.type][0]![0], value: d.type === "choice" ? d.choices![0]![0] : d.type === "stage" ? [stages[0]?.id ?? 1] : undefined });
  };
  return (
    <div className="stack" style={{ gap: 6 }}>
      {value.map((c, i) => {
        const d = defOf(c.field);
        return (
          <div key={i} className="row wrap" style={{ gap: 6 }}>
            <select className="input" style={{ flex: "1 1 140px" }} value={c.field} onChange={(e) => changeField(i, e.target.value)} aria-label="Field">
              {fields.map((f) => <option key={f.field} value={f.field}>{f.label}</option>)}
            </select>
            <select className="input" style={{ flex: "1 1 120px" }} value={c.op} onChange={(e) => set(i, { op: e.target.value })} aria-label="Condition">
              {OPS[d.type].map(([k, l]) => <option key={k} value={k}>{l}</option>)}
            </select>
            {needsValue(c.op) && (d.type === "choice" ? (
              <select className="input" style={{ flex: "1 1 120px" }} value={String(c.value ?? "")} onChange={(e) => set(i, { value: e.target.value })} aria-label="Value">
                {d.choices!.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </select>
            ) : d.type === "stage" ? (
              <select className="input" multiple style={{ flex: "1 1 160px", minHeight: 80 }} aria-label="Stages" value={(Array.isArray(c.value) ? c.value : []).map(String)}
                onChange={(e) => set(i, { value: [...e.target.selectedOptions].map((o) => Number(o.value)) })}>
                {stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            ) : (
              <input className="input" style={{ flex: "1 1 120px" }} aria-label="Value" value={String(c.value ?? "")} min={0}
                type={d.type === "number" || c.op.endsWith("_days") ? "number" : "text"} onChange={(e) => set(i, { value: e.target.value })} />
            ))}
            <button type="button" className="btn quiet sm" onClick={() => onChange(value.filter((_, k) => k !== i))} aria-label="Remove this condition"><Trash2 className="icon s" aria-hidden /></button>
          </div>
        );
      })}
      {value.length < 12 && (
        <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} onClick={() => onChange([...value, { field: fields[0]!.field, op: OPS[fields[0]!.type][0]![0], value: fields[0]!.choices?.[0]?.[0] }])}>
          <Plus className="icon s" aria-hidden />Add a condition
        </button>
      )}
    </div>
  );
}

/** Conditions as the database wants them: numbers as numbers, valueless operators without a value. */
export function toFilters(conds: Condition[], fields: FieldDef[]): { all: Condition[] } {
  return {
    all: conds.map((c) => {
      const d = fields.find((f) => f.field === c.field);
      if (c.field === "owner_id") return { field: "owner_id", op: c.op === "is_true" ? "is_null" : "not_null" };
      if (!needsValue(c.op)) return { field: c.field, op: c.op };
      if (d?.type === "number" || c.op.endsWith("_days")) return { ...c, value: Number(c.value ?? 0) };
      return c;
    }),
  };
}
