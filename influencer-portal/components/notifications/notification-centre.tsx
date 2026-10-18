import Link from "next/link";
import { Settings2 } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import type { Db } from "@/lib/contracts/data";
import { loadNotifications, NOTIFICATIONS_PAGE } from "@/lib/messaging/data";
import { NotificationList } from "./notification-list";

/** The notification centre for any portal (same list for creators, agencies and staff). */
export async function NotificationCentre({
  db,
  base,
  help,
  searchParams,
}: {
  db: Db;
  base: string;
  help: string;
  searchParams: Record<string, string | undefined>;
}) {
  const t = await getTranslations();
  const unreadOnly = searchParams.unread === "1";
  const before =
    searchParams.before && !Number.isNaN(Date.parse(searchParams.before)) ? searchParams.before : undefined;
  const rows = await loadNotifications(db, { before, unread: unreadOnly }).catch(() => null);
  const last = rows?.at(-1);
  const moreHref =
    rows && rows.length === NOTIFICATIONS_PAGE && last
      ? `?${new URLSearchParams({ ...(unreadOnly ? { unread: "1" } : {}), before: last.created_at })}`
      : null;
  return (
    <>
      <PageHeader
        title={t("notifications.title")}
        description={t("notifications.subtitle")}
        help={help}
        actions={
          <Button asChild size="sm" variant="secondary">
            <Link href={`${base}/notifications/settings`}>
              <Settings2 /> {t("notifications.prefs.open")}
            </Link>
          </Button>
        }
      />
      {rows ? (
        <NotificationList
          key={`${unreadOnly}:${before ?? ""}`}
          rows={rows}
          unreadOnly={unreadOnly}
          moreHref={moreHref}
        />
      ) : (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      )}
    </>
  );
}
