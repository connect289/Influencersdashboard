"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Lock, Mail, Phone, Plus } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { addContact, addNote, correctLead, taskAdd } from "@/app/s/actions";
import { setPrimaryFor } from "@/app/s/workspace-actions";
import { maskPhone } from "@/lib/format";
import { TASK_KIND_LABEL } from "@/lib/labels";
import type { Contact } from "@/lib/types";
import { CallButton } from "./CallButton";
import { NextPicker } from "./NextPicker";

function useAction() {
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

// ---------- contacts ----------

const LABEL: Record<string, string> = { intake: "From the enquiry", alternate: "Student (another number)", parent: "Parent or guardian", office: "Office", whatsapp_only: "WhatsApp only" };

/**
 * Contact details (spec B5.3, B8.3): every number and email with its primary for calls, WhatsApp and email; any number can
 * be called from its row. Counsellors add details and choose the primaries; only the Admin edits or removes one.
 */
export function ContactsPanel({ leadId, contacts, canEdit, canCall, name }: { leadId: number; contacts: Contact[]; canEdit: boolean; canCall?: boolean; name?: string }) {
  const [adding, setAdding] = useState(false);
  const { busy, run } = useAction();
  const make = (c: Contact, f: "call" | "whatsapp" | "email") => run(() => setPrimaryFor(c.id, [f], leadId));
  return (
    <section className="panel">
      <header><h3>Contact details</h3>{canEdit && <button type="button" className="btn quiet sm" onClick={() => setAdding(true)}><Plus className="icon s" aria-hidden />Add</button>}</header>
      <div className="body">
        {contacts.length === 0 && <p className="note">No contact details yet.</p>}
        {contacts.map((c) => {
          const Icon = c.kind === "phone" ? Phone : Mail;
          const waOnly = c.label === "whatsapp_only";
          return (
            <div key={c.id} className="contact">
              <Icon className="icon s" aria-hidden />
              <span className={c.kind === "phone" ? "mono" : "ellipsis"}>{c.kind === "phone" ? maskPhone(c.value) : c.value}</span>
              <span className="row wrap" style={{ gap: 4 }}>
                {c.primary_call && <span className="chip ok">Primary for calls</span>}
                {c.primary_wa && <span className="chip ok">Primary for WhatsApp</span>}
                {c.primary_email && <span className="chip ok">Primary email</span>}
                {waOnly && <span className="chip line">WhatsApp only</span>}
                {c.origin === "intake" && <Lock className="icon s" aria-label="From the master lead table" />}
              </span>
              <span className="lbl">{waOnly ? "WhatsApp only: do not call" : LABEL[c.label ?? ""] ?? c.label ?? (c.origin === "intake" ? "From the enquiry" : "Added")}</span>
              {(canEdit || canCall) && (
                <span className="row wrap" style={{ gap: 4, gridColumn: 2 }}>
                  {canCall && c.kind === "phone" && !waOnly && <CallButton leadId={leadId} contactId={c.id} name={name ?? "the student"} small label="Call" />}
                  {canEdit && c.kind === "phone" && !c.primary_call && !waOnly && <button type="button" className="btn quiet sm" disabled={busy} onClick={() => make(c, "call")}>Primary for calls</button>}
                  {canEdit && c.kind === "phone" && !c.primary_wa && <button type="button" className="btn quiet sm" disabled={busy} onClick={() => make(c, "whatsapp")}>Primary for WhatsApp</button>}
                  {canEdit && c.kind === "email" && !c.primary_email && <button type="button" className="btn quiet sm" disabled={busy} onClick={() => make(c, "email")}>Make primary</button>}
                </span>
              )}
            </div>
          );
        })}
        <p className="note">You can add numbers and emails and choose the primary for each. Only the Admin can edit or delete one that exists.</p>
      </div>
      {adding && <AddContactSheet leadId={leadId} onClose={() => setAdding(false)} />}
    </section>
  );
}

function AddContactSheet({ leadId, onClose }: { leadId: number; onClose: () => void }) {
  const [kind, setKind] = useState<"phone" | "email">("phone");
  const [primary, setPrim] = useState(false);
  const { busy, error, run } = useAction();
  return (
    <Sheet title="Add a contact detail" onClose={onClose}>
      <div className="pills">
        <button type="button" className="pill" aria-pressed={kind === "phone"} onClick={() => setKind("phone")}>Phone</button>
        <button type="button" className="pill" aria-pressed={kind === "email"} onClick={() => setKind("email")}>Email</button>
      </div>
      <form className="stack" action={(f) => run(async () => {
        const r = await addContact(leadId, kind, String(f.get("value") ?? ""), String(f.get("label") ?? ""), primary ? (kind === "phone" ? ["call", "whatsapp"] : ["email"]) : []);
        if (r.ok && r.data?.duplicate_of_lead) toast.warning(`This ${kind} also belongs to lead #${r.data.duplicate_of_lead}. The Admin has been told.`);
        return r;
      }, onClose)}>
        <label className="field"><span>{kind === "phone" ? "Number" : "Email"}</span><input className="input" name="value" required inputMode={kind === "phone" ? "tel" : "email"} /></label>
        <label className="field"><span>Whose</span><select className="input" name="label" defaultValue="alternate">
          <option value="alternate">Student (another number)</option><option value="parent">Parent or guardian</option><option value="office">Office</option>
          {kind === "phone" && <option value="whatsapp_only">WhatsApp only (not for calls)</option>}
        </select></label>
        <label className="checkbox"><input type="checkbox" checked={primary} onChange={(e) => setPrim(e.target.checked)} /> Make it the primary {kind === "phone" ? "number for calls and WhatsApp" : "email"}</label>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : "Add"}</button>
      </form>
    </Sheet>
  );
}

