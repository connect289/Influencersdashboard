"use client";
import { useMemo, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowDown, ArrowLeft, ArrowUp, Copy, Pause, Play, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Page } from "@/components/shell/Page";
import { Conditions } from "@/components/marketing/Conditions";
import { inr, when } from "@/lib/format";
import type { Stage } from "@/lib/types";
import { fromFilter, SEGMENT_FIELDS, toFilter, type Condition } from "@/lib/viewFields";
import { journeyClone, journeyPublish, journeySave, journeySet, journeyTest } from "../../../nurture-actions";

export type Step = { id: string; type: string; channel?: string; template?: string | number; days?: number; hours?: number; minutes?: number; until?: string;
  on?: string; classes?: string[]; pct?: number; filters?: unknown; then?: string; else?: string; delta?: number; tag?: string; title?: string; journey?: string; reason?: string;
  field?: string; value?: string };
export type JourneyFull = { id: number; key: string; name: string; description: string | null; trigger: Record<string, unknown>; priority: number; allow_active_sales: boolean;
  test_mode: boolean; status: string; draft_steps: Step[]; current_version: number; updated_at: string };

const TYPES: [string, string][] = [["send", "Send a message"], ["wait", "Wait"], ["branch", "Branch"], ["score", "Change the score"], ["tag", "Add a tag"],
  ["update", "Update a field"], ["task", "Task for the Admin"], ["assign", "Hand to a counsellor"], ["move", "Move to another journey"], ["exit", "Exit"]];
/** What an "update" step may change (b39 journey_check_steps); profile fields also go to the master lead table. */
const UPDATE_FIELDS: [string, string][] = [["temperature", "Temperature"], ["untag", "Remove a tag"], ["preferred_language", "Preferred language"],
  ["enrollment_timeline", "Timeline"], ["annual_budget_inr", "Budget (₹ a year)"], ["study_mode", "Study mode"], ["programme_level", "Level"]];
const TRIGGERS: [string, string][] = [["pool_entry", "Leads entering the pool"], ["segment", "Leads in a segment"], ["tag", "Leads with a tag"],
  ["inactive", "Pooled leads inactive for some days"], ["field", "Leads whose details match"], ["date", "A date arrives"], ["email_engaged", "Opened or clicked an email"],
  ["wa_reply", "Replied on WhatsApp"], ["manual", "Only when started by hand"]];
const REPLY_CLASSES = ["positive", "question", "negative", "other"];
const CLASSES = ["positive", "question", "negative", "other"];
const REASONS: [string, string][] = [["partner_lost", "Partner lost"], ["counsellor_lost", "Counsellor lost"], ["not_qualified", "Not qualified"]];

function newId(steps: Step[]) { let n = steps.length + 1; while (steps.some((s) => s.id === `s${n}`)) n++; return `s${n}`; }

