"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, Star } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { emailTemplateSave } from "../actions";

export type EmailTemplate = {
  id: number; owner_id: string; name: string; category: string; subject: string; body: string; parent_id: number | null; version: number;
  recommended: boolean; hidden: boolean; uses: number;
};

const CATEGORIES: Record<string, string> = {
  first_email: "First email", after_call: "After a call", brochure: "Brochure", fee_emi: "Fees and EMI", documents: "Documents", reminder: "Reminder", other: "Other",
};

/** Shared sales email templates (spec B10.4): editing someone else's saves your own copy; theirs never changes. */
export function EmailTemplates({ templates, me }: { templates: EmailTemplate[]; me: string }) {
  const [edit, setEdit] = useState<EmailTemplate | "new" | null>(null);
  return (
    <div className="stack">
      <div className="row between">
        <p className="note">Everyone&apos;s templates are shared. Edit someone else&apos;s and you save your own copy.</p>
        <button type="button" className="btn ghost sm" onClick={() => setEdit("new")}><Plus className="icon s" aria-hidden />New</button>
      </div>
      <div className="list">
        {templates.length === 0 && <p className="empty">No templates yet.</p>}
        {templates.map((t) => (
          <button key={t.id} type="button" className="li" onClick={() => setEdit(t)}>
            <span className="avatar">{t.recommended ? <Star className="icon s" aria-label="Recommended" /> : t.name[0]}</span>
            <span className="t ellipsis">{t.name}{t.owner_id === me ? " (yours)" : ""}</span>
            <span className="small muted">{CATEGORIES[t.category] ?? t.category} · used {t.uses}</span>
            <span className="s ellipsis">{t.subject}</span>
          </button>
        ))}
      </div>
      {edit && <TemplateSheet t={edit === "new" ? null : edit} mine={edit !== "new" && edit.owner_id === me} onClose={() => setEdit(null)} />}
    </div>
  );
}

function TemplateSheet({ t, mine, onClose }: { t: EmailTemplate | null; mine: boolean; onClose: () => void }) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();
  return (
    <Sheet title={t ? (mine ? "Edit your template" : "Save your own copy") : "New template"} onClose={onClose}>
      <form className="stack" action={(f) => start(async () => {
        const r = await emailTemplateSave({ id: t?.id ?? null, name: f.get("name"), category: f.get("category"), subject: f.get("subject"), body: f.get("body") });
        if (!r.ok) return setError(r.error);
        toast.success(r.notice ?? "Saved.");
        onClose();
        router.refresh();
      })}>
        <label className="field"><span>Name</span><input className="input" name="name" required defaultValue={t?.name ?? ""} maxLength={120} /></label>
        <label className="field"><span>Kind</span><select className="input" name="category" defaultValue={t?.category ?? "after_call"}>
          {Object.entries(CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select></label>
        <label className="field"><span>Subject</span><input className="input" name="subject" required defaultValue={t?.subject ?? ""} maxLength={200} /></label>
        <label className="field"><span>Body</span><textarea className="input" name="body" required defaultValue={t?.body ?? ""} rows={8} placeholder="Hi {{first_name}}, …" /></label>
        <p className="note">Placeholders: {"{{first_name}}"}, {"{{programme}}"}, {"{{university}}"}, {"{{counsellor}}"}.</p>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="btn primary block" type="submit" disabled={busy}>{busy ? "Saving…" : mine || !t ? "Save" : "Save my copy"}</button>
      </form>
    </Sheet>
  );
}
