import Link from "next/link";
import type { Metadata } from "next";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { ReplyRow, type Reply } from "@/app/w/nurture/parts";

export const metadata: Metadata = { title: "Replies" };

/** The Replies inbox in the Sales app (spec B6.3, b39), for the counsellors the Admin named: the Workspace's replies, the same actions. */
export default async function SalesReplies({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  await requireUser("sales", "/s/replies");
  const status = (await searchParams).status === "all" ? "all" : "inbox";
  let rows: Reply[];
  try {
    if (!(await rpc<boolean>("can", { p_perm: "replies" }))) {
      return <Page title="Replies"><Empty>The Admin has not asked you to answer replies. Marketing handles them.</Empty></Page>;
    }
    rows = await rpc<Reply[]>("replies_list", { p: { status, limit: 100 } });
  } catch (e) {
    return <Page title="Replies"><SetupError error={e} /></Page>;
  }
  return (
    <Page title="Replies" sub="Students who answered a nurture message">
      <div className="hscroll">
        <Link className="pill" href="/s/replies" aria-pressed={status === "inbox"} style={{ color: "inherit", textDecoration: "none" }}>Waiting</Link>
        <Link className="pill" href="/s/replies?status=all" aria-pressed={status === "all"} style={{ color: "inherit", textDecoration: "none" }}>All recent</Link>
      </div>
      {rows.length === 0 ? <Empty>No reply waits for a person.</Empty> : <div className="stack">{rows.map((r) => <ReplyRow key={r.reply.id} r={r} base="/s/leads" />)}</div>}
    </Page>
  );
}
