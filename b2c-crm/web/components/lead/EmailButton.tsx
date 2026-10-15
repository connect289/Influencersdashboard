"use client";
import { useEffect, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { BookOpen, Mail, Star } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { emailSend } from "@/app/s/actions";
import { emailLibrary, mergeValues, programmeFitRows, type LibraryTemplate } from "@/app/s/workspace-actions";
import { unfilled, type Vars } from "@/lib/compose";
import type { Programme } from "@/lib/programmes";
import { attachmentLines, renderMerge, type MergeValues } from "@/lib/workspace";

/**
 * The email composer (spec B8.6): a template from the shared library (recommended first, with its author, uses and reply
 * rate) or a blank email, every merge field filled from the lead (b2c.merge_values), brochure links added from Programme
 * fit, edited, then sent from the counsellor's own mailbox. Nothing reaches a student in test mode.
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
  const [templates, setTemplates] = useState<LibraryTemplate[] | null>(null);
  const [mv, setMv] = useState<MergeValues>({ first_name: vars.first_name, programme: vars.programme, university: vars.university, counsellor_name: vars.counsellor });
  const [templateId, setTemplateId] = useState<number | null>(null);
  const [subject, setSubject] = useState("");
  const [text, setText] = useState("");
  const [brochures, setBrochures] = useState<Programme[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();

  useEffect(() => {
    let live = true;
    emailLibrary().then((r) => live && (r.ok ? setTemplates((r.data ?? []).filter((t) => !t.hidden || t.mine)) : setError(r.error)));
    mergeValues(leadId).then((r) => live && r.ok && r.data && setMv((m) => ({ ...m, ...r.data })));
    return () => { live = false; };
  }, [leadId]);

  function pick(t: LibraryTemplate | null) {
    setTemplateId(t?.id ?? null);
    setSubject(t ? renderMerge(t.subject, mv) : "");
    setText(t ? renderMerge(t.body, mv) + attachmentLines(t.attachments) : `Hi ${mv.first_name ?? ""},\n\n\n\n${mv.counsellor_name ?? ""}\nEduwit`);
  }

  function loadBrochures() {
    programmeFitRows(leadId).then((r) => (r.ok ? setBrochures((r.data?.rows ?? []).filter((p) => p.brochure_url && /^https:\/\//.test(p.brochure_url))) : toast.error(r.error)));
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
          {templates?.map((t) => (
            <option key={t.id} value={t.id}>
              {t.recommended ? "★ " : ""}{t.name} · {t.mine ? "yours" : t.author ?? "a colleague"} · {t.uses} sent{t.reply_rate !== null ? `, ${t.reply_rate}% replied` : ""}
            </option>
          ))}
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
      <div className="row wrap" style={{ gap: 6 }}>
        <button type="button" className="btn quiet sm" onClick={loadBrochures}><BookOpen className="icon s" aria-hidden />Add a brochure</button>
        {brochures?.length === 0 && <span className="note">No programme that fits has a brochure.</span>}
        {brochures?.map((p) => (
          <button key={p.id} type="button" className="pill" onClick={() => setText((x) => `${x.trimEnd()}\n\n${p.name}, ${p.university}: ${p.brochure_url}`)}>{p.name} · {p.university_short ?? p.university}</button>
        ))}
      </div>
      {left.length > 0 && <p className="banner small">Fill in or remove: {left.map((k) => `{{${k}}}`).join(", ")}</p>}
      {templateId && <p className="note"><Star className="icon s" aria-hidden /> Your changes here are for this email only; the template stays as it is.</p>}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={send} disabled={busy || !subject.trim() || !text.trim() || left.length > 0}>{busy ? "Sending…" : "Send"}</button>
    </Sheet>
  );
}
