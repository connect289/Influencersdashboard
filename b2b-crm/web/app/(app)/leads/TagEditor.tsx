"use client";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, X } from "lucide-react";
import { toast } from "sonner";
import type { LeadTag } from "@/lib/leads-data";
import { tagLeads } from "./actions";
import { TagChip } from "./TagChip";

/** M33b: the lead's tags with add (any name; a new name creates the tag) and remove. */
export function TagEditor({ leadId, tags, known }: { leadId: number; tags: LeadTag[]; known: LeadTag[] }) {
  const router = useRouter();
  const [adding, setAdding] = useState(false);
  const [value, setValue] = useState("");
  const [pending, start] = useTransition();
  const apply = (name: string, add: boolean) => start(async () => {
    const r = await tagLeads([leadId], name, add);
    if (!r.ok) { toast.error(r.error); return; }
    setValue(""); setAdding(false); router.refresh();
  });
  return (
    <span className="flex flex-wrap items-center gap-1">
      {tags.map((t) => (
        <TagChip key={t.id} name={t.name} color={t.color}>
          <button type="button" aria-label={`Remove tag ${t.name}`} className="rounded opacity-60 hover:opacity-100" disabled={pending} onClick={() => apply(t.name, false)}><X className="size-3" /></button>
        </TagChip>
      ))}
      {adding ? (
        <form className="inline-flex items-center gap-1" onSubmit={(e) => { e.preventDefault(); if (value.trim()) apply(value.trim(), true); }}>
          <input autoFocus list="known-tags" value={value} onChange={(e) => setValue(e.target.value)} maxLength={40} placeholder="Tag name"
            onKeyDown={(e) => { if (e.key === "Escape") { setAdding(false); setValue(""); } }}
            className="h-6 w-32 rounded-md border border-border bg-surface px-1.5 text-[12px] text-fg focus:border-ring focus:outline-none" />
          <datalist id="known-tags">{known.map((k) => <option key={k.id} value={k.name} />)}</datalist>
          <button type="submit" className="text-[11.5px] text-fg hover:underline" disabled={pending}>Add</button>
        </form>
      ) : (
        <button type="button" onClick={() => setAdding(true)} className="inline-flex h-5 items-center gap-0.5 rounded-md border border-dashed border-border px-1.5 text-[11px] text-subtle hover:border-border-strong hover:text-fg">
          <Plus className="size-3" /> tag
        </button>
      )}
    </span>
  );
}
