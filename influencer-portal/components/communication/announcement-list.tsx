"use client";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { Ban, Pencil } from "lucide-react";
import { StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { EmptyState } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { cancelAnnouncement } from "@/lib/actions/communication";
import type { AnnouncementAdminRow } from "@/lib/communication/data";
import { formatDateTime, formatNumber } from "@/lib/format";
import { isEveryone } from "@/lib/notify/segments";

/** Announcements, newest first: drafts and scheduled ones can be edited or cancelled; sent ones show their reach. */
export function AnnouncementList({ rows }: { rows: AnnouncementAdminRow[] }) {
  const t = useTranslations();
  const { pending, run } = useAction();
  if (rows.length === 0)
    return (
      <EmptyState
        title={t("communication.announcements.empty")}
        description={t("communication.announcements.emptyHint")}
      />
    );
  return (
    <ul className="divide-y divide-line overflow-hidden rounded-[var(--radius-card)] bg-surface shadow-[var(--shadow-card)]">
      {rows.map((a) => {
        const editable = a.status === "draft" || a.status === "scheduled";
        return (
          <li key={a.id} className="flex flex-wrap items-start gap-3 px-4 py-3">
            <div className="min-w-0 flex-1">
              <p className="flex flex-wrap items-center gap-2">
                <span className="text-sm font-semibold">{a.title}</span>
                <StatusBadge status={a.status} label={t(`communication.announcements.statuses.${a.status}`)} />
              </p>
              <p className="mt-0.5 line-clamp-2 text-sm text-muted">{a.body}</p>
              <p className="mt-1 text-xs text-faint">
                {a.status === "sent" && a.sent_at
                  ? t("communication.announcements.sentLine", {
                      date: formatDateTime(a.sent_at),
                      count: a.recipients ?? 0,
                      shown: formatNumber(a.recipients ?? 0),
                    })
                  : a.status === "scheduled" && a.scheduled_at
                    ? t("communication.announcements.scheduledLine", { date: formatDateTime(a.scheduled_at) })
                    : formatDateTime(a.created_at)}
                {" · "}
                {isEveryone(a.segment)
                  ? t("communication.announcements.everyoneShort")
                  : t("communication.announcements.segmentShort")}
                {a.created_by ? ` · ${a.created_by}` : ""}
              </p>
            </div>
            {editable ? (
              <div className="flex gap-1">
                <Button asChild size="sm" variant="ghost">
                  <Link href={`/admin/communication/announcements?edit=${a.id}`}>
                    <Pencil /> {t("common.edit")}
                  </Link>
                </Button>
                <ConfirmDialog
                  trigger={
                    <Button size="sm" variant="ghost" disabled={pending}>
                      <Ban /> {t("communication.announcements.cancel")}
                    </Button>
                  }
                  title={t("communication.announcements.cancelTitle")}
                  actionLabel={t("communication.announcements.cancel")}
                  onConfirm={(_, close) => run(() => cancelAnnouncement(a.id), close)}
                />
              </div>
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}
