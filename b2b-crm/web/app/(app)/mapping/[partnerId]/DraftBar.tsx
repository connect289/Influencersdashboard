"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { FilePen, LoaderCircle, Rocket, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import type { Editing } from "@/lib/mapping";
import { discardDraft, publishDraft, startDraft } from "./actions";

/** Which version is being looked at, and the draft's lifecycle: start, publish (with a note), discard. */
export function DraftBar({ partnerId, editing, failingGoldens, held }: { partnerId: number; editing: Editing | null; failingGoldens: number; held: number }) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [dialog, setDialog] = useState<"publish" | "discard" | null>(null);
  const start = async () => {
    setPending(true);
    const r = await startDraft(partnerId);
    setPending(false);
    if (!r.ok) toast.error(r.error); else { toast.success(editing ? "Draft started from the active version" : "Draft started"); router.refresh(); }
  };
  const isDraft = editing?.status === "draft";
  return (
    <div className="mb-6 flex flex-wrap items-center gap-3 rounded-[var(--radius-card)] border border-border bg-surface px-4 py-3">
      <FilePen className="size-4 text-muted" />
      <p className="min-w-0 flex-1 basis-[calc(100%-2rem)] text-[13px] text-muted sm:basis-0">
        {!editing && "No mapping yet. Start a draft, map the partner's stages and fields, test it and publish it."}
        {editing?.status === "active" && <>Viewing the active version <span className="font-medium text-fg">v{editing.version}</span>. Start a draft to change it; the active version keeps working until you publish.</>}
        {isDraft && <>Editing a <span className="font-medium text-fg">draft</span>. Nothing changes for live events until you publish it.{held > 0 && ` Publishing re-applies ${held} held event${held === 1 ? "" : "s"}.`}</>}
      </p>
      {!isDraft && <Button size="sm" onClick={start} disabled={pending}>{pending && <LoaderCircle className="size-3.5 animate-spin" />} Start a draft</Button>}
      {isDraft && (
        <>
          <Button size="sm" variant="ghost" onClick={() => setDialog("discard")}><Trash2 className="size-3.5" /> Discard</Button>
          <Button size="sm" onClick={() => setDialog("publish")} disabled={failingGoldens > 0} title={failingGoldens ? "Golden files fail; fix them first (Test tab)" : undefined}>
            <Rocket className="size-3.5" /> Publish
          </Button>
        </>
      )}
      <ConfirmDialog
        open={dialog === "publish"}
        onClose={() => setDialog(null)}
        title="Publish this draft?"
        confirmLabel="Publish"
        reason={{ label: "What changed (for the version history)", placeholder: "e.g. mapped the new 'Hot' stage; Fee Paid as amount" }}
        onConfirm={async (note) => {
          if (!editing) return;
          const r = await publishDraft(partnerId, editing.id, note);
          if (!r.ok) return r.error;
          const d = r.data;
          toast.success(`Version ${d?.version} is active${d?.reprocess.reprocessed ? `; ${d.reprocess.applied} of ${d.reprocess.reprocessed} held events applied` : ""}`);
          router.refresh();
        }}
      >
        It becomes the active version at once: new partner events use it, held events are re-applied in order, and the queue items it covers are closed. The previous version stays in the history and can be restored.
      </ConfirmDialog>
      <ConfirmDialog
        open={dialog === "discard"}
        onClose={() => setDialog(null)}
        title="Discard this draft?"
        tone="danger"
        confirmLabel="Discard"
        onConfirm={async () => {
          if (!editing) return;
          const r = await discardDraft(partnerId, editing.id);
          if (!r.ok) return r.error;
          toast.success("Draft discarded");
          router.refresh();
        }}
      >
        Its changes are dropped. The active version is not affected.
      </ConfirmDialog>
    </div>
  );
}
