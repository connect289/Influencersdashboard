"use client";
import { useState } from "react";
import { FileCheck2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime } from "@/lib/format";
import { clearPartnerAgreement, confirmPartnerAgreement } from "./agreement-actions";

/** Go-live checklist item 1: the signed agreement and data-processing terms, confirmed by the Admin with a reference. */
export function AgreementCard({ partnerId, confirmedAt, confirmedBy, note }: { partnerId: number; confirmedAt: string | null; confirmedBy: string | null; note: string | null }) {
  const [dialog, setDialog] = useState<"confirm" | "clear" | null>(null);
  return (
    <Card id="agreement">
      <CardHeader title="Agreement and data-processing terms"
        description="Keep the signed documents in your document store; record here where they are. A partner cannot go live without this." />
      <div className="flex flex-wrap items-center gap-3 px-5 pb-5">
        {confirmedAt ? (
          <>
            <FileCheck2 className="size-4 text-success" aria-hidden />
            <div className="min-w-0 flex-1 text-[13px]">
              <p className="text-fg">Confirmed {formatDateTime(confirmedAt)}{confirmedBy ? ` by ${confirmedBy}` : ""}</p>
              {note && <p className="truncate text-muted" title={note}>{note}</p>}
            </div>
            <Button size="sm" variant="secondary" onClick={() => setDialog("clear")}>Clear</Button>
          </>
        ) : (
          <>
            <p className="min-w-0 flex-1 text-[13px] text-muted">Not confirmed yet.</p>
            <Button size="sm" onClick={() => setDialog("confirm")}><FileCheck2 className="size-3.5" /> Confirm agreement</Button>
          </>
        )}
      </div>
      <ConfirmDialog open={dialog === "confirm"} onClose={() => setDialog(null)} title="Confirm the signed agreement" confirmLabel="Confirm"
        reason={{ label: "Where is it?", placeholder: "e.g. Drive › Partners › Acme › MSA 2026-10-01 + DPA" }}
        onConfirm={async (note) => { const err = await confirmPartnerAgreement(partnerId, note); if (!err) toast.success("Agreement confirmed"); return err; }}>
        <p className="text-[13px] text-muted">Confirm only once the agreement and the data-processing terms are signed by both sides.</p>
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "clear"} onClose={() => setDialog(null)} title="Clear the agreement confirmation" confirmLabel="Clear" tone="danger"
        reason={{ label: "Reason", placeholder: "e.g. agreement expired" }}
        onConfirm={async (reason) => { const err = await clearPartnerAgreement(partnerId, reason); if (!err) toast.success("Cleared; the partner's live switch is off"); return err; }}>
        <p className="text-[13px] text-muted">The partner's live switch turns off and it receives no new leads until the agreement is confirmed again.</p>
      </ConfirmDialog>
    </Card>
  );
}
