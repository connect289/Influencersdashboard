"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ArrowDown, ArrowUp, Plus, SlidersHorizontal, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { Conditions } from "@/components/marketing/Conditions";
import { viewSave } from "@/app/s/actions";
import { ROLE_LABEL } from "@/lib/labels";
import type { SavedView, Stage } from "@/lib/types";
import { DEFAULT_COLUMNS, fieldDef, fieldsFor, fromGroups, GROUPABLE, OPS, toGroups, type Filters, type Group } from "@/lib/viewFields";

type Audience = "me" | "role" | "standard" | "standard_sales";

/**
 * New view / Edit view (spec B8.2, B10.1): groups of conditions (all groups hold; inside a group all or any), the columns
 * and their order, sort, group-by, list or board. Shared with the person's own role, or published by the Admin as a
 * standard view for the Workspace or the Sales app.
 */
export function ViewBuilder({ role, base, stages, view, admin, money, myRole }: {
  role: "sales" | "workspace"; base: string; stages: Stage[]; view?: SavedView; admin?: boolean; money?: boolean; myRole?: string | null;
}) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className="btn ghost sm" onClick={() => setOpen(true)}>
        {view ? <><SlidersHorizontal className="icon s" aria-hidden />Edit view</> : <><Plus className="icon s" aria-hidden />New view</>}
      </button>
      {open && <Builder role={role} base={base} stages={stages} view={view} admin={admin} money={!!money} myRole={myRole ?? null} onClose={() => setOpen(false)} />}
    </>
  );
}

