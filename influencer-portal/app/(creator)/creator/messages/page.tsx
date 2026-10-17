import { getTranslations } from "next-intl/server";
import { InboxList } from "@/components/messaging/inbox-list";
import { Thread } from "@/components/messaging/thread";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { loadInbox } from "@/lib/messaging/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("messaging.inbox.title") };
}

/** The creator's messages: a direct line to Eduwit, then every conversation about their campaigns, deals and work. */
export default async function CreatorMessagesPage() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const rows = await loadInbox(supabase).catch(() => null);
  const others = rows?.filter((r) => r.entity_type !== "support") ?? null;
  return (
    <>
      <PageHeader
        title={t("messaging.inbox.title")}
        description={t("messaging.inbox.creatorSubtitle")}
        help="/creator/help/creator#messages"
      />
      <div className="flex flex-col gap-4">
        <Thread
          db={supabase}
          thread={{ type: "support", entityId: me.creatorId }}
          title={t("messaging.support.title")}
          description={t("messaging.support.creatorHint")}
        />
        <section aria-labelledby="other-threads">
          <CardHeader title={<span id="other-threads">{t("messaging.inbox.other")}</span>} />
          {others ? (
            <InboxList rows={others} filtered={false} showCreator={false} />
          ) : (
            <Card>
              <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
            </Card>
          )}
        </section>
      </div>
    </>
  );
}
