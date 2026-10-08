"use client";
import { useState } from "react";
import { Power, PowerOff } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { setCapiLive } from "./actions";

const NAME = { meta: "Meta", google: "Google" } as const;

/** The 'capi_meta' / 'capi_google' live switch. While off, due events wait as held. */
export function CapiSwitch({ platform, live, blockers }: { platform: "meta" | "google"; live: boolean; blockers: string[] }) {
  const [open, setOpen] = useState(false);
  const name = NAME[platform];
  return (
    <>
      {live
        ? <Button variant="danger" size="sm" onClick={() => setOpen(true)}><PowerOff className="size-3.5" /> Turn off</Button>
        : <Button size="sm" onClick={() => setOpen(true)} disabled={blockers.length > 0} title={blockers[0]}><Power className="size-3.5" /> Turn on</Button>}
      <ConfirmDialog
        open={open}
        onClose={() => setOpen(false)}
        title={live ? `Stop sending conversions to ${name}?` : `Start sending conversions to ${name}?`}
        tone={live ? "danger" : "primary"}
        confirmLabel={live ? "Turn off" : "Turn on"}
        reason={{ label: "Reason for the audit log", placeholder: live ? "e.g. checking the event map" : "e.g. test events verified in Events Manager" }}
        onConfirm={async (reason) => {
          const err = await setCapiLive(platform, !live, reason);
          if (err) return err;
          toast.success(live ? `${name} conversions are off` : `${name} conversions are on`);
        }}
      >
        {live ? (
          <p>New events wait as held. They go out if you turn this back on while they are still recent enough for {name}.</p>
        ) : (
          <div className="space-y-2">
            <p>Every minute, the CRM sends {name} the milestones of leads that came from its ads: hashed email and phone only, never raw contact details.
              Only students with the consent the settings ask for are included. Test leads are never sent.</p>
            <p>Events held while the switch was off go now, if they are still inside {name}&apos;s window ({platform === "meta" ? "7" : "90"} days).</p>
          </div>
        )}
      </ConfirmDialog>
    </>
  );
}