// ---------- profile and interest ----------

export type FieldDef = { key: string; label: string; value: string | null; type?: "text" | "number" };

/** A read-only list with an Edit sheet. Changes are kept in field history and synced (b2c.correct_lead). */
export function EditablePanel({ leadId, title, fields, reasonRequired, canEdit, note }: { leadId: number; title: string; fields: FieldDef[]; reasonRequired?: boolean; canEdit: boolean; note?: string }) {
  const [open, setOpen] = useState(false);
  const { busy, error, run } = useAction();
  return (
    <section className="panel">
      <header><h3>{title}</h3>{canEdit && <button type="button" className="btn quiet sm" onClick={() => setOpen(true)}>{reasonRequired ? "Change" : "Edit"}</button>}</header>
      <div className="body">
        <dl className="kv">
          {fields.map((f) => <span key={f.key} style={{ display: "contents" }}><dt>{f.label}</dt><dd>{f.value || "—"}</dd></span>)}
        </dl>
        {note && <p className="note">{note}</p>}
      </div>
      {open && (
        <Sheet title={reasonRequired ? "Change interest" : `Edit ${title.toLowerCase()}`} onClose={() => setOpen(false)}>
          <form className="stack" action={(f) => run(() => {
            const changed: Record<string, string | number | null> = {};
            for (const d of fields) {
              const v = String(f.get(d.key) ?? "").trim();
              if (v !== (d.value ?? "")) changed[d.key] = v === "" ? null : d.type === "number" ? Number(v) : v;
            }
            if (Object.keys(changed).length === 0) return Promise.resolve({ ok: true });
            return correctLead(leadId, changed, String(f.get("reason") ?? "") || undefined);
          }, () => setOpen(false))}>
            {fields.map((d) => (
              <label key={d.key} className="field"><span>{d.label}</span>
                <input className="input" name={d.key} defaultValue={d.value ?? ""} type={d.type === "number" ? "number" : "text"} maxLength={200} />
              </label>
            ))}
            {reasonRequired && <label className="field"><span>Why (required for a programme or university change)</span><input className="input" name="reason" maxLength={300} /></label>}
            {error && <p className="error" role="alert">{error}</p>}
            <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : "Save"}</button>
          </form>
        </Sheet>
      )}
    </section>
  );
}

// ---------- note ----------

export function NoteBox({ leadId }: { leadId: number }) {
  const [text, setText] = useState("");
  const { busy, error, run } = useAction();
  return (
    <form className="stack" style={{ gap: 6 }} action={() => run(() => addNote(leadId, text), () => setText(""))}>
      <textarea className="input" value={text} onChange={(e) => setText(e.target.value)} placeholder="Add a note" maxLength={4000} aria-label="Note" />
      {error && <p className="error" role="alert">{error}</p>}
      <button className="btn ghost sm" type="submit" disabled={busy || !text.trim()} style={{ justifySelf: "end" }}>{busy ? "Saving…" : "Add note"}</button>
    </form>
  );
}

// ---------- add follow-up ----------

export function AddTaskButton({ leadId, label = "Add", className = "btn quiet sm" }: { leadId: number; label?: string; className?: string }) {
  const [open, setOpen] = useState(false);
  const [kind, setKind] = useState("call");
  const [title, setTitle] = useState("");
  const [due, setDue] = useState<string | null>(null);
  const { busy, error, run } = useAction();
  return (
    <>
      <button type="button" className={className} onClick={() => setOpen(true)}><Plus className="icon s" aria-hidden />{label}</button>
      {open && (
        <Sheet title="Add a follow-up" onClose={() => setOpen(false)}>
          <div className="field"><span>Kind</span><div className="pills">
            {Object.entries(TASK_KIND_LABEL).map(([k, v]) => <button key={k} type="button" className="pill" aria-pressed={kind === k} onClick={() => setKind(k)}>{v}</button>)}
          </div></div>
          <label className="field"><span>What</span><input className="input" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={200} placeholder="Share the fee sheet" /></label>
          <NextPicker value={due} onChange={setDue} label="When" />
          {error && <p className="error" role="alert">{error}</p>}
          <button type="button" className="btn primary block" disabled={busy || !due}
            onClick={() => run(() => taskAdd(leadId, kind, title || TASK_KIND_LABEL[kind] || "Follow up", due!), () => setOpen(false))}>{busy ? "Saving…" : "Add follow-up"}</button>
        </Sheet>
      )}
    </>
  );
}
