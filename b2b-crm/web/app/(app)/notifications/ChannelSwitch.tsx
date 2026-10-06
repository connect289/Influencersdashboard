"use client";
import { useState } from "react";
import { Power, PowerOff } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { CHANNEL_LABEL } from "@/lib/notifications";
import { setChannelLive } from "./actions";

/** The 'whatsapp' / 'email' live switch. While off, due messages on that channel are cancelled, never sent late. */
export function ChannelSwitch({ channel, live, blockers }: { channel: "whatsapp" | "email"; live: boolean; blockers: string[] }) {
  const [open, setOpen] = useState(false);
  const name = CHANNEL_LABEL[channel];
  return (
    <>
      {live
        ? <Button variant="danger" size="sm" onClick={() => setOpen(true)}><PowerOff className="size-3.5" /> Turn off</Button>
        : <Button size="sm" onClick={() => setOpen(true)} disabled={blockers.length > 0} title={blockers[0]}><Power className="size-3.5" /> Turn on</Button>}
      <ConfirmDialog
        open={open}
        onClose={() => setOpen(false)}
        title={live ? `Stop ${name} messages to students?` : `Start ${name} messages to students?`}
        tone={live ? "danger" : "primary"}
        confirmLabel={live ? "Turn off" : "Turn on"}
        reason={{ label: "Reason for the audit log", placeholder: live ? "e.g. template paused by Meta" : "e.g. template approved" }}
        onConfirm={async (reason) => {
          const err = await setChannelLive(channel, !live, reason);
          if (err) return err;
          toast.success(live ? `${name} messages are off` : `${name} messages are on`);
        }}
      >
        {live ? (
          <p>Messages waiting for their slot are cancelled rather than sent later. Messages already sent are not affected.</p>
        ) : (
          <div className="space-y-2">
            <p>From now on, each student whose lead a partner accepts gets one {name} message, inside quiet hours, naming the partner and when they will call.
              Test leads, opted-out students and partners with notifications off are never messaged.</p>
            <p>Messages that were due while the switch was off are not sent.</p>
          </div>
        )}
      </ConfirmDialog>
    </>
  );
}
