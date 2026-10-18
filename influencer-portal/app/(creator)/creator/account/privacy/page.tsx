import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { PrivacyPanel } from "@/components/privacy/privacy-panel";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { formatDateTime } from "@/lib/format";
import { loadMyConsents, loadMyPrivacyRequests } from "@/lib/privacy/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("privacy.title") };
}

export default async function CreatorPrivacyPage() {
  const { supabase } = await requireCreator();
  const t = await getTranslations();
  const [requests, consents] = await Promise.all([
    loadMyPrivacyRequests(supabase).catch(() => null),
    loadMyConsents(supabase),
  ]);
  return (
    <>
      <Link href="/creator/account" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.creator.account")}
      </Link>
      <PageHeader title={t("privacy.title")} description={t("privacy.subtitle")} help="/creator/help/creator#my-data" />
      <div className="flex flex-col gap-4">
        {requests ? (
          <PrivacyPanel requests={requests} />
        ) : (
          <Card>
            <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
          </Card>
        )}
        <Card>
          <CardHeader
            title={t("privacy.consents.title")}
            description={t("privacy.consents.hint")}
            actions={
              <Link href="/creator/notifications/settings" className="text-sm text-primary hover:underline">
                {t("notifications.prefs.open")}
              </Link>
            }
          />
          {consents.length === 0 ? (
            <p className="text-sm text-muted">{t("privacy.consents.none")}</p>
          ) : (
            <ul className="flex flex-col divide-y divide-line text-sm">
              {consents.slice(0, 50).map((c, i) => (
                <li key={i} className="flex flex-wrap justify-between gap-2 py-1.5">
                  <span>
                    {c.purpose === "digest"
                      ? t("privacy.consents.digest", { frequency: c.detail ?? "" })
                      : t(
                          `notifications.events.${c.purpose.replace(/\./g, "_")}` as "notifications.events.announcement",
                        )}{" "}
                    · {t(`notifications.channels.${c.channel}`)}
                  </span>
                  <span className="text-muted">
                    {c.granted ? t("privacy.consents.on") : t("privacy.consents.off")} · {formatDateTime(c.created_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </>
  );
}
