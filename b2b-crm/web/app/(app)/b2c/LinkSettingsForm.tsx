"use client";
import { useMemo, useState } from "react";
import { Lock } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import { GROUP_LABEL, KIND_LABEL, groupFields, type LinkField, type LinkSettings } from "@/lib/b2c-link";
import { saveLinkSettings } from "./actions";

/** Link on or off, which leads the B2C CRM sees, and which fields it may write. Saved as a new settings version. */
export function LinkSettingsForm({ settings, fields }: { settings: LinkSettings; fields: LinkField[] }) {
  const [enabled, setEnabled] = useState(settings.enabled);
  const [scope, setScope] = useState(settings.scope);
  const [writable, setWritable] = useState(() => new Set(settings.writable));
  const [open, setOpen] = useState(false);
  const groups = useMemo(() => groupFields(fields), [fields]);
  const dirty = enabled !== settings.enabled || scope !== settings.scope || writable.size !== settings.writable.length
    || settings.writable.some((f) => !writable.has(f));
  const toggle = (f: string, on: boolean) => setWritable((w) => { const n = new Set(w); if (on) n.add(f); else n.delete(f); return n; });
  const setGroup = (g: LinkField[], on: boolean) => setWritable((w) => { const n = new Set(w); for (const f of g) if (f.write === "b2c") { if (on) n.add(f.field); else n.delete(f.field); } return n; });

  return (
    <div className="divide-y divide-border">
      <section className="grid gap-4 p-5 lg:grid-cols-2">
        <div className="space-y-2">
          <h3 className="text-[13.5px] font-semibold text-fg">Real-time sync</h3>
          <label className="flex items-start gap-3 rounded-lg border border-border p-3">
            <input type="checkbox" className="mt-0.5 accent-[var(--primary)]" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
            <span><span className="block text-[13px] font-medium text-fg">Sync lead changes to the B2C CRM</span>
              <span className="block text-[12px] text-muted">Off: nothing new is sent and the change feed stops growing. The B2C CRM keeps what it has and can still read and write.</span></span>
          </label>
        </div>
        <fieldset className="space-y-2">
          <legend className="mb-2 text-[13.5px] font-semibold text-fg">Which leads the B2C CRM sees</legend>
          {([["held", "Only leads it holds", "Leads the engine hands to B2C (sales or nurture). A lead that goes to a partner is released from its copy."],
             ["all", "Every lead, read-only", "It also sees partner-held leads (for lookups and reporting) but can write only the leads it holds."]] as const).map(([k, l, h]) => (
            <label key={k} className={cn("flex cursor-pointer gap-3 rounded-lg border p-3", scope === k ? "border-amber bg-amber/5" : "border-border hover:border-border-strong")}>
              <input type="radio" name="scope" className="mt-0.5 accent-[var(--primary)]" checked={scope === k} onChange={() => setScope(k)} />
              <span><span className="block text-[13px] font-medium text-fg">{l}</span><span className="block text-[12px] text-muted">{h}</span></span>
            </label>
          ))}
        </fieldset>
      </section>

      <section className="p-5">
        <h3 className="text-[13.5px] font-semibold text-fg">Fields</h3>
        <p className="mb-3 text-[12.5px] text-muted">Every field the B2C CRM receives, under the name it uses. Ticked fields it may change, only on leads it holds; every change is
          checked, written by the B2B CRM and kept with the counsellor who made it. Locked fields belong to the B2B CRM (routing, consent, source, Witty&apos;s qualification).</p>
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {groups.map((g) => {
            const own = g.fields.filter((f) => f.write === "b2c");
            const all = own.length > 0 && own.every((f) => writable.has(f.field));
            return (
              <div key={g.group} className="rounded-lg border border-border">
                <div className="flex items-center justify-between border-b border-border px-3 py-2">
                  <span className="text-[12.5px] font-semibold text-fg">{GROUP_LABEL[g.group] ?? g.group}</span>
                  {own.length > 0 ? (
                    <button type="button" className="text-[11.5px] text-info hover:underline" onClick={() => setGroup(g.fields, !all)}>{all ? "Allow none" : "Allow all"}</button>
                  ) : <Badge><Lock className="size-3" /> B2B only</Badge>}
                </div>
                <ul className="divide-y divide-border">
                  {g.fields.map((f) => (
                    <li key={f.field} className="flex items-center gap-2.5 px-3 py-1.5 text-[12.5px]">
                      {f.write === "b2c"
                        ? <input type="checkbox" aria-label={`B2C may write ${f.field}`} className="accent-[var(--primary)]" checked={writable.has(f.field)} onChange={(e) => toggle(f.field, e.target.checked)} />
                        : <Lock className="size-3.5 shrink-0 text-subtle" aria-label="read-only for B2C" />}
                      <code className="min-w-0 flex-1 truncate font-mono text-[12px] text-fg">{f.field}</code>
                      <span className="shrink-0 text-[11.5px] text-subtle">{KIND_LABEL[f.kind] ?? f.kind}</span>
                    </li>
                  ))}
                </ul>
              </div>
            );
          })}
        </div>
      </section>

      <div className="flex items-center justify-end gap-3 bg-surface-2/40 px-5 py-3">
        {dirty && <span className="text-[12.5px] text-muted">Unsaved changes</span>}
        <Button onClick={() => setOpen(true)} disabled={!dirty}>Save</Button>
      </div>
      <ConfirmDialog open={open} onClose={() => setOpen(false)} title="Save the B2C CRM link settings?" confirmLabel="Save"
        reason={{ label: "Reason (kept in the settings history)", placeholder: "e.g. counsellors may now correct the student's city" }}
        onConfirm={async (reason) => {
          const e = await saveLinkSettings({ enabled, scope, writable: [...writable], reason });
          if (!e) toast.success("Saved");
          return e;
        }}>
        {scope !== settings.scope && <p>Changing who the B2C CRM sees takes effect on each lead&apos;s next change; use <em>Resend every lead</em> to apply it now.</p>}
        <p className="mt-2">{writable.size} of {fields.filter((f) => f.write === "b2c").length} fields writable.</p>
      </ConfirmDialog>
    </div>
  );
}
