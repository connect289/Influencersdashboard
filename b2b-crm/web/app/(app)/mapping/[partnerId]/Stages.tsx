"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight, Pencil, Plus, Trash2, Waypoints } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { conditionText, knownStages, STAGE_LABEL, suggestStage, type Condition, type StatusRule, type Studio } from "@/lib/mapping";
import { removeRule, savePipelineField, saveRule } from "./actions";
import { field, fieldBase, Label, Modal } from "@/components/ui/Modal";

type Draft = Partial<StatusRule> & { partner_stage: string };

function StatusRuleDialog({ studio, rule, onClose }: { studio: Studio; rule: Draft | null; onClose: () => void }) {
  const router = useRouter();
  const ed = studio.editing!;
  const [r, setR] = useState<Draft>(rule ?? { partner_stage: "" });
  const [conds, setConds] = useState<Condition[]>(rule?.conditions ?? []);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const set = (k: keyof StatusRule, v: unknown) => setR((cur) => ({ ...cur, [k]: v }));
  const subs = r.stage ? studio.sub_stages[r.stage] ?? [] : [];

  const save = async () => {
    setPending(true); setError(null);
    const payload = {
      id: r.id ?? null, profile_id: ed.id, partner_stage: r.partner_stage, partner_sub_stage: r.partner_sub_stage ?? null, pipeline_key: r.pipeline_key ?? null,
      conditions: conds.filter((c) => c.field.trim()).map((c) => ({ ...c, value: c.op === "in" ? String(c.value ?? "").split(",").map((x) => x.trim()).filter(Boolean) : c.value })),
      ignore: Boolean(r.ignore), ignore_reason: r.ignore_reason ?? null, stage: r.ignore ? null : r.stage ?? null, sub_stage: r.sub_stage ?? null,
      lost_reason: r.stage === "lost" ? r.lost_reason ?? null : null, is_reopen: Boolean(r.is_reopen), priority: r.priority ?? 100,
    };
    const res = await saveRule(studio.partner.id, "status", payload);
    setPending(false);
    if (!res.ok) { setError(res.error); return; }
    toast.success("Stage rule saved");
    onClose(); router.refresh();
  };

  return (
    <Modal open onClose={onClose} title={r.id ? "Edit stage rule" : "Map a partner stage"} error={error} pending={pending} onSubmit={save} wide>
      <div className="grid gap-3 sm:grid-cols-3">
        <Label text="Partner stage"><input value={r.partner_stage} onChange={(e) => set("partner_stage", e.target.value)} className={field} maxLength={200} /></Label>
        <Label text="Partner sub-stage" hint="Empty: any sub-stage"><input value={r.partner_sub_stage ?? ""} onChange={(e) => set("partner_sub_stage", e.target.value || null)} className={field} maxLength={200} /></Label>
        <Label text="Pipeline" hint={`From the field “${ed.pipeline_field}”`}>
          <select value={r.pipeline_key ?? ""} onChange={(e) => set("pipeline_key", e.target.value || null)} className={field}>
            <option value="">Every pipeline</option>
            {ed.pipelines.map((p) => <option key={p.id} value={p.key}>{p.label || p.key}</option>)}
          </select>
        </Label>
      </div>
      <fieldset className="space-y-2 rounded-lg border border-border p-3">
        <legend className="px-1 text-[13px] font-medium">Only when (optional, all must hold)</legend>
        {conds.map((c, i) => (
          <div key={i} className="grid grid-cols-[1fr_120px_1fr_auto] gap-2">
            <input value={c.field} onChange={(e) => setConds(conds.map((x, j) => j === i ? { ...x, field: e.target.value } : x))} placeholder="partner field" className={field} />
            <select value={c.op} onChange={(e) => setConds(conds.map((x, j) => j === i ? { ...x, op: e.target.value as Condition["op"] } : x))} className={field}>
              <option value="eq">equals</option><option value="neq">is not</option><option value="in">is one of</option><option value="empty">is empty</option><option value="not_empty">is filled</option>
            </select>
            <input value={Array.isArray(c.value) ? c.value.join(", ") : c.value ?? ""} disabled={c.op === "empty" || c.op === "not_empty"}
              onChange={(e) => setConds(conds.map((x, j) => j === i ? { ...x, value: e.target.value } : x))} placeholder={c.op === "in" ? "a, b, c" : "value"} className={field} />
            <Button size="sm" variant="ghost" onClick={() => setConds(conds.filter((_, j) => j !== i))} aria-label="Remove condition"><Trash2 className="size-3.5" /></Button>
          </div>
        ))}
        {conds.length < 4 && <Button size="sm" variant="ghost" onClick={() => setConds([...conds, { field: "", op: "eq", value: "" }])}><Plus className="size-3.5" /> Add a condition</Button>}
      </fieldset>
      <label className="flex items-center gap-2 text-[13px]">
        <input type="checkbox" checked={Boolean(r.ignore)} onChange={(e) => set("ignore", e.target.checked)} className="accent-[var(--primary)]" />
        Ignore this stage (it never moves the lead)
      </label>
      {r.ignore ? (
        <Label text="Why it is ignored"><input value={r.ignore_reason ?? ""} onChange={(e) => set("ignore_reason", e.target.value)} className={field} placeholder="e.g. the partner's internal housekeeping status" /></Label>
      ) : (
        <div className="grid gap-3 sm:grid-cols-3">
          <Label text="Eduwit stage">
            <select value={r.stage ?? ""} onChange={(e) => setR((cur) => ({ ...cur, stage: e.target.value || null, sub_stage: null, lost_reason: null }))} className={field}>
              <option value="">Choose…</option>
              {studio.target_stages.map((s) => <option key={s} value={s}>{STAGE_LABEL[s] ?? s}</option>)}
            </select>
          </Label>
          <Label text="Eduwit sub-stage" hint="Optional">
            <input value={r.sub_stage ?? ""} onChange={(e) => set("sub_stage", e.target.value || null)} list="sub-stages" className={field} maxLength={80} />
            <datalist id="sub-stages">{subs.map((s) => <option key={s} value={s} />)}</datalist>
          </Label>
          {r.stage === "lost" && (
            <Label text="Lost reason">
              <select value={r.lost_reason ?? ""} onChange={(e) => set("lost_reason", e.target.value || null)} className={field}>
                <option value="">None</option>
                {studio.lost_reasons.map((x) => <option key={x} value={x}>{x}</option>)}
              </select>
            </Label>
          )}
        </div>
      )}
      <div className="flex flex-wrap items-center gap-x-6 gap-y-2">
        <label className="flex items-center gap-2 text-[13px]">
          <input type="checkbox" checked={Boolean(r.is_reopen)} onChange={(e) => set("is_reopen", e.target.checked)} className="accent-[var(--primary)]" />
          Reopen: may move the lead back to an earlier stage
        </label>
        <label className="flex items-center gap-2 text-[13px]">Priority
          <input type="number" value={r.priority ?? 100} onChange={(e) => set("priority", Number(e.target.value))} className={cn(fieldBase, "w-24")} min={1} max={10000} />
        </label>
      </div>
      {r.stage === "lost" && <p className="text-[12px] text-muted">A lead whose partner stage maps to Lost is handed to Eduwit&apos;s B2C nurture team; the partner keeps its own status.</p>}
    </Modal>
  );
}

