import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { InboxList } from "@/components/messaging/inbox-list";
import { Thread } from "@/components/messaging/thread";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireAgency } from "@/lib/auth/guards";
import { loadInbox } from "@/lib/messaging/data";
import { cn } from "@/lib/utils";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("messaging.inbox.title") };
}

/**
 * The agency's messages: a support line to Eduwit for each creator who granted "view", then the conversations the
 * agency's grants open (negotiation, deliverables, earnings).
 */
export default async function AgencyMessagesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase } = await requireAgency();
  const t = await getTranslations();
  const sp = await searchParams;
  const [links, rows] = await Promise.all([
    supabase.rpc("agency_creators").then((r) => (r.error ? null : r.data)),
    loadInbox(supabase).catch(() => null),
  ]);
  const viewable = (links ?? []).filter((l) => l.link_status === "active" && l.can_view);
  const wanted = z.uuid().safeParse(sp.creator);
  const current = viewable.find((l) => wanted.success && l.creator_id === wanted.data) ?? viewable[0] ?? null;
  return (
    <>
      <PageHeader
        title={t("messaging.inbox.title")}
        description={t("messaging.inbox.agencySubtitle")}
        help="/agency/help/agency#messages"
      />
      <div className="flex flex-col gap-4">
        {links === null ? (
          <Card>
            <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
          </Card>
        ) : current ? (
          <>
            {viewable.length > 1 ? (
              <nav className="flex flex-wrap gap-1" aria-label={t("messaging.support.chooseCreator")}>
                {viewable.map((l) => (
                  <Link
                    key={l.creator_id}
                    href={`/agency/messages?creator=${l.creator_id}`}
                    aria-current={l.creator_id === current.creator_id ? "page" : undefined}
                    className={cn(
                      "rounded-lg px-2.5 py-1 text-sm",
                      l.creator_id === current.creator_id
                        ? "bg-primary-soft font-medium text-primary"
                        : "text-muted hover:bg-surface-2",
                    )}
                    scroll={false}
                  >
                    {l.display_name}
                  </Link>
                ))}
              </nav>
            ) : null}
            <Thread
              db={supabase}
              thread={{ type: "support", entityId: current.creator_id }}
              title={t("messaging.support.agencyTitle", { name: current.display_name })}
              description={t("messaging.support.agencyHint")}
            />
          </>
        ) : (
          <EmptyState title={t("messaging.support.noCreators")} description={t("messaging.support.noCreatorsHint")} />
        )}
        <section aria-labelledby="agency-threads">
          <CardHeader title={<span id="agency-threads">{t("messaging.inbox.other")}</span>} />
          {rows ? (
            <InboxList rows={rows.filter((r) => r.entity_type !== "support")} filtered={false} showCreator />
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
