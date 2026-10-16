import type { Metadata } from "next";
import { requireUser } from "@/lib/auth";
import { InboxView, type InboxParams } from "./InboxView";

export const metadata: Metadata = { title: "Inbox" };

/** WhatsApp on the Eduwit B2C number (spec B8.5): template first when the 24-hour window is closed. */
export default async function InboxPage({ searchParams }: { searchParams: Promise<InboxParams> }) {
  const me = await requireUser("sales", "/s/inbox");
  return <InboxView me={me} base="/s/inbox" leadBase="/s/leads" sp={await searchParams} />;
}
