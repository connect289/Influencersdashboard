"use client";
import { useState } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { Badge } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { relativeTime } from "@/lib/format";
import type { ReviewFlag } from "@/lib/routing-data";
import { resolveFlag } from "./actions";

/** Passed leads that Witty later classified junk or mismatch (Addendum 2): never pulled back, only reviewed. */
export function ReviewQueue({ flags }: { flags: ReviewFlag[] }) {
  const [open, setOpen] = useState<{ flag: ReviewFlag; resolution: "keep" | "close" } | null>(null);
  return (
    <>
      <ul className="divide-y divide-border">
        {flags.map((f) => (
          <li key={f.id} className="flex flex-wrap items-center gap-x-3 gap-y-2 px-5 py-3 text-[13px]">
            <div className="min-w-0 flex-1">
              <Link href={`/leads?lead=${f.lead_id}`} className="font-medium text-fg hover:underline">{f.lead_name || `Lead #${f.lead_id}`}</Link>
              <p className="text-[12px] text-muted">
                Now <Badge tone="danger">{f.lead_status === "PROGRAM_MISMATCH" ? "Programme mismatch" : "Junk"}</Badge>{" "}
                · with {f.destination_type === "partner" ? f.partner_name : "B2C"} ({f.reference}) · {relativeTime(f.created_at)}
              </p>
            </div>
            <Button size="sm" variant="ghost" onClick={() => setOpen({ flag: f, resolution: "keep" })}>Keep</Button>
            <Button size="sm" variant="secondary" onClick={() => setOpen({ flag: f, resolution: "close" })}>
              {f.destination_type === "in_house" ? "Agree B2C closes it" : "Note it"}
            </Button>
          </li>
        ))}
      </ul>
      <ConfirmDialog
        open={open !== null}
        onClose={() => setOpen(null)}
        title={open?.resolution === "keep" ? "Keep this lead where it is?" : open?.flag.destination_type === "in_house" ? "Agree that B2C closes it?" : "Record the reclassification?"}
        confirmLabel={open?.resolution === "keep" ? "Keep" : "Confirm"}
        reason={{ label: "Note for the audit log", placeholder: "e.g. Witty misread a joke" }}
        onConfirm={async (note) => {
          if (!open) return;
          const err = await resolveFlag(open.flag.id, open.resolution, note);
          if (err) return err;
          toast.success("Flag resolved");
        }}
      >
        {open?.flag.destination_type === "partner"
          ? "A partner-held lead stays with the partner either way; this only records your review."
          : open?.resolution === "close"
            ? "The B2C CRM is told you agree, and closes the lead itself."
            : "The lead stays with B2C as it is."}
      </ConfirmDialog>
    </>
  );
}
