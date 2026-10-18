"use client";
// One deliverable's tracking link: the code, the short link to copy, and QR downloads. Shown in the brief and on the
// deliverable so the creator always posts with the right link.
import { Copy, QrCode } from "lucide-react";
import { useTranslations } from "next-intl";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import type { DeliverableLink } from "@/lib/leads/links";

export function TrackingLink({ link }: { link: DeliverableLink }) {
  const t = useTranslations();
  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm">
        {t("links.codeLine")} <span className="font-mono font-semibold">{link.code}</span>
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <code className="min-w-0 flex-1 truncate rounded-lg bg-surface-2 px-2 py-1.5 text-xs">{link.url}</code>
        <Button
          type="button"
          size="sm"
          variant="secondary"
          onClick={() =>
            void navigator.clipboard.writeText(link.url).then(
              () => toast.success(t("links.copied")),
              () => toast.error(t("errors.generic")),
            )
          }
        >
          <Copy /> {t("links.copy")}
        </Button>
        <Button asChild size="sm" variant="ghost">
          <a href={`/api/links/${link.id}/qr?format=png`} download={`${link.code}.png`}>
            <QrCode /> PNG
          </a>
        </Button>
        <Button asChild size="sm" variant="ghost">
          <a href={`/api/links/${link.id}/qr?format=svg`} download={`${link.code}.svg`}>
            <QrCode /> SVG
          </a>
        </Button>
      </div>
    </div>
  );
}
