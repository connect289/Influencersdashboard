"use client";
import { useState } from "react";
import { RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { resync } from "./actions";

/** Re-sends every lead in scope as a new version (the B2C CRM keeps the newest, so it is always safe). */
export function ResyncAll({ count }: { count: number }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <Button size="sm" variant="secondary" onClick={() => setOpen(true)}><RefreshCw className="size-3.5" /> Resend every lead</Button>
      <ConfirmDialog open={open} onClose={() => setOpen(false)} title="Resend every lead to the B2C CRM?" confirmLabel="Resend"
        onConfirm={async () => {
          const r = await resync(null);
          if (!r.ok) return r.error;
          toast.success(`${r.leads} leads queued as new versions`);
        }}>
        <p>About {count} leads are sent again as new versions. Use it after the B2C CRM rebuilt its copy, or after changing which leads it sees.
          The B2C CRM can also rebuild on its own from the change feed (<code>GET /v1/b2c/leads?after=0</code>).</p>
      </ConfirmDialog>
    </>
  );
}
