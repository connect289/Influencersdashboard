"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, Send } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { emailTemplateMSave, waTemplateSave, waTemplateSubmit } from "../nurture-actions";

export type WaTpl = { id: number; name: string; language: string; category: string; audience: string; usable_by_sales: boolean; purpose: string | null; body: string;
  variables: string[]; buttons: { type: string; text: string; url?: string }[]; status: string; rejection_reason: string | null; tags: string[]; uses: number; version: number; archived_at: string | null; updated_at: string };
export type EmailTpl = { id: number; name: string; language: string; subject: string; body: string; tags: string[]; version: number; uses: number; archived_at: string | null; updated_at: string };

const VARS = ["first_name", "programme", "university", "counsellor", "counsellor_first_name", "next_working_time"];
const SAMPLE: Record<string, string> = { first_name: "Asha", programme: "Online MBA", university: "Amity Online", counsellor: "Priya Sharma", counsellor_first_name: "Priya", next_working_time: "10:00 am on Mon 20 Oct", city: "Pune" };

function useSave() {
  const router = useRouter();
  const [busy, start] = useTransition();
  const run = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>, done?: () => void) => start(async () => {
    const r = await fn();
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Saved.");
    done?.();
    router.refresh();
  });
  return { busy, run };
}

export function WaSubmitButton({ id }: { id: number }) {
  const { busy, run } = useSave();
  return <button type="button" className="btn ghost sm" disabled={busy} onClick={() => run(() => waTemplateSubmit(id))}><Send className="icon s" aria-hidden />Submit to Meta</button>;
}

export function WaTemplateButton({ audience, admin, t }: { audience: string; admin: boolean; t?: WaTpl }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className={t ? "btn quiet sm" : "btn ghost sm"} onClick={() => setOpen(true)}>{t ? "Edit" : <><Plus className="icon s" aria-hidden />New template</>}</button>
      {open && <WaSheet audience={audience} admin={admin} t={t} onClose={() => setOpen(false)} />}
    </>
  );
}

function WaSheet({ audience, admin, t, onClose }: { audience: string; admin: boolean; t?: WaTpl; onClose: () => void }) {
  const { busy, run } = useSave();
  const [name, setName] = useState(t?.name ?? "");
  const [language, setLanguage] = useState(t?.language ?? "en");
  const [category, setCategory] = useState(t?.category ?? (audience === "marketing" ? "marketing" : "utility"));
  const [aud, setAud] = useState(t?.audience ?? audience);
  const [purpose, setPurpose] = useState(t?.purpose ?? "");
  const [body, setBody] = useState(t?.body ?? "");
  const [vars, setVars] = useState<string[]>(t?.variables ?? []);
  const [buttons, setButtons] = useState<{ type: string; text: string; url?: string }[]>(t?.buttons ?? []);
  const [tags, setTags] = useState((t?.tags ?? []).join(", "));
  const placeholders = [...new Set([...body.matchAll(/\{\{(\d+)\}\}/g)].map((m) => Number(m[1])))].sort((a, b) => a - b);
  const preview = body.replace(/\{\{(\d+)\}\}/g, (_, n: string) => SAMPLE[vars[Number(n) - 1] ?? ""] ?? `{{${n}}}`);
  const save = (archived?: boolean) => run(() => waTemplateSave({ id: t?.id, name, language, category, audience: aud, purpose: purpose || null, body, variables: vars.slice(0, placeholders.length),
    buttons: buttons.filter((b) => b.text.trim()), tags: tags.split(",").map((x) => x.trim()).filter(Boolean), ...(archived !== undefined ? { archived } : {}), usable_by_sales: aud === "sales" }), onClose);

  return (
    <Sheet title={t ? `Edit ${t.name}` : "New WhatsApp template"} onClose={onClose}>
      <div className="row wrap" style={{ gap: 6 }}>
        <label className="field grow"><span>Name (a-z, 0-9, _)</span><input className="input mono" value={name} onChange={(e) => setName(e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, "_"))} disabled={!!t} maxLength={100} /></label>
        <label className="field"><span>Language</span><select className="input" value={language} onChange={(e) => setLanguage(e.target.value)} disabled={!!t}><option value="en">English</option><option value="hi">Hindi</option><option value="en_IN">English (India)</option></select></label>
      </div>
      <div className="row wrap" style={{ gap: 6 }}>
        <label className="field"><span>Meta category</span><select className="input" value={category} onChange={(e) => setCategory(e.target.value)}><option value="marketing">Marketing</option><option value="utility">Utility</option></select></label>
        {admin && <label className="field"><span>For</span><select className="input" value={aud} onChange={(e) => setAud(e.target.value)} disabled={!!t}><option value="marketing">Marketing</option><option value="sales">Sales (counsellors)</option><option value="system">System</option></select></label>}
        <label className="field grow"><span>Purpose (optional)</span><input className="input" value={purpose} onChange={(e) => setPurpose(e.target.value)} placeholder="opener, followup, documents, journey…" /></label>
      </div>
      <label className="field"><span>Text ({"{{1}}"}, {"{{2}}"} … for variables)</span><textarea className="input" rows={5} value={body} onChange={(e) => setBody(e.target.value)} maxLength={1024} /></label>
      {placeholders.length > 0 && (
        <div className="row wrap" style={{ gap: 6 }}>
          {placeholders.map((n) => (
            <label key={n} className="field"><span>{`{{${n}}}`} is</span>
              <select className="input" value={vars[n - 1] ?? ""} onChange={(e) => { const v = [...vars]; v[n - 1] = e.target.value; setVars(v); }}>
                <option value="">Choose</option>{VARS.map((v) => <option key={v} value={v}>{v.replace(/_/g, " ")}</option>)}
              </select></label>
          ))}
        </div>
      )}
      <div className="field"><span>Buttons (quick replies re-engage the lead: &ldquo;Yes, call me&rdquo;, &ldquo;I&apos;m interested&rdquo;, &ldquo;Share details&rdquo;)</span>
        {buttons.map((b, i) => (
          <div key={i} className="row" style={{ gap: 6 }}>
            <select className="input" value={b.type} onChange={(e) => setButtons(buttons.map((x, k) => (k === i ? { ...x, type: e.target.value } : x)))} style={{ maxWidth: 140 }}><option value="quick_reply">Quick reply</option><option value="url">Link</option></select>
            <input className="input grow" value={b.text} maxLength={25} onChange={(e) => setButtons(buttons.map((x, k) => (k === i ? { ...x, text: e.target.value } : x)))} placeholder="Button text" />
            {b.type === "url" && <input className="input grow" value={b.url ?? ""} onChange={(e) => setButtons(buttons.map((x, k) => (k === i ? { ...x, url: e.target.value } : x)))} placeholder="https://" />}
            <button type="button" className="btn quiet sm" onClick={() => setButtons(buttons.filter((_, k) => k !== i))} aria-label="Remove button">×</button>
          </div>
        ))}
        {buttons.length < 3 && <button type="button" className="btn quiet sm" style={{ justifySelf: "start" }} onClick={() => setButtons([...buttons, { type: "quick_reply", text: "" }])}><Plus className="icon s" aria-hidden />Add a button</button>}
      </div>
      <label className="field"><span>Tags</span><input className="input" value={tags} onChange={(e) => setTags(e.target.value)} placeholder="fee, mba" /></label>
      <div className="thread"><div className="msg out"><span className="tpl">Preview</span><span style={{ whiteSpace: "pre-wrap" }}>{preview || "…"}</span>{buttons.filter((b) => b.text).map((b, i) => <span key={i} className="chip soft">{b.text}</span>)}</div></div>
      {t && t.status === "approved" && <p className="note">Changing the text, buttons or category sends it back to draft: Meta must approve it again.</p>}
      <button type="button" className="btn primary block" disabled={busy || !name || !body.trim() || placeholders.some((n) => !vars[n - 1])} onClick={() => save()}>{busy ? "Saving…" : "Save"}</button>
      {t && <button type="button" className="btn quiet block" disabled={busy} onClick={() => save(!t.archived_at)}>{t.archived_at ? "Restore" : "Archive"}</button>}
    </Sheet>
  );
}

