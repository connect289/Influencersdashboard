"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Download, Printer, Send, ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { toCsv } from "@/lib/intake";
import { formatInr, type InvoiceDetail, type InvoiceStatus } from "@/lib/money";
import { download } from "../../../intake/ui";
import { approveInvoice, cancelInvoice, markInvoiceSent } from "../../actions";

export function InvoiceActions({ id, status, number, blocked, total, lines }: {
  id: number; status: InvoiceStatus; number: string | null; blocked: boolean; total: number; lines: InvoiceDetail["lines"];
}) {
  const router = useRouter();
  const [dialog, setDialog] = useState<"approve" | "sent" | "cancel" | null>(null);
  const close = () => setDialog(null);
  return (
    <div className="flex flex-wrap gap-2">
      <Button size="sm" variant="secondary" onClick={() => window.print()}><Printer className="size-3.5" /> Print or save PDF</Button>
      <Button size="sm" variant="secondary" onClick={() => download(`${(number ?? `draft-${id}`).replace(/\//g, "-")}-lines.csv`,
        toCsv(lines.map((l) => ({ reference: l.reference, description: l.description, taxable: l.taxable_inr, gst: l.gst_inr, total: l.total_inr })), ["reference", "description", "taxable", "gst", "total"]))}>
        <Download className="size-3.5" /> Lines CSV</Button>
      {status === "draft" && <Button size="sm" onClick={() => setDialog("approve")} disabled={blocked || total <= 0}><ShieldCheck className="size-3.5" /> Approve</Button>}
      {status === "approved" && <Button size="sm" onClick={() => setDialog("sent")}><Send className="size-3.5" /> Mark as sent</Button>}
      {["draft", "approved", "sent"].includes(status) && <Button size="sm" variant="ghost" onClick={() => setDialog("cancel")}>Cancel invoice</Button>}

      <ConfirmDialog open={dialog === "approve"} onClose={close} title="Approve and number this invoice?" confirmLabel="Approve"
        onConfirm={async () => { const r = await approveInvoice(id); if (!r.ok) return r.error; toast.success(`Approved as ${r.data.number}`); router.refresh(); }}>
        <p className="text-[13px] text-muted">It gets the next number in the financial year and today&apos;s date, and the parties&apos; details are frozen on it. Total {formatInr(total, true)}.
          The CRM does not email it: print or save it as PDF and send it, then mark it as sent.</p>
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "sent"} onClose={close} title="Mark as sent to the partner?" confirmLabel="Mark as sent"
        onConfirm={async () => { const r = await markInvoiceSent(id); if (!r.ok) return r.error; toast.success("Marked as sent"); router.refresh(); }}>
        <p className="text-[13px] text-muted">Overdue reminders start from the due date.</p>
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "cancel"} onClose={close} title="Cancel this invoice?" confirmLabel="Cancel invoice" tone="danger"
        reason={{ label: "Why", placeholder: "e.g. wrong partner GSTIN" }}
        onConfirm={async (reason) => { const r = await cancelInvoice(id, reason); if (!r.ok) return r.error; toast.success("Invoice cancelled"); router.refresh(); }}>
        <p className="text-[13px] text-muted">Its lines go back to the next draft. {number ? `The number ${number} stays used (shown as cancelled); issue a credit note in your accounts if it was already sent.` : ""}</p>
      </ConfirmDialog>
    </div>
  );
}
