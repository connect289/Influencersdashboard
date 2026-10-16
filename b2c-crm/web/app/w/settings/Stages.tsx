"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { when } from "@/lib/format";
import { stageSave, subStageSave, type StageAdmin } from "../admin-actions";

type Stage = StageAdmin["stages"][number];
type Sub = Stage["sub_stages"][number];

export const REQUIRED_LABEL: Record<string, string> = {
  call_attempt: "A logged call attempt", contact: "A logged call or an inbound reply", profile: "Course, qualification and timeline on file",
  followup: "A scheduled follow-up", programme_shared: "A programme shared or explained", application: "An application",
  checklist: "The document checklist updated", enrollment: "Fee, enrolment date and proof", comment: "A comment",
};
const CANON_LABEL: Record<string, string> = { assigned: "assigned", contacted: "contacted", counselled: "counselled", applied: "applied", enrolled: "enrolled", lost: "lost" };

function useRun(onDone?: () => void) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const run = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>) => start(async () => {
    const r = await fn();
    if (!r.ok) return setError(r.error ?? "That did not work.");
    setError(null);
    toast.success(r.notice ?? "Saved.");
    onDone?.();
    router.refresh();
  });
  return { busy, error, run };
}

/** Stages and sub-stages (spec B5.1, B15): names, what each stage requires, switching off; ids and the canonical stage never change. */
export function Stages({ data, journeys }: { data: StageAdmin; journeys: { key: string; name: string }[] }) {
  const [stage, setStage] = useState<Stage | null>(null);
  const [sub, setSub] = useState<{ stage: Stage; sub: Sub | null } | null>(null);
  const toggle = useRun();
  return (
    <div className="stack">
      <p className="note">Renaming a stage never changes its canonical stage (what the master lead table sees). A stage or sub-stage with leads in it cannot be switched off or renamed: add a new sub-stage and switch the old one off instead. Every change is kept below.</p>
      {data.stages.map((s) => (
        <section key={s.id} className="panel" style={{ opacity: s.active ? 1 : 0.6 }}>
          <header>
            <h3>{s.rank}. {s.name} <span className="chip line">{CANON_LABEL[s.canon] ?? s.canon}</span>{!s.active && <span className="chip line"> Off</span>}</h3>
            <span className="row" style={{ gap: 6 }}><span className="small muted">{s.leads} active leads</span>
              <button type="button" className="btn quiet sm" onClick={() => setStage(s)}>Edit stage</button></span>
          </header>
          <div className="body stack" style={{ gap: 8 }}>
            <p className="small">Needs: {s.required.length ? s.required.map((r) => REQUIRED_LABEL[r] ?? r).join("; ") : "nothing"}{s.reachable_from_any ? " · reachable from any open stage" : ""}</p>
            <div className="table-wrap"><table>
              <thead><tr><th>Sub-stage</th><th className="right">Leads</th><th>Comment</th>{s.canon === "lost" && <><th>Back to the pool</th><th>Journey · first message</th></>}<th /></tr></thead>
              <tbody>
                {s.sub_stages.length === 0 && <tr><td colSpan={6} className="muted">No sub-stages.</td></tr>}
                {s.sub_stages.map((x) => (
                  <tr key={x.id} style={{ opacity: x.active ? 1 : 0.55 }}>
                    <td>{x.name}{!x.active && <span className="chip line" style={{ marginLeft: 4 }}>Off</span>}</td>
                    <td className="right num">{x.leads}</td>
                    <td>{x.comment_required ? "Required" : "Optional"}</td>
                    {s.canon === "lost" && <><td>{x.returns_to_pool ? "Yes" : "Never"}</td><td className="small">{x.returns_to_pool ? `${journeys.find((j) => j.key === x.journey)?.name ?? x.journey ?? "default"} · after ${x.first_message_days ?? 0} days` : "—"}</td></>}
                    <td className="row" style={{ gap: 4, justifyContent: "flex-end" }}>
                      <button type="button" className="btn quiet sm" onClick={() => setSub({ stage: s, sub: x })}>Edit</button>
                      <button type="button" className="btn quiet sm" disabled={toggle.busy}
                        onClick={() => toggle.run(() => subStageSave({ id: x.id, stage_id: s.id, name: x.name, returns_to_pool: x.returns_to_pool, comment_required: x.comment_required, active: !x.active, reason: x.active ? "switched off in Settings" : "switched on in Settings" }))}>
                        {x.active ? "Switch off" : "Switch on"}</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table></div>
            <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} onClick={() => setSub({ stage: s, sub: null })}><Plus className="icon s" aria-hidden />Add a sub-stage</button>
          </div>
        </section>
      ))}
      {toggle.error && <p className="error" role="alert">{toggle.error}</p>}
      <section className="panel">
        <header><h3>Change history</h3><span className="small muted">last 100</span></header>
        <div className="body">
          {data.history.length === 0 ? <p className="note">No changes yet.</p> : (
            <div className="table-wrap" style={{ boxShadow: "none" }}><table>
              <thead><tr><th>When</th><th>Who</th><th>What</th><th>Reason</th></tr></thead>
              <tbody>{data.history.map((h, i) => <tr key={i}><td className="nowrap small">{when(h.at)}</td><td>{h.by ?? "—"}</td><td className="small">{describe(h, data)}</td><td className="small">{String((h.detail.new as Record<string, unknown> | undefined)?.reason ?? h.detail.reason ?? "—")}</td></tr>)}</tbody>
            </table></div>
          )}
        </div>
      </section>
      {stage && <StageSheet s={stage} onClose={() => setStage(null)} />}
      {sub && <SubSheet stage={sub.stage} sub={sub.sub} journeys={journeys} onClose={() => setSub(null)} />}
    </div>
  );
}

function describe(h: StageAdmin["history"][number], data: StageAdmin): string {
  const d = h.detail as { stage?: number; sub_stage?: number; old?: Record<string, unknown> | null; new?: Record<string, unknown> };
  const nu = d.new ?? {};
  if (h.action === "stage_changed") {
    const old = d.old ?? {};
    const name = data.stages.find((s) => s.id === d.stage)?.name ?? `Stage ${d.stage}`;
    const parts = [
      nu.name && nu.name !== old.name ? `renamed from “${String(old.name)}” to “${String(nu.name)}”` : null,
      nu.active !== undefined && nu.active !== old.active ? (nu.active ? "switched on" : "switched off") : null,
      nu.reachable_from_any !== undefined && nu.reachable_from_any !== old.reachable_from_any ? (nu.reachable_from_any ? "reachable from any stage" : "forward only") : null,
      nu.required && JSON.stringify(nu.required) !== JSON.stringify(old.required) ? "requirements changed" : null,
    ].filter(Boolean);
    return `${name}: ${parts.join(", ") || "saved"}`;
  }
  const old = d.old;
  if (!old) return `Sub-stage “${String(nu.name)}” added`;
  const parts = [
    nu.name && nu.name !== old.name ? `renamed to “${String(nu.name)}”` : null,
    nu.active !== undefined && nu.active !== old.active ? (nu.active ? "switched on" : "switched off") : null,
  ].filter(Boolean);
  return `Sub-stage “${String(old.name)}”: ${parts.join(", ") || "edited"}`;
}

function StageSheet({ s, onClose }: { s: Stage; onClose: () => void }) {
  const { busy, error, run } = useRun(onClose);
  const [name, setName] = useState(s.name);
  const [req, setReq] = useState<string[]>(s.required);
  const [any, setAny] = useState(s.reachable_from_any);
  const [active, setActive] = useState(s.active);
  const [why, setWhy] = useState("");
  const fixed = [1, 9, 10].includes(s.id);
  return (
    <Sheet title={`Stage ${s.rank}: ${s.name}`} onClose={onClose}>
      <label className="field"><span>Name counsellors see</span><input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={60} /></label>
      <div className="field"><span>Required to enter</span><div className="pills">
        {Object.entries(REQUIRED_LABEL).map(([k, l]) => (
          <button key={k} type="button" className="pill" aria-pressed={req.includes(k)} onClick={() => setReq(req.includes(k) ? req.filter((x) => x !== k) : [...req, k])}>{l}</button>
        ))}
      </div></div>
      <label className="checkbox"><input type="checkbox" checked={any} onChange={(e) => setAny(e.target.checked)} /> Reachable from any open stage (a move back without approval)</label>
      <label className="checkbox"><input type="checkbox" checked={active} disabled={fixed} onChange={(e) => setActive(e.target.checked)} /> Active{fixed ? " (New Lead, Enrolled and Lost are always on)" : ""}</label>
      <p className="note">Canonical stage: <b>{s.canon}</b>. It stays as it is; it is what the master lead table sees.</p>
      <label className="field"><span>Reason (kept in the history)</span><input className="input" value={why} onChange={(e) => setWhy(e.target.value)} maxLength={300} /></label>
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" disabled={busy || name.trim().length < 2 || why.trim().length < 3}
        onClick={() => run(() => stageSave({ id: s.id, name, required: req as never, reachable_from_any: any, active, reason: why }))}>{busy ? "Saving…" : "Save stage"}</button>
    </Sheet>
  );
}

function SubSheet({ stage, sub, journeys, onClose }: { stage: Stage; sub: Sub | null; journeys: { key: string; name: string }[]; onClose: () => void }) {
  const { busy, error, run } = useRun(onClose);
  const lost = stage.canon === "lost";
  const [f, setF] = useState({
    name: sub?.name ?? "", rank: sub?.rank != null ? String(sub.rank) : "", returns_to_pool: sub?.returns_to_pool ?? lost, journey: sub?.journey ?? "",
    days: sub?.first_message_days != null ? String(sub.first_message_days) : "", comment: sub?.comment_required ?? false, active: sub?.active ?? true, why: "",
  });
  const set = <K extends keyof typeof f>(k: K, v: (typeof f)[K]) => setF({ ...f, [k]: v });
  return (
    <Sheet title={sub ? `Sub-stage: ${sub.name}` : `New sub-stage in ${stage.name}`} onClose={onClose}>
      <label className="field"><span>Name</span><input className="input" value={f.name} onChange={(e) => set("name", e.target.value)} maxLength={80} /></label>
      {sub && sub.leads > 0 && <p className="note">{sub.leads} active leads are in it, so it cannot be renamed: add a new one and switch this one off.</p>}
      <label className="field"><span>Order (smaller first; empty puts it last)</span><input className="input num" type="number" min={0} value={f.rank} onChange={(e) => set("rank", e.target.value)} /></label>
      <label className="checkbox"><input type="checkbox" checked={f.comment} onChange={(e) => set("comment", e.target.checked)} /> A comment is required</label>
      {lost && <>
        <label className="checkbox"><input type="checkbox" checked={f.returns_to_pool} onChange={(e) => set("returns_to_pool", e.target.checked)} /> Goes back to the nurture pool</label>
        {f.returns_to_pool && <div className="grid g2" style={{ gap: 10 }}>
          <label className="field"><span>Journey it starts</span><select className="input" value={f.journey} onChange={(e) => set("journey", e.target.value)}>
            <option value="">The default</option>{journeys.map((j) => <option key={j.key} value={j.key}>{j.name}</option>)}
            {f.journey && !journeys.some((j) => j.key === f.journey) && <option value={f.journey}>{f.journey}</option>}
          </select></label>
          <label className="field"><span>First message after (days)</span><input className="input num" type="number" min={0} max={365} value={f.days} onChange={(e) => set("days", e.target.value)} /></label>
        </div>}
      </>}
      <label className="checkbox"><input type="checkbox" checked={f.active} onChange={(e) => set("active", e.target.checked)} /> Active (counsellors can choose it)</label>
      <label className="field"><span>Reason (kept in the history)</span><input className="input" value={f.why} onChange={(e) => set("why", e.target.value)} maxLength={300} /></label>
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" disabled={busy || f.name.trim().length < 2 || f.why.trim().length < 3}
        onClick={() => run(() => subStageSave({
          id: sub?.id ?? null, stage_id: stage.id, name: f.name, rank: f.rank === "" ? null : Number(f.rank), returns_to_pool: lost ? f.returns_to_pool : false,
          journey: lost && f.returns_to_pool ? f.journey || null : null, first_message_days: lost && f.returns_to_pool && f.days !== "" ? Number(f.days) : null,
          comment_required: f.comment, active: f.active, reason: f.why,
        }))}>{busy ? "Saving…" : "Save sub-stage"}</button>
    </Sheet>
  );
}
