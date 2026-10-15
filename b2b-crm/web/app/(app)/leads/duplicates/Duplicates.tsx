"use client";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { GitMerge, UserCheck } from "lucide-react";
import { toast } from "sonner";
import { Badge, Card, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import { formatPhone, humanize } from "@/lib/leads";
import type { DuplicateLead, DuplicatePair } from "@/lib/leads-data";
import { dismissDuplicate, mergeLeads } from "../actions";

function Side({ l, keep, onKeep }: { l: DuplicateLead; keep: boolean; onKeep: () => void }) {
  const blocked = l.destination === "partner" ? "with a partner" : l.has_enrollment ? "has an enrolment" : null;
  return (
    <div className={`min-w-0 flex-1 rounded-lg border p-3 ${keep ? "border-success/40 bg-success-bg/40" : "border-border"}`}>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <Link href={`/leads?lead=${l.id}`} className="block truncate text-[13px] font-medium text-fg hover:underline">{l.name || "Unnamed"} <span className="text-subtle">#{l.id}</span></Link>
          <p className="tabular text-[12.5px] text-muted">{formatPhone(l.phone)}{l.email ? ` · ${l.email}` : ""}</p>
          <p className="text-[12px] text-subtle">{[l.course, l.city, l.source && humanize(l.source)].filter(Boolean).join(" · ")} · <span title={formatDateTime(l.created_at)}>{relativeTime(l.created_at)}</span></p>
        </div>
        <span className="flex flex-col items-end gap-1">
          {l.destination && <Badge tone={l.destination === "partner" ? "brand" : "info"}>{l.destination === "partner" ? `Partner #${l.partner_id}` : "B2C"}</Badge>}
          {l.has_enrollment && <Badge tone="success">Enrolled</Badge>}
        </span>
      </div>
      <button type="button" onClick={onKeep} className={`mt-2 inline-flex items-center gap-1 text-[12px] ${keep ? "text-success" : "text-muted hover:text-fg"}`}>
        <UserCheck className="size-3.5" /> {keep ? "Keep this one" : "Keep this one instead"}{blocked && !keep ? "" : ""}
      </button>
      {blocked && <p className="mt-1 text-[11.5px] text-subtle">{blocked}: it can only be the one kept.</p>}
    </div>
  );
}

export function Duplicates({ pairs }: { pairs: DuplicatePair[] }) {
  const router = useRouter();
  const [keepSide, setKeepSide] = useState<Record<string, "a" | "b">>({});
  const [merging, setMerging] = useState<DuplicatePair | null>(null);
  const [dismissing, setDismissing] = useState<DuplicatePair | null>(null);
  const key = (p: DuplicatePair) => `${p.a.id}-${p.b.id}`;
  const defaultKeep = (p: DuplicatePair): "a" | "b" => (p.b.destination === "partner" || p.b.has_enrollment) && !(p.a.destination === "partner" || p.a.has_enrollment) ? "b" : "a";
  const kept = (p: DuplicatePair) => keepSide[key(p)] ?? defaultKeep(p);
  if (pairs.length === 0) return <Card><EmptyState icon={GitMerge} title="No possible duplicates">Pairs appear here when two live leads share an email, a recorded number or a name and city.</EmptyState></Card>;
  return (
    <>
      <ul className="space-y-3">
        {pairs.map((p) => {
          const k = kept(p);
          return (
            <li key={key(p)}>
              <Card className="p-4">
                <p className="mb-2 text-[12px] font-medium uppercase tracking-wider text-subtle">{p.why}</p>
                <div className="flex flex-col gap-3 md:flex-row">
                  <Side l={p.a} keep={k === "a"} onKeep={() => setKeepSide({ ...keepSide, [key(p)]: "a" })} />
                  <Side l={p.b} keep={k === "b"} onKeep={() => setKeepSide({ ...keepSide, [key(p)]: "b" })} />
                </div>
                <div className="mt-3 flex justify-end gap-2">
                  <Button size="sm" variant="ghost" onClick={() => setDismissing(p)}>Not a duplicate</Button>
                  <Button size="sm" onClick={() => setMerging(p)}><GitMerge className="size-3.5" /> Merge into #{k === "a" ? p.a.id : p.b.id}</Button>
                </div>
              </Card>
            </li>
          );
        })}
      </ul>
      <ConfirmDialog open={merging !== null} onClose={() => setMerging(null)} confirmLabel="Merge" tone="danger"
        title={merging ? `Merge #${kept(merging) === "a" ? merging.b.id : merging.a.id} into #${kept(merging) === "a" ? merging.a.id : merging.b.id}?` : ""}
        reason={{ label: "Reason (kept in the audit log)", placeholder: "e.g. same student, enquired from two numbers" }}
        onConfirm={async (reason) => {
          if (!merging) return;
          const keep = kept(merging) === "a" ? merging.a.id : merging.b.id;
          const merge = kept(merging) === "a" ? merging.b.id : merging.a.id;
          const r = await mergeLeads(keep, merge, reason);
          if (!r.ok) return r.error;
          toast.success(`Merged #${merge} into #${keep}`);
          setMerging(null); router.refresh();
        }}>
        <p className="text-[13px] text-muted">The kept lead gains the other&rsquo;s empty fields, notes, tags and contacts; the other lead is marked merged and leaves the B2C CRM&rsquo;s copy. Its history stays on its own id. This cannot be undone.</p>
      </ConfirmDialog>
      <ConfirmDialog open={dismissing !== null} onClose={() => setDismissing(null)} confirmLabel="Dismiss" title="Not the same student?"
        reason={{ label: "Note (optional)", placeholder: "e.g. father and son" }}
        onConfirm={async (note) => {
          if (!dismissing) return;
          const err = await dismissDuplicate(dismissing.a.id, dismissing.b.id, note);
          if (err) return err;
          toast.success("Dismissed"); setDismissing(null); router.refresh();
        }}>
        <p className="text-[13px] text-muted">The pair is hidden from this list from now on.</p>
      </ConfirmDialog>
    </>
  );
}
