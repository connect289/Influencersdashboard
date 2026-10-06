"use client";
import { toast } from "sonner";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { passToCrm } from "../routing/actions";

/** Pass not-passed (junk / mismatch) leads to a CRM through the normal rules: one from the drawer, or a group from the list. */
export function PassToCrmDialog({ ids, open, onClose, onDone }: { ids: number[]; open: boolean; onClose: () => void; onDone: (passed: number[]) => void }) {
  return (
    <ConfirmDialog
      open={open}
      onClose={onClose}
      title={ids.length === 1 ? "Pass this lead to a CRM?" : `Pass ${ids.length} leads to a CRM?`}
      confirmLabel="Pass to CRM"
      reason={{ label: "Reason for the audit log", placeholder: "e.g. Eduwit now offers this programme" }}
      onConfirm={async (reason) => {
        const r = await passToCrm(ids, reason);
        if (!r.ok) return r.error;
        if (r.failed) toast.warning(`${r.passed} passed, ${r.failed} could not be passed (already passed or routed).`);
        else toast.success(r.passed === 1 ? "Passed to a CRM" : `${r.passed} leads passed`);
        onDone(ids);
      }}
    >
      The leads go through the normal rules: a partner if qualified, otherwise B2C sales or nurture. While Witty still classifies a lead
      junk or mismatch it counts as not qualified, so it goes to B2C nurture. Each one is logged with your reason.
    </ConfirmDialog>
  );
}
