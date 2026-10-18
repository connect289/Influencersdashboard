import { getTranslations } from "next-intl/server";
import { NotificationCentre } from "@/components/notifications/notification-centre";
import { requireCreator } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("notifications.title") };
}

export default async function NotificationsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase } = await requireCreator();
  return (
    <NotificationCentre
      db={supabase}
      base="/creator"
      help="/creator/help/creator#notifications"
      searchParams={await searchParams}
    />
  );
}
