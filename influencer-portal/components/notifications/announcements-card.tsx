import Link from "next/link";
import { Megaphone } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Card, CardHeader } from "@/components/ui/card";
import { formatDate } from "@/lib/format";
import type { AnnouncementRow } from "@/lib/messaging/data";
import { cn } from "@/lib/utils";

/** The newest announcements from Eduwit on the creator home (hidden when there are none). */
export async function AnnouncementsCard({ rows }: { rows: AnnouncementRow[] }) {
  if (rows.length === 0) return null;
  const t = await getTranslations();
  return (
    <Card>
      <CardHeader
        title={
          <span className="inline-flex items-center gap-2">
            <Megaphone className="size-4 text-accent-ink" aria-hidden /> {t("home.announcements")}
          </span>
        }
      />
      <ul className="flex flex-col gap-3">
        {rows.map((a) => (
          <li key={a.id} className={cn("rounded-xl p-3", a.read_at ? "bg-surface-2" : "bg-accent-soft")}>
            <p className="text-sm font-semibold">{a.title}</p>
            {a.body ? <p className="mt-0.5 text-sm whitespace-pre-line text-muted">{a.body}</p> : null}
            <p className="mt-1 flex flex-wrap items-center gap-3 text-xs text-muted">
              <time dateTime={a.created_at}>{formatDate(a.created_at)}</time>
              {a.link ? (
                <Link href={a.link} className="text-primary hover:underline">
                  {t("home.announcementOpen")}
                </Link>
              ) : null}
            </p>
          </li>
        ))}
      </ul>
    </Card>
  );
}
