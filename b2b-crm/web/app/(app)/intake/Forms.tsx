"use client";
import { useEffect, useRef, useState } from "react";
import { FileText, LoaderCircle, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { formatDateTime, relativeTime } from "@/lib/format";
import { FIELD_LABEL, IMPORT_FIELDS, type LeadForm } from "@/lib/intake";
import { saveForm, type FormForm } from "./actions";
import { area, field, fieldFixed, label } from "./ui";

const DEFAULT_KEYS = [["course", "Course"], ["specialization", "Specialisation"], ["university", "University"], ["programme_level", "Level (UG/PG…)"], ["study_mode", "Study mode"]] as const;

const blank = (platform: "meta" | "google"): FormForm => ({
  platform, form_ref: "", name: "", page_ref: "", field_map: {}, defaults: {}, campaign: "", consent_text: "", consent_version: "", consent_purposes: ["sales", "partner_share"], active: true,
});

function FormDialog({ open, initial, onClose }: { open: boolean; initial: FormForm | null; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  const [f, setF] = useState<FormForm>(blank("meta"));
  const [rows, setRows] = useState<{ q: string; field: string }[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const editing = Boolean(initial?.form_ref);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) {
      const v = initial ?? blank("meta");
      setF(v); setRows(Object.entries(v.field_map).map(([q, x]) => ({ q, field: x }))); setError(null); d.showModal();
    }
    if (!open && d.open) d.close();
  }, [open, initial]);

  const purposes = f.consent_purposes as string[];
  const save = async () => {
    setPending(true); setError(null);
    try {
      const field_map = Object.fromEntries(rows.filter((r) => r.q.trim()).map((r) => [r.q.trim(), r.field])) as FormForm["field_map"];
      const e = await saveForm({ ...f, field_map });
      if (e) setError(e); else { toast.success("Form saved"); onClose(); }
    } finally { setPending(false); }
  };

  return (
    <dialog ref={ref} onClose={onClose} aria-labelledby="form-title"
      className="m-auto w-[min(680px,calc(100vw-2rem))] rounded-[var(--radius-card)] border border-border bg-surface p-0 text-fg shadow-2xl backdrop:bg-overlay backdrop:backdrop-blur-sm">
      <div className="max-h-[75vh] space-y-4 overflow-y-auto p-5">
        <h2 id="form-title" className="text-[15px] font-semibold">{editing ? `Form ${f.form_ref}` : "Add a lead form"}</h2>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block space-y-1"><span className={label}>Platform</span>
            <select className={field} value={f.platform} disabled={editing} onChange={(e) => setF({ ...f, platform: e.target.value as "meta" | "google" })}>
              <option value="meta">Meta Lead Ads</option><option value="google">Google Ads lead form</option>
            </select></label>
          <label className="block space-y-1"><span className={label}>Form ID</span>
            <input className={field} value={f.form_ref} disabled={editing} maxLength={80} placeholder={f.platform === "meta" ? "e.g. 1234567890123456" : "e.g. 98765432"} onChange={(e) => setF({ ...f, form_ref: e.target.value })} /></label>
          <label className="block space-y-1"><span className={label}>Name</span>
            <input className={field} value={f.name} maxLength={120} placeholder="e.g. Online MBA – Oct" onChange={(e) => setF({ ...f, name: e.target.value })} /></label>
          <label className="block space-y-1"><span className={label}>Campaign <span className="font-normal text-subtle">(optional)</span></span>
            <input className={field} value={f.campaign ?? ""} maxLength={120} onChange={(e) => setF({ ...f, campaign: e.target.value })} /></label>
        </div>

        <fieldset className="space-y-2">
          <legend className="text-[13px] font-semibold">Custom questions</legend>
          <p className="text-[12.5px] text-muted">Name, phone, email, city, state and country map by themselves. Map your own questions here by their key (Meta: the question&apos;s name; Google: the column ID). Unmapped answers are kept in the lead&apos;s notes.</p>
          {rows.map((r, i) => (
            <div key={i} className="flex gap-2">
              <input className={`${field} min-w-0`} value={r.q} placeholder="question key, e.g. which_course_are_you_interested_in" aria-label="Question key"
                onChange={(e) => setRows(rows.map((x, j) => (j === i ? { ...x, q: e.target.value } : x)))} />
              <select className={fieldFixed("w-44 sm:w-56")} value={r.field} aria-label="Lead field" onChange={(e) => setRows(rows.map((x, j) => (j === i ? { ...x, field: e.target.value } : x)))}>
                <option value="ignore">Ignore</option>
                {IMPORT_FIELDS.map((x) => <option key={x.key} value={x.key}>{x.label}</option>)}
              </select>
              <Button variant="ghost" size="icon" aria-label="Remove" onClick={() => setRows(rows.filter((_, j) => j !== i))}><Trash2 className="size-4" /></Button>
            </div>
          ))}
          <Button size="sm" variant="secondary" onClick={() => setRows([...rows, { q: "", field: "course" }])}><Plus className="size-3.5" /> Add a question</Button>
        </fieldset>

        <fieldset className="space-y-2">
          <legend className="text-[13px] font-semibold">Fixed values</legend>
          <p className="text-[12.5px] text-muted">For a form that runs for one programme: set here what the form does not ask.</p>
          <div className="grid gap-3 sm:grid-cols-2">
            {DEFAULT_KEYS.map(([k, l]) => (
              <label key={k} className="block space-y-1"><span className={label}>{l}</span>
                <input className={field} value={f.defaults[k] ?? ""} maxLength={200} onChange={(e) => setF({ ...f, defaults: { ...f.defaults, [k]: e.target.value } })} /></label>
            ))}
          </div>
        </fieldset>

        <fieldset className="space-y-2">
          <legend className="text-[13px] font-semibold">Consent on the form</legend>
          <label className="block space-y-1"><span className={label}>Consent text shown on the form</span>
            <textarea className={area} value={f.consent_text ?? ""} maxLength={2000} onChange={(e) => setF({ ...f, consent_text: e.target.value })} /></label>
          <label className="block w-56 space-y-1"><span className={label}>Version</span>
            <input className={field} value={f.consent_version ?? ""} maxLength={80} placeholder="e.g. meta-2026-10" onChange={(e) => setF({ ...f, consent_version: e.target.value })} /></label>
          <div className="flex flex-wrap gap-x-5 gap-y-1.5 text-[13px]">
            <label className="flex items-center gap-2 text-muted"><input type="checkbox" checked disabled className="accent-[var(--primary)]" /> Contact about courses</label>
            {(["partner_share", "marketing"] as const).map((p) => (
              <label key={p} className="flex items-center gap-2"><input type="checkbox" className="accent-[var(--primary)]" checked={purposes.includes(p)}
                onChange={(e) => setF({ ...f, consent_purposes: (e.target.checked ? [...purposes, p] : purposes.filter((x) => x !== p)) as FormForm["consent_purposes"] })} />
                {p === "partner_share" ? "Share with partner institutions" : "Marketing messages"}</label>
            ))}
          </div>
          {!purposes.includes("partner_share") && <p className="text-[12px] text-warning">Without partner sharing, leads from this form go to the B2C CRM only.</p>}
        </fieldset>
        <label className="flex items-center gap-2 text-[13px]"><input type="checkbox" className="accent-[var(--primary)]" checked={f.active} onChange={(e) => setF({ ...f, active: e.target.checked })} /> Active</label>
        {error && <p role="alert" className="text-[13px] text-danger">{error}</p>}
      </div>
      <div className="flex justify-end gap-2 border-t border-border bg-surface-2/60 px-5 py-3">
        <Button variant="secondary" size="sm" onClick={onClose} disabled={pending}>Cancel</Button>
        <Button size="sm" onClick={save} disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Save</Button>
      </div>
    </dialog>
  );
}

