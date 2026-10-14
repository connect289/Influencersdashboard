"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, SlidersHorizontal, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { viewSave } from "@/app/s/actions";
import type { SavedView, Stage } from "@/lib/types";
import { fromFilter, needsValue, OPS, SORTS, toFilter, VIEW_FIELDS, type Condition } from "@/lib/viewFields";

/**
 * New view / Edit view (spec B8.4): conditions (all must hold) and a sort. The person's own views only; the Admin may also
 * publish a standard view for everyone in the Workspace.
 */
export function ViewBuilder({ role, base, stages, view, admin }: { role: "sales" | "workspace"; base: string; stages: Stage[]; view?: SavedView; admin?: boolean }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className="btn ghost sm" onClick={() => setOpen(true)}>
        {view ? <><SlidersHorizontal className="icon s" aria-hidden />Edit view</> : <><Plus className="icon s" aria-hidden />New view</>}
      </button>
      {open && <Builder role={role} base={base} stages={stages} view={view} admin={admin} onClose={() => setOpen(false)} />}
    </>
  );
}

function Builder({ role, base, stages, view, admin, onClose }: { role: "sales" | "workspace"; base: string; stages: Stage[]; view?: SavedView; admin?: boolean; onClose: () => void }) {
  const router = useRouter();
  const fields = VIEW_FIELDS.filter((f) => role === "workspace" || !f.workspaceOnly);
  const initial = ((view?.filters as { all?: Condition[] } | undefined)?.all ?? []).map(fromFilter);
  const [name, setName] = useState(view?.name ?? "");
  const [conds, setConds] = useState<Condition[]>(initial.length ? initial : [{ field: "temperature", op: "eq", value: "hot" }]);
  const [sort, setSort] = useState(view?.sort ?? { field: "next_task_due_at", dir: "asc" as const });
  const [standard, setStandard] = useState(view?.is_standard ?? false);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();

  const set = (i: number, c: Partial<Condition>) => setConds((cs) => cs.map((x, k) => (k === i ? { ...x, ...c } : x)));
  const defOf = (f: string) => fields.find((x) => x.field === f) ?? fields[0]!;

  function changeField(i: number, field: string) {
    const d = defOf(field);
    const op = OPS[d.type][0]![0];
    set(i, { field, op, value: d.type === "choice" ? d.choices![0]![0] : d.type === "stage" ? [stages[0]?.id ?? 1] : undefined });
  }

  function save(hidden = false) {
    setError(null);
    start(async () => {
      const all = conds.map(toFilter).map((c) => {
        const d = defOf(c.field);
        if (!needsValue(c.op) || c.field === "owner_id") return c;
        if (d.type === "number" || c.op === "within_days" || c.op === "older_than_days") return { ...c, value: Number(c.value ?? 0) };
        return c;
      });
      const r = await viewSave(hidden ? { id: view!.id, role, hidden: true }
        : { id: view?.id, name, role, filters: { all }, sort, is_standard: admin && role === "workspace" ? standard : undefined });
      if (!r.ok) return setError(r.error);
      toast.success(r.notice ?? "Saved.");
      onClose();
      router.push(hidden ? base : `${base}?v=${r.data}`);
      router.refresh();
    });
  }

  return (
    <Sheet title={view ? "Edit view" : "New view"} onClose={onClose}>
      <label className="field"><span>Name</span><input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={60} placeholder="For example: Hot MBA leads" /></label>
      <div className="field">
        <span>Show leads where all of these hold</span>
        <div className="stack" style={{ gap: 6 }}>
          {conds.map((c, i) => {
            const d = defOf(c.field);
            return (
              <div key={i} className="row wrap" style={{ gap: 6 }}>
                <select className="input" style={{ flex: "1 1 140px" }} value={c.field} onChange={(e) => changeField(i, e.target.value)} aria-label="Field">
                  {fields.map((f) => <option key={f.field} value={f.field}>{f.label}</option>)}
                </select>
                <select className="input" style={{ flex: "1 1 120px" }} value={c.op} onChange={(e) => set(i, { op: e.target.value })} aria-label="Condition">
                  {OPS[d.type].map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                </select>
                {needsValue(c.op) && d.field !== "owner_id" && (
                  d.type === "choice" ? (
                    <select className="input" style={{ flex: "1 1 120px" }} value={String(c.value ?? "")} onChange={(e) => set(i, { value: e.target.value })} aria-label="Value">
                      {d.choices!.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                    </select>
                  ) : d.type === "stage" ? (
                    <select className="input" multiple style={{ flex: "1 1 160px", minHeight: 80 }} aria-label="Stages"
                      value={(Array.isArray(c.value) ? c.value : []).map(String)} onChange={(e) => set(i, { value: [...e.target.selectedOptions].map((o) => Number(o.value)) })}>
                      {stages.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                    </select>
                  ) : (
                    <input className="input" style={{ flex: "1 1 120px" }} aria-label="Value" value={String(c.value ?? "")}
                      type={d.type === "number" || c.op.endsWith("_days") ? "number" : "text"} min={0}
                      onChange={(e) => set(i, { value: e.target.value })} />
                  )
                )}
                <button type="button" className="btn quiet sm" onClick={() => setConds((cs) => cs.filter((_, k) => k !== i))} aria-label="Remove this condition"><Trash2 className="icon s" aria-hidden /></button>
              </div>
            );
          })}
          {conds.length < 12 && (
            <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} onClick={() => setConds((cs) => [...cs, { field: "temperature", op: "eq", value: "hot" }])}>
              <Plus className="icon s" aria-hidden />Add a condition
            </button>
          )}
        </div>
      </div>
      <div className="row wrap" style={{ gap: 6 }}>
        <label className="field grow"><span>Sort by</span>
          <select className="input" value={sort.field} onChange={(e) => setSort({ ...sort, field: e.target.value })}>
            {SORTS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </label>
        <label className="field"><span>Order</span>
          <select className="input" value={sort.dir} onChange={(e) => setSort({ ...sort, dir: e.target.value as "asc" | "desc" })}>
            <option value="asc">Earliest first</option><option value="desc">Latest first</option>
          </select>
        </label>
      </div>
      {admin && role === "workspace" && !view && (
        <label className="checkbox"><input type="checkbox" checked={standard} onChange={(e) => setStandard(e.target.checked)} /> Standard view for everyone in the Workspace</label>
      )}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={() => save()} disabled={busy || !name.trim()}>{busy ? "Saving…" : "Save view"}</button>
      {view && <button type="button" className="btn quiet block" onClick={() => save(true)} disabled={busy}>Remove this view</button>}
    </Sheet>
  );
}
