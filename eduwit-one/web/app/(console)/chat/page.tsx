import { type Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ChatPanel } from "@/components/chat/chat-panel.tsx";
import { ArchiveThreadButton } from "@/components/chat/thread-forms.tsx";
import { ButtonLink } from "@/components/ui/button.tsx";
import { Card, CardBody } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { PageHeader } from "@/components/ui/state.tsx";
import { chatThreadSchema, chatThreadsSchema, type ChatThread } from "@/lib/ai/chat/db.ts";
import { ago } from "@/lib/format.ts";
import { requireUser } from "@/lib/session.ts";
import { ui, UiError } from "@/lib/ui/api.ts";

export const metadata: Metadata = { title: "Command centre" };

// The command centre (D-094): one place to ask, set up, run and fix the five apps by talking. The list of your
// conversations on the left (or folded away on a phone), the open one on the right. Every write it makes is one of the
// console's own page functions, run as you after you confirm its card.
export default async function ChatPage({ searchParams }: { searchParams: Promise<{ t?: string }> }) {
  const me = await requireUser("/chat");
  const t = Number((await searchParams).t);
  const threadId = Number.isInteger(t) && t > 0 ? t : null;
  let threads;
  let thread: ChatThread | null = null;
  try {
    threads = await ui("ui_chat_threads", chatThreadsSchema, { p_limit: 30 });
    if (threadId !== null) thread = await ui("ui_chat_thread", chatThreadSchema, { p_id: threadId });
  } catch (e) {
    if (e instanceof UiError && e.kind === "not_found") notFound();
    return <PageError error={e} />;
  }
  return (
    <>
      <PageHeader
        title={thread ? thread.thread.title : "Command centre"}
        description="Set up, run and fix Witty, the website, the CRMs, the influencer portal and Eduwit One itself by talking. The AI reads with fixed tools and masked data; it acts only through your own buttons, after you confirm."
        actions={
          <>
            {thread ? <ArchiveThreadButton id={thread.thread.id} /> : null}
            <ButtonLink href="/chat" variant="primary" size="sm">
              New conversation
            </ButtonLink>
          </>
        }
      />
      <div className="grid gap-4 md:grid-cols-[16rem_minmax(0,1fr)]">
        <details className="md:hidden" open={!thread}>
          <summary className="cursor-pointer text-sm text-fg-muted">Your conversations ({threads.length})</summary>
          <ThreadList threads={threads} current={thread?.thread.id ?? null} />
        </details>
        <aside className="hidden md:block">
          <ThreadList threads={threads} current={thread?.thread.id ?? null} />
        </aside>
        <Card>
          <CardBody>
            <ChatPanel
              key={thread?.thread.id ?? "new"}
              threadId={thread?.thread.id ?? null}
              messages={thread?.messages ?? []}
              actions={thread?.actions ?? []}
              busy={thread?.busy ?? false}
              role={me.role}
            />
          </CardBody>
        </Card>
      </div>
    </>
  );
}

function ThreadList({
  threads,
  current,
}: {
  threads: Array<{ id: number; title: string; updated_at: string; messages: number; open_actions: number }>;
  current: number | null;
}) {
  if (threads.length === 0) return <p className="p-2 text-sm text-fg-muted">No conversations yet.</p>;
  return (
    <nav aria-label="Conversations" className="grid gap-0.5 text-sm">
      {threads.map((t) => (
        <Link
          key={t.id}
          href={`/chat?t=${t.id}`}
          aria-current={t.id === current ? "page" : undefined}
          className={
            "grid gap-0.5 rounded-md px-2 py-1.5 hover:bg-surface-2 " +
            (t.id === current ? "bg-surface-2 font-medium" : "")
          }
        >
          <span className="truncate">{t.title}</span>
          <span className="text-xs text-fg-muted">
            {ago(t.updated_at)}
            {t.open_actions ? ` · ${t.open_actions} waiting` : ""}
          </span>
        </Link>
      ))}
    </nav>
  );
}
