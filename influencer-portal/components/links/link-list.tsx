"use client";
// A creator's links: the short link to copy, QR codes to download, clicks and leads, and switching a link off.
import { Copy, QrCode } from "lucide-react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/states";
import { Switch } from "@/components/ui/switch";
import { useAction } from "@/components/ui/use-action";
import { setLinkActive } from "@/lib/actions/links";
import type { LinkRow } from "@/lib/leads/data";
import { formatDate, formatNumber } from "@/lib/format";

export function LinkList({ links, base, canEdit }: { links: LinkRow[]; base: string; canEdit: boolean }) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  if (!links.length) return <EmptyState title={t("links.empty")} description={t("links.emptyHint")} />;
  return (
    <ul className="flex flex-col gap-3">
      {links.map((l) => {
        const url = `${base.replace(/\/$/, "")}/${l.code}`;
        return (
          <li key={l.id} className="rounded-[var(--radius-card)] bg-surface p-4 shadow-[var(--shadow-card)]">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="font-mono text-sm font-semibold">{l.code}</p>
                <p className="text-sm text-muted">
                  {[l.label, l.deal_title, l.deliverable_title, l.programme_name].filter(Boolean).join(" · ") ||
                    t("links.noDetails")}
                </p>
              </div>
              <span className="flex items-center gap-2">
                <Badge>{t(`links.destinations.${l.destination}`)}</Badge>
                {canEdit ? (
                  <Switch
                    aria-label={t("links.active")}
                    checked={l.active}
                    disabled={pending}
                    onCheckedChange={(on) =>
                      run(
                        () => setLinkActive(l.id, on),
                        () => router.refresh(),
                      )
                    }
                  />
                ) : !l.active ? (
                  <Badge family="closed">{t("links.inactiveBadge")}</Badge>
                ) : null}
              </span>
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              <code className="min-w-0 flex-1 truncate rounded-lg bg-surface-2 px-2 py-1.5 text-xs">{url}</code>
              <Button
                type="button"
                size="sm"
                variant="secondary"
                onClick={() =>
                  void navigator.clipboard.writeText(url).then(
                    () => toast.success(t("links.copied")),
                    () => toast.error(t("errors.generic")),
                  )
                }
              >
                <Copy /> {t("links.copy")}
              </Button>
              <Button asChild size="sm" variant="ghost">
                <a href={`/api/links/${l.id}/qr?format=png`} download={`${l.code}.png`}>
                  <QrCode /> PNG
                </a>
              </Button>
              <Button asChild size="sm" variant="ghost">
                <a href={`/api/links/${l.id}/qr?format=svg`} download={`${l.code}.svg`}>
                  <QrCode /> SVG
                </a>
              </Button>
            </div>
            <p className="mt-2 text-xs text-muted">
              {t("links.stats", { clicks: formatNumber(l.clicks), leads: formatNumber(l.leads) })} ·{" "}
              {t("links.createdOn", { date: formatDate(l.created_at) })}
            </p>
          </li>
        );
      })}
    </ul>
  );
}
