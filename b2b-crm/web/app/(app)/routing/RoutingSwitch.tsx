"use client";
import { useState } from "react";
import { Power, PowerOff } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { setRoutingLive } from "./actions";

/** The 'routing' live switch: automatic routing of ready leads every minute. */
export function RoutingSwitch({ live, livePartners, consentRequired }: { live: boolean; livePartners: number; consentRequired: boolean }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      {live
        ? <Button variant="danger" size="sm" onClick={() => setOpen(true)}><PowerOff className="size-3.5" /> Turn off automatic routing</Button>
        : <Button size="sm" onClick={() => setOpen(true)}><Power className="size-3.5" /> Turn on automatic routing</Button>}
      <ConfirmDialog
        open={open}
        onClose={() => setOpen(false)}
        title={live ? "Turn off automatic routing?" : "Turn on automatic routing?"}
        tone={live ? "danger" : "primary"}
        confirmLabel={live ? "Turn off" : "Turn on"}
        reason={{ label: "Reason for the audit log", placeholder: live ? "e.g. partner outage" : "e.g. first partner live" }}
        onConfirm={async (reason) => {
          const err = await setRoutingLive(!live, reason);
          if (err) return err;
          toast.success(live ? "Automatic routing is off" : "Automatic routing is on");
        }}
      >
        {live ? (
          <p>Ready leads stop routing. Leads already routed are not affected. You can still route single leads by hand.</p>
        ) : (
          <div className="space-y-2">
            <p>Every minute, leads at their decision point (not test leads) are decided: junk and programme mismatch are not passed; paid-campaign
              leads go to B2C sales; unqualified leads to B2C nurture; qualified leads to a live partner, or to B2C sales with a reason.</p>
            {livePartners === 0 && <p className="font-medium text-warning">No partner is live yet, so every qualified lead will go to B2C sales.</p>}
            {consentRequired && <p className="font-medium text-warning">Witty does not ask for partner-sharing consent yet, so qualified leads without it go to B2C sales (reason: no consent).</p>}
            <p>Once routed, Witty stops chatting with the lead, B2C nurture leads included, until Witty&apos;s side is changed (Addendum 1 §4b).</p>
          </div>
        )}
      </ConfirmDialog>
    </>
  );
}
