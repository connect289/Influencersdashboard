"use client";
import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Check, ImagePlus, Pencil, Plus, Search, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { guideRead, guideSave, type Article, type Reader } from "@/app/guide-actions";
import { Markdown, type MdImage } from "@/lib/markdown";
import { guideImageAdd, guideImageRemove } from "@/app/w/admin-actions";

export type GuideImages = Record<number, (MdImage & { path: string })[]>;

const GUIDE_LABEL: Record<string, string> = { sales: "Sales guide", marketing: "Marketing guide", admin: "Admin guide" };

/** The in-app guide (spec B16): searchable, grouped by section, tracks what the person has read; the Admin edits it. */
export function Guide({ articles, admin, readers, images }: { articles: Article[]; admin?: boolean; readers?: Reader[]; images?: GuideImages }) {
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
              <div className="md" style={{ marginTop: 8 }}><Markdown text={a.body} images={images?.[a.id]} /></div>
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
      {edit && <Editor a={edit === "new" ? null : edit} images={edit === "new" ? [] : images?.[edit.id] ?? []} onClose={() => setEdit(null)} />}
    </div>
  );
}

function Editor({ a, images, onClose }: { a: Article | null; images: (MdImage & { path: string })[]; onClose: () => void }) {
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
      <div className="row between"><span className="small muted">Blank line: new paragraph · &quot;- &quot; starts a bullet · **bold** · ![caption](image:1) shows screenshot 1</span>
        <button type="button" className="btn quiet sm" onClick={() => setPreview((p) => !p)}>{preview ? "Edit" : "Preview"}</button></div>
      {preview ? <div className="panel md" style={{ padding: 12 }}><Markdown text={body} images={images} /></div>
        : <textarea className="input" rows={12} value={body} onChange={(e) => setBody(e.target.value)} maxLength={20000} aria-label="Text" />}
      <label className="field"><span>Show the &ldquo;?&rdquo; on these screens</span>
        <input className="input" value={screens} onChange={(e) => setScreens(e.target.value)} placeholder="/s/followups, /s/leads/*" /></label>
      {a ? <Screenshots article={a.id} images={images} onInsert={(code) => setBody((b) => `${b.trimEnd()}\n\n${code}`)} />
        : <p className="note">Save the article first, then add screenshots.</p>}
      {error && <p className="error" role="alert">{error}</p>}
      <button type="button" className="btn primary block" onClick={() => save()} disabled={busy || !title.trim() || !body.trim()}>{busy ? "Saving…" : "Save"}</button>
      {a && <button type="button" className="btn quiet block" onClick={() => save(!a.archived)} disabled={busy}>{a.archived ? "Restore article" : "Archive article"}</button>}
    </Sheet>
  );
}

/** Screenshots on an article (spec B15): stored privately; the reader sees them through short signed links. */
function Screenshots({ article, images, onInsert }: { article: number; images: (MdImage & { path: string })[]; onInsert: (code: string) => void }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const add = (f: FormData) => start(async () => {
    const r = await guideImageAdd(article, f);
    if (!r.ok) return setError(r.error);
    setError(null);
    toast.success(`Screenshot ${r.data?.length ?? ""} added. Put ![caption](image:${r.data?.length ?? 1}) where it belongs.`);
    router.refresh();
  });
  const remove = (i: number) => start(async () => {
    const r = await guideImageRemove(article, i);
    if (!r.ok) return setError(r.error);
    toast.success(r.notice ?? "Removed.");
    router.refresh();
  });
  return (
    <div className="field"><span>Screenshots ({images.length} of 12)</span>
      <div className="stack" style={{ gap: 6 }}>
        {images.map((im, i) => (
          <div key={im.path} className="row" style={{ gap: 6 }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            {im.url ? <img src={im.url} alt="" width={64} height={40} style={{ objectFit: "cover", borderRadius: 4, border: "1px solid var(--line)" }} /> : <span className="chip line">missing</span>}
            <span className="grow small"><span className="mono">image:{i + 1}</span> · {im.caption}</span>
            <button type="button" className="btn quiet sm" onClick={() => onInsert(`![${im.caption ?? ""}](image:${i + 1})`)}>Insert</button>
            <button type="button" className="btn quiet sm" disabled={busy} onClick={() => remove(i)} aria-label="Remove screenshot"><Trash2 className="icon s" aria-hidden /></button>
          </div>
        ))}
        {images.length < 12 && (
          <form className="row wrap" style={{ gap: 6 }} action={add}>
            <input className="input" type="file" name="file" accept="image/png,image/jpeg,image/webp" required style={{ maxWidth: 240 }} aria-label="Screenshot file" />
            <input className="input grow" name="caption" placeholder="Caption" maxLength={120} aria-label="Caption" />
            <button className="btn ghost sm" type="submit" disabled={busy}><ImagePlus className="icon s" aria-hidden />{busy ? "Uploading…" : "Add"}</button>
          </form>
        )}
        <span className="note">PNG, JPEG or WebP, up to 2 MB. Removing one renumbers those after it.</span>
        {error && <p className="error" role="alert">{error}</p>}
      </div>
    </div>
  );
}
