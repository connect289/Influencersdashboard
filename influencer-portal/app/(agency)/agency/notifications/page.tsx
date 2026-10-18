import { getTranslations } from "next-intl/server";
import { NotificationCentre } from "@/components/notifications/notification-centre";
import { requireAgency } from "@/lib/auth/guards";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("notifications.title") };
}

export default async function NotificationsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase } = await requireAgency();
  return (
    <NotificationCentre
      db={supabase}
      base="/agency"
      help="/agency/help/agency#notifications"
      searchParams={await searchParams}
    />
  );
}
