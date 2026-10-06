"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { LoaderCircle, Plus, Scale } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Badge, EmptyState } from "@/components/ui/Card";
import { cn } from "@/components/ui/cn";
import { useFormAction } from "@/components/ui/useFormAction";
import { ACTION_LABEL, describeConditions } from "@/lib/routing";
import type { Rule } from "@/lib/routing-data";
import { saveRule, setRuleActive, type FormState } from "./actions";

type Partner = { id: number; name: string; status: string };
const field = "w-full rounded-lg border border-border bg-surface px-3 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30 aria-[invalid=true]:border-danger";
const arr = (c: Record<string, unknown>, k: string) => (Array.isArray(c[k]) ? (c[k] as string[]) : []);

function RuleDialog({ rule, partners, open, onClose }: { rule: Rule | null; partners: Partner[]; open: boolean; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const [state, onSubmit, pending] = useFormAction<FormState>(saveRule, undefined);
  const e = state?.errors ?? {};
  const c = rule?.conditions ?? {};

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);
  // Close once a save succeeds (state.ok is a fresh timestamp per save).
  useEffect(() => { if (state?.ok) { toast.success("Rule saved"); onClose(); } }, [state?.ok, onClose]);

  return (
    <dialog ref={ref} onClose={onClose} aria-labelledby="rule-title"
      className="m-auto w-[min(640px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm">
      <form key={rule?.id ?? "new"} onSubmit={onSubmit} noValidate>
        <input type="hidden" name="id" value={rule?.id ?? ""} />
        <div className="space-y-4 p-5">
          <h2 id="rule-title" className="text-[15px] font-semibold">{rule ? "Edit rule" : "New routing rule"}</h2>
          <div className="grid gap-3 sm:grid-cols-[1fr_120px]">
            <label className="space-y-1">
              <span className="text-[13px] font-medium">Name</span>
              <input name="name" defaultValue={rule?.name ?? ""} maxLength={120} className={cn(field, "h-9")} aria-invalid={Boolean(e.name)} placeholder="e.g. Meta MBA leads to Acme" />
              {e.name && <span className="text-xs text-danger">{e.name}</span>}
            </label>
            <label className="space-y-1">
              <span className="text-[13px] font-medium">Priority</span>
              <input name="priority" defaultValue={rule?.priority ?? 100} inputMode="numeric" className={cn(field, "h-9")} aria-invalid={Boolean(e.priority)} />
              <span className="block text-[11px] text-subtle">Lower runs first</span>
            </label>
          </div>

          <fieldset className="space-y-2 rounded-lg border border-border p-3">
            <legend className="px-1 text-[13px] font-medium">When the lead matches (empty means any)</legend>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="space-y-1"><span className="text-[12px] text-muted">Course keys</span>
                <input name="course_keys" defaultValue={arr(c, "course_keys").join(", ")} placeholder="mba, bba" className={cn(field, "h-9")} /></label>
              <label className="space-y-1"><span className="text-[12px] text-muted">Lead sources</span>
                <input name="sources" defaultValue={arr(c, "sources").join(", ")} placeholder="meta_lead_ad, whatsapp_direct" className={cn(field, "h-9")} /></label>
              <label className="space-y-1"><span className="text-[12px] text-muted">States</span>
                <input name="states" defaultValue={arr(c, "states").join(", ")} placeholder="Delhi, Haryana" className={cn(field, "h-9")} /></label>
              <label className="space-y-1"><span className="text-[12px] text-muted">Campaign contains</span>
                <input name="campaign_contains" defaultValue={typeof c.campaign_contains === "string" ? c.campaign_contains : ""} maxLength={100} className={cn(field, "h-9")} /></label>
            </div>
            <div className="flex flex-wrap gap-x-5 gap-y-2 pt-1 text-[13px]">
              {["Online", "ODL", "Regular"].map((m) => (
                <label key={m} className="flex items-center gap-1.5"><input type="checkbox" name="modes" value={m} defaultChecked={arr(c, "modes").includes(m)} className="accent-[var(--primary)]" /> {m}</label>
              ))}
              <span className="text-border">|</span>
              {["UG", "PG", "DIPLOMA", "CERTIFICATE"].map((l) => (
                <label key={l} className="flex items-center gap-1.5"><input type="checkbox" name="levels" value={l} defaultChecked={arr(c, "levels").includes(l)} className="accent-[var(--primary)]" /> {l}</label>
              ))}
            </div>
          </fieldset>

          <div className="grid gap-3 sm:grid-cols-[200px_1fr]">
            <label className="space-y-1">
              <span className="text-[13px] font-medium">Then</span>
              <select name="action" defaultValue={rule?.action ?? "fix_partner"} className={cn(field, "h-9")}>
                {Object.entries(ACTION_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </label>
            <fieldset className="space-y-1">
              <legend className="text-[13px] font-medium">Partners</legend>
              <div className={cn("max-h-36 space-y-1 overflow-y-auto rounded-lg border p-2", e.partner_ids ? "border-danger" : "border-border")}>
                {partners.map((p) => (
                  <label key={p.id} className="flex items-center gap-2 text-[13px]">
                    <input type="checkbox" name="partner_ids" value={p.id} defaultChecked={rule?.partner_ids.includes(p.id)} className="accent-[var(--primary)]" />
                    {p.name} {p.status !== "active" && <span className="text-[11px] text-subtle">({p.status})</span>}
                  </label>
                ))}
                {partners.length === 0 && <p className="text-[12px] text-subtle">Add a partner first.</p>}
              </div>
              {e.partner_ids && <span className="text-xs text-danger">{e.partner_ids}</span>}
            </fieldset>
          </div>
          <p className="text-[12px] text-subtle">A rule can only narrow the choice between partners. B2C is never a rule target; it only gets leads through the fallback cases.</p>
          {state?.error && <p role="alert" className="text-[13px] text-danger">{state.error}</p>}
        </div>
        <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
          <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
          <Button type="submit" size="sm" disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save rule</Button>
        </div>
      </form>
    </dialog>
  );
}

export function RulesPanel({ rules, partners }: { rules: Rule[]; partners: Partner[] }) {
  const [editing, setEditing] = useState<Rule | null | "new">(null);
  const close = useCallback(() => setEditing(null), []);
  const toggle = async (r: Rule) => {
    const err = await setRuleActive(r.id, !r.active);
    if (err) toast.error(err); else toast.success(r.active ? "Rule turned off" : "Rule turned on");
  };
  return (
    <>
      <div className="flex items-center justify-between border-b border-border px-5 py-3">
        <p className="text-[13px] text-muted">Rules run in priority order after exclusions and before capacity. A rule whose partners are not eligible is skipped.</p>
        <Button size="sm" onClick={() => setEditing("new")}><Plus className="size-3.5" /> New rule</Button>
      </div>
      {rules.length === 0 ? (
        <EmptyState icon={Scale} title="No routing rules">Without rules, every lead goes to the eligible partner with the highest commission.</EmptyState>
      ) : (
        <ul className="divide-y divide-border">
          {rules.map((r) => (
            <li key={r.id} className={cn("flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3", !r.active && "opacity-60")}>
              <span className="tabular w-10 text-[12px] text-subtle">#{r.priority}</span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-[13.5px] font-medium text-fg">{r.name}</p>
                <p className="text-[12.5px] text-muted">{describeConditions(r.conditions)} → {ACTION_LABEL[r.action]?.toLowerCase()} {(r.partner_names ?? []).join(", ")}</p>
              </div>
              <Badge tone={r.active ? "success" : "neutral"}>{r.active ? "On" : "Off"}</Badge>
              <Button size="sm" variant="ghost" onClick={() => setEditing(r)}>Edit</Button>
              <Button size="sm" variant="secondary" onClick={() => toggle(r)}>{r.active ? "Turn off" : "Turn on"}</Button>
            </li>
          ))}
        </ul>
      )}
      <RuleDialog key={editing === null ? "closed" : editing === "new" ? "new" : editing.id} rule={editing === "new" ? null : editing}
        partners={partners} open={editing !== null} onClose={close} />
    </>
  );
}
