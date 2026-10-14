"use client";
import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Check, Pencil, Plus, Search } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { guideRead, guideSave, type Article, type Reader } from "@/app/guide-actions";
import { Markdown } from "@/lib/markdown";

const GUIDE_LABEL: Record<string, string> = { sales: "Sales guide", marketing: "Marketing guide", admin: "Admin guide" };

/** The in-app guide (spec B16): searchable, grouped by section, tracks what the person has read; the Admin edits it. */
export function Guide({ articles, admin, readers }: { articles: Article[]; admin?: boolean; readers?: Reader[] }) {
  const [q, setQ] = useState("");
  const [edit, setEdit] = useState<Article | "new" | null>(null);
  const [read, setRead] = useState<Set<number>>(() => new Set(articles.filter((a) => a.read).map((a) => a.id)));
  const shown = useMemo(() => {
    const t = q.trim().toLowerCase();
    return t ? articles.filter((a) => (a.title + " " + a.body + " " + a.section).toLowerCase().includes(t)) : articles;
  }, [articles, q]);
  const unread = articles.filter((a) => !a.archived && !read.has(a.id)).length;

  function opened(a: Article, open: boolean) {
    if (!open || read.has(a.id)) return;
    setRead((s) => new Set(s).add(a.id));
    void guideRead(a.id);
  }

  let lastGroup = "";
  return (
    <div className="stack">
      <div className="row wrap" style={{ gap: 8 }}>
        <label className="search grow"><Search className="icon s" aria-hidden /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search the guide" aria-label="Search the guide" /></label>
        <span className="small muted">{unread ? `${unread} not read yet` : "All read"}</span>
        {admin && <button type="button" className="btn ghost sm" onClick={() => setEdit("new")}><Plus className="icon s" aria-hidden />New article</button>}
      </div>
      {shown.length === 0 && <p className="empty">Nothing matches.</p>}
      {shown.map((a) => {
        const group = `${GUIDE_LABEL[a.role]} · ${a.section}`;
        const head = group !== lastGroup ? ((lastGroup = group), <h3 key={"h" + a.id} className="eyebrow" style={{ marginTop: 8 }}>{admin ? group : a.section}</h3>) : null;
        return (
          <div key={a.id} className="stack" style={{ gap: 6 }}>
            {head}
            <details className="panel more" style={{ padding: 12, opacity: a.archived ? 0.6 : 1 }} onToggle={(e) => opened(a, (e.currentTarget as HTMLDetailsElement).open)}>
              <summary>
                {a.title}{a.archived ? " (archived)" : ""} {read.has(a.id) ? <Check className="icon s" aria-label="Read" /> : <span className="chip warm">New</span>}
              </summary>
              <div className="md" style={{ marginTop: 8 }}><Markdown text={a.body} /></div>
              {admin && (
                <div className="row" style={{ marginTop: 8, gap: 6 }}>
                  <button type="button" className="btn quiet sm" onClick={() => setEdit(a)}><Pencil className="icon s" aria-hidden />Edit</button>
                  <span className="note">Version {a.version} · shows on {a.screens.length ? a.screens.join(", ") : "no screen"}</span>
                </div>
              )}
            </details>
          </div>
        );
      })}
      {admin && readers && (
        <section className="panel">
          <header><h3>Who has read</h3></header>
          <div className="body">
            <table className="table">
              <thead><tr><th>Person</th><th>Guide</th><th className="num">Read</th></tr></thead>
              <tbody>{readers.map((r) => <tr key={r.user_id}><td>{r.name}</td><td>{r.role}</td><td className="num">{r.read} of {r.total}</td></tr>)}</tbody>
            </table>
          </div>
        </section>
      )}
      {edit && <Editor a={edit === "new" ? null : edit} onClose={() => setEdit(null)} />}
    </div>
  );
}

function Editor({ a, onClose }: { a: Article | null; onClose: () => void }) {
  const router = useRouter();
  const [role, setRole] = useState<Article["role"]>(a?.role ?? "sales");
  const [section, setSection] = useState(a?.section ?? "");
  const [title, setTitle] = useState(a?.title ?? "");
  const [body, setBody] = useState(a?.body ?? "");
  const [screens, setScreens] = useState((a?.screens ?? []).join(", "));
  const [preview, setPreview] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, start] = useTransition();

  function save(archived?: boolean) {
    setError(null);
    start(async () => {
      const r = await guideSave({ id: a?.id, role: a ? undefined : role, section, title, body, archived,
        screens: screens.split(",").map((s) => s.trim()).filter(Boolean) });
      if (!r.ok) return setError(r.error);
      toast.success(archived ? "Article archived." : archived === false ? "Article restored." : "Article saved. Everyone sees it as new.");
      onClose();
      router.refresh();
    });
  }

  return (
    <Sheet title={a ? "Edit article" : "New article"} onClose={onClose}>
      {!a && (
        <label className="field"><span>Guide</span>
          <select className="input" value={role} onChange={(e) => setRole(e.target.value as Article["role"])}>
            {Object.entries(GUIDE_LABEL).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
          </select>
        </label>
      )}
      <label className="field"><span>Section</span><input className="input" value={section} onChange={(e) => setSection(e.target.value)} maxLength={60} placeholder="For example: Working a lead" /></label>
      <label className="field"><span>Title</span><input className="input" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={120} /></label>
      <div className="row between"><span className="small muted">Blank line: new paragraph · "- " starts a bullet · **bold**</span>
        <button type="button" className="btn quiet sm" onClick={() => setPreview((p) => !p)}>{preview ? "Edit" : "Preview"}</button></div>
      {preview ? <div className="panel md" style={{ padding: 12 }}><Markdown text={body} /></div>
        : <textarea className="input" rows={12} value={body} onChange={(e) => setBody(e.target.value)} maxLength={20000} aria-label="Text" />}
      <label className="field"><span>Show the &ldquo;?&rdquo; on these screens</span>
        <input className="input" value={screens} onChange={(e) => setScreens(e.target.value)} placeholder="/s/followups, /s/leads/*" /></label>
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={() => save()} disabled={busy || !title.trim() || !body.trim()}>{busy ? "Saving…" : "Save"}</button>
      {a && <button type="button" className="btn quiet block" onClick={() => save(!a.archived)} disabled={busy}>{a.archived ? "Restore article" : "Archive article"}</button>}
    </Sheet>
  );
}
