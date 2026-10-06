"use client";
import { useState } from "react";
import { Ban, CirclePause, CirclePlay, Power, PowerOff } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { cn } from "@/components/ui/cn";
import type { PartnerStatus } from "@/lib/partners";
import { setPartnerLive, setPartnerStatus } from "../actions";

type Dialog = "activate" | "pause" | "resume" | "close" | "live_on" | "live_off" | null;

/** Status changes and the live switch. The database enforces the same rules (b2b.partner_set_status / _set_live). */
export function PartnerControls({ id, title, status, live, missing }: { id: number; title: string; status: PartnerStatus; live: boolean; missing: number }) {
  const [dialog, setDialog] = useState<Dialog>(null);
  const close = () => setDialog(null);
  const status_ = (next: PartnerStatus, done: string) => async (reason: string) => {
    const err = await setPartnerStatus(id, next, reason);
    if (err) return err;
    toast.success(done);
  };
  const live_ = (on: boolean) => async (reason: string) => {
    const err = await setPartnerLive(id, on, reason);
    if (err) return err;
    toast.success(on ? `${title} is live` : `${title} is switched off`);
  };
  const canGoLive = status === "active" && missing === 0;

  if (status === "closed") return null;

  return (
    <div className="flex flex-wrap items-center gap-2">
      {status === "onboarding" && <Button variant="secondary" size="sm" onClick={() => setDialog("activate")}><CirclePlay className="size-3.5" /> Mark active</Button>}
      {status === "active" && <Button variant="secondary" size="sm" onClick={() => setDialog("pause")}><CirclePause className="size-3.5" /> Pause</Button>}
      {status === "paused" && <Button variant="secondary" size="sm" onClick={() => setDialog("resume")}><CirclePlay className="size-3.5" /> Resume</Button>}
      <Button variant="ghost" size="sm" className="hover:text-danger" onClick={() => setDialog("close")}><Ban className="size-3.5" /> Close</Button>

      {live ? (
        <Button size="sm" variant="danger" onClick={() => setDialog("live_off")}><PowerOff className="size-3.5" /> Switch off</Button>
      ) : (
        <span title={canGoLive ? undefined : status !== "active" ? "Mark the partner active first" : `${missing} go-live checklist ${missing === 1 ? "item is" : "items are"} not done`}>
          <Button size="sm" disabled={!canGoLive} onClick={() => setDialog("live_on")} className={cn(!canGoLive && "pointer-events-none")}>
            <Power className="size-3.5" /> Go live
          </Button>
        </span>
      )}

      <ConfirmDialog open={dialog === "activate"} onClose={close} title={`Mark ${title} active?`} confirmLabel="Mark active" onConfirm={status_("active", "Partner marked active")}>
        Active means onboarding is finished. The partner still receives nothing until its live switch is on.
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "pause"} onClose={close} title={`Pause ${title}?`} confirmLabel="Pause partner" reason={{ label: "Reason", placeholder: "e.g. contract renewal, missed SLAs" }} onConfirm={status_("paused", "Partner paused")}>
        New leads stop routing to this partner at once. Leads it already has stay with it.
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "resume"} onClose={close} title={`Resume ${title}?`} confirmLabel="Resume" onConfirm={status_("active", "Partner resumed")}>
        The partner becomes eligible for new leads again{live ? "" : " once its live switch is on"}.
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "close"} onClose={close} title={`Close ${title}?`} tone="danger" confirmLabel="Close partner" reason={{ label: "Reason", placeholder: "e.g. agreement ended" }} onConfirm={status_("closed", "Partner closed")}>
        The partner is switched off and never receives another lead. Its history, leads and commission records stay. This cannot be undone here.
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "live_on"} onClose={close} title={`Switch ${title} live?`} confirmLabel="Go live" reason={{ label: "Note for the audit log", placeholder: "e.g. 10 test leads passed on 12 Oct" }} onConfirm={live_(true)}>
        Real student leads that match this partner&apos;s programmes start routing to its production CRM, and students are told who will call (when notifications are on).
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "live_off"} onClose={close} title={`Switch ${title} off?`} tone="danger" confirmLabel="Switch off" reason={{ label: "Reason", placeholder: "e.g. partner CRM outage" }} onConfirm={live_(false)}>
        No new lead is sent to this partner. Leads already sent stay with it and keep syncing.
      </ConfirmDialog>
    </div>
  );
}
