"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Activity, ListChecks, Pencil, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { ACTIVITY_KINDS, DIRECTION_LABEL, type ActivityRule, type Direction, type Studio, type ValueRule } from "@/lib/mapping";
import { removeRule, saveRule } from "./actions";
import { field, Label, Modal } from "@/components/ui/Modal";

type ValueDraft = Partial<ValueRule> & { canonical_key: string };
type ActivityDraft = Partial<ActivityRule> & { partner_type: string };

function allowedOf(studio: Studio, key: string): string[] {
  return studio.canonical.find((c) => c.key === key)?.allowed ?? (key === "lost_reason" ? studio.lost_reasons : []);
}

function ValueDialog({ studio, rule, onClose }: { studio: Studio; rule: ValueDraft; onClose: () => void }) {
  const router = useRouter();
  const [r, setR] = useState<ValueDraft>({ direction: "both", ...rule });
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const picklists = studio.canonical.filter((c) => c.data_type === "picklist");
  const save = async () => {
    setPending(true); setError(null);
    const res = await saveRule(studio.partner.id, "value", { id: r.id ?? null, profile_id: studio.editing!.id, canonical_key: r.canonical_key,
      partner_value: r.partner_value ?? "", canonical_value: r.canonical_value ?? "", direction: r.direction });
    setPending(false);
    if (!res.ok) { setError(res.error); return; }
    toast.success("Value mapped");
    onClose(); router.refresh();
  };
  return (
    <Modal open onClose={onClose} title={r.id ? "Edit value" : "Map a value"} error={error} pending={pending} onSubmit={save}>
      <Label text="Eduwit field">
        <select value={r.canonical_key} onChange={(e) => setR({ ...r, canonical_key: e.target.value, canonical_value: undefined })} className={field}>
          <option value="">Choose…</option>
          {picklists.map((c) => <option key={c.key} value={c.key}>{c.label}</option>)}
        </select>
      </Label>
      <div className="grid gap-3 sm:grid-cols-2">
        <Label text="Partner value"><input value={r.partner_value ?? ""} onChange={(e) => setR({ ...r, partner_value: e.target.value })} className={field} maxLength={200} /></Label>
        <Label text="Eduwit value">
          <select value={r.canonical_value ?? ""} onChange={(e) => setR({ ...r, canonical_value: e.target.value })} className={field}>
            <option value="">Choose…</option>
            {allowedOf(studio, r.canonical_key).map((v) => <option key={v} value={v}>{v}</option>)}
          </select>
        </Label>
      </div>
      <Label text="Direction" hint="Both ways: also the value sent when Eduwit has this value. Several partner values may map in; one per Eduwit value should map out.">
        <select value={r.direction} onChange={(e) => setR({ ...r, direction: e.target.value as Direction })} className={field}>
          {(["both", "in", "out"] as Direction[]).map((d) => <option key={d} value={d}>{DIRECTION_LABEL[d]}</option>)}
        </select>
      </Label>
    </Modal>
  );
}