function Builder({ role, base, stages, view, admin, money, myRole, onClose }: {
  role: "sales" | "workspace"; base: string; stages: Stage[]; view?: SavedView; admin?: boolean; money: boolean; myRole: string | null; onClose: () => void;
}) {
  const router = useRouter();
  const [audience, setAudience] = useState<Audience>(view?.is_standard ? "standard" : view?.shared_with_role ? "role" : "me");
  const target = audience === "standard_sales" ? "sales" : role;
  const fields = fieldsFor(target, money && target === "workspace");
  const [name, setName] = useState(view?.name ?? "");
  const initial = toGroups(view?.filters as Filters | undefined);
  const [groups, setGroups] = useState<Group[]>(initial.length ? initial : [{ mode: "all", conds: [{ field: "temperature", op: "eq", value: "hot" }] }]);
  const [columns, setColumns] = useState<string[]>(view?.columns?.length ? view.columns : DEFAULT_COLUMNS.filter((c) => role === "workspace" || c !== "owner_name"));
  const [sort, setSort] = useState(view?.sort ?? { field: "next_task_due_at", dir: "asc" as const });
  const [groupBy, setGroupBy] = useState(view?.group_by ?? "");
  const [layout, setLayout] = useState<"list" | "kanban">(view?.layout ?? "list");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const allowed = new Set(fields.map((f) => f.field));
  const colChoices = fields.filter((f) => !f.noColumn && !columns.includes(f.field));

  const setGroup = (i: number, g: Partial<Group>) => setGroups((gs) => gs.map((x, k) => (k === i ? { ...x, ...g } : x)));
  const moveCol = (i: number, d: number) => setColumns((c) => { const n = [...c]; const [x] = n.splice(i, 1); n.splice(i + d, 0, x!); return n; });

  function save(hidden = false) {
    setError(null);
    start(async () => {
      const usable = groups.map((g) => ({ ...g, conds: g.conds.filter((c) => allowed.has(c.field)) }));
      const r = await viewSave(hidden ? { id: view!.id, role, hidden: true } : {
        id: view?.id, name, role: view ? role : target, filters: fromGroups(usable), sort: allowed.has(sort.field) ? sort : { field: "next_task_due_at", dir: "asc" },
        columns: columns.filter((c) => allowed.has(c)), group_by: groupBy && allowed.has(groupBy) ? groupBy : null, layout,
        shared_with_role: audience === "role" ? myRole : null,
        is_standard: admin && !view ? audience === "standard" || audience === "standard_sales" : undefined,
      });
      if (!r.ok) return setError(r.error);
      toast.success(audience === "standard_sales" && !view ? "Published to everyone in the Sales app." : r.notice ?? "Saved.");
      onClose();
      router.push(hidden || target !== role ? base : `${base}?view=${r.data}`);
      router.refresh();
    });
  }

  return (
    <Sheet title={view ? "Edit view" : "New view"} onClose={onClose}>
      <label className="field"><span>Name</span><input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={60} placeholder="For example: Hot MBA leads this month" /></label>
      <div className="field">
        <span>Show leads where every group holds</span>
        <div className="stack" style={{ gap: 10 }}>
          {groups.map((g, i) => (
            <div key={i} className="panel quiet" style={{ padding: 10 }}>
              <div className="row between wrap" style={{ gap: 6, marginBottom: 6 }}>
                <div className="pills" role="radiogroup" aria-label="Match">
                  <button type="button" className="pill" aria-pressed={g.mode === "all"} onClick={() => setGroup(i, { mode: "all" })}>All of these</button>
                  <button type="button" className="pill" aria-pressed={g.mode === "any"} onClick={() => setGroup(i, { mode: "any" })}>Any of these</button>
                </div>
                {groups.length > 1 && <button type="button" className="btn quiet sm" onClick={() => setGroups((gs) => gs.filter((_, k) => k !== i))} aria-label="Remove this group"><Trash2 className="icon s" aria-hidden /></button>}
              </div>
              <Conditions fields={fields} stages={stages} value={g.conds} onChange={(conds) => setGroup(i, { conds })} max={20} />
            </div>
          ))}
          {groups.length < 6 && (
            <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} onClick={() => setGroups((gs) => [...gs, { mode: "any", conds: [{ field: "source", op: OPS.text[0]![0], value: "" }] }])}>
              <Plus className="icon s" aria-hidden />Add a group (and)
            </button>
          )}
        </div>
      </div>
      <div className="field">
        <span>Columns, in order</span>
        <div className="stack" style={{ gap: 4 }}>
          {columns.map((c, i) => (
            <div key={c} className="row" style={{ gap: 4 }}>
              <span className="grow small">{fieldDef(c)?.label ?? c}</span>
              <button type="button" className="btn quiet sm" disabled={i === 0} onClick={() => moveCol(i, -1)} aria-label={`Move ${c} left`}><ArrowUp className="icon s" aria-hidden /></button>
              <button type="button" className="btn quiet sm" disabled={i === columns.length - 1} onClick={() => moveCol(i, 1)} aria-label={`Move ${c} right`}><ArrowDown className="icon s" aria-hidden /></button>
              <button type="button" className="btn quiet sm" onClick={() => setColumns((cs) => cs.filter((x) => x !== c))} aria-label={`Remove ${c}`}><Trash2 className="icon s" aria-hidden /></button>
            </div>
          ))}
          <select className="input" value="" onChange={(e) => e.target.value && setColumns((cs) => [...cs, e.target.value])} aria-label="Add a column">
            <option value="">Add a column…</option>
            {colChoices.map((f) => <option key={f.field} value={f.field}>{f.label}</option>)}
          </select>
        </div>
      </div>
      <div className="row wrap" style={{ gap: 6 }}>
        <label className="field grow"><span>Sort by</span>
          <select className="input" value={sort.field} onChange={(e) => setSort({ ...sort, field: e.target.value })}>
            {fields.filter((f) => f.field !== "owner_id" && f.field !== "tags").map((f) => <option key={f.field} value={f.field}>{f.label}</option>)}
          </select>
        </label>
        <label className="field"><span>Order</span>
          <select className="input" value={sort.dir} onChange={(e) => setSort({ ...sort, dir: e.target.value as "asc" | "desc" })}>
            <option value="asc">Earliest or lowest first</option><option value="desc">Latest or highest first</option>
          </select>
        </label>
      </div>
      <div className="row wrap" style={{ gap: 6 }}>
        <label className="field grow"><span>Group by (counts{money && target === "workspace" ? " and commission totals" : ""})</span>
          <select className="input" value={groupBy} onChange={(e) => setGroupBy(e.target.value)}>
            <option value="">No grouping</option>
            {GROUPABLE.filter((g) => allowed.has(g)).map((g) => <option key={g} value={g}>{fieldDef(g)?.label ?? g}</option>)}
          </select>
        </label>
        <div className="field"><span>Show as</span>
          <div className="pills" role="radiogroup" aria-label="Show as">
            <button type="button" className="pill" aria-pressed={layout === "list"} onClick={() => setLayout("list")}>List</button>
            <button type="button" className="pill" aria-pressed={layout === "kanban"} onClick={() => setLayout("kanban")}>Board by stage</button>
          </div>
        </div>
      </div>
      {(!view || view.mine || (admin && view.is_standard)) && (
        <label className="field"><span>Who sees it</span>
          <select className="input" value={audience} onChange={(e) => setAudience(e.target.value as Audience)} disabled={!!view?.is_standard}>
            <option value="me">Only me</option>
            {myRole && <option value="role">Everyone who is {ROLE_LABEL[myRole] ?? myRole} (by link and in their list)</option>}
            {admin && (!view || view.is_standard) && <option value="standard">Standard view: everyone in {role === "workspace" ? "the Workspace" : "the Sales app"}</option>}
            {admin && !view && role === "workspace" && <option value="standard_sales">Standard view: everyone in the Sales app</option>}
          </select>
        </label>
      )}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={() => save()} disabled={busy || !name.trim()}>{busy ? "Saving…" : "Save view"}</button>
      {view && <button type="button" className="btn quiet block" onClick={() => save(true)} disabled={busy}>Remove this view</button>}
    </Sheet>
  );
}
