"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { tagOwn, tasksBulk, waBulk } from "../bulk-actions";
import { reassignLeads } from "../workspace-actions";

type Tpl = { id: number; name: string; language: string; purpose: string | null; status: string };

function inTwoHours() {
  const d = new Date(Date.now() + 2 * 3600_000);
  d.setSeconds(0, 0);
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 16);
}

/**
 * A counsellor's bulk tools over the ticked rows (spec B8.2): a tag, one follow-up for all, or a sales template to several
 * leads at once. The database applies the single-lead rules to each and names what it skipped.
 */
export function SalesBulkBar({ templates, people = [] }: { templates: Tpl[]; people?: { user_id: string; name: string }[] }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [op, setOp] = useState<"tag" | "untag" | "task" | "wa" | "reassign">("task");
  const [to, setTo] = useState("");
  const [text, setText] = useState("");
  const [due, setDue] = useState(inTwoHours);
  const [kind, setKind] = useState("call");
  const [tpl, setTpl] = useState<number>(templates[0]?.id ?? 0);

  function selected(form: HTMLFormElement): number[] {
    return Array.from(document.querySelectorAll<HTMLInputElement>(`input[form="${form.id}"][name="lead"]:checked`)).map((i) => Number(i.value));
  }
  function run(form: HTMLFormElement) {
    const leads = selected(form);
    if (leads.length === 0) return void toast.error("Tick at least one lead.");
    start(async () => {
      if (op === "tag" || op === "untag") {
        const r = await tagOwn(leads, text, op === "tag");
        if (!r.ok) return void toast.error(r.error);
        toast.success(`${r.data ?? 0} of ${leads.length} ${op === "tag" ? "tagged" : "untagged"}.`);
      } else if (op === "task") {
        const r = await tasksBulk(leads, { kind: kind as "call", title: text, due: new Date(due).toISOString() });
        if (!r.ok) return void toast.error(r.error);
        toast.success(`${r.data?.created ?? 0} follow-ups added.${r.data?.skipped.length ? ` Skipped: ${r.data.skipped.map((x) => `#${x.lead_id} (${x.why})`).join(", ")}.` : ""}`);
      } else if (op === "reassign") {
        if (text.trim().length < 3) return void toast.error("Give a reason.");
        const r = await reassignLeads(leads, to || null, text);
        if (!r.ok) return void toast.error(r.error);
        toast.success(`${r.data ?? 0} reassigned.`);
      } else {
        if (!tpl) return void toast.error("Choose a template.");
        if (leads.length > 50) return void toast.error("At most 50 leads at a time.");
        const r = await waBulk(leads, tpl);
        if (!r.ok) return void toast.error(r.error);
        toast.success(`${r.data?.sent ?? 0} queued.${r.data?.refused.length ? ` Refused: ${r.data.refused.map((x) => `#${x.lead_id} (${x.why})`).join(", ")}.` : ""}`);
      }
      setText("");
      router.refresh();
    });
  }
  return (
    <form id="bulk" className="bulkbar" onSubmit={(e) => { e.preventDefault(); run(e.currentTarget); }}>
      <b>With the ticked leads:</b>
      <select className="input" value={op} onChange={(e) => setOp(e.target.value as typeof op)} aria-label="Action">
        <option value="task">Add a follow-up</option>
        <option value="wa">Send a WhatsApp template</option>
        <option value="tag">Add a tag</option>
        <option value="untag">Remove a tag</option>
        {people.length > 0 && <option value="reassign">Reassign</option>}
      </select>
      {op === "task" && (
        <>
          <select className="input" value={kind} onChange={(e) => setKind(e.target.value)} aria-label="Kind">
            <option value="call">Call</option><option value="whatsapp">WhatsApp</option><option value="email">Email</option><option value="document">Documents</option><option value="followup">Follow-up</option>
          </select>
          <input className="input" value={text} onChange={(e) => setText(e.target.value)} required minLength={2} maxLength={120} placeholder="What to do" aria-label="What to do" />
          <input className="input" type="datetime-local" value={due} onChange={(e) => setDue(e.target.value)} required aria-label="When" />
        </>
      )}
      {op === "wa" && (
        <select className="input" value={tpl} onChange={(e) => setTpl(Number(e.target.value))} aria-label="Template">
          {templates.length === 0 && <option value={0}>No sales templates yet</option>}
          {templates.map((t) => <option key={t.id} value={t.id}>{t.purpose ?? t.name} · {t.name} ({t.language}){t.status !== "approved" ? " · not approved yet" : ""}</option>)}
        </select>
      )}
      {op === "reassign" && (
        <>
          <select className="input" value={to} onChange={(e) => setTo(e.target.value)} aria-label="To">
            <option value="">Through the allocation rules</option>
            {people.map((p) => <option key={p.user_id} value={p.user_id}>{p.name}</option>)}
          </select>
          <input className="input" value={text} onChange={(e) => setText(e.target.value)} required minLength={3} maxLength={300} placeholder="Reason" aria-label="Reason" />
        </>
      )}
      {(op === "tag" || op === "untag") && (
        <input className="input" value={text} onChange={(e) => setText(e.target.value)} required minLength={1} maxLength={40} placeholder="Tag" aria-label="Tag" />
      )}
      <button className="btn ghost sm" type="submit" disabled={busy}>{busy ? "Working…" : "Apply"}</button>
    </form>
  );
}
