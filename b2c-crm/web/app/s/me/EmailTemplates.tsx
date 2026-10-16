"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { EyeOff, Plus, Star, Trash2, X } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { emailTemplateDelete, emailTemplateFlag, emailTemplateSaveFull, programmeFind, type LibraryTemplate } from "../workspace-actions";
import type { Programme } from "@/lib/programmes";
import { MERGE_FIELDS } from "@/lib/workspace";

const CATEGORIES: Record<string, string> = {
  first_email: "First email", after_call: "After a call", brochure: "Brochure", fee_emi: "Fees and EMI", documents: "Documents", reminder: "Reminder", other: "Other",
};

type Attachment = { name: string; url: string; programme_id?: number };

/**
 * The shared sales email library (spec B8.6): every counsellor's templates with the author, uses and reply rate, recommended
 * first. Editing someone else's saves your own copy; theirs never changes. The author or the Admin deletes; the Admin
 * recommends or hides. Brochure links from the Programme page go with the template.
 */
export function EmailTemplates({ templates, admin }: { templates: LibraryTemplate[]; admin: boolean }) {
  const router = useRouter();
  const [edit, setEdit] = useState<LibraryTemplate | "new" | null>(null);
  const [busy, start] = useTransition();
  const act = (fn: () => Promise<{ ok: boolean; error?: string; notice?: string }>) => start(async () => {
    const r = await fn();
    if (!r.ok) return void toast.error(r.error);
    toast.success(r.notice ?? "Done.");
    router.refresh();
  });
  return (
    <div className="stack">
      <div className="row between">
        <p className="note">Everyone&apos;s templates are shared, best first. Edit someone else&apos;s and you save your own copy.</p>
        <button type="button" className="btn ghost sm" onClick={() => setEdit("new")}><Plus className="icon s" aria-hidden />New</button>
      </div>
      <div className="list">
        {templates.length === 0 && <p className="empty">No templates yet.</p>}
        {templates.map((t) => (
          <div key={t.id} className="li" style={{ gridTemplateColumns: "auto 1fr auto" }}>
            <span className="avatar">{t.recommended ? <Star className="icon s" aria-label="Recommended" /> : t.name[0]}</span>
            <button type="button" className="t ellipsis linkish" onClick={() => setEdit(t)} style={{ textAlign: "left", background: "none", border: 0, padding: 0, color: "inherit", font: "inherit", fontWeight: 600 }}>
              {t.name}{t.mine ? " (yours)" : ""} {t.hidden && <span className="chip line"><EyeOff className="icon s" aria-hidden />Hidden</span>}
            </button>
            <span className="row" style={{ gap: 2 }}>
              {admin && (
                <>
                  <button type="button" className="btn quiet sm" disabled={busy} onClick={() => act(() => emailTemplateFlag(t.id, { recommended: !t.recommended }))}
                    aria-label={t.recommended ? "Stop recommending" : "Recommend"} title={t.recommended ? "Stop recommending" : "Recommend"}><Star className="icon s" aria-hidden /></button>
                  <button type="button" className="btn quiet sm" disabled={busy} onClick={() => act(() => emailTemplateFlag(t.id, { hidden: !t.hidden }))}
                    aria-label={t.hidden ? "Show in the library" : "Hide from the library"} title={t.hidden ? "Show in the library" : "Hide from the library"}><EyeOff className="icon s" aria-hidden /></button>
                </>
              )}
              {(t.mine || admin) && (
                <button type="button" className="btn quiet sm" disabled={busy} aria-label="Delete" title="Delete (copies others saved stay)"
                  onClick={() => window.confirm(`Delete “${t.name}”? Copies colleagues saved stay.`) && act(() => emailTemplateDelete(t.id))}><Trash2 className="icon s" aria-hidden /></button>
              )}
            </span>
            <span className="s ellipsis">
              {CATEGORIES[t.category] ?? t.category} · by {t.mine ? "you" : t.author ?? "a colleague"} · {t.uses} sent{t.reply_rate !== null ? ` · ${t.reply_rate}% replied` : ""}
              {t.attachments?.length ? ` · ${t.attachments.length} brochure${t.attachments.length > 1 ? "s" : ""}` : ""} · {t.subject}
            </span>
          </div>
        ))}
      </div>
      {edit && <TemplateSheet t={edit === "new" ? null : edit} admin={admin} onClose={() => setEdit(null)} />}
    </div>
  );
}

