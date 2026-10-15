"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ArrowDown, ArrowUp, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { FACT_FIELDS, FALLBACK_LABEL, LOGIC_LABEL, OP_LABEL } from "@/lib/labels";
import { perfPreview, ruleSave, rulesReorder } from "../actions";
import type { Pool } from "./Pools";

type Cond = { field: string; op: string; value?: unknown };
export type Rule = {
  id: number; position: number; name: string; enabled: boolean; condition: { all?: Cond[]; any?: Cond[] }; logic: string; params: Record<string, unknown>;
  pool_id: number | null; fallbacks: string[]; applies_from: string; is_catch_all: boolean;
};

const fieldLabel = (f: string) => FACT_FIELDS.find((x) => x.field === f)?.label ?? f;
function describe(c: { all?: Cond[]; any?: Cond[] }): string {
  const one = (x: Cond) => `${fieldLabel(x.field)} ${OP_LABEL[x.op] ?? x.op}${x.value === undefined || x.value === null || x.op.startsWith("is_") || x.op === "not_null" ? "" : ` ${Array.isArray(x.value) ? x.value.join(", ") : String(x.value)}`}`;
  const all = (c.all ?? []).map(one).join(" and ");
  const any = (c.any ?? []).map(one).join(" or ");
  return [all, any && `(${any})`].filter(Boolean).join(" and ") || "Every lead";
}

/** The ordered rules (spec B7.2). The catch-all is always last and cannot be moved or switched off. */
export function Rules({ rules, pools, admin }: { rules: Rule[]; pools: Pool[]; admin: boolean }) {
  const router = useRouter();
  const [edit, setEdit] = useState<Rule | "new" | null>(null);
  const [busy, start] = useTransition();
  const movable = rules.filter((r) => !r.is_catch_all);
  const move = (i: number, d: -1 | 1) => {
    const order = movable.map((r) => r.id);
    const j = i + d;
    if (j < 0 || j >= order.length) return;
    [order[i], order[j]] = [order[j]!, order[i]!];
    start(async () => {
      const r = await rulesReorder(order);
      if (!r.ok) return void toast.error(r.error);
      router.refresh();
    });
  };
  const toggle = (r: Rule) => start(async () => {
    const res = await ruleSave({ id: r.id, name: r.name, enabled: !r.enabled });
    if (!res.ok) return void toast.error(res.error);
    router.refresh();
  });
  return (
    <div className="stack">
      <div className="row between">
        <p className="note">Each rule picks from its pool among people who are working now, not on leave or away, and under their caps. Test leads go only to test users or the Admin.</p>
        {admin && <button type="button" className="btn primary sm" onClick={() => setEdit("new")}><Plus className="icon s" aria-hidden />New rule</button>}
      </div>
      <div className="list">
        {rules.map((r) => {
          const i = movable.findIndex((x) => x.id === r.id);
          return (
            <div key={r.id} className="li" style={{ gridTemplateColumns: "auto 1fr auto" }}>
              <span className="avatar">{r.is_catch_all ? "∞" : i + 1}</span>
              <span className="t ellipsis">{r.name}{!r.enabled && <span className="chip line"> Off</span>}</span>
              <span className="row" style={{ gap: 4 }}>
                {admin && !r.is_catch_all && (
                  <>
                    <button type="button" className="btn quiet sm" disabled={busy || i === 0} onClick={() => move(i, -1)} aria-label="Move up"><ArrowUp className="icon s" aria-hidden /></button>
                    <button type="button" className="btn quiet sm" disabled={busy || i === movable.length - 1} onClick={() => move(i, 1)} aria-label="Move down"><ArrowDown className="icon s" aria-hidden /></button>
                    <button type="button" className="btn quiet sm" disabled={busy} onClick={() => toggle(r)}>{r.enabled ? "Switch off" : "Switch on"}</button>
                  </>
                )}
                {admin && <button type="button" className="btn ghost sm" onClick={() => setEdit(r)}>Edit</button>}
              </span>
              <span className="s">
                When {describe(r.condition)} → {LOGIC_LABEL[r.logic] ?? r.logic} in {pools.find((p) => p.id === r.pool_id)?.name ?? "everyone"}; if nobody: {r.fallbacks.map((f) => FALLBACK_LABEL[f] ?? f).join(", then ")}.
              </span>
            </div>
          );
        })}
      </div>
      {edit && <RuleSheet rule={edit === "new" ? null : edit} pools={pools} onClose={() => setEdit(null)} />}
    </div>
  );
}

