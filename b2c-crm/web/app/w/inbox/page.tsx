import type { Metadata } from "next";
import { InboxView, type InboxParams } from "@/app/s/inbox/InboxView";
import { requireUser } from "@/lib/auth";

export const metadata: Metadata = { title: "Inbox" };

/** Every WhatsApp conversation (spec B15): the Admin answers, Marketing reads. Replies to marketing are under Nurture. */
export default async function WorkspaceInbox({ searchParams }: { searchParams: Promise<InboxParams> }) {
  const me = await requireUser("workspace", "/w/inbox");
  return <InboxView me={me} base="/w/inbox" leadBase="/w/leads" sp={await searchParams} />;
}
