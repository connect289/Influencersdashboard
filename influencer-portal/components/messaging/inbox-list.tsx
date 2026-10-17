import Link from "next/link";
import { Lock } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Badge } from "@/components/ui/badge";
import { EmptyState, NoResults } from "@/components/ui/states";
import { formatDateTime, formatRelative } from "@/lib/format";
import type { InboxRow } from "@/lib/messaging/data";
import { cn } from "@/lib/utils";

/** Conversations, newest first, with the unread count and the latest message (mentions shown as plain names). */
export async function InboxList({
  rows,
  filtered,
  showCreator,
}: {
  rows: InboxRow[];
  filtered: boolean;
  showCreator: boolean;
}) {
  const t = await getTranslations();
  if (rows.length === 0) {
    return filtered ? (
      <NoResults title={t("messaging.inbox.noResults")} />
    ) : (
      <EmptyState title={t("messaging.inbox.empty")} description={t("messaging.inbox.emptyHint")} />
    );
  }
  return (
    <ul className="divide-y divide-line overflow-hidden rounded-[var(--radius-card)] bg-surface shadow-[var(--shadow-card)]">
      {rows.map((r) => (
        <li key={r.id}>
          <Link
            href={r.link ?? "#"}
            className={cn("flex items-start gap-3 px-4 py-3 hover:bg-surface-2", r.unread > 0 && "bg-primary-soft/40")}
          >
            <span className="min-w-0 flex-1">
              <span className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                <span className={cn("text-sm", r.unread > 0 && "font-semibold")}>
                  {r.subject ?? t(`messaging.types.${r.entity_type}`)}
                </span>
                {showCreator && r.creator_name ? <span className="text-xs text-muted">{r.creator_name}</span> : null}
                <Badge>{t(`messaging.types.${r.entity_type}`)}</Badge>
                {r.staff_only ? (
                  <span className="inline-flex items-center gap-0.5 text-xs text-muted">
                    <Lock className="size-3" aria-hidden /> {t("messaging.staffOnlyShort")}
                  </span>
                ) : null}
              </span>
              {r.last_message ? (
                <span className="mt-0.5 line-clamp-1 block text-sm text-muted">{r.last_message}</span>
              ) : null}
            </span>
            <span className="flex shrink-0 flex-col items-end gap-1">
              {r.last_message_at ? (
                <time
                  dateTime={r.last_message_at}
                  title={formatDateTime(r.last_message_at)}
                  className="text-xs text-faint"
                >
                  {formatRelative(r.last_message_at)}
                </time>
              ) : null}
              {r.unread > 0 ? (
                <span className="rounded-full bg-primary px-1.5 text-[11px] leading-[18px] font-semibold text-on-primary">
                  <span className="sr-only">{t("messaging.inbox.unread", { count: r.unread })}</span>
                  <span aria-hidden>{r.unread}</span>
                </span>
              ) : null}
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}