function Pipelines({ studio, canEdit }: { studio: Studio; canEdit: boolean }) {
  const router = useRouter();
  const ed = studio.editing!;
  const [name, setName] = useState(ed.pipeline_field);
  const [key, setKey] = useState("");
  const suggestions = studio.discovered.pipelines.filter((p) => !ed.pipelines.some((x) => x.key === p));
  const run = async (fn: () => Promise<{ ok: boolean; error?: string }>, msg: string) => {
    const r = await fn();
    if (!r.ok) toast.error(r.error ?? "Could not save."); else { toast.success(msg); router.refresh(); }
  };
  return (
    <div className="space-y-3 border-t border-border px-5 py-4">
      <p className="flex items-center gap-2 text-[13px] font-medium"><Waypoints className="size-4 text-muted" /> Pipelines</p>
      <p className="text-[12.5px] text-muted">When the same partner stage means different things in two pipelines, add the pipelines and scope rules to them. The pipeline is read from the payload field below.</p>
      <div className="flex flex-wrap items-end gap-2">
        <div className="w-56"><Label text="Pipeline field"><input value={name} onChange={(e) => setName(e.target.value)} disabled={!canEdit} className={cn(field, "font-mono")} /></Label></div>
        {canEdit && name !== ed.pipeline_field && <Button size="sm" variant="secondary" onClick={() => run(() => savePipelineField(studio.partner.id, ed.id, name), "Pipeline field saved")}>Save</Button>}
      </div>
      <div className="flex flex-wrap gap-1.5">
        {ed.pipelines.map((p) => (
          <Badge key={p.id}>{p.label || p.key}
            {canEdit && <button type="button" aria-label={`Remove ${p.key}`} className="ml-1 text-subtle hover:text-danger"
              onClick={() => run(() => removeRule(studio.partner.id, "pipeline", p.id), "Pipeline removed")}>×</button>}
          </Badge>
        ))}
        {ed.pipelines.length === 0 && <span className="text-[12.5px] text-subtle">None: every rule applies to every pipeline.</span>}
      </div>
      {canEdit && (
        <div className="flex flex-wrap items-center gap-2">
          <div className="w-64 max-w-full"><input value={key} onChange={(e) => setKey(e.target.value)} placeholder="pipeline value, e.g. Online MBA" className={field} list="pipeline-suggestions" /></div>
          <datalist id="pipeline-suggestions">{suggestions.map((s) => <option key={s} value={s} />)}</datalist>
          <Button size="sm" variant="secondary" disabled={!key.trim()} onClick={() => run(async () => { const r = await saveRule(studio.partner.id, "pipeline", { profile_id: ed.id, key }); if (r.ok) setKey(""); return r; }, "Pipeline added")}>
            <Plus className="size-3.5" /> Add
          </Button>
        </div>
      )}
    </div>
  );
}

