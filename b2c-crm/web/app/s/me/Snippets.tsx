"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, Share2 } from "lucide-react";
import { toast } from "sonner";
import { Sheet } from "@/components/ui/Sheet";
import { snippetDelete, snippetSave, type Snippet } from "../snippet-actions";

/** Saved WhatsApp snippets (spec B8.5): your own, and the ones colleagues share. Used from the free-text composer. */
export function Snippets({ snippets }: { snippets: Snippet[] }) {
  const router = useRouter();
  const [edit, setEdit] = useState<Partial<Snippet> | null>(null);
  const [busy, start] = useTransition();
  const mine = snippets.filter((s) => s.mine);
  const theirs = snippets.filter((s) => !s.mine);

  function save(form: FormData) {
    start(async () => {
      const r = await snippetSave({ id: edit?.id, title: String(form.get("title") ?? ""), body: String(form.get("body") ?? ""), shared: form.get("shared") === "on" });
      if (!r.ok) return void toast.error(r.error);
      toast.success(r.notice ?? "Saved.");
      setEdit(null);
      router.refresh();
    });
  }
  function remove(id: number) {
    start(async () => {
      const r = await snippetDelete(id);
      if (!r.ok) return void toast.error(r.error);
      toast.success("Removed.");
      router.refresh();
    });
  }
  return (
    <div className="stack">
      <div className="row between wrap">
        <p className="note grow">Short texts you send often inside the 24-hour window: greetings, fee lines, document lists. Share one and every counsellor can use it; only you can change it.</p>
        <button type="button" className="btn primary sm" onClick={() => setEdit({})}><Plus className="icon s" aria-hidden />New snippet</button>
      </div>
      {mine.length === 0 && theirs.length === 0 && <div className="card empty">No snippets yet. Add the lines you type again and again.</div>}
      {mine.length > 0 && (
        <section className="panel">
          <header><h3>Mine</h3><span className="small muted">{mine.length}</span></header>
          <div className="list">
            {mine.map((s) => (
              <div key={s.id} className="li" style={{ gridTemplateColumns: "1fr auto" }}>
                <span className="t">{s.title}{s.shared && <span className="chip line" style={{ marginLeft: 6 }}><Share2 className="icon s" aria-hidden />Shared</span>}</span>
                <span className="row" style={{ gap: 4 }}>
                  <button type="button" className="btn quiet sm" onClick={() => setEdit(s)}>Edit</button>
                  <button type="button" className="btn quiet sm" disabled={busy} onClick={() => remove(s.id)}>Remove</button>
                </span>
                <span className="s" style={{ gridColumn: "1 / -1", whiteSpace: "pre-wrap" }}>{s.body}</span>
                <span className="s small faint" style={{ gridColumn: "1 / -1" }}>Used {s.uses} {s.uses === 1 ? "time" : "times"}</span>
              </div>
            ))}
          </div>
        </section>
      )}
      {theirs.length > 0 && (
        <section className="panel">
          <header><h3>Shared by colleagues</h3><span className="small muted">{theirs.length}</span></header>
          <div className="list">
            {theirs.map((s) => (
              <div key={s.id} className="li" style={{ gridTemplateColumns: "1fr auto" }}>
                <span className="t">{s.title}</span>
                <span className="small muted">{s.author}</span>
                <span className="s" style={{ gridColumn: "1 / -1", whiteSpace: "pre-wrap" }}>{s.body}</span>
              </div>
            ))}
          </div>
        </section>
      )}
      {edit && (
        <Sheet title={edit.id ? "Edit snippet" : "New snippet"} onClose={() => setEdit(null)}>
          <form className="body stack" action={save}>
            <label className="field"><span>Name</span><input className="input" name="title" defaultValue={edit.title ?? ""} required maxLength={60} placeholder="e.g. Fee and EMI line" /></label>
            <label className="field"><span>Text</span><textarea className="input" name="body" defaultValue={edit.body ?? ""} required maxLength={1000} rows={5} placeholder="Hi {{first_name}}, here are the EMI options for {{programme}} …" /></label>
            <p className="small muted">{"{{first_name}}"}, {"{{programme}}"} and {"{{counsellor_first_name}}"} are filled in when you insert it.</p>
            <label className="checkbox"><input type="checkbox" name="shared" defaultChecked={!!edit.shared} /> Share with every counsellor</label>
            <div className="row" style={{ justifyContent: "flex-end" }}>
              <button type="button" className="btn quiet" onClick={() => setEdit(null)}>Cancel</button>
              <button className="btn primary" type="submit" disabled={busy}>{busy ? "Saving…" : "Save"}</button>
            </div>
          </form>
        </Sheet>
      )}
    </div>
  );
}