const OPS = Object.keys(OP_LABEL);
const NO_VALUE = new Set(["is_true", "is_false", "is_null", "not_null"]);

function RuleSheet({ rule, pools, onClose }: { rule: Rule | null; pools: Pool[]; onClose: () => void }) {
  const router = useRouter();
  const [name, setName] = useState(rule?.name ?? "");
  const [logic, setLogic] = useState(rule?.logic ?? "round_robin");
  const [pool, setPool] = useState<string>(rule?.pool_id ? String(rule.pool_id) : "");
  const [conds, setConds] = useState<Cond[]>(rule?.condition.all ?? []);
  const [fallbacks, setFallbacks] = useState<string[]>(rule?.fallbacks ?? ["next_rule"]);
  const [match, setMatch] = useState<string[]>((rule?.params?.match as string[] | undefined) ?? ["language"]);
  const [perf, setPerf] = useState({ window_days: Number(rule?.params?.window_days ?? 90), floor: Number(rule?.params?.floor ?? 0.5), cap: Number(rule?.params?.cap ?? 2) });
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const catchAll = !!rule?.is_catch_all;

  const setCond = (i: number, c: Partial<Cond>) => setConds(conds.map((x, j) => (j === i ? { ...x, ...c } : x)));
  const parseValue = (op: string, v: unknown) => (NO_VALUE.has(op) ? undefined : op === "in" || op === "not_in" ? String(v ?? "").split(",").map((s) => s.trim()).filter(Boolean) : op === "gte" || op === "lte" ? Number(v) : v);

  const save = () => start(async () => {
    const r = await ruleSave({
      id: rule?.id ?? null, name, logic, pool_id: pool ? Number(pool) : null, fallbacks,
      condition: catchAll ? {} : { all: conds.map((c) => ({ field: c.field, op: c.op, ...(NO_VALUE.has(c.op) ? {} : { value: parseValue(c.op, c.value) }) })) },
      params: logic === "skill_match" ? { match } : logic === "performance" ? perf : {},
    });
    if (!r.ok) return setError(r.error);
    toast.success(r.notice ?? "Saved.");
    onClose();
    router.refresh();
  });

  return (
    <Sheet title={rule ? `Edit rule: ${rule.name}` : "New rule"} onClose={onClose}>
      <label className="field"><span>Name</span><input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={120} /></label>
      {!catchAll && (
        <div className="field">
          <span>When (all of these)</span>
          <div className="stack" style={{ gap: 6 }}>
            {conds.length === 0 && <p className="note">No condition: every lead matches.</p>}
            {conds.map((c, i) => (
              <div key={i} className="row wrap" style={{ gap: 6 }}>
                <select className="input" style={{ width: "auto" }} value={c.field} onChange={(e) => setCond(i, { field: e.target.value })} aria-label="Field">
                  {FACT_FIELDS.map((f) => <option key={f.field} value={f.field}>{f.label}</option>)}
                </select>
                <select className="input" style={{ width: "auto" }} value={c.op} onChange={(e) => setCond(i, { op: e.target.value })} aria-label="Test">
                  {OPS.map((o) => <option key={o} value={o}>{OP_LABEL[o]}</option>)}
                </select>
                {!NO_VALUE.has(c.op) && (
                  <input className="input grow" value={Array.isArray(c.value) ? c.value.join(", ") : String(c.value ?? "")} onChange={(e) => setCond(i, { value: e.target.value })}
                    placeholder={c.op === "in" || c.op === "not_in" ? "Comma-separated" : "Value"} aria-label="Value" />
                )}
                <button type="button" className="btn quiet sm" onClick={() => setConds(conds.filter((_, j) => j !== i))} aria-label="Remove"><Trash2 className="icon s" aria-hidden /></button>
              </div>
            ))}
            <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} onClick={() => setConds([...conds, { field: "source", op: "eq", value: "" }])}><Plus className="icon s" aria-hidden />Add condition</button>
          </div>
        </div>
      )}
      <label className="field"><span>Then give it by</span><select className="input" value={logic} onChange={(e) => setLogic(e.target.value)}>
        {Object.entries(LOGIC_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
      </select></label>
      {logic === "skill_match" && (
        <div className="field"><span>Match on</span><div className="pills">
          {["language", "programme", "university", "level"].map((m) => (
            <button key={m} type="button" className="pill" aria-pressed={match.includes(m)} onClick={() => setMatch(match.includes(m) ? match.filter((x) => x !== m) : [...match, m])}>{m}</button>
          ))}
        </div></div>
      )}
      {logic === "performance" && (
        <div className="field"><span>Performance</span>
          <div className="grid g3">
            <label className="field"><span>Conversion over</span><select className="input" value={perf.window_days} onChange={(e) => setPerf({ ...perf, window_days: Number(e.target.value) })}>
              <option value={30}>30 days</option><option value={90}>90 days</option></select></label>
            <label className="field"><span>At least (× an equal share)</span><select className="input" value={perf.floor} onChange={(e) => setPerf({ ...perf, floor: Number(e.target.value) })}>
              {[0.25, 0.5, 0.75].map((v) => <option key={v} value={v}>{v}</option>)}</select></label>
            <label className="field"><span>At most (× an equal share)</span><select className="input" value={perf.cap} onChange={(e) => setPerf({ ...perf, cap: Number(e.target.value) })}>
              {[1.5, 2, 3].map((v) => <option key={v} value={v}>{v}</option>)}</select></label>
          </div>
          <p className="note">Better converters get more turns. A counsellor with fewer than 20 leads in the window counts at the team&apos;s rate, and small samples lean towards it, so one lucky enrolment does not swing the shares.</p>
          {rule && <PerfPreview ruleId={rule.id} />}
        </div>
      )}
      <label className="field"><span>Among</span><select className="input" value={pool} onChange={(e) => setPool(e.target.value)}>
        <option value="">Everyone who takes leads</option>
        {pools.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
      </select></label>
      <div className="field"><span>If nobody can take it (in order)</span><div className="pills">
        {Object.entries(FALLBACK_LABEL).map(([k, v]) => {
          const at = fallbacks.indexOf(k);
          return <button key={k} type="button" className="pill" aria-pressed={at >= 0} onClick={() => setFallbacks(at >= 0 ? fallbacks.filter((x) => x !== k) : [...fallbacks, k])}>{at >= 0 ? `${at + 1}. ` : ""}{v}</button>;
        })}
      </div></div>
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" disabled={busy || name.trim().length < 2 || fallbacks.length === 0} onClick={save}>{busy ? "Saving…" : "Save rule"}</button>
      <p className="note">A change applies to the next lead; past decisions keep the rule they used. Run a simulation first if you are unsure.</p>
    </Sheet>
  );
}

type Preview = { team_rate: number; window_days: number; floor: number; cap: number; rows: { user_id: string; name: string; assigned: number; enrolled: number; rate: number | null; new: boolean; share: number; weight: number }[] };

/** The shares this rule would use now (as saved), for every active person in its pool. */
function PerfPreview({ ruleId }: { ruleId: number }) {
  const [p, setP] = useState<Preview | null>(null);
  const [busy, start] = useTransition();
  if (!p) return <button type="button" className="btn ghost sm" style={{ justifySelf: "start" }} disabled={busy} onClick={() => start(async () => {
    const r = await perfPreview(ruleId);
    if (!r.ok || !r.data) return void toast.error(r.ok ? "No preview." : r.error);
    setP(r.data as Preview);
  })}>Show current shares (as saved)</button>;
  return (
    <div className="stack" style={{ gap: 4 }}>
      <span className="small">Team conversion {(p.team_rate * 100).toFixed(1)}% over {p.window_days} days; shares between {p.floor}× and {p.cap}× an equal share.</span>
      <div className="table-wrap"><table>
        <thead><tr><th>Counsellor</th><th className="right">Leads</th><th className="right">Enrolled</th><th className="right">Conversion</th><th className="right">Share of turns</th></tr></thead>
        <tbody>{p.rows.map((r) => <tr key={r.user_id}><td>{r.name}{r.new ? <span className="chip line" style={{ marginLeft: 4 }}>team rate</span> : null}</td><td className="right num">{r.assigned}</td>
          <td className="right num">{r.enrolled}</td><td className="right num">{r.rate === null ? "–" : `${(r.rate * 100).toFixed(1)}%`}</td><td className="right num">{(r.share * 100).toFixed(1)}%</td></tr>)}</tbody>
      </table></div>
    </div>
  );
}
