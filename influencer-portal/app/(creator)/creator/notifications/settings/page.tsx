import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { PreferencesForm } from "@/components/notifications/preferences-form";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { loadPreferences } from "@/lib/messaging/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("notifications.prefs.title") };
}

export default async function NotificationSettingsPage() {
  const { supabase } = await requireCreator();
  const t = await getTranslations();
  const prefs = await loadPreferences(supabase).catch(() => null);
  return (
    <>
      <Link
        href="/creator/notifications"
        className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"
      >
        <ArrowLeft className="size-4" aria-hidden /> {t("notifications.title")}
      </Link>
      <PageHeader
        title={t("notifications.prefs.title")}
        description={t("notifications.prefs.subtitle")}
        help="/creator/help/creator#notifications"
      />
      {prefs ? (
        <PreferencesForm audience="creator" initial={prefs} digestDefault="weekly" whatsappAvailable={true} />
      ) : (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      )}
    </>
  );
}