/** The journey builder (spec B9.4): steps as a vertical flow with live counts; draft, publish, versions, test mode. */
export function JourneyEditor({ j, stats, versions, templates, segments, journeys, admin, stages }: {
  j: JourneyFull; stats: { at_step: Record<string, number>; entered: number; running: number; completed: number; exits: Record<string, number>; blocked: Record<string, number>; re_engaged: number; enrolled: number; sent: number; test_runs: number; wa_cost?: number; emails?: number };
  stages: Stage[];
  versions: { version: number; published_at: string; steps: unknown[] }[]; templates: { whatsapp: { name: string; status: string }[]; email: { name: string; status: string }[] };
  segments: { id: number; name: string }[]; journeys: { key: string; name: string }[]; admin: boolean;
}) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [steps, setSteps] = useState<Step[]>(j.draft_steps ?? []);
  const [name, setName] = useState(j.name);
  const [description, setDescription] = useState(j.description ?? "");
  const [trigger, setTrigger] = useState<Record<string, unknown>>(j.trigger ?? { type: "manual" });
  const [priority, setPriority] = useState(j.priority);
  const [testMode, setTestMode] = useState(j.test_mode);
  const [allowActive, setAllowActive] = useState(j.allow_active_sales);
  const [testLead, setTestLead] = useState("");
  const [conds, setConds] = useState<Condition[]>((((j.trigger?.filters as { all?: Condition[] } | undefined)?.all) ?? []).map(fromFilter));
  const setConditions = (c: Condition[]) => {
    setConds(c);
    setTrigger((t) => {
      const rest = { ...t };
      delete rest.filters;
      return c.length ? { ...rest, filters: { all: c.map(toFilter) } } : rest;
    });
  };
  const published = versions[0]?.steps;
  const dirty = useMemo(() => JSON.stringify(steps) !== JSON.stringify(j.draft_steps) || name !== j.name || description !== (j.description ?? "")
    || JSON.stringify(trigger) !== JSON.stringify(j.trigger) || priority !== j.priority || testMode !== j.test_mode || allowActive !== j.allow_active_sales, [steps, name, description, trigger, priority, testMode, allowActive, j]);
  const unpublished = JSON.stringify(published ?? null) !== JSON.stringify(j.draft_steps);

  const run = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>) => start(async () => {
    const r = await fn();
    if (!r.ok) return void toast.error(r.error);
    if (r.notice) toast.success(r.notice);
    router.refresh();
  });
  const save = () => run(() => journeySave({ id: j.id, name, description, trigger, priority, test_mode: testMode, ...(admin ? { allow_active_sales: allowActive } : {}), draft_steps: steps }));
  const set = (i: number, p: Partial<Step>) => setSteps((s) => s.map((x, k) => (k === i ? { ...x, ...p } : x)));
  const move = (i: number, d: number) => setSteps((s) => { const c = [...s]; const [x] = c.splice(i, 1); c.splice(i + d, 0, x!); return c; });
  const add = (type: string) => setSteps((s) => [...s, { id: newId(s), type, ...(type === "send" ? { channel: "whatsapp", template: templates.whatsapp[0]?.name } : type === "wait" ? { days: 3 }
    : type === "branch" ? { on: "reply", classes: ["positive"] } : type === "update" ? { field: "temperature", value: "warm" } : {}) }]);
  const pickTrigger = (type: string) => {
    const fresh: Record<string, unknown> = type === "field" ? { type, filters: { all: [{ field: "temperature", op: "eq", value: "hot" }] } }
      : type === "date" ? { type, at: "", days_before: 0 } : type === "email_engaged" ? { type, kind: "open", within_days: 2 }
      : type === "wa_reply" ? { type, classes: ["positive", "question"], within_days: 2 } : { type };
    setTrigger(fresh);
    setConds(type === "field" ? [{ field: "temperature", op: "eq", value: "hot" }] : []);
  };
  const tType = String(trigger.type ?? "manual");

  return (
    <Page title={j.name} sub={`Version ${j.current_version}${unpublished ? " · the draft has unpublished changes" : ""} · ${j.status}${j.test_mode ? " · test mode" : ""}`}
      back={<Link className="btn quiet sm" href="/w/nurture?tab=journeys" aria-label="Back to journeys"><ArrowLeft className="icon s" aria-hidden /></Link>}
      actions={
        <span className="row" style={{ gap: 4 }}>
          {j.status !== "active" && j.current_version > 0 && <button type="button" className="btn ghost sm" disabled={busy} onClick={() => run(() => journeySet(j.id, "active"))}><Play className="icon s" aria-hidden />Run</button>}
          {j.status === "active" && <button type="button" className="btn ghost sm" disabled={busy} onClick={() => run(() => journeySet(j.id, "paused"))}><Pause className="icon s" aria-hidden />Pause</button>}
          <button type="button" className="btn quiet sm" disabled={busy} onClick={() => start(async () => { const r = await journeyClone(j.id); if (r.ok) router.push(`/w/nurture/journeys/${r.data}`); else toast.error(r.error); })} aria-label="Copy journey"><Copy className="icon s" aria-hidden /></button>
        </span>
      }>
      <div className="grid g-lead">
        <div className="stack">
          <section className="panel">
            <header><h3>Steps</h3><span className="small muted">Counts: leads at each step now</span></header>
            <div className="body">
              {steps.length === 0 && <p className="note">Add the first step.</p>}
              {steps.map((s, i) => (
                <div key={s.id} className="jstep">
                  <div className="jhead">
                    <b className="mono">{i + 1}</b>
                    <select className="input" value={s.type} onChange={(e) => set(i, { type: e.target.value })} aria-label="Step type" style={{ maxWidth: 220 }}>
                      {TYPES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                    </select>
                    <span className="jcount">{stats.at_step[String(i)] ?? 0} here</span>
                    <button type="button" className="btn quiet sm" disabled={i === 0} onClick={() => move(i, -1)} aria-label="Move up"><ArrowUp className="icon s" aria-hidden /></button>
                    <button type="button" className="btn quiet sm" disabled={i === steps.length - 1} onClick={() => move(i, 1)} aria-label="Move down"><ArrowDown className="icon s" aria-hidden /></button>
                    <button type="button" className="btn quiet sm" onClick={() => setSteps((x) => x.filter((_, k) => k !== i))} aria-label="Remove step"><Trash2 className="icon s" aria-hidden /></button>
                  </div>
                  <StepFields s={s} set={(p) => set(i, p)} steps={steps} templates={templates} journeys={journeys} />
                </div>
              ))}
              <div className="row wrap" style={{ gap: 4 }}>
                {TYPES.map(([k, l]) => <button key={k} type="button" className="btn quiet sm" onClick={() => add(k)}><Plus className="icon s" aria-hidden />{l}</button>)}
              </div>
            </div>
          </section>
          <div className="row wrap" style={{ gap: 6 }}>
            <button type="button" className="btn primary" disabled={busy || !dirty} onClick={save}>{busy ? "Saving…" : "Save draft"}</button>
            <button type="button" className="btn ghost" disabled={busy || dirty || !unpublished} title={dirty ? "Save the draft first" : undefined}
              onClick={() => run(() => journeyPublish(j.id, stats.running > 0 && confirm(`${stats.running} leads are in this journey. Move them to the new version? (Cancel keeps them on their version.)`)))}>Publish the draft</button>
          </div>
        </div>
        <div className="stack">
          <section className="panel">
            <header><h3>Settings</h3></header>
            <div className="body">
              <label className="field"><span>Name</span><input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={100} /></label>
              <label className="field"><span>Description</span><input className="input" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={300} /></label>
              <label className="field"><span>Who enters</span>
                <select className="input" value={tType} onChange={(e) => pickTrigger(e.target.value)}>
                  {TRIGGERS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                </select></label>
              {tType === "pool_entry" && (
                <>
                  <div className="pills">{REASONS.map(([k, l]) => {
                    const on = ((trigger.reasons as string[] | undefined) ?? []).includes(k);
                    return <button key={k} type="button" className="pill" aria-pressed={on} onClick={() => setTrigger({ ...trigger, reasons: on ? (trigger.reasons as string[]).filter((x) => x !== k) : [...((trigger.reasons as string[] | undefined) ?? []), k] })}>{l}</button>;
                  })}</div>
                  <label className="field"><span>Lost sub-stages (comma separated, optional)</span>
                    <input className="input" value={((trigger.sub_stages as string[] | undefined) ?? []).join(", ")} onChange={(e) => setTrigger({ ...trigger, sub_stages: e.target.value.split(",").map((x) => x.trim()).filter(Boolean) })} /></label>
                  <p className="note">The lost sub-stage&apos;s own journey wins; then the first matching journey by priority.</p>
                </>
              )}
              {tType === "segment" && (
                <select className="input" value={String(trigger.segment_id ?? "")} onChange={(e) => setTrigger({ type: "segment", segment_id: Number(e.target.value) })} aria-label="Segment">
                  <option value="">Choose a segment</option>{segments.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
                </select>
              )}
              {tType === "tag" && <input className="input" value={String(trigger.tag ?? "")} onChange={(e) => setTrigger({ type: "tag", tag: e.target.value })} placeholder="Tag" aria-label="Tag" />}
              {tType === "inactive" && <label className="field"><span>Days without activity</span><input className="input num" type="number" min={1} value={Number(trigger.days ?? 30)} onChange={(e) => setTrigger({ type: "inactive", days: Number(e.target.value) })} /></label>}
              {tType === "field" && (
                <div className="field"><span>Leads where all of these hold (each lead enters once)</span>
                  <Conditions fields={SEGMENT_FIELDS} stages={stages} value={conds} onChange={setConditions} /></div>
              )}
              {tType === "date" && (
                <>
                  <div className="row wrap" style={{ gap: 6 }}>
                    <label className="field grow"><span>Date (IST)</span><input className="input" type="date" value={String(trigger.at ?? "")} onChange={(e) => setTrigger({ ...trigger, at: e.target.value })} /></label>
                    <label className="field"><span>Start … days before</span><input className="input num" type="number" min={0} max={365} value={Number(trigger.days_before ?? 0)} onChange={(e) => setTrigger({ ...trigger, days_before: Number(e.target.value) })} /></label>
                  </div>
                  <div className="field"><span>Only leads where (optional)</span><Conditions fields={SEGMENT_FIELDS} stages={stages} value={conds} onChange={setConditions} /></div>
                  <p className="note">Leads enter from that many days before the date until the end of the day itself: an intake deadline, an exam date.</p>
                </>
              )}
              {tType === "email_engaged" && (
                <div className="row wrap" style={{ gap: 6 }}>
                  <label className="field grow"><span>When a lead</span>
                    <select className="input" value={String(trigger.kind ?? "open")} onChange={(e) => setTrigger({ ...trigger, kind: e.target.value })}><option value="open">opened a marketing email</option><option value="click">clicked a link in one</option></select></label>
                  <label className="field"><span>In the last … days</span><input className="input num" type="number" min={1} max={30} value={Number(trigger.within_days ?? 2)} onChange={(e) => setTrigger({ ...trigger, within_days: Number(e.target.value) })} /></label>
                </div>
              )}
              {tType === "wa_reply" && (
                <>
                  <div className="pills">{REPLY_CLASSES.map((c) => {
                    const cur = (trigger.classes as string[] | undefined) ?? [];
                    const on = cur.includes(c);
                    return <button key={c} type="button" className="pill" aria-pressed={on} onClick={() => setTrigger({ ...trigger, classes: on ? cur.filter((x) => x !== c) : [...cur, c] })}>{c}</button>;
                  })}</div>
                  <label className="field"><span>Replied on WhatsApp in the last … days</span><input className="input num" type="number" min={1} max={30} value={Number(trigger.within_days ?? 2)} onChange={(e) => setTrigger({ ...trigger, within_days: Number(e.target.value) })} /></label>
                </>
              )}
              <label className="field"><span>Priority (lower wins)</span><input className="input num" type="number" min={0} max={1000} value={priority} onChange={(e) => setPriority(Number(e.target.value))} /></label>
              <label className="checkbox"><input type="checkbox" checked={testMode} onChange={(e) => setTestMode(e.target.checked)} /> Test mode: only test leads enter</label>
              {admin && <label className="checkbox"><input type="checkbox" checked={allowActive} onChange={(e) => setAllowActive(e.target.checked)} /> May reach leads in active sales (Admin)</label>}
            </div>
          </section>
          <section className="panel">
            <header><h3>Results</h3></header>
            <div className="body small">
              <dl className="kv">
                <dt>Entered</dt><dd>{stats.entered}</dd><dt>In it now</dt><dd>{stats.running}</dd><dt>Completed</dt><dd>{stats.completed}</dd>
                <dt>Messages sent</dt><dd>{stats.sent}</dd><dt>Emails sent</dt><dd>{stats.emails ?? 0}</dd><dt>WhatsApp spend</dt><dd>{inr(stats.wa_cost ?? 0)}</dd>
                <dt>Re-engaged</dt><dd>{stats.re_engaged}{stats.re_engaged && stats.wa_cost ? ` (${inr(stats.wa_cost / stats.re_engaged)} each)` : ""}</dd><dt>Enrolled</dt><dd>{stats.enrolled}</dd><dt>Test runs</dt><dd>{stats.test_runs}</dd>
              </dl>
              {Object.keys(stats.exits).length > 0 && <p><b>Exits:</b> {Object.entries(stats.exits).map(([k, v]) => `${k} ${v}`).join(" · ")}</p>}
              {Object.keys(stats.blocked).length > 0 && <p><b>Held back (30 days):</b> {Object.entries(stats.blocked).map(([k, v]) => `${k.replace(/^wait: /, "")} ${v}`).join(" · ")}</p>}
            </div>
          </section>
          <section className="panel">
            <header><h3>Test on a test lead</h3></header>
            <div className="body">
              <div className="row" style={{ gap: 6 }}>
                <input className="input grow" value={testLead} onChange={(e) => setTestLead(e.target.value.replace(/\D/g, ""))} placeholder="Lead # (a test lead)" aria-label="Test lead number" />
                <button type="button" className="btn ghost sm" disabled={busy || !testLead || j.current_version === 0} onClick={() => run(() => journeyTest(j.id, Number(testLead)))}>Start</button>
              </div>
              <p className="note">Runs the published version now. Nothing reaches a student: test leads never get real messages.</p>
            </div>
          </section>
          <section className="panel">
            <header><h3>Versions</h3></header>
            <div className="body small">
              {versions.length === 0 ? <p className="note">Not published yet.</p> : versions.map((v) => <div key={v.version}>v{v.version} · {when(v.published_at)} · {v.steps.length} steps</div>)}
            </div>
          </section>
        </div>
      </div>
    </Page>
  );
}

function StepFields({ s, set, steps, templates, journeys }: { s: Step; set: (p: Partial<Step>) => void; steps: Step[]; templates: { whatsapp: { name: string; status: string }[]; email: { name: string; status: string }[] }; journeys: { key: string; name: string }[] }) {
  const target = (k: "then" | "else", label: string) => (
    <label className="field" style={{ flex: "1 1 140px" }}><span>{label}</span>
      <select className="input" value={s[k] ?? ""} onChange={(e) => set({ [k]: e.target.value || undefined })}>
        <option value="">The next step</option>{steps.filter((x) => x.id !== s.id).map((x) => <option key={x.id} value={x.id}>Step {steps.indexOf(x) + 1}</option>)}
      </select></label>
  );
  switch (s.type) {
    case "send": {
      const list = s.channel === "email" ? templates.email : templates.whatsapp;
      return (
        <div className="row wrap" style={{ gap: 6 }}>
          <select className="input" value={s.channel ?? "whatsapp"} onChange={(e) => set({ channel: e.target.value, template: (e.target.value === "email" ? templates.email : templates.whatsapp)[0]?.name })} aria-label="Channel" style={{ maxWidth: 140 }}>
            <option value="whatsapp">WhatsApp</option><option value="email">Email</option>
          </select>
          <select className="input grow" value={String(s.template ?? "")} onChange={(e) => set({ template: e.target.value })} aria-label="Template">
            {list.map((t) => <option key={t.name} value={t.name}>{t.name}{s.channel !== "email" && t.status !== "approved" ? ` (${t.status})` : ""}</option>)}
          </select>
        </div>
      );
    }
    case "wait":
      return (
        <div className="row wrap" style={{ gap: 6 }}>
          <label className="field"><span>Days</span><input className="input num" type="number" min={0} value={s.days ?? 0} onChange={(e) => set({ days: Number(e.target.value), until: undefined })} style={{ maxWidth: 90 }} /></label>
          <label className="field"><span>Hours</span><input className="input num" type="number" min={0} value={s.hours ?? 0} onChange={(e) => set({ hours: Number(e.target.value), until: undefined })} style={{ maxWidth: 90 }} /></label>
          <label className="field"><span>Or until (IST)</span><input className="input" type="time" value={s.until ?? ""} onChange={(e) => set({ until: e.target.value || undefined, days: e.target.value ? undefined : s.days })} /></label>
        </div>
      );
    case "branch":
      return (
        <div className="stack" style={{ gap: 6 }}>
          <select className="input" value={s.on ?? "reply"} onChange={(e) => set({ on: e.target.value })} aria-label="Branch on" style={{ maxWidth: 260 }}>
            <option value="reply">A reply since entering, of class…</option><option value="ab">A/B split</option><option value="condition">A condition on the lead</option>
          </select>
          {s.on === "ab" ? <label className="field"><span>% to the first path</span><input className="input num" type="number" min={1} max={99} value={s.pct ?? 50} onChange={(e) => set({ pct: Number(e.target.value) })} style={{ maxWidth: 90 }} /></label>
            : s.on === "condition" ? <label className="field"><span>Filter (JSON, as in segments)</span><textarea className="input mono" rows={3} defaultValue={JSON.stringify(s.filters ?? { all: [] })} onBlur={(e) => { try { set({ filters: JSON.parse(e.target.value) }); } catch { /* keep the last valid */ } }} /></label>
            : <div className="pills">{CLASSES.map((c) => { const on = (s.classes ?? []).includes(c); return <button key={c} type="button" className="pill" aria-pressed={on} onClick={() => set({ classes: on ? (s.classes ?? []).filter((x) => x !== c) : [...(s.classes ?? []), c] })}>{c}</button>; })}</div>}
          <div className="row wrap" style={{ gap: 6 }}>{target("then", "If yes, go to")}{target("else", "If not, go to")}</div>
        </div>
      );
    case "score": return <label className="field"><span>Points (+/-)</span><input className="input num" type="number" min={-100} max={100} value={s.delta ?? 0} onChange={(e) => set({ delta: Number(e.target.value) })} style={{ maxWidth: 100 }} /></label>;
    case "tag": return <input className="input" value={s.tag ?? ""} onChange={(e) => set({ tag: e.target.value })} placeholder="Tag" aria-label="Tag" />;
    case "update":
      return (
        <div className="row wrap" style={{ gap: 6 }}>
          <select className="input" value={s.field ?? "temperature"} onChange={(e) => set({ field: e.target.value, value: e.target.value === "temperature" ? "warm" : "" })} aria-label="Field" style={{ maxWidth: 220 }}>
            {UPDATE_FIELDS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
          {(s.field ?? "temperature") === "temperature" ? (
            <select className="input" value={s.value ?? "warm"} onChange={(e) => set({ value: e.target.value })} aria-label="Value"><option value="hot">Hot</option><option value="warm">Warm</option><option value="cold">Cold</option></select>
          ) : (
            <input className="input grow" value={s.value ?? ""} onChange={(e) => set({ value: e.target.value })} placeholder={s.field === "untag" ? "Tag to remove" : "New value"} aria-label="Value" maxLength={200} />
          )}
        </div>
      );
    case "task": return <input className="input" value={s.title ?? ""} onChange={(e) => set({ title: e.target.value })} placeholder="What the Admin should do" aria-label="Task" maxLength={200} />;
    case "move": return (
      <select className="input" value={s.journey ?? ""} onChange={(e) => set({ journey: e.target.value })} aria-label="Journey">
        <option value="">Choose a journey</option>{journeys.map((x) => <option key={x.key} value={x.key}>{x.name}</option>)}
      </select>
    );
    case "exit": return <input className="input" value={s.reason ?? ""} onChange={(e) => set({ reason: e.target.value })} placeholder="Why (shown in the results)" aria-label="Exit reason" />;
    case "assign": return <p className="note">The lead leaves the pool and goes to a counsellor by the allocation rules, as hot.</p>;
    default: return null;
  }
}
