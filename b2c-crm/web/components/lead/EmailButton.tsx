"use client";
import { useEffect, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Mail, Star } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { emailSend, emailTemplatesList, type ComposeTemplate } from "@/app/s/actions";
import { fill, unfilled, type Vars } from "@/lib/compose";

/**
 * The email composer (spec B8.6): a sales template or a blank email, placeholders filled from the lead, edited, then sent
 * from the counsellor's own mailbox. Nothing reaches a student in test mode.
 */
export function EmailButton({ leadId, to, vars, blocked }: { leadId: number; to: string | null; vars: Vars; blocked?: string | null }) {
  const [open, setOpen] = useState(false);
  const why = blocked ?? (to ? null : "This lead has no email. Add one under Contacts.");
  return (
    <>
      <button type="button" className="btn ghost" onClick={() => (why ? toast.error(why) : setOpen(true))} aria-disabled={!!why} title={why ?? undefined}>
        <Mail className="icon s" aria-hidden />Email
      </button>
      {open && to && <Composer leadId={leadId} to={to} vars={vars} onClose={() => setOpen(false)} />}
    </>
  );
}

function Composer({ leadId, to, vars, onClose }: { leadId: number; to: string; vars: Vars; onClose: () => void }) {
  const router = useRouter();
  const [templates, setTemplates] = useState<ComposeTemplate[] | null>(null);
  const [templateId, setTemplateId] = useState<number | null>(null);
  const [subject, setSubject] = useState("");
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();

  useEffect(() => {
    let live = true;
    emailTemplatesList().then((r) => live && (r.ok ? setTemplates(r.data ?? []) : setError(r.error)));
    return () => { live = false; };
  }, []);

  function pick(t: ComposeTemplate | null) {
    setTemplateId(t?.id ?? null);
    setSubject(t ? fill(t.subject, vars) : "");
    setText(t ? fill(t.body, vars) : `Hi ${vars.first_name ?? ""},\n\n\n\n${vars.counsellor ?? ""}\nEduwit`);
  }

  const left = useMemo(() => unfilled(subject + " " + text), [subject, text]);

  function send() {
    setError(null);
    start(async () => {
      const r = await emailSend({ lead: leadId, subject, text, template: templateId });
      if (!r.ok) return setError(r.error);
      toast.success(r.notice ?? "Email queued.");
      onClose();
      router.refresh();
    });
  }

  return (
    <Sheet title="Email" onClose={onClose}>
      <p className="small muted">To <b>{to}</b>, from your @eduwit.in mailbox.</p>
      <label className="field">
        <span>Template</span>
        <select className="input" value={templateId ?? ""} onChange={(e) => pick(templates?.find((t) => t.id === Number(e.target.value)) ?? null)} disabled={!templates}>
          <option value="">{templates ? "Blank email" : "Loading templates…"}</option>
          {templates?.map((t) => <option key={t.id} value={t.id}>{t.recommended ? "★ " : ""}{t.name}{t.mine ? " (yours)" : ""}</option>)}
        </select>
      </label>
      {templates && templates.length === 0 && <p className="note">No templates yet. Write your own under Me → Email templates.</p>}
      <label className="field">
        <span>Subject</span>
        <input className="input" value={subject} onChange={(e) => setSubject(e.target.value)} maxLength={300} />
      </label>
      <label className="field">
        <span>Message</span>
        <textarea className="input" rows={10} value={text} onChange={(e) => setText(e.target.value)} maxLength={20000} />
      </label>
      {left.length > 0 && <p className="banner small">Fill in or remove: {left.map((k) => `{{${k}}}`).join(", ")}</p>}
      {templateId && <p className="note"><Star className="icon s" aria-hidden /> Your changes here are for this email only; the template stays as it is.</p>}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={send} disabled={busy || !subject.trim() || !text.trim() || left.length > 0}>{busy ? "Sending…" : "Send"}</button>
    </Sheet>
  );
}
