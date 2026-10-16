"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { Download } from "lucide-react";
import { toast } from "sonner";
import { waTemplatesImport } from "../admin-actions";

/** Reads every template already on the WhatsApp account into Spark (new ones as marketing templates). */
export function ImportTemplatesButton({ label = "Import templates from WhatsApp" }: { label?: string }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  return (
    <button type="button" className="btn ghost sm" disabled={busy} onClick={() => start(async () => {
      const r = await waTemplatesImport();
      if (!r.ok) return void toast.error(r.error);
      toast.success(r.notice ?? "Imported.");
      router.refresh();
    })}><Download className="icon s" aria-hidden />{busy ? "Importing…" : label}</button>
  );
}
