"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { FileText, Undo2, UserRoundCog } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { customFieldSet, documentOpen, handBackLead, reassignLeads } from "@/app/s/workspace-actions";
import { date, when } from "@/lib/format";
import { TASK_KIND_LABEL } from "@/lib/labels";
import type { CustomField, LeadDetail, LeadDocument } from "@/lib/types";

function useRun() {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const run = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>, after?: () => void) =>
    start(async () => {
      const r = await fn();
      if (!r.ok) return setError(r.error ?? "That did not work.");
      setError(null);
      if (r.notice) toast.success(r.notice);
      after?.();
      router.refresh();
    });
  return { busy, error, run };
}

const show = (f: CustomField, v: unknown) =>
  v === null || v === undefined || v === "" ? "—" : f.type === "yes_no" ? (v ? "Yes" : "No") : f.type === "date" ? date(String(v)) : String(v);

/** The Admin's own profile fields (Settings), edited one at a time with field history (b2c.custom_field_set). */
export function CustomFieldsPanel({ leadId, fields, values, canEdit }: { leadId: number; fields: CustomField[]; values: Record<string, unknown>; canEdit: boolean }) {
  const [edit, setEdit] = useState<CustomField | null>(null);
  if (fields.length === 0) return null;
  return (
    <section className="panel">
      <header><h3>More details</h3></header>
      <div className="body">
        <dl className="kv">
          {fields.map((f) => (
            <span key={f.key} style={{ display: "contents" }}>
              <dt>{f.label}</dt>
              <dd className="row between" style={{ gap: 6 }}>
                <span>{show(f, values[f.key])}</span>
                {canEdit && <button type="button" className="btn quiet sm" onClick={() => setEdit(f)} aria-label={`Change ${f.label}`}>Change</button>}
              </dd>
            </span>
          ))}
        </dl>
      </div>
      {edit && <CustomFieldSheet leadId={leadId} f={edit} value={values[edit.key]} onClose={() => setEdit(null)} />}
    </section>
  );
}

function CustomFieldSheet({ leadId, f, value, onClose }: { leadId: number; f: CustomField; value: unknown; onClose: () => void }) {
  const [v, setV] = useState(value === null || value === undefined ? "" : f.type === "yes_no" ? (value ? "yes" : "no") : String(value));
  const { busy, error, run } = useRun();
  return (
    <Sheet title={f.label} onClose={onClose}>
      <form className="stack" action={() => run(() => customFieldSet(leadId, f.key, v), onClose)}>
        {f.type === "select" ? (
          <select className="input" value={v} onChange={(e) => setV(e.target.value)} aria-label={f.label}>
            <option value="">Not set</option>
            {(f.options ?? []).map((o) => <option key={o} value={o}>{o}</option>)}
          </select>
        ) : f.type === "yes_no" ? (
          <div className="pills">
            {[["yes", "Yes"], ["no", "No"], ["", "Not set"]].map(([k, l]) => <button key={k} type="button" className="pill" aria-pressed={v === k} onClick={() => setV(k!)}>{l}</button>)}
          </div>
        ) : (
          <input className="input" aria-label={f.label} value={v} onChange={(e) => setV(e.target.value)} maxLength={300}
            type={f.type === "number" ? "number" : f.type === "date" ? "date" : "text"} />
        )}
        <p className="note">The change is kept in the lead&apos;s field history.</p>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : "Save"}</button>
      </form>
    </Sheet>
  );
}

/** Done and cancelled follow-ups, newest first, with what happened. */
export function DoneTasks({ tasks }: { tasks: NonNullable<LeadDetail["done_tasks"]> }) {
  if (tasks.length === 0) return null;
  return (
    <details className="panel">
      <summary>Done ({tasks.length})</summary>
      <div className="body small stack tight">
        {tasks.map((t) => (
          <div key={t.id} className="row between wrap">
            <span><b>{TASK_KIND_LABEL[t.kind] ?? t.kind}</b> · {t.title}{t.outcome ? <span className="muted"> · {t.outcome}</span> : null}</span>
            <span className="muted">{t.status === "cancelled" ? "Cancelled " : ""}{when(t.done_at ?? t.due_at)}</span>
          </div>
        ))}
      </div>
    </details>
  );
}

