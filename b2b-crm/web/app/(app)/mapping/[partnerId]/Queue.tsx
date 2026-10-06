"use client";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Inbox } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import { QUEUE_KIND_LABEL, type QueueItem, type Studio } from "@/lib/mapping";
import { resolveQueue } from "./actions";

const TAB_FOR: Record<QueueItem["kind"], string> = { stage: "stages", field: "fields", value: "values", activity: "activities", drift: "schema" };

/** Everything a partner sent that the active version could not map, with how often and for how many leads. */
export function QueuePanel({ studio }: { studio: Studio }) {
  const router = useRouter();
  const [ignore, setIgnore] = useState<QueueItem | null>(null);
  const reopen = async (q: QueueItem) => {
    const r = await resolveQueue(studio.partner.id, q.id, "open", "");
    if (!r.ok) toast.error(r.error); else { toast.success("Reopened"); router.refresh(); }
  };
  if (studio.queue.length === 0) return <EmptyState icon={Inbox} title="Nothing unmapped">When a partner sends a stage, field, value or activity the mapping does not know, it lands here; the event waits and is re-applied once you map it.</EmptyState>;
  return (
    <>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[820px] text-left text-[12.5px]">
          <thead className="text-[11px] uppercase tracking-wider text-subtle">
            <tr className="border-b border-border">
              <th scope="col" className="px-5 py-2 font-medium">Item</th>
              <th scope="col" className="px-3 py-2 font-medium">Seen</th>
              <th scope="col" className="px-3 py-2 font-medium">Leads</th>
              <th scope="col" className="px-3 py-2 font-medium">Last seen</th>
              <th scope="col" className="px-3 py-2 font-medium">Status</th>
              <th scope="col" className="px-5 py-2"><span className="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {studio.queue.map((q) => (
              <tr key={q.id} className={q.status === "open" ? "" : "opacity-70"}>
                <td className="px-5 py-2"><Badge className="mr-2">{QUEUE_KIND_LABEL[q.kind]}</Badge><span className="text-fg">{q.item}</span>
                  {q.kind === "drift" && q.sample?.required === true && <Badge tone="danger" className="ml-2">required field</Badge>}</td>
                <td className="tabular px-3 py-2 text-muted">{q.seen_count}</td>
                <td className="px-3 py-2 text-muted">
                  {q.leads > 0 ? <>{q.lead_sample.map((id, i) => <span key={id}>{i > 0 && ", "}<Link href={`/leads?lead=${id}`} className="hover:underline">#{id}</Link></span>)}{q.leads > q.lead_sample.length && ` +${q.leads - q.lead_sample.length}`}</> : "—"}
                </td>
                <td className="whitespace-nowrap px-3 py-2 text-muted" title={formatDateTime(q.last_seen)}>{relativeTime(q.last_seen)}</td>
                <td className="px-3 py-2">
                  <Badge tone={q.status === "open" ? "warning" : q.status === "mapped" ? "success" : "neutral"}>{q.status}</Badge>
                  {q.resolution && <span className="ml-1.5 text-subtle">{q.resolution}</span>}
                </td>
                <td className="whitespace-nowrap px-5 py-2 text-right">
                  {q.status === "open" && <>
                    <Link href={`?tab=${TAB_FOR[q.kind]}`} className="mr-1 text-[12.5px] text-info hover:underline">{q.kind === "drift" ? "See schema" : "Map"}</Link>
                    <Button size="sm" variant="ghost" onClick={() => setIgnore(q)}>{q.kind === "field" ? "Keep as custom" : "Dismiss"}</Button>
                  </>}
                  {q.status === "ignored" && <Button size="sm" variant="ghost" onClick={() => reopen(q)}>Reopen</Button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ConfirmDialog
        open={ignore !== null}
        onClose={() => setIgnore(null)}
        title={ignore?.kind === "field" ? "Keep this field as a custom field?" : "Dismiss this item?"}
        confirmLabel={ignore?.kind === "field" ? "Keep as custom" : "Dismiss"}
        reason={{ label: "Why", placeholder: ignore?.kind === "field" ? "e.g. partner's internal score" : "e.g. one-off test value" }}
        onConfirm={async (note) => {
          if (!ignore) return;
          const r = await resolveQueue(studio.partner.id, ignore.id, "ignored", note);
          if (!r.ok) return r.error;
          toast.success("Updated");
          router.refresh();
        }}
      >
        {ignore?.kind === "stage" || ignore?.kind === "activity"
          ? "Held events with it stay held. To let them through, map it or add an “ignore” rule for it in a new version."
          : "Its values stay stored on each lead's allocation. If it appears again, its count still grows here."}
      </ConfirmDialog>
    </>
  );
}
