import { getTranslations } from "next-intl/server";
import { InboxList } from "@/components/messaging/inbox-list";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Select } from "@/components/ui/input";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadInbox } from "@/lib/messaging/data";
import { inboxFilter, THREAD_TYPES } from "@/lib/messaging/schemas";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("messaging.inbox.title") };
}

/** Staff inbox (spec 14): every conversation the person may read, searchable, with unread and @mention filters. */
export default async function AdminMessagesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const { supabase } = await requireStaff("message.read");
  const t = await getTranslations();
  const sp = await searchParams;
  const parsed = inboxFilter.safeParse({
    q: sp.q || undefined,
    type: sp.type || undefined,
    unread: sp.unread === "1" || undefined,
    mentions: sp.mentions === "1" || undefined,
    creatorId: sp.creator || undefined,
  });
  const filter = parsed.success ? parsed.data : {};
  const rows = await loadInbox(supabase, filter).catch(() => null);
  const filtered = Object.values(filter).some(Boolean);
  return (
    <>
      <PageHeader
        title={t("messaging.inbox.title")}
        description={t("messaging.inbox.staffSubtitle")}
        help="/admin/help/getting-started#messages"
      />
      <form method="get" action="/admin/messages" className="mb-3 flex flex-wrap items-center gap-2" role="search">
        <label htmlFor="msg-q" className="sr-only">
          {t("messaging.inbox.search")}
        </label>
        <Input
          id="msg-q"
          name="q"
          defaultValue={filter.q ?? ""}
          placeholder={t("messaging.inbox.search")}
          maxLength={100}
          className="min-w-48 flex-1"
        />
        <Select name="type" defaultValue={filter.type ?? ""} aria-label={t("messaging.inbox.type")} className="w-auto">
          <option value="">{t("messaging.inbox.allTypes")}</option>
          {THREAD_TYPES.map((x) => (
            <option key={x} value={x}>
              {t(`messaging.types.${x}`)}
            </option>
          ))}
        </Select>
        <label className="inline-flex items-center gap-1.5 text-sm">
          <input type="checkbox" name="unread" value="1" defaultChecked={filter.unread === true} />
          {t("messaging.inbox.unreadOnly")}
        </label>
        <label className="inline-flex items-center gap-1.5 text-sm">
          <input type="checkbox" name="mentions" value="1" defaultChecked={filter.mentions === true} />
          {t("messaging.inbox.mentionsOnly")}
        </label>
        {filter.creatorId ? <input type="hidden" name="creator" value={filter.creatorId} /> : null}
        <Button type="submit" size="sm" variant="secondary">
          {t("messaging.inbox.apply")}
        </Button>
      </form>
      {rows ? (
        <InboxList rows={rows} filtered={filtered} showCreator />
      ) : (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      )}
    </>
  );
}
