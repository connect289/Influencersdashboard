"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Pin, PinOff, StickyNote, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { EmptyState } from "@/components/ui/Card";
import { formatDateTime, relativeTime } from "@/lib/format";
import type { LeadNote } from "@/lib/leads-data";
import { addNote, removeNote, updateNote } from "./actions";

/** M33b: internal notes on the lead. Never sent anywhere; pinned notes first. */
export function NotesTab({ leadId, notes }: { leadId: number; notes: LeadNote[] }) {
  const router = useRouter();
  const [body, setBody] = useState("");
  const [pinned, setPinned] = useState(false);
  const [pending, start] = useTransition();
  const run = (fn: () => Promise<string | void>, done: string) => start(async () => { const err = await fn(); if (err) toast.error(err); else { toast.success(done); router.refresh(); } });
  return (
    <div>
      <form className="space-y-2 border-b border-border px-5 py-4" onSubmit={(e) => { e.preventDefault(); if (body.trim()) run(async () => { const err = await addNote(leadId, body, pinned); if (!err) { setBody(""); setPinned(false); } return err; }, "Note added"); }}>
        <textarea value={body} onChange={(e) => setBody(e.target.value)} maxLength={4000} rows={3} placeholder="An internal note: what the student said, what to do next, who to ask. Only the team sees it."
          className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-[13px] text-fg placeholder:text-subtle focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30" />
        <div className="flex items-center gap-3">
          <label className="flex items-center gap-1.5 text-[12.5px] text-muted"><input type="checkbox" checked={pinned} onChange={(e) => setPinned(e.target.checked)} className="accent-[var(--primary)]" /> Pin to the top</label>
          <Button type="submit" size="sm" className="ml-auto" disabled={pending || !body.trim()}>Add note</Button>
        </div>
      </form>
      {notes.length === 0 ? <EmptyState icon={StickyNote} title="No notes yet" /> : (
        <ul className="divide-y divide-border">
          {notes.map((n) => (
            <li key={n.id} className="px-5 py-3">
              <div className="flex items-center gap-2 text-[12px] text-subtle">
                {n.pinned && <Pin className="size-3 text-amber" aria-label="Pinned" />}
                <span className="font-medium text-muted">{n.author}</span>
                <span title={formatDateTime(n.created_at)}>{relativeTime(n.created_at)}</span>
                {n.updated_at !== n.created_at && <span>· edited</span>}
                <span className="ml-auto inline-flex gap-1">
                  <button type="button" className="rounded p-1 text-subtle hover:text-fg" title={n.pinned ? "Unpin" : "Pin"} disabled={pending}
                    onClick={() => run(() => updateNote(n.id, { pinned: !n.pinned }), n.pinned ? "Unpinned" : "Pinned")}>{n.pinned ? <PinOff className="size-3.5" /> : <Pin className="size-3.5" />}</button>
                  <button type="button" className="rounded p-1 text-subtle hover:text-danger" title="Remove" disabled={pending}
                    onClick={() => { if (confirm("Remove this note?")) run(() => removeNote(n.id), "Note removed"); }}><Trash2 className="size-3.5" /></button>
                </span>
              </div>
              <p className="mt-1 whitespace-pre-wrap text-[13px] text-fg">{n.body}</p>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
