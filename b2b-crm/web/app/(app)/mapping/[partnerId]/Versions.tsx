"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { History, RotateCcw } from "lucide-react";
import { toast } from "sonner";
import { Badge, EmptyState } from "@/components/ui/Card";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { formatDateTime, relativeTime } from "@/lib/format";
import type { Profile, Studio } from "@/lib/mapping";
import { restoreVersion } from "./actions";

export function VersionsPanel({ studio }: { studio: Studio }) {
  const router = useRouter();
  const [restore, setRestore] = useState<Profile | null>(null);
  if (studio.profiles.length === 0) return <EmptyState icon={History} title="No versions yet" />;
  return (
    <>
      <ul className="divide-y divide-border">
        {studio.profiles.map((p) => (
          <li key={p.id} className="flex flex-wrap items-center gap-x-4 gap-y-1 px-5 py-3 text-[13px]">
            <span className="tabular w-12 font-semibold text-fg">{p.version ? `v${p.version}` : "Draft"}</span>
            <Badge tone={p.status === "active" ? "success" : p.status === "draft" ? "info" : "neutral"}>{p.status}</Badge>
            <span className="min-w-0 flex-1 text-muted">
              {p.note ?? (p.status === "draft" ? "Not published" : "")}
              <span className="block text-[12px] text-subtle">
                {p.rules} rules · {p.activated_at ? <>published <span title={formatDateTime(p.activated_at)}>{relativeTime(p.activated_at)}</span></> : <>started <span title={formatDateTime(p.created_at)}>{relativeTime(p.created_at)}</span></>}
              </span>
            </span>
            {p.status === "retired" && p.version && <Button size="sm" variant="secondary" onClick={() => setRestore(p)}><RotateCcw className="size-3.5" /> Restore</Button>}
          </li>
        ))}
      </ul>
      <ConfirmDialog
        open={restore !== null}
        onClose={() => setRestore(null)}
        title={`Make version ${restore?.version ?? ""} active again?`}
        confirmLabel="Restore"
        reason={{ label: "Reason for the version history", placeholder: "e.g. the new version mapped Hot to Applied by mistake" }}
        onConfirm={async (reason) => {
          if (!restore) return;
          const r = await restoreVersion(studio.partner.id, restore.id, reason);
          if (!r.ok) return r.error;
          toast.success(`Restored as version ${r.data?.version}`);
          router.refresh();
        }}
      >
        Its rules become a new version, active at once; the current one is kept in the history. A draft in progress is not touched.
      </ConfirmDialog>
    </>
  );
}
