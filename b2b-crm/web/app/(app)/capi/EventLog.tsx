"use client";
import { useState } from "react";
import Link from "next/link";
import { Send } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { formatDateTime, relativeTime } from "@/lib/format";
import { EVENT_STATUS, MATCH_KEY_LABEL, STAGE_LABEL, formatInr, type CapiEvent } from "@/lib/capi";
import { retryCapiEvent } from "./actions";

/** The latest conversion events, newest first, with Retry for failed, rejected and held ones. */
export function EventLog({ rows }: { rows: CapiEvent[] }) {
  const [busy, setBusy] = useState<number | null>(null);
  if (rows.length === 0) {
    return <EmptyState icon={Send} title="No events yet">Events appear once leads that came from Meta or Google ads reach a milestone. Test leads show up as dry runs.</EmptyState>;
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[820px] text-left text-[12.5px]">
        <thead className="text-[11px] uppercase tracking-wider text-subtle">
          <tr className="border-b border-border">
            <th scope="col" className="px-5 py-2 font-medium">When</th>
            <th scope="col" className="px-3 py-2 font-medium">Lead</th>
            <th scope="col" className="px-3 py-2 font-medium">Event</th>
            <th scope="col" className="px-3 py-2 text-right font-medium">Value</th>
            <th scope="col" className="px-3 py-2 font-medium">Matched by</th>
            <th scope="col" className="px-3 py-2 font-medium">Status</th>
            <th scope="col" className="px-5 py-2"><span className="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {rows.map((e) => {
            const st = EVENT_STATUS[e.status] ?? { label: e.status, tone: "neutral" as const, hint: "" };
            const note = e.error ?? e.reason;
            return (
              <tr key={e.id} className="align-top">
                <td className="whitespace-nowrap px-5 py-2 text-muted" title={`Happened ${formatDateTime(e.occurred_at)}`}>{relativeTime(e.occurred_at)}</td>
                <td className="px-3 py-2"><Link href={`/leads?lead=${e.lead_id}`} className="text-fg hover:underline">{e.name ?? `#${e.lead_id}`}</Link></td>
                <td className="px-3 py-2">
                  <span className="font-medium text-fg">{e.platform === "meta" ? "Meta" : "Google"}</span> · {e.platform === "meta" ? e.event_name : STAGE_LABEL[e.stage]?.label ?? e.stage}
                  <span className="block font-mono text-[11px] text-subtle">{e.event_id}</span>
                </td>
                <td className="tabular px-3 py-2 text-right">{formatInr(e.value_inr)}</td>
                <td className="px-3 py-2 text-muted">{e.match_keys.map((k) => MATCH_KEY_LABEL[k] ?? k).join(", ") || "—"}</td>
                <td className="max-w-64 px-3 py-2">
                  <Badge tone={st.tone}>{st.label}</Badge>
                  {e.attempts > 1 && <span className="ml-1.5 text-[11.5px] text-subtle">{e.attempts} tries</span>}
                  {note && <span className={`block truncate text-[11.5px] ${e.error ? "text-danger" : "text-subtle"}`} title={note}>{note}</span>}
                </td>
                <td className="px-5 py-2 text-right">
                  {["failed", "dead", "rejected", "held"].includes(e.status) && !e.is_test && (
                    <Button size="sm" variant="secondary" disabled={busy === e.id}
                      onClick={async () => { setBusy(e.id); const err = await retryCapiEvent(e.id); setBusy(null); if (err) toast.error(err); else toast.success("Queued again"); }}>Retry</Button>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
