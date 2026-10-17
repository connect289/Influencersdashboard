import { getTranslations } from "next-intl/server";
import { CommNav } from "@/components/communication/comm-nav";
import { WebhookManager } from "@/components/communication/webhook-manager";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadWebhooks } from "@/lib/communication/data";
import { env } from "@/lib/env";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("communication.sections.webhooks") };
}

/** Outbound webhooks (spec 18, Super Admin). */
export default async function WebhooksPage() {
  const { supabase, me } = await requireStaff("webhook.manage");
  const t = await getTranslations();
  const endpoints = await loadWebhooks(supabase).catch(() => null);
  return (
    <>
      <PageHeader
        title={t("communication.title")}
        description={t("communication.webhooks.subtitle")}
        help="/admin/help/super-admin#webhooks"
      />
      <CommNav current="webhooks" permissions={me.permissions} />
      {endpoints ? (
        <WebhookManager endpoints={endpoints} liveMode={env().LIVE_MODE === "on"} />
      ) : (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      )}
    </>
  );
}