export function StagesPanel({ studio }: { studio: Studio }) {
  const router = useRouter();
  const ed = studio.editing;
  const canEdit = ed?.status === "draft";
  const [dialog, setDialog] = useState<Draft | null>(null);
  const [remove, setRemove] = useState<StatusRule | null>(null);
  const unmapped = knownStages(studio).filter((s) => !s.mapped);

  if (!ed) return <EmptyState icon={Waypoints} title="No mapping yet">Start a draft to map this partner&apos;s stages.</EmptyState>;
  return (
    <>
      {unmapped.length > 0 && (
        <div className="border-b border-border px-5 py-4">
          <p className="mb-2 text-[13px] font-medium text-fg">Partner stages with no rule <Badge tone="warning">{unmapped.length}</Badge></p>
          <ul className="flex flex-wrap gap-2">
            {unmapped.map((s) => {
              const sug = suggestStage(s.stage, s.sub);
              return (
                <li key={`${s.stage}/${s.sub}`} className="flex items-center gap-2 rounded-lg border border-border px-2.5 py-1.5 text-[12.5px]">
                  <span className="font-medium text-fg">{s.stage}{s.sub && <span className="text-muted"> / {s.sub}</span>}</span>
                  {s.count > 0 && <span className="tabular text-subtle">×{s.count}</span>}
                  {sug && <span className="text-subtle">→ {STAGE_LABEL[sug.key]}?</span>}
                  {canEdit && <Button size="sm" variant="ghost" onClick={() => setDialog({ partner_stage: s.stage, partner_sub_stage: s.sub, stage: sug?.key ?? null })}>Map</Button>}
                </li>
              );
            })}
          </ul>
        </div>
      )}
      <div className="flex justify-end px-5 py-2.5">
        <Button size="sm" disabled={!canEdit} onClick={() => setDialog({ partner_stage: "" })}><Plus className="size-3.5" /> Stage rule</Button>
      </div>
      {ed.status_rules.length === 0 ? (
        <EmptyState icon={Waypoints} title="No stage rules yet">Every partner stage needs a rule (or an explicit ignore) before go-live.</EmptyState>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] text-left text-[12.5px]">
            <thead className="text-[11px] uppercase tracking-wider text-subtle">
              <tr className="border-y border-border">
                <th scope="col" className="px-5 py-2 font-medium">Partner stage</th>
                <th scope="col" className="px-3 py-2 font-medium">When</th>
                <th scope="col" className="px-3 py-2 font-medium">Eduwit</th>
                <th scope="col" className="px-5 py-2"><span className="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {ed.status_rules.map((r) => (
                <tr key={r.id}>
                  <td className="px-5 py-2">
                    <span className="font-medium text-fg">{r.partner_stage}</span>
                    <span className="text-muted"> / {r.partner_sub_stage ?? <em className="not-italic text-subtle">any</em>}</span>
                    {r.pipeline_key && <Badge className="ml-2">{r.pipeline_key}</Badge>}
                  </td>
                  <td className="px-3 py-2 text-muted">{r.conditions.length ? r.conditions.map(conditionText).join(" and ") : "always"}{r.priority !== 100 && <span className="text-subtle"> · priority {r.priority}</span>}</td>
                  <td className="px-3 py-2">
                    {r.ignore ? <Badge>Ignored: {r.ignore_reason}</Badge> : (
                      <span className="flex flex-wrap items-center gap-1.5">
                        <ArrowRight className="size-3.5 text-subtle" />
                        <Badge tone={r.stage === "lost" ? "warning" : r.stage === "enrolled" ? "success" : "info"}>{STAGE_LABEL[r.stage ?? ""] ?? r.stage}</Badge>
                        {r.sub_stage && <span className="text-muted">{r.sub_stage}</span>}
                        {r.lost_reason && <span className="text-muted">· {r.lost_reason}</span>}
                        {r.is_reopen && <Badge tone="brand">reopen</Badge>}
                      </span>
                    )}
                  </td>
                  <td className="whitespace-nowrap px-5 py-2 text-right">
                    {canEdit && <>
                      <Button size="sm" variant="ghost" onClick={() => setDialog(r)} aria-label="Edit"><Pencil className="size-3.5" /></Button>
                      <Button size="sm" variant="ghost" onClick={() => setRemove(r)} aria-label="Remove"><Trash2 className="size-3.5" /></Button>
                    </>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Pipelines studio={studio} canEdit={canEdit} />
      {dialog && <StatusRuleDialog studio={studio} rule={dialog} onClose={() => setDialog(null)} />}
      <ConfirmDialog
        open={remove !== null}
        onClose={() => setRemove(null)}
        title="Remove this stage rule from the draft?"
        tone="danger"
        confirmLabel="Remove"
        onConfirm={async () => {
          if (!remove) return;
          const r = await removeRule(studio.partner.id, "status", remove.id);
          if (!r.ok) return r.error;
          toast.success("Rule removed from the draft");
          router.refresh();
        }}
      >
        {remove && <p>{remove.partner_stage}{remove.partner_sub_stage ? ` / ${remove.partner_sub_stage}` : ""}. The active version keeps it until you publish.</p>}
      </ConfirmDialog>
    </>
  );
}