export function Forms({ forms }: { forms: LeadForm[] }) {
  const [edit, setEdit] = useState<FormForm | null>(null);
  const [open, setOpen] = useState(false);
  const toForm = (x: LeadForm): FormForm => ({
    platform: x.platform, form_ref: x.form_ref, name: x.name, page_ref: x.page_ref ?? "", field_map: x.field_map as FormForm["field_map"],
    defaults: x.defaults as FormForm["defaults"], campaign: x.campaign ?? "", consent_text: x.consent_text ?? "", consent_version: x.consent_version ?? "",
    consent_purposes: x.consent_purposes as FormForm["consent_purposes"], active: x.active,
  });
  return (
    <>
      <div className="flex justify-end border-b border-border px-5 py-3">
        <Button size="sm" onClick={() => { setEdit(null); setOpen(true); }}><Plus className="size-3.5" /> Add a form</Button>
      </div>
      {forms.length === 0 ? (
        <EmptyState icon={FileText} title="No forms yet">A form is added by itself when its first lead arrives (with an alert to map it). You can also add one ahead of a campaign.</EmptyState>
      ) : (
        <ul className="divide-y divide-border">
          {forms.map((x) => {
            const mapped = Object.values(x.field_map).filter((v) => v !== "ignore");
            const unnamed = x.name.startsWith("Meta form ") || x.name.startsWith("Google form ");
            return (
              <li key={x.id} className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3">
                <div className="min-w-0 flex-1 basis-[16rem]">
                  <p className="truncate text-[13.5px] font-medium text-fg">{x.name}</p>
                  <p className="text-[12px] text-subtle">{x.platform === "meta" ? "Meta" : "Google"} · <span className="font-mono">{x.form_ref}</span>
                    {mapped.length > 0 && <> · maps {mapped.map((m) => FIELD_LABEL[m as keyof typeof FIELD_LABEL] ?? m).join(", ")}</>}
                    {Object.keys(x.defaults).length > 0 && <> · fixed {Object.entries(x.defaults).map(([k, v]) => `${k.replace("_", " ")}: ${v}`).join(", ")}</>}</p>
                </div>
                <span className="text-[12px] text-muted"><span className="tabular">{x.leads_7d}</span> in 7 days{x.last_at && <> · last <span title={formatDateTime(x.last_at)}>{relativeTime(x.last_at)}</span></>}</span>
                <div className="flex gap-1.5">
                  {unnamed && <Badge tone="warning">Needs mapping</Badge>}
                  {!x.consent_purposes.includes("partner_share") && <Badge>B2C only</Badge>}
                  {!x.active && <Badge>Off</Badge>}
                </div>
                <Button size="sm" variant="secondary" onClick={() => { setEdit(toForm(x)); setOpen(true); }}>Edit</Button>
              </li>
            );
          })}
        </ul>
      )}
      <FormDialog open={open} initial={edit} onClose={() => setOpen(false)} />
    </>
  );
}
