"use client";
import { toast } from "sonner";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { passToCrm } from "../routing/actions";

/** Pass not-passed (junk / mismatch / spam) leads to a CRM: one from the drawer, or a group from the list. The lead is then
 *  judged on its details (b2b.pass_to_crm sets the override) and goes through the normal rules, so it can reach partners. */
export function PassToCrmDialog({ ids, open, onClose, onDone }: { ids: number[]; open: boolean; onClose: () => void; onDone: (passed: number[]) => void }) {
  const one = ids.length === 1;
  return (
    <ConfirmDialog
      open={open}
      onClose={onClose}
      title={one ? "Pass this lead to a CRM?" : `Pass ${ids.length} leads to a CRM?`}
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
      {one ? "The lead" : "Each lead"} is judged on its details, not on the junk or mismatch label, and goes through the normal routing rules: it can
      reach partners when it is qualified and the student has consented to sharing; otherwise it goes to B2C sales or nurture. Partner-barred
      leads stay with B2C. Each one is logged with your reason.
    </ConfirmDialog>
  );
}
