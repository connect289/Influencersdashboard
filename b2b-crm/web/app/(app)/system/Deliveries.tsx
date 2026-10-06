"use client";
import { useState } from "react";
import Link from "next/link";
import { RotateCcw } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import { DELIVERY_LABEL, DELIVERY_TONE, type DeliveryRow } from "@/lib/integrations";
import { retryDelivery } from "./actions";

/** The latest 100 webhook deliveries. One that gave up (8 attempts over about 11 hours) can be sent again. */
export function Deliveries({ rows }: { rows: DeliveryRow[] }) {
  const [open, setOpen] = useState<DeliveryRow | null>(null);
  return (
    <>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[820px] text-left text-[12.5px]">
          <thead className="text-[11px] uppercase tracking-wider text-subtle">
            <tr className="border-b border-border">
              <th scope="col" className="px-5 py-2 font-medium">When</th>
              <th scope="col" className="px-3 py-2 font-medium">Event</th>
              <th scope="col" className="px-3 py-2 font-medium">Lead</th>
              <th scope="col" className="px-3 py-2 font-medium">Endpoint</th>
              <th scope="col" className="px-3 py-2 font-medium">Status</th>
              <th scope="col" className="px-5 py-2"><span className="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {rows.map((r) => (
              <tr key={r.id}>
                <td className="whitespace-nowrap px-5 py-2 text-muted" title={formatDateTime(r.created_at)}>{relativeTime(r.created_at)}</td>
                <td className="px-3 py-2 font-mono text-[12px] text-fg">{r.event_type}</td>
                <td className="px-3 py-2">{r.lead_id ? <Link href={`/leads?lead=${r.lead_id}`} className="text-fg hover:underline">#{r.lead_id}</Link> : <span className="text-subtle">—</span>}</td>
                <td className="px-3 py-2 text-muted">{r.endpoint ?? `#${r.endpoint_id}`}</td>
                <td className="px-3 py-2">
                  <span className="flex flex-wrap items-center gap-1.5">
                    <Badge tone={DELIVERY_TONE[r.status]}>{DELIVERY_LABEL[r.status]}</Badge>
                    {r.attempts > 1 && <span className="text-subtle">{r.attempts} attempts</span>}
                    {r.response_status && <span className="font-mono text-subtle">HTTP {r.response_status}</span>}
                    {r.status === "failed" && r.next_attempt_at && <span className="text-subtle">next {formatDateTime(r.next_attempt_at)}</span>}
                    {r.last_error && r.status !== "delivered" && <span className="max-w-[260px] truncate text-subtle" title={r.last_error}>{r.last_error}</span>}
                  </span>
                </td>
                <td className="px-5 py-2 text-right">
                  {(r.status === "dead" || r.status === "failed") && (
                    <Button size="sm" variant="ghost" onClick={() => setOpen(r)}><RotateCcw className="size-3.5" /> Send now</Button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ConfirmDialog
        open={open !== null}
        onClose={() => setOpen(null)}
        title="Send this delivery again?"
        confirmLabel="Send now"
        onConfirm={async () => {
          if (!open) return;
          const err = await retryDelivery(open.id);
          if (err) return err;
          toast.success("Queued; it goes out within 15 seconds");
        }}
      >
        {open && <p>The same <span className="font-mono">{open.event_type}</span> envelope, with the same Idempotency-Key, so a receiver that already processed it ignores the repeat. Its attempt count starts again.</p>}
      </ConfirmDialog>
    </>
  );
}