export function ValuesPanel({ studio }: { studio: Studio }) {
  const router = useRouter();
  const ed = studio.editing;
  const canEdit = ed?.status === "draft";
  const [dialog, setDialog] = useState<ValueDraft | null>(null);
  const [remove, setRemove] = useState<ValueRule | null>(null);
  if (!ed) return <EmptyState icon={ListChecks} title="No mapping yet">Start a draft first.</EmptyState>;

  const picklistRules = ed.field_rules.filter((f) => !f.not_available && studio.canonical.find((c) => c.key === f.canonical_key)?.data_type === "picklist");
  const keys = [...new Set([...picklistRules.map((f) => f.canonical_key), ...ed.value_rules.map((v) => v.canonical_key)])];
  const unmapped = studio.queue.filter((q) => q.kind === "value" && q.status === "open");
  const label = (k: string) => studio.canonical.find((c) => c.key === k)?.label ?? k;

  return (
    <>
      {unmapped.length > 0 && (
        <div className="border-b border-border px-5 py-4">
          <p className="mb-2 text-[13px] font-medium text-fg">Values the partner sent that no rule covers <Badge tone="warning">{unmapped.length}</Badge></p>
          <ul className="flex flex-wrap gap-2">
            {unmapped.map((q) => {
              const [key, value] = q.item.split(" = ");
              return (
                <li key={q.id} className="flex items-center gap-2 rounded-lg border border-border px-2.5 py-1.5 text-[12.5px]">
                  <span className="text-muted">{label(key ?? "")}:</span> <span className="font-medium text-fg">{String(q.sample?.value ?? value)}</span>
                  {typeof q.sample?.error === "string" && <span className="text-danger">({q.sample.error})</span>}
                  <span className="tabular text-subtle">×{q.seen_count}</span>
                  {canEdit && !q.sample?.error && <Button size="sm" variant="ghost" onClick={() => setDialog({ canonical_key: key ?? "", partner_value: String(q.sample?.value ?? value ?? "") })}>Map</Button>}
                </li>
              );
            })}
          </ul>
        </div>
      )}
      <div className="flex items-center justify-between gap-3 px-5 py-2.5">
        <p className="text-[12.5px] text-muted">A value that already matches an Eduwit value (any case) needs no rule.</p>
        <Button size="sm" disabled={!canEdit} onClick={() => setDialog({ canonical_key: keys[0] ?? "" })}><Plus className="size-3.5" /> Value</Button>
      </div>
      {keys.length === 0 ? (
        <EmptyState icon={ListChecks} title="No picklist fields mapped">Map a picklist field (qualification, call outcome, application status…) in the Fields tab first.</EmptyState>
      ) : (
        <div className="divide-y divide-border border-t border-border">
          {keys.map((k) => {
            const rules = ed.value_rules.filter((v) => v.canonical_key === k);
            return (
              <div key={k} className="px-5 py-3">
                <p className="mb-1.5 text-[13px] font-medium text-fg">{label(k)} <span className="text-[12px] font-normal text-subtle">· Eduwit values: {allowedOf(studio, k).join(", ")}</span></p>
                {rules.length === 0 ? <p className="text-[12.5px] text-subtle">No value rules.</p> : (
                  <ul className="flex flex-wrap gap-1.5">
                    {rules.map((v) => (
                      <li key={v.id} className="flex items-center gap-1 rounded-md border border-border bg-surface-2 px-2 py-0.5 text-[12.5px]">
                        <span className="text-fg">{v.partner_value}</span><span className="text-subtle">{v.direction === "both" ? "⇄" : v.direction === "in" ? "→" : "←"}</span><span className="text-fg">{v.canonical_value}</span>
                        {canEdit && <>
                          <button type="button" aria-label="Edit" onClick={() => setDialog(v)} className="ml-1 text-subtle hover:text-fg"><Pencil className="size-3" /></button>
                          <button type="button" aria-label="Remove" onClick={() => setRemove(v)} className="text-subtle hover:text-danger"><Trash2 className="size-3" /></button>
                        </>}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            );
          })}
        </div>
      )}
      {dialog && <ValueDialog studio={studio} rule={dialog} onClose={() => setDialog(null)} />}
      <ConfirmDialog
        open={remove !== null} onClose={() => setRemove(null)} title="Remove this value rule from the draft?" tone="danger" confirmLabel="Remove"
        onConfirm={async () => {
          if (!remove) return;
          const r = await removeRule(studio.partner.id, "value", remove.id);
          if (!r.ok) return r.error;
          toast.success("Rule removed from the draft");
          router.refresh();
        }}
      />
    </>
  );
}

function ActivityDialog({ studio, rule, onClose }: { studio: Studio; rule: ActivityDraft; onClose: () => void }) {
  const router = useRouter();
  const [r, setR] = useState<ActivityDraft>({ kind: "call", ...rule });
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const callOutcomes = studio.canonical.find((c) => c.key === "call_outcome")?.allowed ?? [];
  const save = async () => {
    setPending(true); setError(null);
    const res = await saveRule(studio.partner.id, "activity", { id: r.id ?? null, profile_id: studio.editing!.id, partner_type: r.partner_type,
      partner_outcome: r.partner_outcome ?? null, kind: r.kind, outcome: r.outcome ?? null });
    setPending(false);
    if (!res.ok) { setError(res.error); return; }
    toast.success("Activity mapped");
    onClose(); router.refresh();
  };
  return (
    <Modal open onClose={onClose} title={r.id ? "Edit activity rule" : "Map an activity"} error={error} pending={pending} onSubmit={save}>
      <div className="grid gap-3 sm:grid-cols-2">
        <Label text="Partner activity type"><input value={r.partner_type} onChange={(e) => setR({ ...r, partner_type: e.target.value })} className={field} /></Label>
        <Label text="Partner outcome" hint="Empty: any outcome"><input value={r.partner_outcome ?? ""} onChange={(e) => setR({ ...r, partner_outcome: e.target.value || null })} className={field} /></Label>
        <Label text="Eduwit activity">
          <select value={r.kind} onChange={(e) => setR({ ...r, kind: e.target.value, outcome: null })} className={field}>
            {ACTIVITY_KINDS.map((k) => <option key={k} value={k}>{k.replace("_", " ")}</option>)}
          </select>
        </Label>
        <Label text="Eduwit outcome" hint="Empty: keep the partner's outcome">
          {r.kind === "call" ? (
            <select value={r.outcome ?? ""} onChange={(e) => setR({ ...r, outcome: e.target.value || null })} className={field}>
              <option value="">Keep the partner&apos;s</option>
              {callOutcomes.map((o) => <option key={o} value={o}>{o.replace("_", " ")}</option>)}
            </select>
          ) : <input value={r.outcome ?? ""} onChange={(e) => setR({ ...r, outcome: e.target.value || null })} className={field} />}
        </Label>
      </div>
      <p className="text-[12px] text-muted">A call counts as a contact attempt on the lead; a call with outcome “connected” moves a new lead to Contacted.</p>
    </Modal>
  );
}

export function ActivitiesPanel({ studio }: { studio: Studio }) {
  const router = useRouter();
  const ed = studio.editing;
  const canEdit = ed?.status === "draft";
  const [dialog, setDialog] = useState<ActivityDraft | null>(null);
  const [remove, setRemove] = useState<ActivityRule | null>(null);
  if (!ed) return <EmptyState icon={Activity} title="No mapping yet">Start a draft first.</EmptyState>;
  const unmapped = studio.queue.filter((q) => q.kind === "activity" && q.status === "open");
  const seen = studio.discovered.activities.filter((a) => !ed.activity_rules.some((r) => r.partner_type.toLowerCase() === a.type.toLowerCase()));
  return (
    <>
      {(unmapped.length > 0 || seen.length > 0) && (
        <div className="border-b border-border px-5 py-4">
          <p className="mb-2 text-[13px] font-medium text-fg">Partner activities with no rule</p>
          <ul className="flex flex-wrap gap-2">
            {unmapped.map((q) => {
              const [t, o] = q.item.split(" / ");
              return (
                <li key={q.id} className="flex items-center gap-2 rounded-lg border border-border px-2.5 py-1.5 text-[12.5px]">
                  <span className="font-medium text-fg">{q.item}</span><span className="tabular text-subtle">×{q.seen_count}</span>
                  {canEdit && <Button size="sm" variant="ghost" onClick={() => setDialog({ partner_type: t ?? q.item, partner_outcome: o ?? null })}>Map</Button>}
                </li>
              );
            })}
            {seen.filter((a) => !unmapped.some((q) => q.item.startsWith(a.type))).map((a) => (
              <li key={a.type} className="flex items-center gap-2 rounded-lg border border-border px-2.5 py-1.5 text-[12.5px]">
                <span className="font-medium text-fg">{a.type}</span>{a.outcomes.length > 0 && <span className="text-subtle">{a.outcomes.join(", ")}</span>}
                {canEdit && <Button size="sm" variant="ghost" onClick={() => setDialog({ partner_type: a.type })}>Map</Button>}
              </li>
            ))}
          </ul>
        </div>
      )}
      <div className="flex justify-end px-5 py-2.5"><Button size="sm" disabled={!canEdit} onClick={() => setDialog({ partner_type: "" })}><Plus className="size-3.5" /> Activity rule</Button></div>
      {ed.activity_rules.length === 0 ? <EmptyState icon={Activity} title="No activity rules yet">Map the partner&apos;s call logs, messages and meetings so they count as sales effort.</EmptyState> : (
        <ul className="divide-y divide-border border-t border-border">
          {ed.activity_rules.map((a) => (
            <li key={a.id} className="flex flex-wrap items-center gap-2 px-5 py-2.5 text-[12.5px]">
              <span className="font-medium text-fg">{a.partner_type}</span><span className="text-muted">/ {a.partner_outcome ?? "any outcome"}</span>
              <span className="text-subtle">→</span><Badge tone="info">{a.kind.replace("_", " ")}</Badge>{a.outcome && <span className="text-muted">{a.outcome.replace("_", " ")}</span>}
              <span className="ml-auto">{canEdit && <>
                <Button size="sm" variant="ghost" onClick={() => setDialog(a)} aria-label="Edit"><Pencil className="size-3.5" /></Button>
                <Button size="sm" variant="ghost" onClick={() => setRemove(a)} aria-label="Remove"><Trash2 className="size-3.5" /></Button>
              </>}</span>
            </li>
          ))}
        </ul>
      )}
      {dialog && <ActivityDialog studio={studio} rule={dialog} onClose={() => setDialog(null)} />}
      <ConfirmDialog
        open={remove !== null} onClose={() => setRemove(null)} title="Remove this activity rule from the draft?" tone="danger" confirmLabel="Remove"
        onConfirm={async () => {
          if (!remove) return;
          const r = await removeRule(studio.partner.id, "activity", remove.id);
          if (!r.ok) return r.error;
          toast.success("Rule removed from the draft");
          router.refresh();
        }}
      />
    </>
  );
}