const SOURCE: Record<string, string> = { upload: "Uploaded", whatsapp: "From WhatsApp", email: "From email" };

/** The lead's documents: each opens by a short signed link (b2c.document_open logs who opened it). */
export function DocumentsPanel({ docs }: { docs: LeadDocument[] }) {
  const [busy, start] = useTransition();
  const open = (d: LeadDocument) => start(async () => {
    const r = await documentOpen(d.id);
    if (!r.ok || !r.data) return void toast.error(r.ok ? "The file could not be opened." : r.error);
    window.open(r.data, "_blank", "noopener,noreferrer");
  });
  return (
    <section className="panel">
      <header><h3>Documents</h3><span className="small muted">{docs.length}</span></header>
      <div className="body small stack tight">
        {docs.length === 0 && <p className="note">No documents yet. Upload against a checklist item under Applications, or add one the student sent on WhatsApp.</p>}
        {docs.map((d) => (
          <div key={d.id} className="row between wrap">
            <span className="row" style={{ gap: 6 }}><FileText className="icon s" aria-hidden /><span><b>{d.kind}</b>{d.file_name && d.file_name !== d.kind ? <span className="muted"> · {d.file_name}</span> : null}
              <span className="muted" style={{ display: "block" }}>{SOURCE[d.source ?? ""] ?? d.source ?? ""} · {when(d.created_at)}</span></span></span>
            <button type="button" className="btn ghost sm" disabled={busy} onClick={() => open(d)}>Open</button>
          </div>
        ))}
      </div>
    </section>
  );
}

/** A counsellor hands a lead back with a reason; the allocation rules choose someone else (b2c.hand_back). */
export function HandBackButton({ leadId }: { leadId: number }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const router = useRouter();
  const { busy, error, run } = useRun();
  return (
    <>
      <button type="button" className="btn quiet sm" onClick={() => setOpen(true)}><Undo2 className="icon s" aria-hidden />Hand back</button>
      {open && (
        <Sheet title="Hand this lead back" onClose={() => setOpen(false)}>
          <p className="note">The allocation rules give it to someone else. Say why, for them and for the Admin.</p>
          <label className="field"><span>Reason (required)</span><textarea className="input" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} placeholder="For example: the student wants a Tamil-speaking counsellor" /></label>
          {error && <p className="error" role="alert">{error}</p>}
          <button type="button" className="btn primary block" disabled={busy || reason.trim().length < 3}
            onClick={() => run(() => handBackLead(leadId, reason), () => { setOpen(false); router.push("/s/leads"); })}>{busy ? "Saving…" : "Hand back"}</button>
        </Sheet>
      )}
    </>
  );
}

/** The sales head (within their team) or the Admin gives the lead to someone, or back to the rules (b2c.reassign). */
export function ReassignButton({ leadIds, people, label = "Reassign", onDone }: { leadIds: number[]; people: { user_id: string; name: string }[]; label?: string; onDone?: () => void }) {
  const [open, setOpen] = useState(false);
  const [to, setTo] = useState("");
  const [reason, setReason] = useState("");
  const { busy, error, run } = useRun();
  return (
    <>
      <button type="button" className="btn quiet sm" onClick={() => setOpen(true)}><UserRoundCog className="icon s" aria-hidden />{label}</button>
      {open && (
        <Sheet title={leadIds.length > 1 ? `Reassign ${leadIds.length} leads` : "Reassign"} onClose={() => setOpen(false)}>
          <label className="field"><span>To</span><select className="input" value={to} onChange={(e) => setTo(e.target.value)}>
            <option value="">Through the allocation rules (not the current counsellor)</option>
            {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
          </select></label>
          <label className="field"><span>Reason (required)</span><input className="input" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300} /></label>
          {error && <p className="error" role="alert">{error}</p>}
          <button type="button" className="btn primary block" disabled={busy || reason.trim().length < 3}
            onClick={() => run(() => reassignLeads(leadIds, to || null, reason), () => { setOpen(false); setReason(""); onDone?.(); })}>{busy ? "Saving…" : "Reassign"}</button>
        </Sheet>
      )}
    </>
  );
}
