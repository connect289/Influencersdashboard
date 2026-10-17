import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { PreferencesForm } from "@/components/notifications/preferences-form";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadPreferences } from "@/lib/messaging/data";
import { readSetting } from "@/lib/settings/read";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("notifications.prefs.title") };
}

export default async function NotificationSettingsPage() {
  const { supabase } = await requireStaff();
  const t = await getTranslations();
  const [prefs, delivery] = await Promise.all([
    loadPreferences(supabase).catch(() => null),
    readSetting("notifications.delivery"),
  ]);
  return (
    <>
      <Link
        href="/admin/notifications"
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("notifications.title")}
      </Link>
      <PageHeader
        title={t("notifications.prefs.title")}
        description={t("notifications.prefs.subtitle")}
        help="/admin/help/getting-started#notifications"
      />
      {prefs ? (
        <PreferencesForm
          audience="staff"
          initial={prefs}
          digestDefault={delivery.staff_digest}
          whatsappAvailable={false}
        />
      ) : (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      )}
    </>
  );
}
