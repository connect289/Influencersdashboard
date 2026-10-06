"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { discardVersion, publishVersion } from "../../../actions";

/** Publish (or restore) a version, or discard a draft. The database refuses while rows still need review. */
export function PublishBar({ partnerId, versionId, status, pending, summary, warnRemovals }: {
  partnerId: number; versionId: number; status: string; pending: number; summary: string; warnRemovals: number;
}) {
  const [dialog, setDialog] = useState<"publish" | "discard" | null>(null);
  const router = useRouter();
  const go = (err: string | void, to: string) => { if (err) return err; router.push(to); };
  const restore = status !== "draft";
  return (
    <div className="flex flex-wrap items-center gap-2">
      {status === "draft" && <Button variant="ghost" size="sm" className="hover:text-danger" onClick={() => setDialog("discard")}>Discard draft</Button>}
      <span title={pending ? `${pending} ${pending === 1 ? "row needs" : "rows need"} review first` : undefined}>
        <Button size="sm" disabled={pending > 0} onClick={() => setDialog("publish")}>{restore ? "Restore this version" : "Publish"}</Button>
      </span>

      <ConfirmDialog open={dialog === "publish"} onClose={() => setDialog(null)} title={restore ? "Restore this version?" : "Publish this version?"}
        confirmLabel={restore ? "Restore" : "Publish"} tone={warnRemovals ? "danger" : "primary"}
        reason={{ label: "Note for the version history (optional)", placeholder: restore ? "e.g. new file had wrong fees" : "e.g. October price list" }}
        onConfirm={async (note) => go(await publishVersion(partnerId, versionId, note || (restore ? "Restored" : "")), `/programmes/${partnerId}?published=${versionId}`)}>
        <p>{summary}</p>
        {warnRemovals > 0 && (
          <p className="mt-2 font-medium text-danger">
            {warnRemovals} {warnRemovals === 1 ? "programme loses its" : "programmes lose their"} only partner: new leads for {warnRemovals === 1 ? "it" : "them"} will go to B2C.
          </p>
        )}
        <p className="mt-2">New leads route by this version at once. Leads already with a partner stay where they are.</p>
      </ConfirmDialog>
      <ConfirmDialog open={dialog === "discard"} onClose={() => setDialog(null)} title="Discard this draft?" tone="danger" confirmLabel="Discard"
        onConfirm={async () => go(await discardVersion(partnerId, versionId), `/programmes/${partnerId}?tab=versions`)}>
        The live programmes do not change. The uploaded file stays in the version history.
      </ConfirmDialog>
    </div>
  );
}