function TemplateSheet({ t, admin, onClose }: { t: LibraryTemplate | null; admin: boolean; onClose: () => void }) {
  const router = useRouter();
  // the author and the Admin change the template itself; anyone else saves their own copy
  const mine = !t || t.mine || admin;
  const [files, setFiles] = useState<Attachment[]>(() => (t?.attachments ?? []).filter((a): a is Attachment => !!a.url && !!a.name));
  const [q, setQ] = useState("");
  const [found, setFound] = useState<Programme[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const find = () => start(async () => {
    const r = await programmeFind(q);
    if (!r.ok) return setError(r.error);
    setFound((r.data ?? []).filter((p) => p.brochure_url && /^https:\/\//.test(p.brochure_url)));
  });
  return (
    <Sheet title={t ? (mine ? "Edit your template" : "Save your own copy") : "New template"} onClose={onClose}>
      <form className="stack" action={(f) => start(async () => {
        const r = await emailTemplateSaveFull({ id: t?.id ?? null, name: String(f.get("name") ?? ""), category: String(f.get("category") ?? "other"),
          subject: String(f.get("subject") ?? ""), body: String(f.get("body") ?? ""), attachments: files });
        if (!r.ok) return setError(r.error);
        toast.success(r.notice ?? "Saved.");
        onClose();
        router.refresh();
      })}>
        {t && !mine && <p className="note">By {t.author ?? "a colleague"}. Saving makes your own copy; theirs stays as it is.</p>}
        {t && !t.mine && admin && <p className="note">By {t.author ?? "a colleague"}. As the Admin you change their template itself.</p>}
        <label className="field"><span>Name</span><input className="input" name="name" required defaultValue={t?.name ?? ""} maxLength={120} /></label>
        <label className="field"><span>Kind</span><select className="input" name="category" defaultValue={t?.category ?? "after_call"}>
          {Object.entries(CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select></label>
        <label className="field"><span>Subject</span><input className="input" name="subject" required defaultValue={t?.subject ?? ""} maxLength={300} /></label>
        <label className="field"><span>Body</span><textarea className="input" name="body" required defaultValue={t?.body ?? ""} rows={8} placeholder="Hi {{first_name}}, …" /></label>
        <p className="note">Merge fields: {MERGE_FIELDS.map((k) => `{{${k}}}`).join(", ")}.</p>
        <div className="field">
          <span>Brochures from the Programme page</span>
          {files.map((a, i) => (
            <span key={a.url} className="row between small">
              <a href={a.url} target="_blank" rel="noopener noreferrer" className="ellipsis">{a.name}</a>
              <button type="button" className="btn quiet sm" aria-label={`Remove ${a.name}`} onClick={() => setFiles((x) => x.filter((_, j) => j !== i))}><X className="icon s" aria-hidden /></button>
            </span>
          ))}
          <span className="row" style={{ gap: 6 }}>
            <input className="input grow" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Find a programme" aria-label="Find a programme"
              onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); find(); } }} />
            <button type="button" className="btn ghost sm" disabled={busy} onClick={find}>Find</button>
          </span>
          {found && found.length === 0 && <span className="note">No programme with a brochure matches.</span>}
          {found && found.length > 0 && (
            <span className="row wrap" style={{ gap: 4 }}>
              {found.slice(0, 8).map((p) => (
                <button key={p.id} type="button" className="pill" disabled={files.length >= 6 || files.some((a) => a.url === p.brochure_url)}
                  onClick={() => setFiles((x) => [...x, { name: `${p.name}, ${p.university_short ?? p.university} brochure`.slice(0, 200), url: p.brochure_url!, programme_id: p.id }])}>
                  {p.name} · {p.university_short ?? p.university}
                </button>
              ))}
            </span>
          )}
        </div>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : mine ? "Save" : "Save my copy"}</button>
      </form>
    </Sheet>
  );
}
