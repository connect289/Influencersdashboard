"use client";
import { CheckCheck, Lock } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/states";
import { useAction } from "@/components/ui/use-action";
import { markNotificationsRead } from "@/lib/actions/messaging";
import { markNotificationsReadNow } from "@/lib/messaging/client";
import { NOTIFICATIONS_CHANGED } from "./bell";
import { formatDateTime, formatRelative } from "@/lib/format";
import type { NotificationRow } from "@/lib/messaging/data";
import { cn } from "@/lib/utils";

/**
 * The notification centre list (spec 14): newest first, unread marked, opening one marks it read and goes to its
 * page. "Mark all read" clears the bell.
 */
export function NotificationList({
  rows,
  unreadOnly,
  moreHref,
}: {
  rows: NotificationRow[];
  unreadOnly: boolean;
  moreHref: string | null;
}) {
  const t = useTranslations();
  const router = useRouter();
  const { pending, run } = useAction();
  const [items, setItems] = useState(rows);
  const unread = items.filter((n) => !n.read_at).length;

  function open(n: NotificationRow) {
    if (!n.read_at) {
      setItems((xs) => xs.map((x) => (x.id === n.id ? { ...x, read_at: new Date().toISOString() } : x)));
      void markNotificationsReadNow([n.id]).then(() => window.dispatchEvent(new Event(NOTIFICATIONS_CHANGED)));
    }
    if (n.link) router.push(n.link);
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <nav className="flex gap-1" aria-label={t("notifications.filter")}>
          {[
            { key: false, label: t("notifications.all") },
            { key: true, label: t("notifications.unread") },
          ].map((f) => (
            <Link
              key={String(f.key)}
              href={f.key ? "?unread=1" : "?"}
              aria-current={f.key === unreadOnly ? "page" : undefined}
              className={cn(
                "rounded-lg px-2.5 py-1 text-sm",
                f.key === unreadOnly ? "bg-primary-soft font-medium text-primary" : "text-muted hover:bg-surface-2",
              )}
              scroll={false}
            >
              {f.label}
            </Link>
          ))}
        </nav>
        <Button
          size="sm"
          variant="secondary"
          disabled={pending || unread === 0}
          onClick={() =>
            run(
              () => markNotificationsRead(null),
              () => {
                setItems((xs) => xs.map((x) => ({ ...x, read_at: x.read_at ?? new Date().toISOString() })));
                window.dispatchEvent(new Event(NOTIFICATIONS_CHANGED));
                router.refresh();
              },
            )
          }
        >
          <CheckCheck /> {t("notifications.markAll")}
        </Button>
      </div>
      {items.length === 0 ? (
        <EmptyState
          title={unreadOnly ? t("notifications.noneUnread") : t("notifications.none")}
          description={t("notifications.noneHint")}
        />
      ) : (
        <ul className="divide-y divide-line overflow-hidden rounded-[var(--radius-card)] bg-surface shadow-[var(--shadow-card)]">
          {items.map((n) => (
            <li key={n.id}>
              <button
                type="button"
                onClick={() => open(n)}
                className={cn(
                  "flex w-full items-start gap-3 px-4 py-3 text-left hover:bg-surface-2",
                  !n.read_at && "bg-primary-soft/40",
                )}
              >
                <span
                  aria-hidden
                  className={cn("mt-1.5 size-2 shrink-0 rounded-full", n.read_at ? "bg-transparent" : "bg-primary")}
                />
                <span className="min-w-0 flex-1">
                  <span className={cn("block text-sm", !n.read_at && "font-semibold")}>
                    {!n.read_at ? <span className="sr-only">{t("notifications.unreadMark")} </span> : null}
                    {n.title}
                  </span>
                  {n.body ? <span className="mt-0.5 line-clamp-2 block text-sm text-muted">{n.body}</span> : null}
                  <span className="mt-1 flex items-center gap-2 text-xs text-faint">
                    <time dateTime={n.created_at} title={formatDateTime(n.created_at)}>
                      {formatRelative(n.created_at)}
                    </time>
                    {n.mandatory ? (
                      <span className="inline-flex items-center gap-0.5">
                        <Lock className="size-3" aria-hidden /> {t("notifications.important")}
                      </span>
                    ) : null}
                  </span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
      {moreHref ? (
        <div className="text-center">
          <Button asChild size="sm" variant="ghost">
            <Link href={moreHref} scroll={false}>
              {t("notifications.older")}
            </Link>
          </Button>
        </div>
      ) : null}
    </div>
  );
}
