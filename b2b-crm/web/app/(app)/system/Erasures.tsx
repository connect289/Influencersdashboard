"use client";
import { useState } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import type { ErasureRow } from "@/lib/integrations";
import { closeErasure } from "./actions";

/** Erasure requests the B2C CRM passed on. The Admin carries out the erasure, then closes the request with a note. */
export function Erasures({ rows }: { rows: ErasureRow[] }) {
  const [open, setOpen] = useState<{ r: ErasureRow; status: "done" | "rejected" } | null>(null);
  return (
    <>
      <ul className="divide-y divide-border">
        {rows.map((r) => (
          <li key={r.id} className="flex flex-wrap items-center gap-x-3 gap-y-2 px-5 py-3 text-[13px]">
            <div className="min-w-0 flex-1">
              <p className="font-medium text-fg"><Link href={`/leads?lead=${r.lead_id}`} className="hover:underline">{r.name || `Lead #${r.lead_id}`}</Link></p>
              <p className="text-[12px] text-muted">
                Asked through the B2C CRM <span title={formatDateTime(r.requested_at)}>{relativeTime(r.requested_at)}</span>{r.note && <> · “{r.note}”</>}
              </p>
            </div>
            <Button size="sm" variant="secondary" onClick={() => setOpen({ r, status: "done" })}>Erase and close</Button>
            <Button size="sm" variant="ghost" onClick={() => setOpen({ r, status: "rejected" })}>Reject</Button>
          </li>
        ))}
      </ul>
      <ConfirmDialog
        open={open !== null}
        onClose={() => setOpen(null)}
        title={open?.status === "done" ? "Erase this student's data and close the request?" : "Reject this request?"}
        tone={open?.status === "done" ? "primary" : "danger"}
        confirmLabel={open?.status === "done" ? "Erase and close" : "Reject"}
        reason={{ label: "Note for the audit log", placeholder: open?.status === "done" ? "e.g. request verified on the phone" : "e.g. legal hold: enrolment in progress" }}
        onConfirm={async (note) => {
          if (!open) return;
          const err = await closeErasure(open.r.id, open.status, note);
          if (err) return err;
          toast.success("Request closed");
        }}
      >
        {open?.status === "done"
          ? "The student's personal data is removed from this CRM now (name, numbers, email, notes, contacts, message and delivery copies); statistics stay without identity. Then remove it from Witty's chat history and at every partner that received the lead: the runbook lists the steps and an alert names each partner."
          : "The B2C CRM is not told automatically; let the student know why."}
      </ConfirmDialog>
    </>
  );
}
