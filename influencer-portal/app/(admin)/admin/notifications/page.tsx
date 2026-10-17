import { getTranslations } from "next-intl/server";
import { NotificationCentre } from "@/components/notifications/notification-centre";
import { requireStaff } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("notifications.title") };
}

export default async function NotificationsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase } = await requireStaff();
  return (
    <NotificationCentre
      db={supabase}
      base="/admin"
      help="/admin/help/getting-started#notifications"
      searchParams={await searchParams}
    />
  );
}
