import Link from "next/link";
import type { Metadata } from "next";
import { Search } from "lucide-react";
import { Empty, Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { initials, when } from "@/lib/format";
import { Thread, type Compose } from "./Thread";
import type { Snippet } from "../snippet-actions";

export const metadata: Metadata = { title: "Inbox" };

type Convo = { phone: string; lead_id: number | null; name: string | null; course: string | null; owner_name: string | null; unread: number; window_open: boolean; last_at: string | null; last: string | null };

/** WhatsApp on the Eduwit B2C number (spec B10): my leads' conversations, template first when the 24-hour window is closed. */
export default async function InboxPage({ searchParams }: { searchParams: Promise<{ lead?: string; q?: string; unread?: string }> }) {
  const me = await requireUser("sales", "/s/inbox");
  const sp = await searchParams;
  const leadId = Number(sp.lead) || null;
  let list: Convo[];
  let compose: Compose | null = null;
  let snippets: Snippet[] = [];
  try {
    [list, compose, snippets] = await Promise.all([
      rpc<Convo[]>("inbox_list", { p: { search: sp.q ?? "", unread: sp.unread === "1" } }),
      leadId ? rpc<Compose>("wa_compose", { p_lead: leadId }) : Promise.resolve(null),
      leadId ? rpc<Snippet[]>("snippets_mine").catch(() => [] as Snippet[]) : Promise.resolve([] as Snippet[]),
    ]);
  } catch (e) {
    return <Page title="Inbox"><SetupError error={e} /></Page>;
  }
  const current = list.find((c) => c.lead_id === leadId);
  const listing = (
    <div className="stack">
      <form className="search" action="/s/inbox" role="search">
        <Search className="icon s" aria-hidden />
        <input name="q" defaultValue={sp.q ?? ""} placeholder="Name or number" aria-label="Search conversations" />
      </form>
      <div className="hscroll">
        <Link className="pill" href="/s/inbox" aria-pressed={sp.unread !== "1"} style={{ color: "inherit", textDecoration: "none" }}>All mine</Link>
        <Link className="pill" href="/s/inbox?unread=1" aria-pressed={sp.unread === "1"} style={{ color: "inherit", textDecoration: "none" }}>Unread</Link>
      </div>
      {list.length === 0 ? <Empty>No conversations yet.</Empty> : (
        <div className="list">
          {list.map((c) => (
            <Link key={c.phone} className="li" href={c.lead_id ? `/s/inbox?lead=${c.lead_id}` : "/s/inbox"} aria-current={c.lead_id === leadId ? "page" : undefined}>
              <span className="avatar">{initials(c.name)}</span>
              <span className="t ellipsis">{c.name ?? c.phone}</span>
              <span className="row" style={{ gap: 4 }}>{c.unread > 0 && <span className="chip hot">{c.unread}</span>}<span className="small muted">{when(c.last_at)}</span></span>
              <span className="s ellipsis">{c.window_open ? "● " : ""}{c.last ?? ""}</span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
  return (
    <Page title="Inbox" sub="Your leads' WhatsApp on the Eduwit B2C number">
      <div className="grid" style={{ gridTemplateColumns: compose ? "minmax(240px, 340px) minmax(0, 1fr)" : "1fr", alignItems: "start" }}>
        <div className={compose ? "only-desk" : undefined}>{listing}</div>
        {compose && leadId && <Thread leadId={leadId} name={current?.name ?? null} compose={compose} snippets={snippets} vars={{ first_name: (current?.name ?? "").split(" ")[0] || null, programme: current?.course, counsellor_first_name: (me.full_name ?? "").split(" ")[0] || null }} />}
      </div>
    </Page>
  );
}
