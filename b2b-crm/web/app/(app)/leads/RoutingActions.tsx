"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Send, UserX, Waypoints } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { markPartnerLost, routeToPartners } from "../routing/actions";
import { PassToCrmDialog } from "./PassToCrm";

/** The drawer's routing actions (Addenda 1 and 2): rescue a not-passed lead, send a B2C lead to partners, record a partner's loss. */
export function RoutingActions({ leadId, notPassed, b2cHeld, consent, openPartnerAllocation }: {
  leadId: number; notPassed: boolean; b2cHeld: boolean; consent: boolean; openPartnerAllocation: { id: number; partner: string | null } | null;
}) {
  const router = useRouter();
  const [dialog, setDialog] = useState<"pass" | "partners" | "lost" | null>(null);
  const close = () => setDialog(null);
  if (!notPassed && !b2cHeld && !openPartnerAllocation) return null;
  return (
    <div className="flex flex-wrap gap-2">
      {notPassed && <Button size="sm" onClick={() => setDialog("pass")}><Send className="size-3.5" /> Pass to CRM</Button>}
      {b2cHeld && (
        <Button size="sm" variant="secondary" onClick={() => setDialog("partners")} disabled={!consent} title={consent ? undefined : "The student has not consented to sharing with partners"}>
          <Waypoints className="size-3.5" /> Send to partners
        </Button>
      )}
      {openPartnerAllocation && (
        <Button size="sm" variant="ghost" onClick={() => setDialog("lost")}><UserX className="size-3.5" /> Partner reported lost</Button>
      )}

      <PassToCrmDialog ids={[leadId]} open={dialog === "pass"} onClose={close} onDone={() => router.refresh()} />
      <ConfirmDialog
        open={dialog === "partners"}
        onClose={close}
        title="Send this lead to partners?"
        confirmLabel="Send to partners"
        reason={{ label: "Reason for the audit log", placeholder: "e.g. student wants a university only partners offer" }}
        onConfirm={async (reason) => {
          const r = await routeToPartners(leadId, reason);
          if (!r.ok) return r.error;
          if (r.decision.destination === "partner") toast.success(`Routed to ${r.decision.partner_name}`);
          else toast.warning("No partner could take it; it went back to B2C sales.");
          router.refresh();
        }}
      >
        The B2C allocation is closed and the lead goes through partner routing. If no partner can take it, it returns to B2C sales with the reason
        &quot;sent to partners by hand, none could take it&quot;.
      </ConfirmDialog>
      <ConfirmDialog
        open={dialog === "lost"}
        onClose={close}
        tone="danger"
        title={`${openPartnerAllocation?.partner ?? "The partner"} marked this lead lost?`}
        confirmLabel="Record and hand to B2C nurture"
        reason={{ label: "What the partner reported", placeholder: "e.g. not interested, joined elsewhere" }}
        onConfirm={async (reason) => {
          const err = await markPartnerLost(openPartnerAllocation!.id, reason);
          if (err) return err;
          toast.success("Handed to B2C nurture");
          router.refresh();
        }}
      >
        The allocation is closed with outcome lost and the lead goes to B2C nurture. B2B sends the student no message. Partner sync will do this
        automatically once it is built.
      </ConfirmDialog>
    </div>
  );
}
