import { getTranslations } from "next-intl/server";
import type { Db } from "@/lib/contracts/data";
import { loadMentionable, loadThread } from "@/lib/messaging/data";
import type { ThreadRef } from "@/lib/messaging/schemas";
import { Card } from "@/components/ui/card";
import { ErrorState } from "@/components/ui/states";
import { ThreadPanel } from "./thread-panel";

/**
 * Loads the conversation about one entity for the signed-in person and shows it; renders nothing for someone who may
 * not read it (for example an agency without the matching grant), so pages can include it unconditionally.
 */
export async function Thread({
  db,
  thread,
  title,
  description,
}: {
  db: Db;
  thread: ThreadRef;
  title?: string;
  description?: string;
}) {
  const t = await getTranslations();
  const view = await loadThread(db, thread).catch(() => undefined);
  if (view === null) return null;
  if (view === undefined) {
    return (
      <Card>
        <ErrorState title={t("messaging.loadFailed")} description={t("errors.tryAgain")} />
      </Card>
    );
  }
  const mentionable = view.side === "eduwit" && view.can_post ? await loadMentionable(db) : [];
  return (
    <ThreadPanel
      key={`${thread.type}:${thread.entityId}:${thread.creatorId ?? ""}`}
      thread={thread}
      initial={view}
      mentionable={mentionable}
      title={title}
      description={description}
    />
  );
}