export function EmailTemplateButton({ t }: { t?: EmailTpl }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className={t ? "btn quiet sm" : "btn ghost sm"} onClick={() => setOpen(true)}>{t ? "Edit" : <><Plus className="icon s" aria-hidden />New template</>}</button>
      {open && <EmailSheet t={t} onClose={() => setOpen(false)} />}
    </>
  );
}

function EmailSheet({ t, onClose }: { t?: EmailTpl; onClose: () => void }) {
  const { busy, run } = useSave();
  const [name, setName] = useState(t?.name ?? "");
  const [language, setLanguage] = useState(t?.language ?? "en");
  const [subject, setSubject] = useState(t?.subject ?? "");
  const [body, setBody] = useState(t?.body ?? "Hi {{first_name}},\n\n\n\nTeam Eduwit");
  const [tags, setTags] = useState((t?.tags ?? []).join(", "));
  const fill = (s: string) => s.replace(/\{\{(\w+)\}\}/g, (_, k: string) => SAMPLE[k] ?? `{{${k}}}`);
  const save = (archived?: boolean) => run(() => emailTemplateMSave({ id: t?.id, name, language, subject, body, tags: tags.split(",").map((x) => x.trim()).filter(Boolean), ...(archived !== undefined ? { archived } : {}) }), onClose);
  return (
    <Sheet title={t ? `Edit ${t.name}` : "New marketing email"} onClose={onClose}>
      <div className="row wrap" style={{ gap: 6 }}>
        <label className="field grow"><span>Name</span><input className="input" value={name} onChange={(e) => setName(e.target.value)} maxLength={100} /></label>
        <label className="field"><span>Language</span><select className="input" value={language} onChange={(e) => setLanguage(e.target.value)}><option value="en">English</option><option value="hi">Hindi</option><option value="hinglish">Hinglish</option></select></label>
      </div>
      <label className="field"><span>Subject</span><input className="input" value={subject} onChange={(e) => setSubject(e.target.value)} maxLength={300} /></label>
      <label className="field"><span>Text (a blank line starts a paragraph; https links are tracked)</span><textarea className="input" rows={10} value={body} onChange={(e) => setBody(e.target.value)} maxLength={50000} /></label>
      <label className="field"><span>Tags</span><input className="input" value={tags} onChange={(e) => setTags(e.target.value)} /></label>
      <details className="panel more" style={{ padding: 10 }}><summary>Preview with a sample student</summary>
        <div className="md" style={{ marginTop: 8 }}><b>{fill(subject)}</b>{fill(body).split(/\n{2,}/).map((p, i) => <p key={i} style={{ whiteSpace: "pre-wrap" }}>{p}</p>)}
          <p><span className="btn primary sm">I&apos;m interested, call me</span></p><p className="small muted">You get this because you asked Eduwit about online programmes. Unsubscribe.</p></div>
      </details>
      <button type="button" className="btn primary block" disabled={busy || !name.trim() || !subject.trim() || !body.trim()} onClick={() => save()}>{busy ? "Saving…" : "Save"}</button>
      {t && <button type="button" className="btn quiet block" disabled={busy} onClick={() => save(!t.archived_at)}>{t.archived_at ? "Restore" : "Archive"}</button>}
    </Sheet>
  );
}
