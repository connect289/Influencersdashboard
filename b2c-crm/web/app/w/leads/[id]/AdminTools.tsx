"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { when } from "@/lib/format";
import { LOGIC_LABEL } from "@/lib/labels";
import type { Contact } from "@/lib/types";
import { adminEditContact, coachingNote, eraseLead, reassign, routeToPartners } from "../../actions";
import { FlagActions } from "../flagged/FlagActions";

type Person = { user_id: string; name: string };

/** Why the lead went to whom (the allocation decision) and the Admin's actions on one lead. */
export function AdminTools({ leadId, admin, decision, contacts, people, barred, consent, status, flagged }: {
  leadId: number; admin: boolean; decision: Record<string, unknown> | null; contacts: Contact[]; people: Person[]; barred: boolean; consent: string | null; status: string; flagged?: string | null;
}) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [sheet, setSheet] = useState<"reassign" | "route" | "coach" | "contacts" | "erase" | null>(null);
  const [to, setTo] = useState("");
  const [text, setText] = useState("");
  const [reference, setReference] = useState("");
  const [typed, setTyped] = useState("");
  const close = () => { setSheet(null); setText(""); setReference(""); setTyped(""); };
  const go = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>, msg?: string) => start(async () => {
    const r = await fn();
    if (!r.ok) return void toast.error(r.error);
    toast.success(msg ?? r.notice ?? "Done.");
    close();
    router.refresh();
  });
  const skipped = (decision?.skipped as { name: string; why: string }[] | undefined) ?? [];
  return (
    <section className="panel">
      <header><h3>Allocation</h3>{decision && <span className="chip soft">Decision #{String(decision.id)}</span>}</header>
      <div className="body">
        {decision ? (
          <dl className="kv">
            <dt>When</dt><dd>{when(decision.at as string)} · {String(decision.trigger)}</dd>
            <dt>Rule</dt><dd>{String(decision.rule_name ?? "—")} · {LOGIC_LABEL[String(decision.logic)] ?? String(decision.logic ?? "—")}{decision.pool ? ` · pool ${String(decision.pool)}` : ""}</dd>
            <dt>Outcome</dt><dd>{String(decision.outcome)}{decision.why ? ` · ${String(decision.why)}` : ""}</dd>
            {skipped.length > 0 && <><dt>Skipped</dt><dd>{skipped.map((s) => `${s.name} (${s.why})`).join(", ")}</dd></>}
          </dl>
        ) : <p className="note">No allocation decision yet.</p>}
        {admin && flagged && status !== "closed" && (
          <div className="banner"><div className="grow stack tight"><span><b>Flagged as {flagged.replace(/_/g, " ")}</b>: no marketing until you decide.</span><FlagActions leadId={leadId} /></div></div>
        )}
        {admin && (
          <div className="row wrap" style={{ gap: 6 }}>
            {status === "active" && <button type="button" className="btn ghost sm" onClick={() => setSheet("reassign")}>Reassign</button>}
            {status !== "closed" && !barred && <button type="button" className="btn ghost sm" onClick={() => setSheet("route")} disabled={consent !== "given"} title={consent !== "given" ? "Needs the student's partner-sharing consent" : undefined}>Send to partner routing</button>}
            <button type="button" className="btn ghost sm" onClick={() => setSheet("coach")}>Coaching note</button>
            <button type="button" className="btn ghost sm" onClick={() => setSheet("contacts")}>Edit contact details</button>
            <button type="button" className="btn quiet sm" onClick={() => setSheet("erase")}>Erase on the student&apos;s request</button>
          </div>
        )}
      </div>
      {sheet === "reassign" && (
        <Sheet title="Reassign" onClose={close}>
          <label className="field"><span>To</span><select className="input" value={to} onChange={(e) => setTo(e.target.value)}>
            <option value="">Through the allocation rules (not the current counsellor)</option>
            {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
          </select></label>
          <label className="field"><span>Reason (required)</span><input className="input" value={text} onChange={(e) => setText(e.target.value)} maxLength={300} /></label>
          <button type="button" className="btn primary block" disabled={busy || text.trim().length < 3} onClick={() => go(() => reassign([leadId], to || null, text))}>Reassign</button>
        </Sheet>
      )}
      {sheet === "route" && (
        <Sheet title="Send to partner routing" onClose={close}>
          <p className="note">The engine looks for a partner now. If none takes the lead it comes back to its counsellor.</p>
          <label className="field"><span>Reason (3 to 300 characters, kept in the audit log)</span><input className="input" value={text} onChange={(e) => setText(e.target.value)} maxLength={300} /></label>
          <button type="button" className="btn primary block" disabled={busy || text.trim().length < 3} onClick={() => go(async () => {
            const r = await routeToPartners([leadId], text);
            if (r.ok && r.data?.refused.length) return { ok: false, error: `Refused: ${r.data.refused[0]!.why}` };
            return r;
          }, "Sent. The result arrives in a minute.")}>Send</button>
        </Sheet>
      )}
      {sheet === "coach" && (
        <Sheet title="Coaching note" onClose={close}>
          <p className="note">Only the Admin and the sales head see coaching notes.</p>
          <textarea className="input" value={text} onChange={(e) => setText(e.target.value)} maxLength={4000} rows={5} aria-label="Note" />
          <button type="button" className="btn primary block" disabled={busy || !text.trim()} onClick={() => go(() => coachingNote(leadId, text))}>Save</button>
        </Sheet>
      )}
      {sheet === "contacts" && (
        <Sheet title="Edit contact details" onClose={close}>
          <p className="note">Edits and removals are kept in the field history. A change to the enquiry&apos;s own number or email also goes to the master lead table.</p>
          {contacts.map((c) => <ContactRow key={c.id} c={c} busy={busy} onSave={(v, rm) => go(() => adminEditContact(c.id, v, rm, leadId))} />)}
        </Sheet>
      )}
      {sheet === "erase" && (
        <Sheet title="Erase on the student's request" onClose={close}>
          <p className="note">For a request under India&apos;s data protection law (DPDP). The name, numbers and emails are anonymised, message bodies, notes and documents
            are removed, the lead leaves every view, journey and queue, and the B2B CRM is told so every partner that had the lead is told too. Money rows stay, by
            lead number only. <b>This cannot be undone.</b></p>
          <label className="field"><span>Request reference (the email or ticket the student used)</span><input className="input" value={reference} onChange={(e) => setReference(e.target.value)} maxLength={200} placeholder="SUP-0042, or the student's email of 15 Oct" /></label>
          <label className="field"><span>Note (optional, kept in the audit log)</span><textarea className="input" value={text} onChange={(e) => setText(e.target.value)} maxLength={300} rows={3} /></label>
          <label className="field"><span>Type ERASE {leadId} to confirm</span><input className="input" value={typed} onChange={(e) => setTyped(e.target.value)} autoComplete="off" /></label>
          <button type="button" className="btn danger block" disabled={busy || reference.trim().length < 3 || typed.trim() !== `ERASE ${leadId}`} onClick={() => start(async () => {
            const r = await eraseLead(leadId, reference, text);
            if (!r.ok) return void toast.error(r.error);
            toast.success(`Erased. ${r.data?.messages ?? 0} messages emptied; ${r.data?.files ?? 0} files are being removed.`);
            close();
            router.push("/w/leads");
          })}>Erase this student</button>
        </Sheet>
      )}
    </section>
  );
}

function ContactRow({ c, busy, onSave }: { c: Contact; busy: boolean; onSave: (value: string | null, remove: boolean) => void }) {
  const [v, setV] = useState(c.value);
  return (
    <div className="row">
      <input className="input grow" value={v} onChange={(e) => setV(e.target.value)} aria-label={c.kind} />
      <button type="button" className="btn ghost sm" disabled={busy || v === c.value} onClick={() => onSave(v, false)}>Save</button>
      <button type="button" className="btn quiet sm" disabled={busy} onClick={() => onSave(null, true)}>Remove</button>
    </div>
  );
}
