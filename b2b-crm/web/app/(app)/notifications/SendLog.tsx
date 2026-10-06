"use client";
import { useState } from "react";
import Link from "next/link";
import { RotateCcw } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import { CHANNEL_LABEL, STATUS_LABEL, STATUS_TONE, type LogRow } from "@/lib/notifications";
import { retryNotification } from "./actions";

/** The latest 100 messages; recipients are masked by the database. Failed or cancelled ones can be sent again once. */
export function SendLog({ rows }: { rows: LogRow[] }) {
  const [open, setOpen] = useState<LogRow | null>(null);
  return (
    <>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[820px] text-left text-[12.5px]">
          <thead className="text-[11px] uppercase tracking-wider text-subtle">
            <tr className="border-b border-border">
              <th scope="col" className="px-5 py-2 font-medium">When</th>
              <th scope="col" className="px-3 py-2 font-medium">Student</th>
              <th scope="col" className="px-3 py-2 font-medium">Partner</th>
              <th scope="col" className="px-3 py-2 font-medium">Channel</th>
              <th scope="col" className="px-3 py-2 font-medium">To</th>
              <th scope="col" className="px-3 py-2 font-medium">Status</th>
              <th scope="col" className="px-5 py-2"><span className="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {rows.map((r) => {
              const at = r.sent_at ?? (r.status === "scheduled" ? r.scheduled_for : null) ?? r.created_at;
              return (
                <tr key={r.id}>
                  <td className="whitespace-nowrap px-5 py-2 text-muted" title={formatDateTime(at)}>
                    {r.status === "scheduled" && r.scheduled_for && Date.parse(r.scheduled_for) > Date.now() ? `due ${formatDateTime(r.scheduled_for)}` : relativeTime(at)}
                  </td>
                  <td className="px-3 py-2"><Link href={`/leads?lead=${r.lead_id}`} className="text-fg hover:underline">{r.lead_name || `Lead #${r.lead_id}`}</Link></td>
                  <td className="px-3 py-2 text-muted">{r.partner_name ?? "—"}</td>
                  <td className="px-3 py-2 text-muted">{CHANNEL_LABEL[r.channel]} · {r.language}</td>
                  <td className="px-3 py-2 font-mono text-[12px] text-muted">{r.recipient || "—"}</td>
                  <td className="px-3 py-2">
                    <span className="flex flex-wrap items-center gap-1.5">
                      <Badge tone={STATUS_TONE[r.status] ?? "neutral"}>{STATUS_LABEL[r.status] ?? r.status}</Badge>
                      {r.error && <span className="max-w-[280px] truncate text-subtle" title={r.error}>{r.error}</span>}
                    </span>
                  </td>
                  <td className="px-5 py-2 text-right">
                    {(r.status === "failed" || r.status === "cancelled") && (
                      <Button size="sm" variant="ghost" onClick={() => setOpen(r)}><RotateCcw className="size-3.5" /> Send again</Button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <ConfirmDialog
        open={open !== null}
        onClose={() => setOpen(null)}
        title="Send this message again?"
        confirmLabel="Send again"
        onConfirm={async () => {
          if (!open) return;
          const err = await retryNotification(open.id);
          if (err) return err;
          toast.success("Queued for the next sending slot");
        }}
      >
        {open && <p>{CHANNEL_LABEL[open.channel]} to {open.lead_name || `lead #${open.lead_id}`}, at the next slot inside quiet hours. It is still skipped if the student has opted out,
          the partner no longer holds the lead or the channel is switched off.</p>}
      </ConfirmDialog>
    </>
  );
}
